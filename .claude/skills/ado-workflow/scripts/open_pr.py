#!/usr/bin/env python3
"""
open_pr.py — vetted Azure DevOps PR helper for dc1.azure.

Encapsulates the full PR dance so any Claude model (or person) gets identical,
gotcha-free behavior:

    branch  ->  create PR  ->  link work item  ->  self-approve  ->
    arm auto-complete (squash, delete branch, transition WIs)  ->  verify

Run it from inside the repo, on the branch you want to merge, after you have
pushed that branch. Requires ADO_PAT in the environment (source
docs/dev-environment.sh first — it is gitignored and per-user).

Why this exists (hard-won gotchas baked in here so nobody re-discovers them):
  * The WI->PR artifact link MUST use the project GUID + repo GUID, not their
    names. The name form (vstfs:///Git/PullRequestId/dc1.azure/...) is accepted
    by the API but resolves to ZERO linked work items, so the branch's
    "Work item linking" policy stays rejected and the PR never auto-completes.
  * "Work item linking" is one of FIVE branch policies and is a hard merge gate
    even when the build is green and the PR is approved. Always link before you
    expect a merge.
  * Self-approve works because the "Minimum number of reviewers" policy has
    creatorVoteCounts=true (solo repo). We vote 10 as the authenticated user.
  * connectionData needs api-version=7.1-preview to return the caller identity.

Subcommands:
    create   create+link+approve+arm-autocomplete for the current branch
    status   print PR status + per-policy evaluation (what's blocking a merge)
    link     (re)link a work item to a PR the GUID-correct way

Examples:
    source docs/dev-environment.sh
    python .claude/skills/ado-workflow/scripts/open_pr.py create --wi 158
    python .claude/skills/ado-workflow/scripts/open_pr.py status --pr 145
    python .claude/skills/ado-workflow/scripts/open_pr.py link --pr 145 --wi 158
"""
import argparse
import base64
import json
import os
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request

API = "api-version=7.1"


def die(msg):
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def git(*args):
    return subprocess.check_output(["git", *args], text=True).strip()


def parse_origin():
    """Derive (org, project, repo) from the ADO 'origin' remote.

    Handles both SSH (git@ssh.dev.azure.com:v3/<org>/<project>/<repo>) and
    HTTPS (https://dev.azure.com/<org>/<project>/_git/<repo>) forms.
    """
    url = git("remote", "get-url", "origin")
    if "ssh.dev.azure.com" in url:
        tail = url.split("ssh.dev.azure.com:", 1)[1]      # v3/org/project/repo
        parts = tail.split("/")
        if len(parts) >= 4 and parts[0] == "v3":
            return parts[1], parts[2], parts[3]
    if "dev.azure.com" in url and "/_git/" in url:
        left, repo = url.split("/_git/", 1)
        org_proj = left.split("dev.azure.com/", 1)[1]
        org, project = org_proj.split("/", 1)
        return org, project, repo.rstrip("/")
    die(f"could not parse ADO org/project/repo from origin remote: {url}")


class Ado:
    def __init__(self):
        pat = os.environ.get("ADO_PAT")
        if not pat:
            die("ADO_PAT not set — run: source docs/dev-environment.sh")
        self.auth = base64.b64encode(f":{pat}".encode()).decode()
        self.org, self.project, self.repo = parse_origin()
        self.base = f"https://dev.azure.com/{self.org}"
        self.git_base = f"{self.base}/{self.project}/_apis/git/repositories/{self.repo}"
        self._proj_id = None
        self._repo_id = None
        self._me = None

    def call(self, method, url, body=None, patch=False):
        ct = "application/json-patch+json" if patch else "application/json"
        headers = {"Authorization": f"Basic {self.auth}", "Content-Type": ct}
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(url, data=data, headers=headers, method=method)
        try:
            with urllib.request.urlopen(req) as resp:
                raw = resp.read().decode()
                return resp.status, (json.loads(raw) if raw else {})
        except urllib.error.HTTPError as e:
            return e.code, e.read().decode()

    # --- lazily-resolved identifiers -------------------------------------
    @property
    def proj_id(self):
        if self._proj_id is None:
            st, d = self.call("GET", f"{self.base}/_apis/projects/{self.project}?{API}")
            if st != 200:
                die(f"project lookup failed ({st}): {d}")
            self._proj_id = d["id"]
        return self._proj_id

    @property
    def repo_id(self):
        if self._repo_id is None:
            st, d = self.call("GET", f"{self.git_base}?{API}")
            if st != 200:
                die(f"repo lookup failed ({st}): {d}")
            self._repo_id = d["id"]
        return self._repo_id

    @property
    def me(self):
        if self._me is None:
            st, d = self.call("GET", f"{self.base}/_apis/connectionData?api-version=7.1-preview")
            if st != 200:
                die(f"identity lookup failed ({st}): {d}")
            self._me = d["authenticatedUser"]["id"]
        return self._me

    # --- operations ------------------------------------------------------
    def find_active_pr(self, branch):
        q = (f"{self.git_base}/pullrequests?"
             f"searchCriteria.sourceRefName=refs/heads/{urllib.parse.quote(branch)}"
             f"&searchCriteria.status=active&{API}")
        st, d = self.call("GET", q)
        if st == 200 and d.get("count", 0) > 0:
            return d["value"][0]
        return None

    def create_pr(self, branch, target, title, description):
        existing = self.find_active_pr(branch)
        if existing:
            print(f"reusing existing active PR #{existing['pullRequestId']}")
            return existing["pullRequestId"]
        body = {
            "sourceRefName": f"refs/heads/{branch}",
            "targetRefName": f"refs/heads/{target}",
            "title": title,
            "description": description,
        }
        st, d = self.call("POST", f"{self.git_base}/pullrequests?{API}", body)
        if st not in (200, 201):
            die(f"PR create failed ({st}): {d}")
        return d["pullRequestId"]

    def link_wi(self, pr_id, wi):
        """Link a work item to a PR via an ArtifactLink ON THE WORK ITEM,
        using the GUID form so the PR side actually resolves it."""
        artifact = (f"vstfs:///Git/PullRequestId/"
                    f"{self.proj_id}%2F{self.repo_id}%2F{pr_id}")
        patch = [{"op": "add", "path": "/relations/-",
                  "value": {"rel": "ArtifactLink", "url": artifact,
                            "attributes": {"name": "Pull Request"}}}]
        st, d = self.call("PATCH",
                          f"{self.base}/{self.project}/_apis/wit/workitems/{wi}?{API}",
                          patch, patch=True)
        if st != 200:
            die(f"work-item link failed ({st}): {d}")

    def pr_workitem_count(self, pr_id):
        st, d = self.call("GET", f"{self.git_base}/pullRequests/{pr_id}/workitems?{API}")
        return d.get("count", 0) if st == 200 else 0

    def approve(self, pr_id):
        st, d = self.call("PUT",
                          f"{self.git_base}/pullRequests/{pr_id}/reviewers/{self.me}?{API}",
                          {"vote": 10})
        if st != 200:
            die(f"self-approve failed ({st}): {d}")

    def arm_autocomplete(self, pr_id):
        body = {"autoCompleteSetBy": {"id": self.me},
                "completionOptions": {"deleteSourceBranch": True,
                                      "mergeStrategy": "squash",
                                      "transitionWorkItems": True}}
        st, d = self.call("PATCH", f"{self.git_base}/pullrequests/{pr_id}?{API}", body)
        if st != 200:
            die(f"auto-complete arm failed ({st}): {d}")

    def get_pr(self, pr_id):
        st, d = self.call("GET", f"{self.git_base}/pullrequests/{pr_id}?{API}")
        if st != 200:
            die(f"PR fetch failed ({st}): {d}")
        return d

    def policies(self, pr_id):
        aid = urllib.parse.quote(
            f"vstfs:///CodeReview/CodeReviewId/{self.proj_id}/{pr_id}", safe="")
        st, d = self.call(
            "GET",
            f"{self.base}/{self.project}/_apis/policy/evaluations"
            f"?artifactId={aid}&api-version=7.1-preview.1")
        if st != 200:
            return []
        return [(e.get("configuration", {}).get("type", {}).get("displayName", "?"),
                 e.get("status")) for e in d.get("value", [])]

    def pr_url(self, pr_id):
        return f"{self.base}/{self.project}/_git/{self.repo}/pullrequest/{pr_id}"


def cmd_create(ado, args):
    branch = git("rev-parse", "--abbrev-ref", "HEAD")
    if branch in ("main", "master"):
        die(f"refusing to open a PR from {branch} — switch to a feature branch")
    # warn if the branch isn't pushed / is behind its remote
    try:
        git("rev-parse", "--verify", f"origin/{branch}")
    except subprocess.CalledProcessError:
        die(f"branch {branch} is not pushed yet — run: git push -u origin {branch}")

    title = args.title or git("log", "-1", "--pretty=%s")
    description = args.description or git("log", "-1", "--pretty=%b") or title

    pr_id = ado.create_pr(branch, args.target, title, description)
    print(f"PR #{pr_id}: {ado.pr_url(pr_id)}")

    ado.link_wi(pr_id, args.wi)
    n = ado.pr_workitem_count(pr_id)
    if n < 1:
        die("work item did not link (PR shows 0 work items) — the merge "
            "policy would block. Check the GUID artifact URL / WI id.")
    print(f"linked work item AB#{args.wi} (PR now shows {n} work item(s))")

    ado.approve(pr_id)
    print("self-approved (vote 10)")

    if args.no_autocomplete:
        print("auto-complete NOT armed (--no-autocomplete)")
    else:
        ado.arm_autocomplete(pr_id)
        print("auto-complete armed (squash, delete branch, transition WIs)")

    pr = ado.get_pr(pr_id)
    print(f"\nstatus={pr['status']} mergeStatus={pr.get('mergeStatus')}")
    print("policies:")
    for name, status in ado.policies(pr_id):
        print(f"  - {name}: {status}")
    print("\nMerge waits on the CI pipeline (dc1.azure — lint + validate). "
          "Poll with:  open_pr.py status --pr %d" % pr_id)


def cmd_status(ado, args):
    pr = ado.get_pr(args.pr)
    print(f"PR #{args.pr}: status={pr['status']} mergeStatus={pr.get('mergeStatus')}")
    if pr["status"] == "completed":
        print(f"MERGED commit {pr.get('lastMergeCommit', {}).get('commitId', '')[:8]}")
        return
    print("policies:")
    for name, status in ado.policies(args.pr):
        print(f"  - {name}: {status}")
    print(f"linked work items: {ado.pr_workitem_count(args.pr)}")


def cmd_link(ado, args):
    ado.link_wi(args.pr, args.wi)
    n = ado.pr_workitem_count(args.pr)
    print(f"linked AB#{args.wi} to PR #{args.pr} (PR now shows {n} work item(s))")


def main():
    p = argparse.ArgumentParser(description="Azure DevOps PR helper for dc1.azure")
    sub = p.add_subparsers(dest="cmd", required=True)

    c = sub.add_parser("create", help="create+link+approve+arm-autocomplete current branch")
    c.add_argument("--wi", type=int, required=True, help="work item id to link (required)")
    c.add_argument("--title", help="PR title (default: last commit subject)")
    c.add_argument("--description", help="PR description (default: last commit body)")
    c.add_argument("--target", default="main", help="target branch (default: main)")
    c.add_argument("--no-autocomplete", action="store_true",
                   help="open + link + approve but do not arm auto-complete")
    c.set_defaults(func=cmd_create)

    s = sub.add_parser("status", help="print PR status + policy evaluations")
    s.add_argument("--pr", type=int, required=True)
    s.set_defaults(func=cmd_status)

    l = sub.add_parser("link", help="(re)link a work item to a PR the GUID-correct way")
    l.add_argument("--pr", type=int, required=True)
    l.add_argument("--wi", type=int, required=True)
    l.set_defaults(func=cmd_link)

    args = p.parse_args()
    args.func(Ado(), args)


if __name__ == "__main__":
    main()

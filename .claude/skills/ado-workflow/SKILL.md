---
name: ado-workflow
description: >-
  Drive the dc1.azure Azure DevOps PR workflow end to end: create a pull
  request from the current branch, link an ADO work item, self-approve, arm
  auto-complete, and confirm the merge. Ships a vetted helper
  (scripts/open_pr.py) so every Claude model gets identical, gotcha-free
  behavior. TRIGGER when the user asks to open / create a PR, commit or push to
  ADO, link a work item to a PR, approve or complete a PR, merge to main, or
  check why a PR is not merging. SKIP for local-only code edits with no PR, pure
  repo inspection, or GitHub-specific requests (this repo's source of truth is
  ADO; GitHub is a read-only mirror driven by the pipeline).
---

# Azure DevOps PR workflow — dc1.azure

This repo lives in Azure DevOps. **All** work (issues, PRs, merges) goes through
ADO; GitHub is a read-only mirror the CI pipeline pushes to — never `git push
github` by hand. The conventions (work-item types, `AB#` autolink, namespacing)
live in `CLAUDE.md` → *Issue Tracking (ADO Boards)*. This skill is the
**executable procedure** that complements those rules.

## Prerequisites

1. **`ADO_PAT`** must be in the environment. It lives in the gitignored,
   per-user `docs/dev-environment.sh`. Always:
   ```bash
   source docs/dev-environment.sh
   ```
2. **Linters pass first** — `yamllint .`, `ansible-lint`, and
   `terraform fmt -check terraform/` locally before pushing. The pipeline runs
   them and will block the merge otherwise.
3. **A work item exists** for the change. Every PR must link one (it is a hard
   merge gate — see below). Create one first if needed (see *Creating a work
   item*).

## The happy path (one shot)

From the repo, on your feature branch, **after pushing it**:

```bash
source docs/dev-environment.sh
git push -u origin <your-branch>          # the script refuses if not pushed
python .claude/skills/ado-workflow/scripts/open_pr.py create --wi <ID>
```

That single command:

1. Creates the PR (current branch → `main`), or reuses the branch's existing
   active PR.
2. Links work item `AB#<ID>` **and verifies the PR shows ≥1 work item** (fails
   loudly if not).
3. Self-approves (vote 10).
4. Arms auto-complete: **squash** merge, delete source branch, transition work
   items.
5. Prints status + every branch-policy evaluation so you can see what's left.

The merge then happens automatically once the CI pipeline (`dc1.azure — lint +
validate`) goes green. Poll it:

```bash
python .claude/skills/ado-workflow/scripts/open_pr.py status --pr <PR#>
```

After it merges, sync local:
```bash
git checkout main && git pull --ff-only origin main
```

## Title / description

The script defaults the PR title to the last commit subject and the description
to the commit body. Override with `--title` / `--description`. Keep the
`AB#<ID>` reference in the commit message so ADO also creates the "Fixed in
commit" links automatically.

## The five branch policies (what gates a merge)

A PR on `main` must satisfy **all** of these — `status` prints each one:

| Policy | How it's satisfied here |
|--------|-------------------------|
| Minimum number of reviewers | self-approve works (`creatorVoteCounts=true`, solo repo) |
| **Work item linking** | **must link a WI — the #1 reason a green, approved PR won't merge** |
| Comment requirements | resolve any PR comments |
| Require a merge strategy | the script sets `squash` |
| Build | the `lint + validate` pipeline must pass |

## Gotchas baked into the helper (don't re-derive these)

- **WI→PR link must use GUIDs, not names.** The artifact URL is
  `vstfs:///Git/PullRequestId/{projectGUID}%2F{repoGUID}%2F{prId}`. The
  name form (`.../dc1.azure/...`) is accepted by the API but resolves to **zero**
  linked work items, so the *Work item linking* policy stays rejected and the PR
  never auto-completes. The script resolves both GUIDs for you.
- **Link the work item, then check the PR side.** Adding the ArtifactLink to the
  work item is what makes the PR show it; the script verifies
  `pullRequests/{id}/workitems` returns ≥1 before continuing.
- **`connectionData` needs `api-version=7.1-preview`** to return the caller id
  used for approve / auto-complete.
- **`az boards` cannot create the ArtifactLink** — that's why this is a REST
  helper, not an `az` wrapper.

## Re-linking a PR that won't merge

If `status` shows *Work item linking: rejected* (or 0 linked work items):

```bash
python .claude/skills/ado-workflow/scripts/open_pr.py link --pr <PR#> --wi <ID>
```

## Creating a work item

Always link a work item; never bypass the policy. Quick create via REST (use the
right type — `Bug`, `Task`, or `User Story`; title prefix `[Phase N] …`):

```bash
source docs/dev-environment.sh
python3 - "$ADO_PAT" <<'PY'
import sys,json,base64,urllib.request
ORG="https://dev.azure.com/ericcames"; PROJ="dc1.azure"
auth=base64.b64encode(f":{sys.argv[1]}".encode()).decode()
patch=[{"op":"add","path":"/fields/System.Title","value":"[Phase N] <title>"}]
r=urllib.request.Request(f"{ORG}/{PROJ}/_apis/wit/workitems/$Task?api-version=7.1",
  data=json.dumps(patch).encode(),
  headers={"Authorization":f"Basic {auth}","Content-Type":"application/json-patch+json"},
  method="POST")
print("created WI", json.loads(urllib.request.urlopen(r).read())["id"])
PY
```

(Change `$Task` to `$Bug` or `$User%20Story` for other types.) Set the work
item's state to **Resolved** in the same flow if you want it to close on merge;
`transitionWorkItems` (already on in the script) advances linked items when the
PR completes.

## Notes

- The helper is pure Python stdlib (`urllib`) — no pip deps, runs anywhere the
  repo is checked out.
- Org / project / repo are derived from the `origin` remote, so the script works
  unchanged for anyone who clones (SSH or HTTPS remote).
- One concern per PR (see `CLAUDE.md`). If a change needs a new work item, make
  it first, then `create --wi`.

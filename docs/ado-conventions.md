# ADO Operating Conventions

How `dc1.azure` uses Azure DevOps. This is the single-page reference for the
Boards hierarchy, branch policies, PR template, Service Connections, and
Library content that collectively define how this repo is operated. If you
are an SE picking up this demo, or a customer auditing the engineering
practices behind it — read this file end-to-end.

Companion docs:

- [`ROADMAP.md`](../ROADMAP.md) — what we are building (Phase 0.5 is the home of these conventions)
- [`CONTRIBUTING.md`](../CONTRIBUTING.md) — the developer workflow that sits on top of these conventions
- [`CLAUDE.md`](../CLAUDE.md) — guidelines for the AI assistant working in this repo

---

## 1. Boards hierarchy

We use the standard Agile process: **Epic → Feature → User Story / Task**.
Every work item gets an Area Path and an Iteration Path so dashboards in
ADO render the work the way an enterprise team would expect.

| Level       | Purpose                                                          | Naming convention                          |
|-------------|------------------------------------------------------------------|--------------------------------------------|
| **Epic**    | One per ROADMAP phase                                            | `Phase N — <phase title>`                  |
| **Feature** | A work-stream under a phase (multiple per epic)                  | `Phase N → <work stream>`                  |
| **Story**   | A single shippable change (typically maps to one PR)             | `[Phase N] <action>`                       |
| **Task**    | A subtask of a story (optional; use when a story has &gt;1 day of work) | Free-form, but should fit on one card title |

**Area Path:** `dc1.azure` (single area path — keeps queries simple while
the project is solo).

**Iteration Paths:** `Sprint 1`, `Sprint 2`, ... Even for solo work, sprint
paths give the customer something recognizable on the dashboard and tie
chunks of work to a date range.

**Tags (apply liberally):** `phase-0` … `phase-10` (one per ROADMAP phase),
`terraform`, `aap`, `ado`, `windows`, `azure`, `servicenow`, `cac`, `docs`,
`pipeline`.

---

## 2. Branch policies on `main`

Configured under: *Project Settings → Repositories → dc1.azure → Policies → main branch*

| Policy                                | Setting                                                              | Why                                                                 |
|---------------------------------------|----------------------------------------------------------------------|---------------------------------------------------------------------|
| **Require minimum reviewers**         | 1 reviewer (self-review acceptable for solo work)                    | Forces every change to be reviewed at least once, even solo         |
| **Check for linked work items**       | Required                                                             | Enforces the AB# discipline — no PR without a Board item            |
| **Build validation**                  | `dc1.azure` pipeline (wired up in Phase 5)                           | Lint + validate every PR before merge                               |
| **Limit merge types**                 | Squash-merge only                                                    | Keeps `main` history linear and reviewable                          |
| **Automatically include reviewers**   | See [§3 Reviewers by path](#3-reviewers-by-path) below               | ADO equivalent of GitHub's `CODEOWNERS`                             |
| **Comment requirements**              | All comments resolved before completion                              | Forces explicit closure on every review point                       |
| **Block direct push to `main`**       | Enabled (Phase 0.5 exit criterion)                                   | All changes go through PRs — applies to humans AND service accounts |

All seven policies above are now active on `main` (Phase 0.5 completed
2026-05-26, build-validation policy added with the Phase 5 pipeline). Direct
push to `main` is blocked — every change goes through a PR.

---

## 3. Reviewers by path

ADO does not parse `CODEOWNERS` natively. We mirror that pattern via the
*Automatically include code reviewers* branch policy. The mapping below is
the canonical source-of-truth — the `CODEOWNERS` file at the repo root
mirrors this for GitHub's benefit.

| Path                  | Required reviewer | Notes                                                  |
|-----------------------|-------------------|--------------------------------------------------------|
| `/terraform/**`       | @ericcames        | Layer 0 — Azure infrastructure                         |
| `/playbooks/**`       | @ericcames        | AAP runtime playbooks (provision / configure / teardown) |
| `/aap_config/**`      | @ericcames        | Phase 3 canonical install path                         |
| `/.azuredevops/**`    | @ericcames        | Pipeline + PR template                                 |
| `/ROADMAP.md`         | @ericcames        | Strategic doc — changes affect every downstream phase  |
| `/CONTRIBUTING.md`    | @ericcames        | Developer workflow                                     |
| `/CLAUDE.md`          | @ericcames        | AI assistant guidelines                                |
| `/CODEOWNERS`         | @ericcames        | This mapping                                           |
| catch-all (`*`)       | @ericcames        | Anything not matched above                             |

When a teammate joins, add them here AND update the branch policy AND
update `CODEOWNERS`. All three must stay in sync.

---

## 4. PR template

Lives at [`.azuredevops/pull_request_template.md`](../.azuredevops/pull_request_template.md).
ADO auto-applies it to every PR opened against this repo. Sections:

| Section            | Purpose                                                                |
|--------------------|------------------------------------------------------------------------|
| **Summary**        | 1-3 sentences — what changes and the user-visible outcome              |
| **Work item**      | The `AB#<id>` autolink — required by branch policy                     |
| **Test plan**      | Markdown checklist of what was tested (minimums vary by area)          |
| **Risk / rollback**| Blast radius if the change is wrong; how to revert                     |
| **Checklist**      | One-concern PR; CHANGELOG updated; no secrets committed                |

---

## 5. `AB#<id>` autolink syntax

`AB#123` (no slash, case-sensitive on the `AB`) is ADO's built-in autolink
shorthand for work item 123 in the current project. It works in:

- PR descriptions
- PR comments
- Commit messages (preserved through squash-merge)
- Work item discussion fields

Use it everywhere a change touches a work item. Setting the work item State
to *Resolved* in the PR side-panel additionally auto-closes the work item
on merge.

---

## 6. Service Connections (ADO Library)

Lives under: *Project Settings → Pipelines → Service connections*

| Service Connection name | Type                          | Purpose                                                                                | Owner          |
|-------------------------|-------------------------------|----------------------------------------------------------------------------------------|----------------|
| `dc1-azure-rhdp-sp`     | Azure Resource Manager        | Replaces inline Azure creds in `terraform/terraform.tfvars` for pipeline-driven runs   | @ericcames     |
| `github-ericcames`      | GitHub (PAT or deploy key)    | Auth for the Phase 5 auto-mirror push to `github.com/ericcames/dc1.azure`              | @ericcames     |

**Never paste credentials inline in `azure-pipelines.yml`.** Every external
auth context goes through a Service Connection so the secret material stays
in the ADO Library and is rotatable.

---

## 7. Variable Groups (ADO Library)

Lives under: *Pipelines → Library*

| Variable Group        | Variables                                                                                    | Linked to                                |
|-----------------------|----------------------------------------------------------------------------------------------|------------------------------------------|
| `dc1-azure-shared`    | `location`, `resource_group_name`, `subscription_id` (secret), `storage_account_name`        | `azure-pipelines.yml` (Phase 5)          |
| `dc1-azure-aap`       | `AAP_HOSTNAME`, `AAP_TOKEN` (secret)                                                          | `azure-pipelines-launch.yml` (Phase 10)  |

`dc1-azure-aap` holds the AAP API connection the **launch** pipeline (Phase 10)
uses to fire the provisioning workflow. `AAP_HOSTNAME` is the gateway base URL
(e.g. `https://<gateway>.rhdp.net`); `AAP_TOKEN` is a **UI-minted** AAP API
token marked **secret** (this AAP authenticates via SSO and cannot basic-auth-mint
a token — a manually-minted token still works for direct API calls). Rotate by
editing the Library variable; it is never pasted in YAML and is masked in logs.
No new Service Connection is needed — token auth goes straight to the AAP API.

Shared values that multiple pipeline stages need go in the Variable Group
so they are configurable without editing YAML. Mark anything sensitive as
secret in the Library UI — secret variables are masked in logs.

---

## 8. Wiki

The ADO Wiki for this project has a single landing page that points at
[`README.md`](../README.md) and [`ROADMAP.md`](../ROADMAP.md). The wiki is
not the source-of-truth for any technical content — everything lives
in-repo. The wiki exists only so ADO-native users who never `git clone`
the repo can still find the entry points.

---

## 9. What this gives a customer reviewer

If a customer is auditing this repo's engineering practices, the
artifacts above collectively answer "do you operate like a team
we would want to work with?" with:

- Boards in active use (Epic → Feature → Story → Task), not just a code dump
- Branch policies blocking unreviewed merges to `main`
- Mandatory work-item linkage on every PR (visible in `git log` after squash)
- Reviewers-by-path enforced via branch policy
- Standard PR template applied to every PR
- Service Connections + Variable Group — no inline creds in YAML
- Auto-mirror to GitHub (Phase 5) — external visibility without manual steps

Anything missing from that list is a Phase 0.5 ⬜ item — see
[`ROADMAP.md`](../ROADMAP.md).

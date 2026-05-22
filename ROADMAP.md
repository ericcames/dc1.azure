# DC1 Azure — Windows on Azure Demo Roadmap

## Vision

`dc1.azure` is the Azure-cloud expression of the DC1 demo pattern. Where
[`demo.datacenter`](https://github.com/ericcames/demo.datacenter) builds a
virtual datacenter on AWS, `dc1.azure` delivers a parallel, presentable
Microsoft-stack story:

> *"Same automation. Same self-service experience. Your cloud, your tools."*

The narrative target is **self-service Windows VM provisioning on Azure**,
driven by an end user picking a t-shirt size in an AAP survey and getting a
fully configured Windows Server 2025 box in ~10 minutes — with the source code
living in Azure DevOps Repos and gated by an Azure DevOps Pipeline.

`dc1.azure` is intentionally scoped smaller than `demo.datacenter`: a single
VM, a focused story, and a chance to build hands-on Azure + ADO muscle without
re-implementing the entire DC1 layered platform.

---

## Guiding Principles

- **Mirror DC1 patterns where reasonable** — directory layout, CHANGELOG
  style, `infra.aap_configuration` version pinning, CaC-for-everything all
  match `demo.datacenter` / `aap.as.code` conventions.
- **Deviate only where the platform demands it** — Azure-native services
  (Storage backend for Terraform state, Azure RM credential type, ADO
  Pipelines) replace their AWS/GitHub equivalents; the *shape* of the
  automation stays the same.
- **Single VM, single story** — no platform sprawl. Layer 0 + a Windows
  workload is the entire scope.
- **AAP is the orchestrator** — even with ADO Pipelines in the picture, ADO
  handles code quality (lint/validate) only. All provisioning,
  configuration, and teardown runs from AAP. Matches the AWS DC1 split.
- **CaC for every AAP object** — credentials, projects, inventories, job
  templates, workflows defined in `playbooks/bootstrap_aap.yml` via the
  `infra.aap_configuration` collection.
- **No project-local `ansible.cfg`** — the user's global `~/.ansible.cfg`
  holds the Automation Hub `galaxy_server` token; shadowing it breaks
  `ansible-galaxy collection install` for Red Hat certified content. Set
  inventory/options via CLI flags or env vars.
- **Namespaced AAP objects** — every credential, project, JT, and workflow
  name is prefixed `DC1.Azure -` so it can co-exist safely with `demo.datacenter`
  AWS objects in shared AAP instances.

---

## Architecture

```
┌────────────────────────────────────────────────────────────────────┐
│ Source & CI                                                        │
│   Azure DevOps  org: ericcames                                     │
│     ├─ Repo:     dc1.azure                                         │
│     ├─ Boards:   epic + per-phase work items                       │
│     └─ Pipeline: yamllint · ansible-lint · terraform fmt/validate  │
└──────────────────────┬─────────────────────────────────────────────┘
                       │ project sync (PAT)
                       ▼
┌────────────────────────────────────────────────────────────────────┐
│ Orchestration — AAP (RHDP)                                         │
│   Credentials                                                      │
│     ├─ Azure RM — RHDP            (Service Principal)              │
│     ├─ ADO Source Control         (PAT)                            │
│     ├─ Windows Machine            (WinRM admin)                    │
│     └─ Vault — dc1.azure                                           │
│   Project:     DC1.Azure (synced from ADO repo)                    │
│   Inventory:   dc1-azure (Windows host populated at runtime)       │
│   Job Templates                                                    │
│     ├─ DC1.Azure - Provision VM        (survey: vm_size_tier)      │
│     ├─ DC1.Azure - Configure Windows                               │
│     └─ DC1.Azure - Teardown                                        │
│   Workflow: DC1.Azure - Provision and Configure                    │
└──────────────────────┬─────────────────────────────────────────────┘
                       │ terraform apply / winrm
                       ▼
┌────────────────────────────────────────────────────────────────────┐
│ Cloud — Azure (RHDP open environment)                              │
│   Resource Group (provided by RHDP)                                │
│     ├─ Storage Account            (Terraform state backend)        │
│     ├─ Virtual Network + Subnet                                    │
│     ├─ Network Security Group     (WinRM 5986 · RDP 3389)          │
│     ├─ Public IP + NIC                                             │
│     └─ Windows Server 2025 VM     (size from survey tier)          │
└────────────────────────────────────────────────────────────────────┘
```

---

## Sizing Tiers

The provisioning JT survey asks for `vm_size_tier`. Mapping is enforced in
Terraform `locals.tf`:

| Tier   | Azure SKU          | vCPU | RAM   | Approx $/hr | Use case                |
|--------|--------------------|------|-------|-------------|-------------------------|
| small  | `Standard_D2s_v5`  | 2    | 8 GB  | ~$0.10      | Dev / quick smoke test  |
| medium | `Standard_D4s_v5`  | 4    | 16 GB | ~$0.19      | Default demo path       |
| large  | `Standard_D8s_v5`  | 8    | 32 GB | ~$0.38      | "Production-like" story |

All three are in the `Dsv5` general-purpose family — same family / more
cores tells a clean scaling story without introducing burstable-vs-dedicated
nuance into the demo. Quota in the RHDP open environment must be confirmed
to cover `D8s_v5` (8 vCPU); if not, slide tiers down one notch.

---

## Phases

### Phase 0 — Azure DevOps Account Setup  ✅
*Manual browser work, ~15 min, blocks all subsequent phases. Completed 2026-05-21.*

- ✅ Create ADO org `ericcames` at https://dev.azure.com
- ✅ Create project `dc1.azure` (Private, Git, Agile process)
- ✅ Initialize default `dc1.azure` repo with README + VisualStudio gitignore
- ✅ Create Personal Access Token scoped to Code (RW), Build (RX), Work Items (RW); save to password manager
- ✅ Clone repo to `/home/eames/git-repos/dc1.azure/` using PAT for auth

> ADO Boards Epic creation and the rest of the "operate like a mature dev team" setup now lives in **Phase 0.5 — ADO Operating Conventions** below.

**Exit criteria:** local clone of an empty (README-only) ADO repo at the expected path; PAT stored.

### Phase 0.5 — ADO Operating Conventions  🔄
*Make `dc1.azure` read as a mature dev-team project to an ADO-fluent customer audience. Runs alongside Phase 1+ work — not strictly blocking, but every item below should land before the demo is presented to the customer. Chunk A (in-repo files) landed 2026-05-21 in commit e0c826f; Chunk B (ADO UI / az devops CLI work) landed 2026-05-21.*

**Why this phase exists:** the customer for this demo is fluent in Azure DevOps and will notice if the repo looks like "one person pushing to main." Boards in active use, branch policies enforced, AB# in every commit, and shared Service Connections instead of inline creds collectively read as "this team operates the way ours does."

**Boards hierarchy (backfill from existing phases):**
- ✅ Create Epic per ROADMAP phase: 10 Epics created — Phase 0/1 Closed, Phase 0.5/2/3 Active, Phase 4-8 New (2026-05-21)
- ✅ Under each Epic, group work-streams as **Features**: 13 Features created under the 3 Active Epics (2026-05-21)
- ✅ Decompose Features into **User Stories** / **Tasks**: 11 initial Stories created (4 Closed for historical commits, 1 Active for current work, 6 New for upcoming) (2026-05-21)
- ✅ Configure **Area Path** `dc1.azure` (default) + **Iteration Paths** Sprint 1/2/3 with rolling 2-week date ranges starting 2026-05-21 (2026-05-21)
- ✅ Tag every work item with `phase-N` + topic tags (`terraform`, `aap`, `ado`, `cac`, `windows`, `azure`, `pipeline`, `policy`, `docs`, `wiki`, `boards`, `credentials`, `secrets`, `testing`, `workflow`, `validation`, `cleanup`, `servicenow`, `demo`) as applicable (2026-05-21)

**Branch policies on `main`:**
- ✅ Require a minimum of 1 reviewer (self-review allowed via `creator-vote-counts=true` for solo; switch to required external reviewer when teammate joins) — policy ID 2 (2026-05-21)
- ✅ Require linked work item on every PR (enforces the AB# discipline) — policy ID 3 (2026-05-21)
- ⬜ Require Build validation = Phase 5 pipeline pass (deferred until Phase 5 pipeline exists)
- ✅ Block direct push to `main` — implicit consequence of the four blocking policies being in place (2026-05-21)
- ✅ Squash-only merge strategy — policy ID 5 (2026-05-21)
- ✅ **Bonus:** Comments must be resolved before merge — policy ID 4 (2026-05-21; not on the original list but worth keeping)

**PR template + commit conventions:**
- ✅ `.azuredevops/pull_request_template.md` — sections: *Summary*, *Work item*, *Test plan*, *Risk / rollback* (2026-05-21)
- ✅ Document `AB#<id>` autolink syntax in `CONTRIBUTING.md` — added explicit autolink-mechanics section + pointer to the PR template (2026-05-21)
- ✅ `CODEOWNERS` file mapping `/terraform/` → @ericcames, `/playbooks/` → @ericcames, `/aap_config/` → @ericcames + catch-all + governance docs (2026-05-21). Note: ADO doesn't natively parse `CODEOWNERS` — file works AS-IS on the GitHub mirror; ADO enforcement happens via the "Automatically include code reviewers" branch policy (see `docs/ado-conventions.md`).

**Service Connections + Library (replace inline creds):**
- ✅ Create **Azure Resource Manager** service connection `dc1-azure-rhdp-sp` from the RHDP Service Principal — id `86d0df16-75b6-4197-9ddb-4cd097d14245`, IsReady true (2026-05-21)
- ⬜ Create **GitHub** service connection `github-ericcames` for the Phase 5 auto-mirror push (deferred to Phase 5 — no GitHub PAT exists yet; manual `git push github main` covers the gap)
- ✅ Create **Variable Group** `dc1-azure-shared` in Library — id 1, 4 variables (`location=eastus`, `resource_group_name=openenv-blsvm-1`, `subscription_id`, `storage_account_name=REPLACE_ME_TF_STATE_SA`), authorized for all pipelines (2026-05-21)
- ✅ Document the Library / Service Connection inventory in `docs/ado-conventions.md` so a customer SE walking in sees the same shape an enterprise team would maintain (2026-05-21)

**Wiki vs. in-repo docs:**
- ✅ Project Wiki `dc1.azure.wiki` with single `/Home` landing page pointing at `README.md`, `ROADMAP.md`, and `docs/ado-conventions.md` for ADO-native discoverability (2026-05-21)

**Project metadata:**
- ✅ Project description set on the ADO project landing page (2026-05-21): *"Azure-cloud expression of the DC1 demo pattern: AAP-orchestrated self-service Windows Server 2025 VM provisioning with t-shirt sizing. Source in ADO Repos, gated by ADO Pipelines. See ROADMAP.md for architecture and phases."*

**Deferred to later phases:**
- GitHub Service Connection → Phase 5 (when auto-mirror pipeline is built)
- Build validation branch policy → Phase 5 (no pipeline to validate against yet)
- Auto-include reviewers-by-path policy → when a teammate joins (cosmetic for solo project; `CODEOWNERS` documents the intent today)

**Exit criteria:** an ADO-fluent customer browsing `dev.azure.com/ericcames/dc1.azure` sees: Boards with an Epic→Feature→Story hierarchy in active use, branch policies enforced on `main`, a PR template applied to recent PRs, AB# linking present on every commit since Phase 0.5 landed, and Service Connections + a Variable Group provisioned in the Library — even if Phase 5 hasn't wired the pipeline to use them yet.

### Phase 1 — Repo Skeleton  ✅
*Completed 2026-05-21 (commit 2848f54).*

- ✅ Top-level files: `README.md`, `CHANGELOG.md`, `CLAUDE.md`, `CODE_OF_CONDUCT.md`, `CONTRIBUTING.md`, `LICENSE`
- ✅ Directory scaffolding: `terraform/`, `playbooks/`, `inventories/dc1-azure/`, `docs/`, `docs/images/`, `meta/`, `collections/`
- ✅ `galaxy.yml`, `meta/runtime.yml`
- ✅ `collections/requirements.yml` pinning `infra.aap_configuration` 4.2.0, plus `azure.azcollection`, `ansible.windows`, `community.windows`
- ✅ **No** project-local `ansible.cfg`
- ✅ `.gitignore` covering `*.tfstate*`, `.terraform/`, `*.tfvars` (except `*.tfvars.example`), `__pycache__`, `.DS_Store`

**Exit criteria:** repo opens cleanly in VS Code, `ansible-galaxy collection install -r collections/requirements.yml` succeeds against Eric's `~/.ansible.cfg`.

### Phase 2 — Terraform: Azure Windows VM  🔄
*Code complete 2026-05-21 (commit 2848f54); manual smoke test still pending.*

- ✅ `providers.tf` — `azurerm` provider + `azurerm` remote state backend
- ✅ `backend.tf` — Storage Account / container / key for state
- ✅ `variables.tf` — `vm_size_tier`, `location`, `resource_group_name`, `admin_username`, `admin_password` (sensitive), `tags`
- ✅ `locals.tf` — t-shirt → SKU map (see table above)
- ✅ `main.tf` — VNet, Subnet, NSG (5986 + 3389), Public IP, NIC, `azurerm_windows_virtual_machine` (image `MicrosoftWindowsServer:WindowsServer:2025-datacenter-azure-edition:latest`), `custom_data` (via `terraform/scripts/winrm_bootstrap.ps1`) enables WinRM-HTTPS + opens firewall
- ✅ `outputs.tf` — `public_ip`, `fqdn`, `admin_username`, `vm_size_chosen`
- ✅ `terraform.tfvars.example` documenting required inputs
- ⬜ Manual smoke test from Eric's laptop: `terraform init && plan && apply` with `vm_size_tier=small`, confirm WinRM reachable, `destroy`

**Exit criteria:** `terraform apply` from Eric's laptop produces a reachable Windows VM in the RHDP open env; `destroy` cleans it up; state lives in Azure Storage.

### Phase 3 — AAP Configuration as Code  🔄

Pattern adopted (2026-05-21): `url_checker`-style self-contained `aap_config/`
directory at the repo root, dispatched via `infra.aap_configuration.dispatch`.
Chosen over `aap.as.code`'s `playbooks/files/config_as_code/` because it's
more discoverable for new users (single top-level directory contains
everything to install AAP objects) and matches the upstream
`infra.aap_configuration` collection's recommended layout.

**Implementation — new canonical path** (`aap_config/`):

- ⬜ `aap_config/load.yml` — entry-point playbook; `include_role: infra.aap_configuration.dispatch`
- ⬜ `aap_config/requirements.yml` — pin `infra.aap_configuration` 4.5.0+
- ⬜ `aap_config/README.md` — one-page explanation of the pattern, env vars required, command to run
- ⬜ `aap_config/inventory/aap.yml` — localhost only (CaC playbook runs locally and talks to AAP via API)
- ⬜ `aap_config/group_vars/all.yml` — `AAP_HOSTNAME` + `AAP_TOKEN` env-var lookups (user creates a personal token in AAP UI first); `AZURE_*` + `ADO_PAT` lookups for credential inputs
- ⬜ `aap_config/files/controller_credentials.yml` — 4 credentials (Vault, Azure RM, ADO SCM, Windows Machine)
- ⬜ `aap_config/files/controller_projects.yml` — DC1.Azure project syncing from ADO
- ⬜ `aap_config/files/controller_inventories.yml` — dc1-azure inventory with empty `windows` group (populated at runtime by Provision JT via `add_host` + `set_stats`)
- ⬜ `aap_config/files/controller_templates.yml` — 3 JTs (Provision, Configure, Teardown) with surveys
- ⬜ `aap_config/files/controller_templates_workflow.yml` — Provision and Configure workflow chaining Provision → Configure with artifact passing
- ⬜ Post-load validation step (per global rule: never exit green without verifying every object exists)

**Transition / deprecation:**

- 🔄 `playbooks/bootstrap_aap.yml` — transitional; to be removed once `aap_config/load.yml` is the verified canonical path. Currently still in repo because it covers the "first run with no AAP token, only admin password" case via `ansible.platform.token` lifecycle. Once a user can manually create a token in the AAP UI and run `load.yml`, this file's value drops to zero.
- ✅ Add deprecation banner to top of `playbooks/bootstrap_aap.yml` (2026-05-21)
- ⬜ Remove `playbooks/bootstrap_aap.yml` after `aap_config/load.yml` is end-to-end verified

**Credentials live in AAP (status independent of which path created them):**

- ✅ `DC1.Azure - Vault` — created 2026-05-21 via bootstrap_aap.yml
- ✅ `DC1.Azure - Azure RM` — created 2026-05-21 via bootstrap_aap.yml, SP fields verified via API
- ⬜ `DC1.Azure - ADO Source Control` — blocked on AAP-scoped PAT creation
- ⬜ `DC1.Azure - Windows Machine`

**Exit criteria:** a user with a fresh AAP, AAP personal token, Azure SP, and ADO PAT can run `ansible-playbook -i aap_config/inventory/ aap_config/load.yml` and end with every dc1.azure AAP object created. Re-running is idempotent.

### Phase 4 — Post-Provision Playbook  ⬜
- ⬜ `playbooks/provision_vm.yml` — wraps `terraform apply`, parses output, `add_host` to `windows` group, `set_stats` to pass IP to workflow
- ⬜ `playbooks/configure_windows.yml` runs against the new host:
  - ⬜ `powershell_improvement` role
  - ⬜ `windows_account_create` role
  - ⬜ `website_setup` role (IIS sample site)
  - ⬜ `windows_patching` role
- ⬜ `playbooks/teardown.yml` — `terraform destroy`
- ⬜ Role sourcing decision: import via `collections/requirements.yml` from upstream `aap.dailydemo.windows`, *or* vendor the four roles locally. Default: requirements.yml (DRY).

**Exit criteria:** end-to-end workflow run produces a VM that serves an IIS page on its public IP, has the demo account, has PS7, and has run Windows Update.

### Phase 5 — Azure DevOps Pipeline  ⬜

**Current state (manual workflow, in place today):**

GitHub remote is already configured locally — the working tree has both `origin` (ADO) and `github` (GitHub) remotes. Today the sync is manual: after every `git push origin main`, Eric also runs `git push github main` from the laptop. This keeps https://github.com/ericcames/dc1.azure visible for outside-the-firewall audiences but adds a step that's easy to forget. Phase 5 automates it away.

**Planned work:**

- ⬜ `azure-pipelines.yml` at repo root, PR trigger to `main`
- ⬜ Steps on `ubuntu-latest`: `yamllint`, `ansible-lint`, `terraform fmt -check -recursive`, `terraform validate` (with `-backend=false`)
- ⬜ Branch policy: require pipeline pass + 1 reviewer before merge to `main` (Phase 0.5 sets up the policy slot; Phase 5 wires the pipeline into it)
- ⬜ **Auto-mirror to GitHub** — pipeline stage (or separate `azure-pipelines-mirror.yml`) triggered on push to `main` that runs `git push github main`. Auth via the `github-ericcames` Service Connection created in Phase 0.5 (PAT or deploy key — never inline in YAML). Goal: https://github.com/ericcames/dc1.azure stays in sync without the manual `git push github main` step described above.

**Exit criteria:** opening a PR triggers the pipeline; a deliberately bad YAML/TF change fails it; merging to `main` mirrors the commit to the GitHub repo within a minute, and `git push github main` is no longer in the developer workflow.

### Phase 6 — Demo Runbook (v1 — AAP-driven)  ⬜
- ⬜ `docs/demo-runbook.md` — SE-facing live-demo script for the AAP-driven flow
- ⬜ Persona framing, click-by-click flow through AAP UI, talking points, expected timings
- ⬜ Failure-mode appendix (what to do if Azure quota hit, if WinRM doesn't come up, if AAP project sync fails)
- ⬜ `docs/images/` — screenshots of the AAP survey, the IIS landing page, the ADO Boards epic

**Exit criteria:** Eric runs the AAP-driven demo cold off the runbook end-to-end without consulting the source code.

### Phase 7 — Install Documentation (manual + Claude Code skill)  ⬜

Two paths to install dc1.azure into a working RHDP AAP: a manual path for
human-only operators, and a Claude Code skill that drives the install
interactively.

- ⬜ `docs/INSTALL.md` — manual install for humans. Pre-reqs (AAP up, Azure SP, ADO PAT, ansible-galaxy collections installed), step-by-step commands, expected output per step, troubleshooting
- ⬜ `.claude/skills/install-dc1-azure/SKILL.md` — Claude Code skill auto-loaded when running Claude in this repo. Walks the user through prereqs, prompts for missing env-var values, runs `aap_config/load.yml`, verifies via AAP API, reports each created object
- ⬜ `README.md` — point at both install paths from Getting Started; framing: "use the AI path if you have Claude Code, manual path otherwise"
- ⬜ Acceptance test: fresh repo clone + fresh AAP + each path independently produces a green install

**Exit criteria:** a first-time user can install dc1.azure into a fresh AAP via either path without consulting source code or this ROADMAP.

### Phase 8 — ServiceNow Integration (Demo v2)  ⬜

End-state demo flow: business user goes to ServiceNow self-service catalog,
requests a Windows VM (Azure), picks size, submits. SNow triggers the
dc1.azure workflow in AAP. AAP runs Terraform + post-provision. On success,
AAP calls back to ServiceNow to update the RITM with status, public IP,
FQDN, admin username. End user closes the ticket.

**Instance:** Red Hat shared ServiceNow dev (URL TBD — capture in `docs/dev-environment.md` when obtained).

- ⬜ Capture Red Hat shared SNow URL + access credentials in `docs/dev-environment.md`
- ⬜ ServiceNow catalog item: "Request Windows VM (Azure)"
  - ⬜ Variables: `vm_size_tier` (dropdown small/medium/large), `justification` (text), `requestor` (auto-populated)
  - ⬜ Flow Designer flow: REST POST to AAP `/api/v2/job_templates/<id>/launch/` with extra_vars
- ⬜ AAP credential: `DC1.Azure - ServiceNow Callback` (HTTP token / Source Control type) for AAP→SNow callbacks
- ⬜ AAP workflow: add a final "Update ServiceNow RITM" JT that PATCHes the RITM Table record with status + IP + FQDN
- ⬜ `playbooks/servicenow_update_ritm.yml` — reusable callback playbook using `servicenow.itsm` collection
- ⬜ `aap_config/files/controller_credentials.yml` — add ServiceNow callback credential entry
- ⬜ `aap_config/files/controller_templates.yml` — add Update RITM JT
- ⬜ `aap_config/files/controller_templates_workflow.yml` — wire callback into Provision-and-Configure workflow
- ⬜ End-to-end test: file a request in SNow self-service → watch RITM update → confirm VM exists → close RITM
- ⬜ `docs/demo-runbook.md` — v2 section covering the SNow-driven flow alongside v1 (AAP-driven)

**Open questions for Phase 8 (decide during phase execution):**
- Connection direction: SNow polls AAP (simpler) vs AAP calls SNow back (richer UX; requires AAP→SNow cred)
- Time-out behavior: what does the RITM show if Azure provisioning hangs at 9 minutes (workflow time-out)?
- Auth from SNow to AAP: mid-server vs direct REST (mid-server is enterprise-standard but more setup)

**Exit criteria:** a user with zero prior context can request a Windows VM through the SNow self-service portal, receive a fulfilled RITM with the IP + admin credentials, and RDP into a working Windows machine.

---

## Naming Conventions

To avoid collision with existing `demo.datacenter` (AWS) objects in shared AAP instances:

| Object type        | Pattern                                  | Example                              |
|--------------------|------------------------------------------|--------------------------------------|
| AAP credential     | `DC1.Azure - <purpose>`                  | `DC1.Azure - Azure RM`               |
| AAP project        | `DC1.Azure`                              | `DC1.Azure`                          |
| AAP inventory      | `dc1-azure`                              | `dc1-azure`                          |
| AAP job template   | `DC1.Azure - <verb> <object>`            | `DC1.Azure - Provision VM`           |
| AAP workflow       | `DC1.Azure - <story>`                    | `DC1.Azure - Provision and Configure`|
| Azure VM           | `dc1-azure-win-<tier>-<short_id>`        | `dc1-azure-win-medium-a1b2`          |
| Azure resource tag | `Environment=demo`, `Project=dc1.azure`, `Owner=ericcames` |        |
| ADO work item      | `[Phase N] <task>`                       | `[Phase 2] Write azurerm Terraform`  |

---

## Decisions Log

| Date       | Decision                                                       | Rationale |
|------------|----------------------------------------------------------------|-----------|
| 2026-05-21 | ADO org name = `ericcames`                                     | Matches GitHub handle, consistent personal brand |
| 2026-05-21 | VM tiers = `D2s_v5` / `D4s_v5` / `D8s_v5`                      | Same Dsv5 family — clean "more cores" story; no burstable-vs-dedicated nuance |
| 2026-05-21 | Windows Server 2025 Datacenter                                 | Newest; aligns with `demo.datacenter` AD instance moving to win25 |
| 2026-05-21 | Terraform state in Azure Storage backend                       | Survives EE recycle, supports locking, idiomatic for Azure |
| 2026-05-21 | AAP→Azure auth via Service Principal                           | Works for both Terraform and `azcollection`; standard pattern |
| 2026-05-21 | ADO usage = Repos + lint/validate Pipeline                     | AAP keeps orchestration ownership; ADO adds code-quality value without duplicating provisioning logic |
| 2026-05-21 | Demo narrative = self-service Windows VM                       | Strongest single-VM story; ties survey UX to a tangible business outcome |
| 2026-05-21 | Issue tracking via ADO Boards work items                       | Hands-on ADO Boards experience; tracking lives next to the code |
| 2026-05-21 | Post-provision roles = powershell_improvement, windows_account_create, website_setup, windows_patching | Covers PS baseline, identity, visible result (IIS), and patching story |
| 2026-05-21 | Roadmap lives in dc1.azure repo only                           | Departs from "central in aap.as.code" convention — dc1.azure is a sibling effort, not a DC1 sub-layer |
| 2026-05-21 | CaC pattern = `url_checker`-style `aap_config/` at repo root   | More discoverable for new users (single self-contained dir at top level) than `aap.as.code`'s `playbooks/files/config_as_code/`; matches upstream `infra.aap_configuration` recommended layout |
| 2026-05-21 | Two install paths: `docs/INSTALL.md` (manual) + `.claude/skills/install-dc1-azure/` (Claude Code skill) | Skill ships co-located with the repo, auto-loaded when Claude runs in dir — no plugin marketplace install. Doc covers the no-AI path |
| 2026-05-21 | `playbooks/bootstrap_aap.yml` is transitional; will be removed once `aap_config/load.yml` is canonical | Avoids two competing install entry-points; admin-password bootstrap was a stepping stone |
| 2026-05-21 | ServiceNow instance = Red Hat shared dev (URL TBD)             | Avoids PDI hibernation cycle; production-like shared SNow environment |
| 2026-05-21 | dc1.azure IS the canonical "Windows on Azure" story            | `aap.dailydemo.windows` stays AWS-only (covered by demo.datacenter). SNow integration sits on top of dc1.azure — no need to fork the daily-demo repo for cloud parity |

---

## Risks / Open Questions

- **RHDP Azure open-env quota** — needs verification that `D8s_v5` (8 vCPU) fits within open-env quota. Mitigation: slide tiers down one notch (B2s / D2s_v5 / D4s_v5) if not.
- **Windows Server 2025 WinRM bootstrap on Azure** — Azure marketplace image may not have WinRM enabled by default. Mitigation: `custom_data` PowerShell snippet enables WinRM-HTTPS + opens firewall on first boot.
- **`infra.aap_configuration` Azure RM credential support** — ✅ verified 2026-05-21: `Microsoft Azure Resource Manager` credential type works via `ansible.controller.credential` with `inputs.subscription/tenant/client/secret`. Re-verify the same fields are accepted by `infra.aap_configuration.controller_credentials` role.
- **ADO PAT expiration** — 90-day PATs require rotation. Mitigation: documented in runbook + a calendar reminder; future enhancement could use a workload-identity federation pattern.
- **Open-env lifespan** — RHDP envs are time-limited. Mitigation: teardown JT keeps Azure spend predictable; demo runbook starts with a "is the env still alive?" check.
- **AAP object collision in shared instances** — multiple SEs may share an AAP instance. Mitigation: `DC1.Azure -` prefix on every named object.
- **AAP personal token expiration** (Phase 3 new) — `aap_config/load.yml` requires the user to create a personal token in AAP UI first. Tokens are user-scoped and expire (configurable, default 365 days). Mitigation: install doc + skill prompt user to check token validity; future enhancement could fall back to admin-password auth when token is absent.
- **Red Hat shared SNow availability** (Phase 8 new) — shared instance means shared state (other SEs' catalog items, flows). Risk of conflicts or accidental changes. Mitigation: namespace SNow objects with `dc1.azure - ` prefix (mirror our AAP naming). Confirm with the SNow admin before standing up the catalog item.
- **AAP→SNow callback complexity** (Phase 8 new) — RITM update requires a SNow credential in AAP plus the `servicenow.itsm` collection. Risk: time-out behavior when Azure provisioning hangs > workflow time-out leaves RITM in an indeterminate state. Mitigation: explicit failure-path JT that updates RITM with `Failed` + error context.
- **`aap.dailydemo.windows` role compatibility with Azure VMs** (Phase 4 reaffirmation) — roles assume an AWS-provisioned Windows box (likely AWS-specific tags or metadata service calls). Mitigation: review each of the 4 roles' tasks before importing; vendor + adapt locally if upstream isn't cloud-agnostic.

---

## Reference Repositories

| Repo | Role in dc1.azure |
|------|--------------------|
| [demo.datacenter](https://github.com/ericcames/demo.datacenter) | AWS sibling — source for Terraform patterns and overall DC1 conventions |
| [aap.as.code](https://github.com/ericcames/aap.as.code) | Source for AAP bootstrap patterns; `bootstrap_aap.yml` is the Azure-flavored adaptation |
| [aap.dailydemo.windows](https://github.com/ericcames/aap.dailydemo.windows) | Upstream of the four post-provision Windows roles |
| [aap.aws.infrastructure](https://github.com/ericcames/aap.aws.infrastructure) | Reference for AWS-side IaaS structure being replaced by Azure equivalents |

---

## Status Legend

- ✅ Complete
- 🔄 In progress
- ⬜ Not started

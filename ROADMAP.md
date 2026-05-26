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

- **Stands independently of `aap.as.code`** — dc1.azure must install and run
  without any sibling repo checked out. It borrows *patterns* from
  `aap.as.code` / `demo.datacenter`, never a runtime or repo-level dependency.
  This is what lets it drop into the Ansible Product Demo cleanly.
- **`infra.aap_configuration` collection is the guide** — follow the
  collection's own docs and recommended layout over the `aap.as.code` repo
  wherever the collection prescribes a pattern. Name each CaC variable file
  after the **role/module it feeds** (`controller_credentials.yml` →
  `controller_credentials` role) so the authoritative variable schema is one
  README away.
- **Deviate only where the platform demands it** — Azure-native services
  (Storage backend for Terraform state, Azure RM credential type, ADO
  Pipelines) replace their AWS/GitHub equivalents; the *shape* of the
  automation stays the same.
- **Single VM, single story** — no platform sprawl. Layer 0 + a Windows
  workload is the entire scope.
- **AAP is the orchestrator** — even with ADO Pipelines in the picture, ADO
  handles code quality (lint/validate) only. All provisioning,
  configuration, and teardown runs from AAP. Matches the AWS DC1 split.
- **One core workflow, four triggers** — the demo exposes a single
  survey-driven, API-launchable workflow. Each entry point (AAP UI, AAP
  Self-Service Portal, ServiceNow catalog, Azure DevOps) is a *thin adapter*
  in front of that one workflow — never a parallel re-implementation.
- **Retain the proven Windows configure workflow** — the post-provision half
  reuses the working roles from `aap.dailydemo.windows` (sourced via a pinned
  git reference, not rewritten). dc1.azure adds the Azure *provision* half in
  front of them.
- **CaC for every AAP object** — credentials, projects, inventories, job
  templates, workflows defined under `aap_config/` and applied via
  `infra.aap_configuration.dispatch`. (`playbooks/bootstrap_aap.yml` is a
  deprecated stopgap pending the `aap_config/` path being verified.)
- **Repo-based Claude skills, not marketplace** — setup/install skills live in
  `.claude/skills/` committed in this repo, so the demo carries its own
  tooling and doesn't depend on a marketplace plugin being installed.
- **Ship `ansible.cfg.example`, never a live `ansible.cfg`** — Ansible loads
  exactly one cfg (no merge), so a *live* project-local `ansible.cfg` shadows
  the user's home cfg and breaks `ansible-galaxy` install of Hub-certified
  content. A committed `ansible.cfg.example` (never auto-loaded) encodes the
  canonical `galaxy_server` stanza; the repo-based setup skill writes it to the
  user's standard local path.
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

> **Runtime AAP:** dc1.azure installs additively onto the AAP provisioned by
> the **Ansible Product Demo** RHDP catalog item — it targets the EE/orgs that
> AAP already provides and namespaces its own objects `DC1.Azure -`. It does
> *not* require the `ansible/product-demos` repo layout.

**Demo triggers — four entry points, one workflow:**

```
   AAP UI               ─┐
   AAP Self-Service Portal─┤
   ServiceNow catalog   ─┼──►  launch  "DC1.Azure - Provision and Configure"
   Azure DevOps pipeline ─┘            (the single AAP workflow above)
```

Each trigger is a thin adapter that launches the same survey-driven,
API-launchable workflow — no parallel re-implementations.

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
- ✅ `collections/requirements.yml` pinning `infra.aap_configuration` 4.2.0, plus `azure.azcollection`, `ansible.windows`, `community.windows` *(bumped to 4.4.0 in Phase 3 — see Decisions Log 2026-05-26)*
- ✅ **No** *live* project-local `ansible.cfg` *(a committed `ansible.cfg.example` template is added in Phase 3 — never auto-loaded, so it doesn't shadow the home cfg)*
- ✅ `.gitignore` covering `*.tfstate*`, `.terraform/`, `*.tfvars` (except `*.tfvars.example`), `__pycache__`, `.DS_Store`

**Exit criteria:** repo opens cleanly in VS Code, `ansible-galaxy collection install -r collections/requirements.yml` succeeds against Eric's `~/.ansible.cfg`.

### Phase 2 — Terraform: Azure Windows VM  ✅
*Code complete 2026-05-21 (commit 2848f54); smoke test passed 2026-05-21 against RHDP env (`openenv-blsvm-1`, `eastus`). Three real design bugs discovered + fixed inline.*

- ✅ `providers.tf` — `azurerm` provider + `azurerm` remote state backend
- ✅ `backend.tf` — Storage Account / container / key for state (uses partial backend config; storage account bootstrap is a separate follow-up — for the smoke test, local state was used per the documented escape hatch in `backend.tf`)
- ✅ `variables.tf` — `vm_size_tier`, `location`, `resource_group_name`, `admin_username`, `admin_password` (sensitive), `tags`
- ✅ `locals.tf` — t-shirt → SKU map (see table above)
- ✅ `main.tf` — VNet, Subnet, NSG (5986 + 3389), Public IP, NIC, `azurerm_windows_virtual_machine` (image `MicrosoftWindowsServer:WindowsServer:2025-datacenter-azure-edition:latest`), `custom_data` (via `terraform/scripts/winrm_bootstrap.ps1`) deposits the script, `azurerm_virtual_machine_extension` (CustomScriptExtension) triggers execution, opens WinRM-HTTPS firewall on first boot
- ✅ `outputs.tf` — `public_ip`, `fqdn`, `admin_username`, `vm_size_chosen`
- ✅ `terraform.tfvars.example` documenting required inputs
- ✅ Manual smoke test against RHDP env (2026-05-21): `terraform init && plan && apply` with `vm_size_tier=small` provisioned a reachable Windows Server 2025 VM (public IP `20.127.118.198`, FQDN `dc1az-small-uf29p.eastus.cloudapp.azure.com`); WinRM-HTTPS port 5986 verified open + TLS handshake succeeds + HTTP 405 confirms WinRM listener responding; `terraform destroy` cleaned all 9 resources

**Bugs discovered + fixed during the smoke test:**
- **`patch_mode` required for hotpatch-enabled images** — Windows Server 2025 Azure Edition is a hotpatch image; azurerm v4.x fails the VM create unless `patch_mode = "AutomaticByPlatform"` + `hotpatching_enabled = true` are set explicitly on the `azurerm_windows_virtual_machine` resource. Added to `main.tf`.
- **`custom_data` does not auto-execute on Windows** — Azure deposits the bootstrap script at `C:\AzureData\CustomData.bin` but does NOT execute it (unlike Linux cloud-init). Without an `azurerm_virtual_machine_extension` of type `CustomScriptExtension`, WinRM is never configured and port 5986 stays closed. Extension added to `main.tf` to copy `CustomData.bin` → `bootstrap.ps1` and execute via PowerShell.
- **`cmd.exe /c winrm create ...` mangles under SYSTEM context** — the original `winrm_bootstrap.ps1` shelled out to `cmd.exe` to create the HTTPS listener with a quoted ValueSet containing the cert thumbprint. When the CustomScriptExtension runs the script as SYSTEM, the nested quoting collapses and the listener is created with an empty `CertificateThumbprint`. Replaced with PowerShell-native `New-WSManInstance` which avoids the cmd.exe quoting hazard entirely.

**Exit criteria:** `terraform apply` from Eric's laptop produces a reachable Windows VM in the RHDP open env; `destroy` cleans it up; state lives in Azure Storage. *(Storage-backend bootstrap is a separate follow-up issue — local-state path is documented in `backend.tf`.)*

### Phase 3 — AAP Configuration as Code  🔄

Pattern (revised 2026-05-26): a self-contained `aap_config/` directory at the
repo root, dispatched via `infra.aap_configuration.dispatch`, following the
**upstream `infra.aap_configuration` collection's own recommended layout** —
the collection's docs are the guide, not `aap.as.code`. Each variable file is
named after the **role it feeds**, so the authoritative variable schema for any
file is that role's README in the collection. Collection pinned to **4.4.0**
(the release available in Red Hat Automation Hub; installs via the existing Hub
token — no galaxy.ansible.com). Role names below to be confirmed against 4.4.0.

**Implementation — canonical path** (`aap_config/`):

- ⬜ `aap_config/load.yml` — entry-point playbook; `include_role: infra.aap_configuration.dispatch`
- ⬜ `aap_config/requirements.yml` — pin `infra.aap_configuration` **4.4.0**
- ⬜ `aap_config/README.md` — one-page explanation of the pattern, env vars required, command to run
- ⬜ `aap_config/inventory/aap.yml` — localhost only (CaC playbook runs locally and talks to AAP via API)
- ⬜ `aap_config/group_vars/all.yml` — `AAP_HOSTNAME` + `AAP_TOKEN` env-var lookups (user creates a personal token in AAP UI first); `AZURE_*` + `ADO_PAT` lookups for credential inputs; vault password from a **dc1.azure-owned vault source** (own vault-id / env var provisioned by the repo-based setup skill — *not* the borrowed `~/.ansible/secrets2` path)
- ⬜ `aap_config/files/controller_credentials.yml` — 4 credentials (Vault, Azure RM, ADO SCM, Windows Machine)
- ⬜ `aap_config/files/controller_projects.yml` — DC1.Azure project syncing from ADO
- ⬜ `aap_config/files/controller_inventories.yml` — dc1-azure inventory with empty `windows` group (populated at runtime by Provision JT via `add_host` + `set_stats`)
- ⬜ `aap_config/files/controller_job_templates.yml` — 3 JTs (Provision, Configure, Teardown) with surveys
- ⬜ `aap_config/files/controller_workflow_job_templates.yml` — "Provision and Configure" workflow chaining Provision → Configure with artifact passing
- ⬜ Post-load validation step (per global rule: never exit green without verifying every object exists)

**Standalone-setup prerequisites (built here, documented in Phase 7):**

- ⬜ `ansible.cfg.example` at repo root — encodes the canonical `galaxy_server`
  (Automation Hub) stanza; the setup skill writes it to the user's standard
  local path. Never commit a *live* `ansible.cfg`.
- ⬜ Carve `.claude/skills/` out of `.gitignore` so the repo-based setup/install
  skill can be committed (replaces the marketplace `/aap-first-time` skill).

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

### Phase 4 — Post-Provision Playbooks  🔄
*Code built 2026-05-26 (PR #5). Live end-to-end run deferred until the target EE + AAP/Controller credential are confirmed on the Product Demo AAP.*

- ✅ `playbooks/provision_vm.yml` — runs `terraform init/apply` (CLI + `output -json`) for the survey's `vm_size_tier`, parses the `ansible_inventory` Terraform output, then **registers the VM into the `dc1-azure` inventory's `windemo` group via the controller API** (short-lived token created + deleted in `always:`, mirroring the `aap.dailydemo.windows` `inventory` role) and `set_stats` for the workflow. Replaces the AWS provisioning nodes.
- ✅ Configure half is **not** a new `configure_windows.yml` — it reuses the pinned `aap.dailydemo.windows` project's existing playbooks via the Phase 3 Configure JTs (`05_powershell_improve` / `06_website_setup` / `06_windows_account_create` / `07_windows_patching`), which target `hosts: windemo`. This is what "retain the existing workflow" means in practice.
- ✅ `playbooks/teardown.yml` — `terraform destroy` + deregisters the host from the inventory (token lifecycle in `always:`).
- ✅ New `DC1.Azure - Controller` (Red Hat AAP) credential added to `aap_config/` and attached to the Provision/Teardown JTs so they can call the controller API. RG/location passed as JT `extra_vars` from env-baked group vars.
- ⬜ **Live run** against the Product Demo AAP: needs the Windows-capable EE name (`DC1_AZURE_EE`) with the `terraform` binary, the Controller credential populated, and the admin password synced between Terraform and the `DC1.Azure - Windows Machine` credential.

**Open design note:** host hand-off uses explicit controller-API registration (mirrors the daily demo). A future alternative is an `azure_rm` dynamic inventory source on `dc1-azure` that auto-discovers the tagged VM — removes the Controller credential + registration step, but needs `azure.azcollection` in the EE.

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

### Phase 9 — AAP Self-Service Portal Trigger  ⬜

The second of the four triggers (AAP UI = Phase 6, ServiceNow = Phase 8). The
AAP platform Self-Service Portal surfaces the existing "DC1.Azure - Provision
and Configure" workflow to non-admin end users — same survey, simplified UX, no
new workflow.

- ⬜ Expose the DC1.Azure workflow in the Self-Service Portal (publish/surface the existing workflow + survey; no re-implementation)
- ⬜ Confirm a non-admin user with only Self-Service access can launch it and see status
- ⬜ Verify the survey (vm_size_tier) renders and passes through to the same workflow the other triggers use
- ⬜ `docs/demo-runbook.md` — Self-Service Portal section (screenshots of the portal launch + result)

**Exit criteria:** a non-admin user launches the same Windows-VM workflow from the Self-Service Portal and gets an identical result to the AAP-UI path.

### Phase 10 — Azure DevOps Trigger  ⬜

The fourth trigger. Distinct from Phase 5 (which uses ADO Pipelines for
lint/validate CI + GitHub mirror): here an ADO pipeline *launches* the AAP
workflow on demand.

- ⬜ `azure-pipelines-launch.yml` — parameterized/manual-trigger pipeline (parameter: `vm_size_tier`) that POSTs to the AAP `/api/v2/workflow_job_templates/<id>/launch/` endpoint with `extra_vars`
- ⬜ AAP auth from the pipeline via a secured pipeline variable / Service Connection holding an AAP token — never inline in YAML (mirror the no-inline-creds rule from Phase 0.5)
- ⬜ Confirm the launched run is the *same* workflow the other three triggers use (no parallel definition)
- ⬜ `docs/demo-runbook.md` — ADO-trigger section

**Exit criteria:** running the launch pipeline in ADO (picking a size) provisions a Windows VM via the same AAP workflow, with run status observable from ADO.

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
| 2026-05-26 | Pin `infra.aap_configuration` to **4.4.0**                      | Newest release available in Red Hat Automation Hub — installs via the existing Hub `galaxy_server` token, no galaxy.ansible.com. Supersedes the 4.2.0 pin and the earlier "4.5.0+" note |
| 2026-05-26 | dc1.azure stands **independent of `aap.as.code`**              | Destined for the Ansible Product Demo; can't assume a sibling repo is checked out. Borrow patterns, not a runtime/repo dependency |
| 2026-05-26 | `infra.aap_configuration` collection docs are the guide; CaC var files named per role/module | Collection READMEs are the authoritative variable schema and lead aap.as.code; file↔role-doc mapping becomes 1:1 |
| 2026-05-26 | Runtime AAP = the **Ansible Product Demo** RHDP catalog item's AAP | "Loaded into the Ansible Product Demo" means it *runs on that AAP* (install additively, namespaced). Does NOT impose the `ansible/product-demos` repo layout |
| 2026-05-26 | **One core workflow, four triggers** (AAP UI · Self-Service Portal · ServiceNow · Azure DevOps) | Trigger-agnostic core + thin adapters avoids four parallel implementations; keeps the demo Product-Demo-portable |
| 2026-05-26 | Reuse `aap.dailydemo.windows` roles via a **pinned git reference** | Reuses proven code, stays DRY, AAP installs on sync — keeps dc1.azure standalone. Vendor only as fallback |
| 2026-05-26 | Vault password from a **dc1.azure-owned vault source** (option 2) | Self-contained setup consistent with standalone goal; drops the borrowed `~/.ansible/secrets2` path |
| 2026-05-26 | Ship `ansible.cfg.example` (never a live cfg); **repo-based** Claude skills | Example encodes the canonical Hub `galaxy_server` stanza without shadowing the home cfg; in-repo skills replace the marketplace `/aap-first-time`, completing independence |

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
| [aap.as.code](https://github.com/ericcames/aap.as.code) | Pattern reference only — dc1.azure stands independent (Decisions Log 2026-05-26). The `infra.aap_configuration` collection's own docs are the primary CaC guide |
| [infra.aap_configuration](https://github.com/redhat-cop/infra.aap_configuration) | **Primary CaC guide** — pinned 4.4.0; `aap_config/` follows its recommended layout; var files named per its roles |
| [aap.dailydemo.windows](https://github.com/ericcames/aap.dailydemo.windows) | Source of the reused post-provision Windows roles (pinned git reference, not vendored) |
| [aap.aws.infrastructure](https://github.com/ericcames/aap.aws.infrastructure) | Reference for AWS-side IaaS structure being replaced by Azure equivalents |

---

## Status Legend

- ✅ Complete
- 🔄 In progress
- ⬜ Not started

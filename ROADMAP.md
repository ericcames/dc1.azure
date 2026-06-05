# DC1 Azure — Datacenter on Azure Demo Roadmap

## Vision

`dc1.azure` is the Azure-cloud expression of the DC1 demo pattern. Where
[`demo.datacenter`](https://github.com/ericcames/demo.datacenter) builds a
virtual datacenter on AWS, `dc1.azure` delivers a parallel, presentable
Microsoft-stack story:

> *"Same automation. Same self-service experience. Your cloud, your tools."*

The narrative target is **self-service VM provisioning on Azure** — Windows
Server 2025 and/or RHEL 9 Linux — driven by an end user picking a t-shirt size
and OS type in an AAP survey and getting fully configured, monitored VMs in
~10 minutes. The source code lives in Azure DevOps Repos and is gated by an
Azure DevOps Pipeline.

The platform grows in layers: **provision** (Terraform) → **configure**
(Windows IIS / Linux Apache web server) → **monitor** (Dynatrace OneAgent) →
**load balance** (F5 BIG-IP VE) → **patch** (F5-aware rolling patching). Each
layer is a demo story on its own and composes with the others.

`dc1.azure` started intentionally scoped smaller than `demo.datacenter` — a
single Windows VM, a focused story, and a chance to build hands-on Azure + ADO
muscle. It is now growing toward a multi-OS, load-balanced, monitored
environment while keeping the same "one workflow, four triggers" architecture.

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
- **Single VM, single story** — no platform sprawl. Layer 0 + a Linux or
  Windows workload is the entire scope.
- **AAP is the orchestrator** — even with ADO Pipelines in the picture, ADO
  handles code quality (lint/validate) only. All provisioning,
  configuration, and teardown runs from AAP. Matches the AWS DC1 split.
- **One core workflow, four triggers** — the demo exposes a single
  survey-driven, API-launchable workflow. Each entry point (AAP UI, AAP
  Self-Service Portal, ServiceNow catalog, Azure DevOps) is a *thin adapter*
  in front of that one workflow — never a parallel re-implementation.
- **Retain the proven configure workflows** — Windows post-provision reuses
  the working roles from `aap.dailydemo.windows`; Linux uses the Apache
  pattern from `aap.dailydemo.F5` (both sourced via pinned git references,
  not rewritten). dc1.azure adds the Azure *provision* half in front of them.
- **CaC for every AAP object** — credentials, projects, inventories, job
  templates, workflows defined under `aap_config/` and applied via
  `infra.aap_configuration.dispatch`.
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

> **All four triggers are live and validated** (AAP UI — Phase 6 ✅; ServiceNow —
> Phase 8 ✅; Self-Service Portal — Phase 9 ✅; Azure DevOps — Phase 10 ✅), each
> launching the one `DC1.Azure - Provision and Configure` workflow.

---

## Sizing Tiers

The provisioning JT survey asks for `vm_size_tier`. Mapping is enforced in
Terraform `locals.tf`:

| Tier              | Azure SKU       | vCPU | RAM   | Windows $/hr | Use case                |
|-------------------|-----------------|------|-------|--------------|-------------------------|
| `small-2cpu-4gb`  | `Standard_B2s`  | 2    | 4 GB  | ~$0.07       | Dev / quick smoke test  |
| `medium-2cpu-8gb` | `Standard_B2ms` | 2    | 8 GB  | ~$0.11       | Default demo path       |
| `large-4cpu-16gb` | `Standard_B4ms` | 4    | 16 GB | ~$0.22       | "Production-like" story |

> **Why B-series?** B-series (burstable) VMs are cheaper (~60-70% less than
> DSv5), sufficient for demo workloads (IIS/Apache serving a landing page),
> and — critically — use their **own separate vCPU quota** in RHDP open
> environments. This frees the DSv5 quota for the Phase 19 F5 BIG-IP appliance.
> `os_type=both` at `large-4cpu-16gb` = 8 vCPUs, well within the 10-vCPU
> B-series quota. Nightly teardown caps a forgotten VM at one evening (~$1–5).

All three are in the B-series (burstable) family — right-sized for demo
workloads that are mostly idle between customer page loads.

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

### Phase 0.5 — ADO Operating Conventions  ✅
*Completed 2026-05-26. Make `dc1.azure` read as a mature dev-team project to an ADO-fluent customer audience. Chunk A (in-repo files) landed 2026-05-21 in commit e0c826f; Chunk B (ADO UI / az devops CLI work) landed 2026-05-21. Build-validation branch policy (AB#48) and GitHub auto-mirror (AB#49) landed 2026-05-26 — all exit criteria met.*

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
- ✅ Require Build validation = Phase 5 pipeline pass — registered pipeline + Build Validation policy added (AB#48, 2026-05-26)
- ✅ Block direct push to `main` — implicit consequence of the four blocking policies being in place (2026-05-21)
- ✅ Squash-only merge strategy — policy ID 5 (2026-05-21)
- ✅ **Bonus:** Comments must be resolved before merge — policy ID 4 (2026-05-21; not on the original list but worth keeping)

**PR template + commit conventions:**
- ✅ `.azuredevops/pull_request_template.md` — sections: *Summary*, *Work item*, *Test plan*, *Risk / rollback* (2026-05-21)
- ✅ Document `AB#<id>` autolink syntax in `CONTRIBUTING.md` — added explicit autolink-mechanics section + pointer to the PR template (2026-05-21)
- ✅ `CODEOWNERS` file mapping `/terraform/` → @ericcames, `/playbooks/` → @ericcames, `/aap_config/` → @ericcames + catch-all + governance docs (2026-05-21). Note: ADO doesn't natively parse `CODEOWNERS` — file works AS-IS on the GitHub mirror; ADO enforcement happens via the "Automatically include code reviewers" branch policy (see `docs/ado-conventions.md`).

**Service Connections + Library (replace inline creds):**
- ✅ Create **Azure Resource Manager** service connection `dc1-azure-rhdp-sp` from the RHDP Service Principal — id `<rhdp-sp-app-id>`, IsReady true (2026-05-21)
- ✅ Create **GitHub** service connection `github-ericcames` for the Phase 5 auto-mirror push — PAT created + service connection registered (AB#49, 2026-05-26)
- ✅ Create **Variable Group** `dc1-azure-shared` in Library — id 1, 4 variables (`location=eastus`, `resource_group_name=<rhdp-resource-group>`, `subscription_id`, `storage_account_name=REPLACE_ME_TF_STATE_SA`), authorized for all pipelines (2026-05-21)
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
*Code complete 2026-05-21 (commit 2848f54); smoke test passed 2026-05-21 against RHDP env (`<rhdp-resource-group>`, `eastus`). Three real design bugs discovered + fixed inline.*

- ✅ `providers.tf` — `azurerm` provider + `azurerm` remote state backend
- ✅ `backend.tf` — Storage Account / container / key for state (uses partial backend config; storage account bootstrap is a separate follow-up — for the smoke test, local state was used per the documented escape hatch in `backend.tf`)
- ✅ `variables.tf` — `vm_size_tier`, `location`, `resource_group_name`, `admin_username`, `admin_password` (sensitive), `tags`
- ✅ `locals.tf` — t-shirt → SKU map (see table above)
- ✅ `main.tf` — VNet, Subnet, NSG (5986 + 3389), Public IP, NIC, `azurerm_windows_virtual_machine` (image `MicrosoftWindowsServer:WindowsServer:2025-datacenter-azure-edition:latest`), `custom_data` (via `terraform/scripts/winrm_bootstrap.ps1`) deposits the script, `azurerm_virtual_machine_extension` (CustomScriptExtension) triggers execution, opens WinRM-HTTPS firewall on first boot
- ✅ `outputs.tf` — `public_ip`, `fqdn`, `admin_username`, `vm_size_chosen`
- ✅ `terraform.tfvars.example` documenting required inputs
- ✅ Manual smoke test against RHDP env (2026-05-21): `terraform init && plan && apply` with `vm_size_tier=small` provisioned a reachable Windows Server 2025 VM (public IP `<vm-public-ip>`, FQDN `dc1az-small-<suffix>.eastus.cloudapp.azure.com`); WinRM-HTTPS port 5986 verified open + TLS handshake succeeds + HTTP 405 confirms WinRM listener responding; `terraform destroy` cleaned all 9 resources

**Bugs discovered + fixed during the smoke test:**
- **`patch_mode` required for hotpatch-enabled images** — Windows Server 2025 Azure Edition is a hotpatch image; azurerm v4.x fails the VM create unless `patch_mode = "AutomaticByPlatform"` + `hotpatching_enabled = true` are set explicitly on the `azurerm_windows_virtual_machine` resource. Added to `main.tf`.
- **`custom_data` does not auto-execute on Windows** — Azure deposits the bootstrap script at `C:\AzureData\CustomData.bin` but does NOT execute it (unlike Linux cloud-init). Without an `azurerm_virtual_machine_extension` of type `CustomScriptExtension`, WinRM is never configured and port 5986 stays closed. Extension added to `main.tf` to copy `CustomData.bin` → `bootstrap.ps1` and execute via PowerShell.
- **`cmd.exe /c winrm create ...` mangles under SYSTEM context** — the original `winrm_bootstrap.ps1` shelled out to `cmd.exe` to create the HTTPS listener with a quoted ValueSet containing the cert thumbprint. When the CustomScriptExtension runs the script as SYSTEM, the nested quoting collapses and the listener is created with an empty `CertificateThumbprint`. Replaced with PowerShell-native `New-WSManInstance` which avoids the cmd.exe quoting hazard entirely.

**Exit criteria:** `terraform apply` from Eric's laptop produces a reachable Windows VM in the RHDP open env; `destroy` cleans it up; state lives in Azure Storage. *(Storage-backend bootstrap is a separate follow-up issue — local-state path is documented in `backend.tf`.)*

### Phase 3 — AAP Configuration as Code  ✅
*Completed 2026-05-26. First live `load.yml` run: `ok=80 changed=15 failed=0`; `validate.yml` confirmed all objects created. Gateway, EDA, and credential-type files from `aap.as.code` merged (PR #10, AB#51). `my_organization = "IT Service Automation"`.*

Pattern: a self-contained `aap_config/` directory at the repo root, dispatched
via `infra.aap_configuration.dispatch`, following the **upstream
`infra.aap_configuration` collection's own recommended layout**. Each variable
file is named after the **role it feeds**. Collection pinned to **4.4.0**.

**Implementation — canonical path** (`aap_config/`):

- ✅ `aap_config/load.yml` — entry-point playbook; `infra.aap_configuration.dispatch`
- ✅ `aap_config/requirements.yml` — pin `infra.aap_configuration` **4.4.0**
- ✅ `aap_config/README.md` — pattern explanation, env vars, run command
- ✅ `aap_config/inventory/aap.yml` — localhost only
- ✅ `aap_config/group_vars/all.yml` — all env-var lookups; `my_organization = "IT Service Automation"`
- ✅ `aap_config/files/controller_credentials.yml` — 5 credentials (Vault, Azure RM, ADO SCM, Windows Machine, Controller)
- ✅ `aap_config/files/controller_projects.yml` — DC1.Azure + aap.dailydemo.windows projects
- ✅ `aap_config/files/controller_inventories.yml` — dc1-azure inventory
- ✅ `aap_config/files/controller_job_templates.yml` — 6 JTs (Provision, 4 Configure, Teardown)
- ✅ `aap_config/files/controller_workflow_job_templates.yml` — Provision and Configure workflow
- ✅ `aap_config/files/gateway_settings.yml` — platform gateway settings (token, expiry, proxy, login banner)
- ✅ `aap_config/files/gateway_organizations.yml` — 6 orgs with Hub Galaxy credentials
- ✅ `aap_config/files/gateway_teams.yml` — Network / Server / Storage / ITO teams
- ✅ `aap_config/files/eda_projects.yml` — event.driven.ansible EDA project
- ✅ `aap_config/files/controller_credential_types.yml` — ServiceNow ITSM custom type
- ✅ `validate.yml` — post-dispatch validation asserts every object exists

**Standalone-setup prerequisites:**

- ✅ `ansible.cfg.example` at repo root — canonical Hub `galaxy_server` stanza; never auto-loaded
- ✅ `.claude/skills/` carved out of `.gitignore` so the install skill ships with the repo

**Transition / deprecation:**

- ✅ Deprecation banner added to `playbooks/bootstrap_aap.yml` (2026-05-21)
- ✅ Removed `playbooks/bootstrap_aap.yml` and its dedicated `inventories/dc1-azure/` bootstrap inventory (2026-06-02, AB#102) — `aap_config/load.yml` is the proven canonical path (run live via the `install-dc1-azure` skill)

**Exit criteria:** ✅ Met 2026-05-26. `load.yml` run green against Ansible Product Demo AAP; all objects created; `validate.yml` passed; re-run is idempotent.

### Phase 4 — Post-Provision Playbooks  ✅
*Completed 2026-05-27. End-to-end workflow validated green (workflow job 46, ~14 min).*

- ✅ `playbooks/provision_vm.yml` — runs `terraform init/apply` (CLI + `output -json`) for the survey's `vm_size_tier`, parses the `ansible_inventory` Terraform output, then **registers the VM into the `dc1-azure` inventory's `windemo` group via the controller API** (short-lived token created + deleted in `always:`, mirroring the `aap.dailydemo.windows` `inventory` role) and `set_stats` for the workflow. Replaces the AWS provisioning nodes.
- ✅ `playbooks/website_setup.yml` + `playbooks/roles/website_setup_azure/` (AB#59) — Azure-specific IIS role with a clean `index.html.j2` using `inventory_hostname`, `vm_size_tier`, `dc1_azure_location`, and `ticket_number | default('N/A')` (placeholder until ServiceNow integration). Replaces the AWS-only `website_setup` role from `aap.dailydemo.windows`.
- ✅ Configure half: `05_powershell_improve` / `06_windows_account_create` / `07_windows_patching` still reuse pinned `aap.dailydemo.windows` playbooks; `06_website_setup` replaced by the dc1.azure-native role above.
- ✅ `playbooks/teardown.yml` — `terraform destroy` + deregisters the host from the inventory (token lifecycle in `always:`).
- ✅ New `DC1.Azure - Controller` (Red Hat AAP) credential attached to Provision/Teardown JTs for controller API calls. RG/location passed as JT `extra_vars` from env-baked group vars.
- ✅ EE pulls from Private Automation Hub (AB#56). Terraform authenticates via `ARM_*` env vars mapped from AAP Azure RM credential (AB#57). Nightly teardown schedule added (AB#58).
- ✅ **Windows Admin Password** (AB#60) — `DC1.Azure - Windows Admin Password` custom credential type injects `dc1_azure_windows_admin_password` as an extra var. `WINDOWS_ADMIN_PASSWORD` is the single source of truth.
- ✅ **Demo Account Password** (AB#59) — `DC1.Azure - Demo Account Password` custom credential type injects `default_passwd` extra var for the Provision Access JT. Sourced from `DC1_AZURE_DEFAULT_PASSWD` in `dev-environment.sh`. No survey prompt at workflow launch.
- ✅ **VM size tier choices** (AB#62) — choices renamed `small-2cpu-8gb / medium-4cpu-16gb / large-8cpu-32gb`; spec visible in AAP survey Multiple Choice Options field. `terraform/locals.tf` and `terraform/variables.tf` keys updated to match.
- ✅ **Validation run bugs fixed** (AB#65/66/67) — `provision_vm.yml` assert + `terraform/variables.tf` validation rule both used old tier names; `website_setup_azure` role was at project root `roles/` (AWX EE searches `<playbook_dir>/roles/`). All three fixed.

**Open design note:** host hand-off uses explicit controller-API registration (mirrors the daily demo). A future alternative is an `azure_rm` dynamic inventory source on `dc1-azure` that auto-discovers the tagged VM — removes the Controller credential + registration step, but needs `azure.azcollection` in the EE.

**Exit criteria:** ✅ Met 2026-05-27. End-to-end workflow run (job 46) produced a VM serving an IIS page on its public IP, with the demo accounts, PS7, and Windows Update applied.

### Phase 5 — Azure DevOps Pipeline  ✅
*Completed 2026-05-26. Lint/validate pipeline (PR #7), Build Validation branch policy (AB#48), and GitHub auto-mirror stage (AB#49) all landed. Pipeline verified green on every PR since. `git push github main` is retired — mirror runs automatically on every merge to `main`.*

**Work:**

- ✅ `azure-pipelines.yml` — two stages: **Lint** (`yamllint`, `ansible-lint`, `terraform fmt -check`, `terraform validate -backend=false`) always runs; **Mirror** pushes `main` to GitHub via `GITHUB_PAT`, skipped on PRs.
- ✅ `.yamllint` + `.ansible-lint` configs — yamllint line-length warning at 200; ansible-lint `production` profile, `offline` (no Hub token in CI).
- ✅ **Build-validation branch policy on `main`** — pipeline registered (ID 1) + Build Validation policy added (AB#48, 2026-05-26). Every PR now gates on Lint.
- ✅ **Auto-mirror to GitHub** — Mirror stage in `azure-pipelines.yml`; `github-ericcames` GitHub service connection + `GITHUB_PAT` secret pipeline variable (AB#49, 2026-05-26). Verified: run 7 mirrored the PR #10 merge automatically.

**Exit criteria:** ✅ Met 2026-05-26. PRs trigger the Lint gate; merging to `main` mirrors to GitHub within ~1 minute; no manual `git push github main` needed.

### Phase 6 — Demo Runbook (v1 — AAP-driven)  ✅
- ✅ `docs/demo-runbook.md` — SE-facing live-demo script for the AAP-driven flow (AB#76); has since grown to cover all four triggers (§7 ServiceNow, §8 Self-Service, §9 ADO)
- ✅ Persona framing, click-by-click flow through AAP UI, talking points, expected timings (from live runs: provision ~10 min, teardown ~7 min)
- ✅ Failure-mode appendix (Azure quota, WinRM not up, project sync, expired token, teardown)
- ✅ `docs/images/` — full demo-00..08 screenshot set captured (2026-06-02) and embedded; live identifiers redacted per policy (capture checklist in Appendix B of the runbook)

**Exit criteria:** ✅ Met. The runbook drives the demo end-to-end from the AAP UI; screenshots captured and embedded. *(A cold dry-run off the runbook is still a nice-to-have but the script is complete and live-proven.)*

### Phase 7 — Install Documentation (manual + Claude Code skill)  ✅
*Completed 2026-05-26. Docs + skill written (PR #6); acceptance test passed via first live `load.yml` run using the `/install-dc1-azure` skill (2026-05-26). Lessons from the live run captured in a follow-up PR (PR #9, AB#50).*

Two paths to install dc1.azure into a working RHDP AAP: a manual path for
human-only operators, and a Claude Code skill that drives the install
interactively.

- ✅ `docs/INSTALL.md` — manual install: prerequisites (incl. §2.5 Hub Galaxy credentials), `ansible.cfg.example` → `~/.ansible.cfg`, collection install, full env-var table (incl. `CONTROLLER_HOST`/`CONTROLLER_OAUTH_TOKEN`/`CONTROLLER_VERIFY_SSL`), `aap_config/load.yml` run, post-install launch, troubleshooting table
- ✅ `.claude/skills/install-dc1-azure/SKILL.md` — repo-based skill: checks Hub Galaxy credentials on Default org, creates/deletes the gateway v1 token, prompts for missing env vars **by name only**, runs all exports + playbook in one shell call, deletes token after green run
- ✅ `README.md` — Getting Started points at both paths; stale "not wired up" notes removed
- ✅ Aligned `WINDOWS_ADMIN_USERNAME` default (`demoadmin`) to Terraform's `admin_username` default
- ✅ Acceptance test: `/install-dc1-azure` skill drove the first live AAP run 2026-05-26 — `ok=80 changed=15 failed=0`, `validate.yml` passed

**Exit criteria:** ✅ Met 2026-05-26. First-time install completed via the Claude Code skill without consulting source code beyond what the skill prompted.

### Phase 8 — ServiceNow Integration (Demo v2)  ✅

End-state demo flow: business user goes to ServiceNow self-service catalog,
requests a Windows VM (Azure), picks size, submits. SNow triggers the
dc1.azure workflow in AAP. AAP runs Terraform + post-provision. On success,
AAP calls back to ServiceNow to update the RITM with status, public IP,
FQDN, admin username. End user closes the ticket.

**Instance:** Red Hat shared ServiceNow dev — instance URL + `SN_HOST`/`SN_USERNAME`/`SN_PASSWORD` are captured in `docs/dev-environment.sh` (gitignored); `EDA_EVENT_STREAM_TOKEN` minted there too. EDA verified enabled on the AAP (2026-05-28).

Inbound is **event-driven** (EDA), not a direct REST launch: a ServiceNow
Business Rule → Outbound REST Message → AAP EDA event stream → dc1.azure-owned
rulebook → `run_workflow_template`. See [`docs/servicenow-integration.md`](docs/servicenow-integration.md).

- ✅ Capture Red Hat shared SNow URL + access creds + `EDA_EVENT_STREAM_TOKEN` in `docs/dev-environment.sh` (`SN_*` + minted token present)
- ✅ ServiceNow catalog item: "Request Windows VM (Azure)" — `vm_size_tier` Multiple Choice + recurring prices; pinned `short_description` = `DC1.Azure Windows VM on Azure` *(built in SNow UI; as-built captured in `servicenow/` + `docs/servicenow-integration.md`)*
- ✅ ServiceNow Business Rule + Outbound REST Message → EDA event-stream URL (Bearer token) *(built; hardened script in [`servicenow/business_rules/fire_eda_on_ritm.js`](servicenow/business_rules/fire_eda_on_ritm.js))*
- ✅ EDA ingress (CaC) (**AB#81, PR #40**): `ansible.eda` in `aap_config/requirements.yml`; `DC1.Azure - EDA` project (this repo); `rulebooks/servicenow_events.yml`; `eda_credentials.yml` (event-stream + Controller + EDA SCM creds); `eda_event_streams.yml`; `eda_rulebook_activations.yml`. *(Reuses the platform's built-in Default Decision Environment — no `eda_decision_environments.yml` needed.)*
- ✅ Callback / CMDB / incident (full Windows parity) (**AB#83, PR #42**) — `DC1.Azure - ServiceNow` ITSM credential + five JTs (Create CMDB CI, Create CMDB Relationship, Update RITM success/failure, Create Incident). *(Uses dc1.azure-owned guarded playbooks under `playbooks/servicenow/`, not the Windows project's — they no-op without `ticket_number` so non-SNow triggers stay green.)*
- ✅ Wire workflow nodes (mirror DDW) (**AB#83 + AB#84, PR #42/#43**): CMDB CI branches off Provision VM success (parallel, early); Patching `always`→Update RITM (success); Provision VM failure→Create Incident→Update RITM (failure)
- ✅ `provision_vm.yml` — `set_stats` FQDN/IP/admin/size/ticket for the callback + CMDB nodes (**AB#83, PR #42**)
- ✅ `validate.yml` — assert the new EDA objects + creds + JTs (**AB#81/AB#83**)
- ✅ `docs/demo-runbook.md` v2 section (runbook §7, ServiceNow-driven variant)
- ✅ **EE rebuild + push** — hardened EE (AB#86, errata + `servicenow.itsm`) pushed `quay.io/zigfreed/dc1-azure-ee@sha256:4423a10…`, PAH-synced, Controller EE pull policy set; the callback JTs run on it (2026-06-02)
- ✅ **Start-notice — two-way link at launch** (AB#94, PR #51) — root node writes the AAP workflow job ID + deep link back to the RITM (comment + work note) and the reverse `snow_ritm_url` onto the AAP job
- ✅ **Inbound-trigger CaC live-fixes** (AB#91, PR #49) — `my_organization` in the activation extra_vars, `ask_variables_on_launch` on the workflow, EE pull policy
- ✅ **End-to-end validated live (2026-06-02)** — **success:** ServiceNow order → workflow green → CMDB CI + relationship → RITM **Closed Complete** with IP/FQDN/admin (RITM0011938). **Failure:** forced Provision VM failure → **INC0011350** opened → RITM **Closed Incomplete** (RITM0011931). Request-state mappings confirmed (`3`=Closed Complete, `4`=Closed Incomplete)

**Open questions — RESOLVED (see [`docs/servicenow-integration.md`](docs/servicenow-integration.md)):**
- Inbound trigger → **EDA event stream** (Business Rule → Outbound REST → rulebook → `run_workflow_template`); SNow holds no workflow ID/launch token. *(Revised 2026-05-28 from the original direct-REST decision.)*
- Rulebook home → **dc1.azure-owned rulebook** (no cross-repo PR into `event.driven.ansible`).
- EDA project git URL → the **Azure DevOps repo** (PAT-backed SCM credential).
- Result direction → **AAP calls SNow back** (reuses the `ServiceNow ITSM Credential` type).
- Callback scope → **full Windows parity** (RITM + CMDB CI `cmdb_ci_win_server` + relationship + Incident-on-failure).
- Timeout behavior → callback runs on **both success and failure paths**; RITM never hangs.

**Progress:**
- ✅ `docs/servicenow-integration.md` — design v1 written (AB#78), then **redesigned to event-driven Demo v2** (EDA event stream + full Windows parity); decisions above resolved.
- ✅ **Implementation merged** — inbound EDA ingress (AB#81, PR #40), outbound callback/CMDB/incident (AB#83, PR #42), workflow layout mirroring DDW (AB#84, PR #43), and the self-managing CaC token (AB#85, PR #44) are all on `main`. `EDA_EVENT_STREAM_TOKEN` minted; `SN_*` creds in `docs/dev-environment.sh`.
- ✅ **Operational steps done (2026-06-02):** EE hardened + pushed + PAH-synced; SNow catalog item + Business Rule + Outbound REST Message built (as-built in `servicenow/`); start-notice two-way link added (AB#94); inbound-trigger CaC live-fixes captured (AB#91).
- ✅ **Validated end-to-end live (2026-06-02)** — success + failure paths both proven (see checklist above).
- ✅ **Follow-ups — all shipped:** AB#92 hardened the live SNow config (hardened Business Rule deployed + plaintext bearer moved to an encrypted `sys_property`, PR #61); AB#93 related the CMDB CI to the RITM via `configuration_item` (PR #53, live-validated RITM0011939); AB#95 EE deliberate-update model (`pull: missing` + immutable semver tags, PR #63, replacing the AB#91 `pull: always` placeholder).
- ⬜ **Only remaining (external blocker):** the Quay security-scan before/after table in `ee-security-remediation.md` awaits Quay's Clair scanning coming back online (down since 2026-06-01) — not a code item.

**Exit criteria:** ✅ Met 2026-06-02. A user requests a Windows VM through the ServiceNow catalog, the workflow provisions + configures it, and the RITM is auto-fulfilled with IP/FQDN/admin (RDP-ready); a failed provision opens an Incident and marks the RITM Closed Incomplete.

### Phase 9 — AAP Self-Service Portal Trigger  ✅

*Validated live 2026-06-03 — `jr-dev` self-served a VM from the portal (launcher job 151 → workflow job 152).*

The second of the four triggers (AAP UI = Phase 6, ServiceNow = Phase 8). The
AAP platform Self-Service Portal (Red Hat Developer Hub) surfaces the existing
"DC1.Azure - Provision and Configure" workflow to non-admin end users — same
survey, simplified UX, no new workflow.

**Scope split:** the portal itself (RHDH `redhat-rhaap-portal` Helm chart on
OpenShift) is the **`aap.selfservice`** repo's job — dc1.azure **references** it
(pinned), it is not vendored here. dc1.azure owns only the **AAP RBAC** + a thin
launcher JT (see the finding below): the portal lets all authenticated users
browse templates; AAP enforces Execute at launch, so RBAC is the control point.

> **KEY FINDING (2026-06-03): the portal surfaces JOB templates only — NOT
> workflow JTs.** Proven live (with an identical team-level grant, a team-granted
> *job* template surfaced for `jr-dev` while the team-granted *workflow* did not;
> the backend provider is `AAPJobTemplateProvider`) and confirmed in Red Hat's
> **2.6** docs ("job templates … are synced … fetches updates for auto-generated
> self-service templates only"). This is a product-design choice — newer charts
> (2.2.0) do **not** add workflow support. So the workflow can't be launched from
> the portal directly; Phase 9 bridges it with a **launcher job template**.

- ✅ **Verify-first** — found the portal surfaces **job** templates only, not
  workflows (see finding above). The earlier "workflow surfaces" read was a false
  positive (those were the job templates).
- ✅ **RBAC as Config-as-Code** (AB#107) — `DC1.Azure - Developers` team; users
  `dev-lead` (Organization Admin) + `jr-dev` (least-privilege); team holds Execute
  via membership. Validated live: `jr-dev` can Start only what it's granted, can't
  edit; `dev-lead` is full admin.
- ✅ **Launcher JT** — `DC1.Azure - Request Windows VM` (job template, `vm_size_tier`
  survey) runs `playbooks/launch_workflow.yml` (`ansible.controller.workflow_launch`)
  that fires the existing `DC1.Azure - Provision and Configure` workflow with the tier
  passed through. Surfaces in the portal; team gets Execute on it. No parallel workflow.
- ✅ End-to-end (2026-06-03): `jr-dev` Started the launcher JT **from the portal UI** →
  launcher job 151 fired workflow job 152 → VM provisioned. Least-privilege proven
  (jr-dev sees only the launcher + facts JTs).
- ✅ `docs/demo-runbook.md` — Self-Service Portal section (§8) with portal-launch
  screenshots (demo-09..12).

**Exit criteria:** ✅ Met 2026-06-03. A non-admin user (`jr-dev`) triggers the same
Windows-VM workflow from the Self-Service Portal (via the launcher JT) and gets an
identical result to the AAP-UI path.

### Phase 10 — Azure DevOps Trigger  ✅

*Validated live 2026-06-03. The fourth and final trigger is proven end-to-end.*

The fourth trigger. Distinct from Phase 5 (which uses ADO Pipelines for
lint/validate CI + GitHub mirror): here an ADO pipeline *launches* the AAP
workflow on demand.

- ✅ `azure-pipelines-launch.yml` (AB#110) — manual-trigger pipeline (`trigger:`/`pr: none`) with a `vm_size_tier` queue-time parameter (small/medium/large dropdown). Resolves the workflow **by name** (`GET …/workflow_job_templates/?name=…`) rather than hardcoding the env-specific id, then POSTs `extra_vars: {vm_size_tier}` to `…/workflow_job_templates/<id>/launch/`. Fire-and-forget: prints the workflow-job deep link and uploads it to the ADO run summary (`task.uploadsummary`), mirroring the other three triggers (the Phase 9 launcher JT uses `wait: false`).
- ✅ AAP auth from the pipeline via the new ADO **Variable Group** `dc1-azure-aap` (`AAP_HOSTNAME` + secret `AAP_TOKEN`, UI-minted) — referenced with `variables: - group:`, never inline in YAML (mirrors the no-inline-creds rule from Phase 0.5). The secret token is mapped to the script env explicitly. Documented in `docs/ado-conventions.md`.
- ✅ Same workflow as the other three triggers — the pipeline launches `DC1.Azure - Provision and Configure` by name; no parallel definition.
- ✅ `docs/demo-runbook.md` — ADO-trigger section (§9).

- ✅ **Operational setup done (2026-06-03):** `dc1-azure-aap` Variable Group created in the Library (`AAP_HOSTNAME` + secret UI-minted `AAP_TOKEN`); pipeline registered as *DC1.Azure — Launch Windows VM*; the pipeline→variable-group authorization granted on first run.
- ✅ **Live-found fix (AB#111):** the launch step initially 404'd because it used the legacy `/api/v2` Controller base; corrected to `/api/controller/v2` (the AAP 2.5 gateway path) — the path used everywhere else in this repo.

**Exit criteria:** ✅ **Met 2026-06-03.** ADO run *DC1.Azure — Launch Windows VM* (`large-8cpu-32gb`) → AAP launch API → **workflow job 163** (`DC1.Azure - Provision and Configure`, id 28 — the *same* workflow the other three triggers use). All nodes succeeded; the guarded ServiceNow nodes correctly no-op'd on this ticket-less ADO launch. Run status observable from ADO via the workflow-job deep link uploaded to the run summary.

### Phase 11 — Fact Caching & Inventory Visibility  🔄

A value/demo-story phase (distinct from the Phases 9/10 *triggers*): show
customers and sellers the Ansible facts AAP collects about a host — both
**persisted in the AAP database** (queryable per-host inventory data that
re-stamps every run, so you can narrate drift) and **printed to the job log**
(a curated, narratable summary). Fact storage is one of AAP's strongest
"show, don't tell" capabilities and is rarely known by non-admins.

- ✅ **v1 (now): standalone JT** — `DC1.Azure - Gather and Display Facts`
  (`use_fact_cache: true`) running this repo's `playbooks/gather_facts.yml`
  against the provisioned Windows VM. Prints a curated summary (OS, CPU, memory,
  IPs, domain, last boot); a `show_full_facts` survey toggle dumps the complete
  set. Full facts land in the AAP DB (Infrastructure → Hosts → Facts).
- ⬜ **v2: wire into the provision workflow** — add the fact-gather as a final
  node on `DC1.Azure - Provision and Configure` so facts auto-populate right
  after a VM is built (additive; the standalone JT stays).
- ⬜ **v3: CMDB enrichment** — feed the curated facts into the Phase 8
  ServiceNow CMDB CI created on provision (closes the loop: AAP-discovered truth
  enriching the system of record).
- ⬜ `docs/demo-runbook.md` — Facts section (job-log summary + the per-host
  Facts tab in the UI).

**Exit criteria (v1):** launching `DC1.Azure - Gather and Display Facts` against
the VM prints the curated summary to the job log AND the host's Facts tab in the
AAP UI shows the timestamped, persisted fact set.

### Phase 12 — Automate the ADO Trigger Setup (AAP-driven)  ✅

*Post-demo addition (2026-06-03). Phase 10 proved the ADO launch trigger, but its
wiring was hand-built in the ADO UI: the `dc1-azure-aap` Variable Group
(`AAP_HOSTNAME` + secret `AAP_TOKEN`), the registered* DC1.Azure — Launch Windows VM
*pipeline, and the pipeline→variable-group authorization. Each fresh Ansible
Product Demo env changes the AAP hostname + token, so today those values are
re-entered by hand. This phase makes the ADO side **Config-as-Code driven from
AAP** — a playbook/role that creates the pipeline + variable group on a clean ADO
project (the "new" path) and idempotently re-points them when the env changes (the
"update" path).*

- ⬜ `playbooks/ado/` role(s) that, given `ADO_ORG` / `ADO_PROJECT` / `ADO_PAT` and
  the current `AAP_HOSTNAME` / `AAP_TOKEN`: create-or-update the `dc1-azure-aap`
  Variable Group (secret `AAP_TOKEN`), register/update the
  *DC1.Azure — Launch Windows VM* pipeline pointing at `azure-pipelines-launch.yml`,
  and grant the pipeline→variable-group authorization. Both the **new** (fresh
  project) and **update** (re-point existing) paths idempotent.
- ⬜ `DC1.Azure - Configure ADO Trigger` JT wrapping the role, run during env
  bring-up. ADO PAT supplied via a custom credential type (mirrors the
  `DC1.Azure - Windows Admin Password` pattern), not a survey.
- ✅ **ADO driver — RESOLVED (AB#121): the ADO REST API via `ansible.builtin.uri`**,
  not the `az devops` CLI. The pipeline→variable-group authorization step
  (`pipelinePermissions`) has **no `az` command**, so REST is unavoidable for at
  least one step — using it for all three (Variable Group, pipeline, authorization)
  beats mixing two tools. `uri` is also built-in (zero new EE deps) and matches the
  repo's existing playbook→API pattern. See Decisions Log 2026-06-03.
- ⬜ Keep the manual UI steps documented in `docs/ado-conventions.md` as the
  no-AAP fallback (additive-only).
- ⬜ A check (in `validate.yml` or the JT) asserts the Variable Group + pipeline
  exist and point at the live AAP.
- ⬜ `docs/demo-runbook.md` / `docs/ado-conventions.md` updated.

**Exit criteria:** on a fresh ADO project (or after an env swap), one JT run
produces a working *DC1.Azure — Launch Windows VM* pipeline whose Variable Group
points at the current AAP, and a manual pipeline run launches the workflow — with
zero ADO-UI clicks.

### Phase 13 — Automate the ServiceNow Outbound REST Message (AAP-driven)  ⬜

*Post-demo addition (2026-06-03). Phase 8's inbound trigger relies on a SNow
Business Rule → Outbound REST Message whose endpoint is the AAP **EDA event-stream
URL** and whose auth is a **bearer token** (now in an encrypted `sys_property`,
AB#92). Both are per-env: a fresh install mints a new event stream + token, so today
the REST Message is hand-edited in the SNow UI. This phase makes AAP update SNow —
a playbook/role that sets the `sys_rest_message` endpoint + the encrypted token
property to match the freshly-installed EDA activation.*

- ⬜ `playbooks/servicenow/configure_outbound_rest.yml` + role: given `SN_*` creds,
  the current EDA event-stream URL, and `EDA_EVENT_STREAM_TOKEN`, create-or-update
  the Outbound REST Message record (`sys_rest_message` / `sys_rest_message_fn`)
  endpoint and the encrypted bearer `sys_property`; optionally ensure the Business
  Rule exists (its JS already lives in
  [`servicenow/business_rules/fire_eda_on_ritm.js`](servicenow/business_rules/fire_eda_on_ritm.js)).
- ⬜ Source the event-stream URL **programmatically** from the just-applied EDA
  event stream (controller/EDA API) rather than a hand-copied value — closes the
  "new env → new URL" loop.
- ✅ **SNow driver — RESOLVED (AB#125): `servicenow.itsm.api`** (the collection's
  generic Table API module — already in the EE and already used for the Phase 8 CMDB
  CI patch), **not** raw `ansible.builtin.uri`. The "servicenow.itsm can't reach
  `sys_rest_message`" worry was a false dichotomy — the `api` module *is* the Table
  API and reaches any table the user's roles allow. Live PoC confirmed the `SN_*`
  user has the **admin** role, so it can write `sys_rest_message` /
  `sys_rest_message_fn` / the `dc1.eda_event_stream_token` (`password2`) property. NB
  the endpoint lives on the `sys_rest_message_fn` (function) record, not the parent;
  every write must be `sys_id`-scoped + `Ames -`-namespaced (33 other-SE REST
  Messages share the instance). See Decisions Log 2026-06-03.
- ⬜ `DC1.Azure - Configure SNow Trigger` JT wrapping it; reuse the existing
  `DC1.Azure - ServiceNow` ITSM credential / `SN_*` creds.
- ⬜ Keep the manual SNow-UI build documented in `docs/servicenow-integration.md`
  + `servicenow/README.md` as the no-AAP fallback (additive-only).
- ⬜ A check asserts the REST Message endpoint matches the live EDA URL.

**Exit criteria:** after a fresh install on a new env, one JT run updates the SNow
Outbound REST Message to the new EDA event-stream URL + token, and a catalog order
fires the workflow — with zero SNow-UI edits.

### Phase 14 — Fresh-Env End-to-End Validation  ⬜

*Post-demo addition (2026-06-03). Spin a brand-new Ansible Product Demo RHDP env
and prove the whole thing cold — now that env bring-up is fully automatable
(Phases 12–13 remove the last manual ADO/SNow UI steps).*

- ⬜ Activate a fresh Product Demo + Azure open env; capture identifiers only in
  `docs/dev-environment.sh` (gitignored) — placeholder/redact in any commit.
- ⬜ Run install (`/install-dc1-azure` → `load.yml`) green; `validate.yml` passes.
- ⬜ Run the Phase 12 ADO-config JT + Phase 13 SNow-config JT → ADO + SNow
  re-pointed at the new env.
- ⬜ Exercise all four triggers green: AAP UI, Self-Service Portal, ServiceNow
  catalog order (**Eric places the order** per convention), ADO launch pipeline.
  Confirm the guarded SNow nodes fire on the SNow path and no-op on the others.
- ⬜ Teardown verified clean (no lingering Azure spend); ad-hoc tokens cleaned up
  (never the operator SA token).
- ⬜ Capture any live-only fixes back into CaC (the recurring "lint never
  exercises a live launch" lesson — see AB#91/AB#111).

**Exit criteria:** a from-scratch env reaches "all four triggers green" using only
automation + documented one-shot JT runs — no UI click-throughs for ADO or SNow
wiring.

### Phase 15 — Claude Skills Expansion  ⬜

*Post-demo addition (2026-06-03). Today the repo ships one skill
(`install-dc1-azure`), which assumes prerequisites are already met. Add the skills
that cover the rest of the lifecycle, all repo-based (Decisions Log 2026-05-26 —
repo-based, not marketplace).*

- ⬜ **`first-time-setup`** — prerequisites walkthrough for a brand-new user:
  validates the `~/.ansible.cfg` Hub `galaxy_server` stanza, collection install,
  `docs/dev-environment.sh` from the `.example`, and each Azure SP / RHDP RG / ADO
  PAT / SNow / EDA-token var (**by name only**), one at a time, before handing off
  to `install-dc1-azure`. The repo-based replacement for the marketplace
  `aap-first-time`.
- ⬜ **`spin-env`** — full fresh-env bring-up (the Phase 14 cold-run as a skill):
  `load.yml` install → Phase 12 ADO-config JT → Phase 13 SNow-config JT → validate
  all four triggers.
- ⬜ **`demo-readiness`** — SE-facing preflight: confirms **this** env is demo-ready
  before standing in front of a customer (namespaced objects exist, the EDA
  activation is running, the SNow REST Message points at this env's EDA URL, the ADO
  Variable Group/pipeline are present, the nightly teardown schedule is armed).
  Emits a go/no-go checklist.
- ⬜ **`teardown`** — run the Teardown JT, verify zero Azure spend, and clean up
  ad-hoc tokens (never the operator SA token).

**Exit criteria:** a brand-new user can go from a fresh laptop to a validated
four-trigger demo using only the repo-based skills, and an SE can confirm
demo-readiness (and tear down afterward) without hand-checking the AAP / SNow / ADO
UIs.

### Phase 16 — Linux VM Provisioning (Terraform + Multi-OS Survey)  ✅

*Extends the Terraform layer to provision RHEL 9 Linux VMs alongside — or instead
of — the existing Windows Server 2025 VMs. The workflow survey gains an `os_type`
parameter so a single launch can produce Windows only, Linux only, or both.*

Reference pattern: `aap.dailydemo.F5` (AWS Linux web-server provisioning).

- ⬜ **Terraform: `azurerm_linux_virtual_machine`** — RHEL 9 image from Azure
  Marketplace (`RedHat:RHEL:9-lvm-gen2:latest`), SSH key auth via `admin_ssh_key`
  block, `cloud-init` for first-boot config (replaces the Windows
  `custom_data` + `CustomScriptExtension` pattern). Same VNet/Subnet/NSG.
- ⬜ **NSG: SSH rule** — port 22 inbound (alongside existing RDP 3389, WinRM 5986).
- ⬜ **Survey: `os_type`** — new survey variable on the workflow with choices
  `windows` / `linux` / `both` (default `windows` for backward compatibility).
  `provision_vm.yml` passes `os_type` to Terraform; Terraform uses `count` (or
  `for_each`) to conditionally create the Windows VM, Linux VM, or both. Each VM
  gets its own Public IP + NIC.
- ⬜ **`locals.tf`: Linux SKU map** — same `Dsv5` family tiers (the Linux base rate
  is ~half the Windows PAYG rate — good demo talking point for Hybrid Benefit).
- ⬜ **`outputs.tf`** — Linux public IP, FQDN, admin username; structured so
  `provision_vm.yml` can parse and register both hosts.
- ⬜ **Inventory registration** — `provision_vm.yml` registers the Linux VM into a
  `linuxweb` group in the `dc1-azure` inventory (alongside the existing `windemo`
  group for Windows).
- ⬜ **Machine credential** — `DC1.Azure - Linux Machine` (Machine credential type,
  SSH key-based).
- ⬜ **Teardown** — `teardown.yml` destroys all VMs regardless of `os_type`; host
  deregistration covers both groups.

**Exit criteria:** `terraform apply` with `os_type=both` produces a reachable
Windows VM (WinRM) + a reachable Linux VM (SSH) in the same VNet; `os_type=linux`
produces only the Linux VM; `os_type=windows` produces only the Windows VM (backward
compatible). Both register into the AAP inventory under their respective groups.

### Phase 17 — Linux Post-Provision Configuration (Web Server)  ✅

*Configures the provisioned RHEL 9 VM as an Apache web server — mirroring the
`aap.dailydemo.F5` pattern (RHSM → post-install → website setup) with Red Hat CDN
registration instead of Satellite.*

Reference pattern: `aap.dailydemo.F5` roles — `rhsm`, `linux_post_install`,
`website_setup`.

- ⬜ **RHSM / CDN registration** — deferred (activation key ready). Azure PAYG
  RHEL images have RHUI access for dnf updates; RHSM registration requires EE
  rebuild (`redhat.rhel_system_roles`) + new credential type. Will add as a
  follow-up.
- ✅ **Linux post-install** — combined `linux_configure` role handles SSH banner,
  MOTD, and `dnf` security/bugfix updates. Chrony and Insights deferred with RHSM.
- ✅ **Website setup** — `linux_configure` role installs Apache (`httpd`),
  `firewalld` (port 80), and deploys a dc1.azure-branded `index.html` showing
  hostname, OS, tier, ticket number — mirrors the Windows IIS page layout.
- ✅ **Job template** — single combined `DC1.Azure - Configure Linux` JT with
  `cred_linux` credential, targeting `linuxweb` group. Consolidates post-install +
  website setup into one step (role chain is short enough for a single JT).
- ✅ **Workflow node** — `configure-linux` fires after `provision-vm` success in
  parallel with the Windows chain, limited to `linuxweb`. Both paths converge at
  `update-ritm-success` (`all_parents_must_converge: true`). When an OS is absent
  its chain targets an empty group (no-op).
- ✅ **Inventory groups** — `provision_vm.yml` now creates both `windemo` and
  `linuxweb` groups unconditionally so workflow nodes with limit always resolve.
- ⬜ **EE update** — deferred with RHSM; current EE has all needed collections
  (`ansible.posix` for `firewalld`).
- ⬜ **Collections** — deferred with RHSM; `redhat.rhel_system_roles` not needed
  until RHSM registration is added.

**Exit criteria:** a workflow launch with `os_type=linux` (or `both`) produces a
RHEL 9 VM patched, running Apache on port 80, and serving a dc1.azure-branded page
at its public IP. RHSM/CDN registration deferred to a follow-up.

### Phase 18 — Dynatrace OneAgent Integration  ⬜

*Installs Dynatrace OneAgent on every provisioned VM so hosts appear in the
Dynatrace tenant and can generate real problems — closing the loop with the
[`aap.eda.dynatrace.push`](https://github.com/ericcames/aap.eda.dynatrace.push)
EDA demo (push model — Dynatrace pushes problem events to AAP EDA via webhook)
(GitHub Issue #1).*

The Dynatrace SaaS tenant (`ybz84624.live.dynatrace.com`) is always on.

- ⬜ **Custom credential type** — `DC1.Azure - Dynatrace` injecting `DT_API_HOST`
  (the `.live.dynatrace.com` tenant URL) and `DT_PAAS_TOKEN` (installer download
  token — generated in the Dynatrace UI under Deploy > OneAgent). Sourced from
  `docs/dev-environment.sh` env vars (already added).
- ⬜ **Playbook: `playbooks/dynatrace_oneagent.yml`** — OS-aware installer:
  - **Windows:** PowerShell — download via the OneAgent deployment API
    (`/api/v1/deployment/installer/agent/windows/default/latest`), run
    `Dynatrace-OneAgent.exe` with `/TENANT_URL` + `/PAAS_TOKEN` + `/HOST_GROUP`.
  - **Linux:** shell — download via
    `/api/v1/deployment/installer/agent/unix/default/latest`, run with
    `--set-host-group` + `--set-infra-only=false`.
- ⬜ **Host group tagging** — register hosts in a `dc1-azure` host group so the
  `aap.eda.dynatrace` rulebook's metric event (`builtin:host.disk.usedPct > 80%`)
  can be scoped to dc1.azure-provisioned VMs.
- ⬜ **Workflow node** — after the VM is reachable and configured (post-configure,
  pre-patching). Runs against both Windows and Linux hosts.
- ⬜ **Job template** — `DC1.Azure - Install Dynatrace OneAgent`, attached to the
  Dynatrace credential.
- ⬜ **`docs/dev-environment.sh.example`** — Dynatrace section already added
  (`DT_API_HOST` + `DT_PAAS_TOKEN`).
- ⬜ `validate.yml` — assert the credential type + credential + JT exist.
- ⬜ `docs/demo-runbook.md` — Dynatrace section (verify host appears in the
  Dynatrace Hosts app after provisioning).

**Exit criteria:** after provisioning, each new VM (Windows and/or Linux) is visible
in the Dynatrace tenant's Hosts app under the `dc1-azure` host group. Filling a
host's disk past 80% opens a "High Disk Usage" problem — which Dynatrace pushes to
the `aap.eda.dynatrace.push` EDA event stream, firing the remediation workflow.

### Phase 19 — F5 Load Balancing on Azure  ⬜

*Deploys an F5 BIG-IP Virtual Edition on Azure and places the Linux web servers
behind it — bringing the proven `aap.dailydemo.F5` load-balancing and patching
workflow to the Azure platform.*

Reference pattern: `aap.dailydemo.F5` — pool/VIP setup (`f5networks.f5_modules`),
patching workflow (disable pool member → stop httpd → dnf update → health check →
restart httpd → re-enable pool member).

- ⬜ **F5 BIG-IP VE on Azure** — Azure Marketplace PAYG image (GOOD tier = LTM
  only; 30-day free trial). Terraform resource or the official
  `F5Networks/bigip-module/azure` module. Management NIC + data NIC in the existing
  VNet.
- ⬜ **Marketplace term acceptance** — `az vm image terms accept --publisher
  f5-networks ...`. Risk: RHDP open environments grant Contributor on the RG only;
  term acceptance is a subscription-level operation. Needs early validation.
- ⬜ **F5 post-deploy configuration** — `f5networks.f5_modules` collection:
  - Pool: `bigip_pool` with HTTP health monitor
  - Pool members: Linux web-server VMs (port 80)
  - Virtual server: public VIP (port 80/443) → pool
  - Profiles: HTTP, client-SSL (optional)
- ⬜ **Credential** — `DC1.Azure - F5 BIG-IP` (Network credential type, or custom
  type with management IP + admin password).
- ⬜ **Patching workflow** — reuse the `aap.dailydemo.F5` pattern:
  1. Pre-checks (pool check, web check)
  2. Disable pool member (`bigip_pool_member` → `forced_offline`)
  3. Stop httpd → `dnf update` (security/bugfix) → health check → reboot if needed
  4. Start httpd → HTTP health probe (retry until 200)
  5. Re-enable pool member (`bigip_pool_member` → `present`)
  6. Post-checks
- ⬜ **Job templates** — `DC1.Azure - Setup F5 Pool`, `DC1.Azure - F5 Patching`
  (or a patching workflow with approval node, mirroring the daily demo).
- ⬜ **Collections** — add `f5networks.f5_modules` to `collections/requirements.yml`.
  EE version bump.
- ⬜ **Survey integration** — the provision workflow optionally deploys F5 when
  `os_type` includes `linux` (F5 requires pool members).

**Exit criteria:** F5 BIG-IP VE running on Azure with a VIP fronting the Linux web
servers; the patching workflow gracefully drains a pool member, patches it, health
checks, and re-enables it — matching the proven `aap.dailydemo.F5` pattern on Azure
infrastructure.

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
| Azure VM (Windows) | `dc1-azure-win-<tier>-<short_id>`        | `dc1-azure-win-medium-a1b2`          |
| Azure VM (Linux)   | `dc1-azure-lin-<tier>-<short_id>`        | `dc1-azure-lin-medium-a1b2`          |
| Azure resource tag | `Environment=demo`, `Project=dc1.azure`, `Owner=ericcames` |        |
| Dynatrace host grp | `dc1-azure`                              | —                                     |
| F5 pool            | `dc1-azure-web-pool`                     | —                                     |
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
| 2026-05-27 | Custom EE (`execution-environment.yml`) built with ansible-builder v3 on `ee-minimal-rhel9:2.17.14` + **Terraform 1.15.4** | Phase 4 blocker — default EE lacks `terraform`; one EE covers all six JTs (Terraform for Provision/Teardown, pywinrm from azure.azcollection for Windows Configure) |
| 2026-05-27 | EE image hosted on **quay.io** (public) as `quay.io/zigfreed/dc1-azure-ee:latest`; Hub syncs from quay.io; Controller points to Hub (or quay.io directly via `DC1_AZURE_EE_IMAGE` override) | quay.io = always-accessible source; Hub copy = enterprise demo story; `DC1_AZURE_EE_IMAGE` env var lets either work without code changes |
| 2026-05-27 | EE registration in Controller handled by **CaC** (`aap_config/files/controller_execution_environments.yml` + `hub_ee_registries.yml` + `hub_ee_repositories.yml`) | Eliminates the only remaining manual bootstrap step for Phase 4; `load.yml` is now fully self-contained for a fresh env |
| 2026-05-27 | **`DC1.Azure - Windows Admin Password` custom credential type** (AB#60) replaces the workflow survey `dc1_azure_windows_admin_password` question | Credential type injects the password as an extra var — zero friction at workflow launch. `WINDOWS_ADMIN_PASSWORD` env var covers both Machine credential (WinRM) and custom credential (Terraform) |
| 2026-05-27 | **VM size tier choices** renamed `small-2cpu-8gb / medium-4cpu-16gb / large-8cpu-32gb` (AB#62) | Choice string = Terraform map key; DNS-label-safe format makes the spec visible directly in the AAP survey Multiple Choice Options field without a "display vs value" split (which AAP multiplechoice doesn't support) |
| 2026-05-27 | **`docs/dev-environment.sh`** (gitignored, sourceable) replaces `docs/dev-environment.md` (AB#61); `docs/dev-environment.sh.example` committed as template | `source docs/dev-environment.sh && ansible-playbook …` is the canonical load.yml invocation — all exports and the playbook run in one shell call (env vars don't persist across separate invocations) |
| 2026-05-27 | **`website_setup_azure` role** (AB#59) at `playbooks/roles/` instead of project root `roles/` | AWX EEs search `<playbook_dir>/roles/` only — project root `roles/` is invisible to the EE. All roles called from `playbooks/` must live in `playbooks/roles/`. |
| 2026-05-27 | **`DC1.Azure - Demo Account Password` custom credential type** (AB#59) injects `default_passwd` extra var for the Provision Access JT | JT surveys do not fire when a JT runs as a workflow node — the credential type is the only way to inject the secret without a survey at workflow launch |
| 2026-05-27 | Azure-native `website_setup_azure` role (AB#59) instead of reusing `aap.dailydemo.windows`'s `website_setup` role | Upstream `website_setup` used AWS-only vars (`my_ami_id`, `vpc_create_time`, availability zone etc.); Azure equivalents are `inventory_hostname`, `vm_size_tier`, `dc1_azure_location`. `ticket_number` left as `default('N/A')` until ServiceNow (Phase 8) |
| 2026-05-28 | **Phase 8 ServiceNow: AAP calls SNow back** (not SNow polls AAP); **direct REST** SNow→AAP (not mid-server); **callback node on success+failure paths** (AB#78) | Callback gives the richer demo payoff (RITM auto-fills with IP/FQDN on screen) and keeps status logic out of SNow; direct REST is far less setup than a MID Server for a demo; dual-path callback means the RITM never hangs silently on a failed/timed-out workflow. `ticket_number` passed into the launch threads to both the landing page and the callback, closing the `N/A` loop. Design-doc-first: code deferred until the live instance is wired |
| 2026-05-28 | **Phase 8 ServiceNow REDESIGNED to event-driven** (AB#79) — *supersedes the inbound + sequencing parts of the AB#78 row above*: inbound is now SNow Business Rule → Outbound REST Message → **AAP EDA event stream** → dc1.azure-owned rulebook → `run_workflow_template` (**not** a direct REST `launch/`); callback scope expanded to **full Windows parity** (RITM + CMDB CI + relationship + Incident-on-failure); status flipped to **ready to implement** (no longer deferred) | EDA event stream means SNow holds no workflow ID / launch token and EDA routes by `short_description` — one ingress for every SNow demo, mirroring the proven `aap.dailydemo.windows` pattern. Full parity is mostly *wiring* the already-synced Windows ServiceNow playbooks, not new code. `SN_*` creds + a minted `EDA_EVENT_STREAM_TOKEN` are in `docs/dev-environment.sh`; EDA verified enabled on the AAP. *(The AB#78 decisions that still hold: AAP-calls-SNow-back and the dual success/failure callback path.)* |
| 2026-06-01 | **Workflow layout mirrors DDW** (AB#84) — Create CMDB CI branches off **Provision VM success** (parallel, early — alongside the configure chain) instead of being gated behind Patching; **Update RITM (success)** hangs off **Patching `always`** instead of the tail of the CMDB chain | Matches the proven `aap.dailydemo.windows` graph: the CI is registered while the demo runs (better story, CMDB visible sooner) and the "Fulfilled" RITM update is decoupled from CMDB so a CMDB hiccup no longer blocks the request being marked fulfilled. RITM-success fires on Patching `always` (mirrors DDW) so it lands whenever the workflow reaches Patching. Layout-only — no JT/credential/playbook changes |
| 2026-06-01 | **EE hardened with build-time OS errata** (AB#86) + **the remediation is a documented demo story** (AB#87, `docs/ee-security-remediation.md`) | The Quay scan flagged 351 CVEs (24 High) on `DC1.Azure - EE`, almost all inherited from the `ee-minimal-rhel9:2.17.14` base (cut 2025-09-21; verified already the newest in-line rebuild == `2.17.14-4`). A `microdnf upgrade` step in `prepend_base` pulls ubi9 errata at build time, clearing the High RPM findings (openssl/openssh/libnghttp2 → el9_8). **Deliberately deferred** (each its own work item): `pyOpenSSL`≥26 (drags `cryptography` 37→48 under a pinned `azure-cli-core`) and the 2.18.x base (ansible-core minor bump). Captured as an SE talking track because "we own/patch our EE supply chain, and we change-manage the risky fixes" is a stronger customer story than a green scan badge |
| 2026-06-01 | **CaC auth = self-managing token dance** (AB#85) — `load.yml`/`validate.yml` mint a short-lived token from `AAP_CONTROLLER_USERNAME`/`PASSWORD` and delete it in `always:`, instead of authenticating with a stored `AAP_TOKEN`. `AAP_TOKEN` kept only as an SSO/MFA escape hatch (used as-is, not deleted) | A stored token expires and 401s (the "mint a new one" failure class). Minting fresh from username/password each run removes that class entirely and leaves nothing behind — consistent with the in-job dance already in `provision_vm`/`teardown`/`bootstrap` and with the "always delete tokens" rule. Basic auth was the alternative but introduces a second auth style and sends the password on every call; the dance keeps one pattern + a scoped, revocable, audited token |
| 2026-06-02 | **RITM start-notice — two-way link at launch** (AB#94) — a root workflow node writes the AAP workflow job ID + deep link back to the RITM (comment + work note) at launch, and publishes the reverse `snow_ritm_url` onto the AAP job | A "fire and forget" launch leaves the requester staring at an unchanged ticket for ~10 min. Posting at launch (root node, parallel to Provision VM, `awx_workflow_job_id` for the link) gives immediate feedback and lets a fulfiller click straight from the ticket into the live AAP job; the reverse link makes it genuinely bidirectional. Guarded on `ticket_number` so non-ServiceNow triggers stay green |
| 2026-06-02 | **Phase 8 validated end-to-end live; three inbound-trigger fixes were live-only** (AB#91) — captured `my_organization` (activation extra_vars), `ask_variables_on_launch` (workflow), and EE `pull` policy in CaC | Lint/build never exercise a live launch; all three only surfaced driving a real ServiceNow→workflow run (job 78→97). Capturing them in CaC keeps a `load.yml` re-apply from reverting the working demo. Confirmed the instance's request-state ints (`3`=Closed Complete, `4`=Closed Incomplete) so the `update_ritm.yml` defaults are correct as-is |
| 2026-06-02 | **EE update model = deliberate, not auto-pull** (AB#95, direction set; impl deferred) — replace `pull: always` (AB#91 placeholder) with `pull: missing` + immutable version tags + pinning the Controller EE to a tag | `pull: always` re-pulls the 521 MB EE every run (throughput cost, visibly queued concurrent jobs) and is the wrong model — Eric prefers updating the EE deliberately when needed. The safe replacement needs the *reference* to change on a deliberate update (immutable tag + repoint), which is the same immutable-tagging/backout work; blocked on the tag-scheme decision. `pull: always` stays until the replacement lands (additive-only) |
| 2026-06-03 | **EE tag scheme = semver `vX.Y.Z`** (AB#95 implemented) — Controller EE pins to `ee_version` (default `v1.0.0`) with `pull: missing`; `hub_ee_repositories.yml` `include_tags` templates off `ee_version`; `latest` retained as the smoke-test escape hatch. `v1.0.0` minted from the existing 2026-06-01 hardened digest (`sha256:4423a10…`) via `skopeo copy` — no rebuild. Runbook in `docs/ee-versioning.md`; rationale for the custom EE itself in `docs/ee-why-custom-ee.md` | Semver gives the cleanest platform-engineering demo narrative ("the EE is versioned like a product; we promote deliberately") and the most readable CaC diff on a bump. Bump rule resolves the errata-rebuild ambiguity: CVE-only → patch, +collection → minor, new base → major. Chosen over date / git-SHA / date+sha after two deferrals |
| 2026-06-03 | **Post-demo roadmap: automate the ADO + SNow trigger wiring from AAP** (Phases 12–13) — the two remaining manual UI build steps become AAP-driven Config-as-Code (`DC1.Azure - Configure ADO Trigger` / `... SNow Trigger` JTs), each with a **new** (create) and **update** (re-point) path | Both trigger wirings carry per-env churn — ADO needs the fresh AAP host/token; SNow needs the fresh EDA event-stream URL/token — so today a fresh Product Demo env can't be stood up without UI click-throughs. Making them code completes "every trigger reconfigures from a repo run," which is what makes the demo cleanly Product-Demo-portable. Driver choice (`az devops` CLI vs ADO REST; `servicenow.itsm` vs SNow Table API) deferred to implementation as open questions |
| 2026-06-03 | **Skills cover the full lifecycle, repo-based** (Phase 15): `first-time-setup`, `spin-env`, `demo-readiness`, `teardown` (added alongside the existing `install-dc1-azure`) | `install-dc1-azure` assumes prerequisites are already met; the gaps are onboarding (first-time-setup), full env bring-up (spin-env), pre-demo go/no-go (demo-readiness), and cleanup (teardown). All repo-based per the 2026-05-26 marketplace→in-repo decision so the demo carries its own tooling |
| 2026-06-03 | **Phase 12 ADO driver = the ADO REST API via `ansible.builtin.uri`, not the `az devops` CLI** (AB#121 spike resolved) | Decisive: the pipeline→variable-group authorization step uses the `pipelinePermissions` API, which has **no `az devops` command** (confirmed live + the Phase 10 finding), so REST is unavoidable for ≥1 step — using it for all three (Variable Group, pipeline, authorization) beats mixing two tools. Also: `uri` is built-in (zero new EE deps) vs. adding + version-maintaining the `azure-devops` CLI extension in the EE; it matches the repo's established playbook→API pattern (controller-API token dance, `servicenow.itsm.api`); and the versioned REST API (`api-version=7.1`) is more stable than the CLI surface. PoC: a read-only REST GET listed the live `dc1-azure-aap` (id 2) + `dc1-azure-shared` (id 1) variable groups. Auth = PAT via `Authorization: Basic base64(":"+PAT)` header, sourced from an AAP custom credential type (AB#124) |
| 2026-06-03 | **Phase 13 SNow driver = `servicenow.itsm.api` (the collection's Table API module), not raw `ansible.builtin.uri`** (AB#125 spike resolved) | The collection's generic `api` module already ships in the EE and is already used for the Phase 8 CMDB CI `configuration_item` patch — reusing it keeps one SNow pattern and handles auth/JSON/idempotency (query→patch by `sys_id`), vs. hand-rolling `uri`. The "servicenow.itsm can't reach `sys_rest_message`" worry was a false dichotomy: `servicenow.itsm.api` *is* the Table API and reaches any table the user's roles allow. **Live PoC:** the shared-instance `SN_*` user has the **admin** role (full write to `sys_rest_message` / `sys_rest_message_fn` / the `dc1.eda_event_stream_token` `password2` property); the existing `Ames - DC1.Azure EDA Event Stream` REST Message is present — the endpoint lives on the `_fn` (function) record, not the parent. **Caveat carried forward:** 33 REST Messages from other SEs live on the shared instance, so every write must target the exact `sys_id` and stay `Ames -`-namespaced (blast-radius) |
| 2026-06-04 | **Multi-OS provisioning: `os_type` survey (windows / linux / both)** — the workflow survey gains an `os_type` parameter; Terraform conditionally creates Windows, Linux, or both VMs in one launch. Linux = RHEL 9, SSH key, cloud-init. Same VNet/NSG, separate inventory groups (`windemo` / `linuxweb`). Backward compatible: default `os_type=windows` preserves existing behavior |
| 2026-06-04 | **Linux web-server pattern from `aap.dailydemo.F5`** (not `aap.dailydemo.linux`) — the F5 daily demo's `rhsm` → `linux_post_install` → `website_setup` role chain is the better reference because it already builds the Apache web server that later sits behind the F5 pool. CDN registration direct to Red Hat (no Satellite) |
| 2026-06-04 | **Dynatrace OneAgent as a standard workflow node** (not conditional/best-effort) — the Dynatrace SaaS tenant (`ybz84624.live.dynatrace.com`) is always on; OneAgent installs on every provisioned VM (Windows + Linux). Uses the **push model** (`aap.eda.dynatrace.push`) — Dynatrace pushes problem events to AAP EDA. Credential: `DC1.Azure - Dynatrace` (PaaS token from `docs/dev-environment.sh`). Hosts tagged into `dc1-azure` host group |
| 2026-06-04 | **F5 BIG-IP on Azure added to roadmap (Phase 19)** — F5 BIG-IP VE is available in Azure Marketplace (PAYG GOOD tier = LTM, 30-day free trial). Deploys via Terraform; configured via `f5networks.f5_modules`. Linux web servers become pool members; the `aap.dailydemo.F5` patching workflow (disable → patch → re-enable) runs against them. Key risk: RHDP open-env term acceptance is subscription-scoped |
| 2026-06-03 | **Phase 9: Self-Service Portal surfaces JOB templates only, not workflows → bridge with a launcher JT** (AB#107) | Proven live (identical team-level grant: a job template surfaced for `jr-dev`, the workflow did not; backend provider `AAPJobTemplateProvider`) and confirmed in RH 2.6 docs — a product-design choice, not a version gap (chart 2.2.0 doesn't add it). A thin launcher JT (`DC1.Azure - Request Windows VM`, `vm_size_tier` survey → `ansible.controller.workflow_launch`) fires the existing workflow, preserving "one core workflow, four triggers" and keeping everything in dc1.azure's scope (vs a portal-side custom Backstage template). NB: the portal catalog only refreshes per-user access on a `sync_portal_orgs.yml` run (it restarts the portal); the in-UI "Sync now" button does not |

---

## Risks / Open Questions

- **RHDP Azure open-env quota** — needs verification that `D8s_v5` (8 vCPU) fits within open-env quota. Mitigation: slide tiers down one notch (B2s / D2s_v5 / D4s_v5) if not.
- **Windows Server 2025 WinRM bootstrap on Azure** — Azure marketplace image may not have WinRM enabled by default. Mitigation: `custom_data` PowerShell snippet enables WinRM-HTTPS + opens firewall on first boot.
- **`infra.aap_configuration` Azure RM credential support** — ✅ verified 2026-05-21: `Microsoft Azure Resource Manager` credential type works via `ansible.controller.credential` with `inputs.subscription/tenant/client/secret`. Re-verify the same fields are accepted by `infra.aap_configuration.controller_credentials` role.
- **ADO PAT expiration** — 90-day PATs require rotation. Mitigation: documented in runbook + a calendar reminder; future enhancement could use a workload-identity federation pattern.
- **Open-env lifespan** — RHDP envs are time-limited. Mitigation: teardown JT keeps Azure spend predictable; demo runbook starts with a "is the env still alive?" check.
- **AAP object collision in shared instances** — multiple SEs may share an AAP instance. Mitigation: `DC1.Azure -` prefix on every named object.
- ~~**AAP personal token expiration** (Phase 3)~~ — ✅ **RESOLVED by AB#85 (2026-06-01).** `load.yml`/`validate.yml` no longer need a stored token: they mint a short-lived one from `AAP_CONTROLLER_USERNAME`/`PASSWORD` and delete it in `always:`. No token to expire.
- **SSO/MFA AAP breaks token minting** (Phase 3, AB#85) — the self-managing dance mints via **basic auth**, which a federated (SSO) or MFA-enforced account can't satisfy; the mint 401s on `.../gateway/v1/tokens/` even with "correct" creds. Mitigation: documented escape hatch — UI-mint a token (the browser SSO session satisfies the IdP) and `export AAP_TOKEN`; the run then uses it as-is and never deletes it. INSTALL §4 + troubleshooting row cover the symptom→fix.
- **Red Hat shared SNow availability** (Phase 8 new) — shared instance means shared state (other SEs' catalog items, flows). Risk of conflicts or accidental changes. Mitigation: namespace SNow objects with `dc1.azure - ` prefix (mirror our AAP naming). Confirm with the SNow admin before standing up the catalog item.
- **AAP→SNow callback complexity** (Phase 8 new) — RITM update requires a SNow credential in AAP plus the `servicenow.itsm` collection. Risk: time-out behavior when Azure provisioning hangs > workflow time-out leaves RITM in an indeterminate state. Mitigation: explicit failure-path JT that updates RITM with `Failed` + error context.
- ~~**ADO automation driver** (Phase 12 new)~~ — ✅ **RESOLVED by AB#121 (2026-06-03): the ADO REST API via `ansible.builtin.uri`** (not the `az devops` CLI). The `pipelinePermissions` authorization step has no `az` command → REST is unavoidable; `uri` is built-in (no EE-weight cost, no `azure-devops` extension to maintain) and matches the existing playbook→API pattern (controller-API token dance, `servicenow.itsm.api`). PoC: read-only REST GET listed the live `dc1-azure-aap` (id 2) + `dc1-azure-shared` (id 1) variable groups. See Decisions Log.
- ~~**SNow Outbound REST automation scope** (Phase 13 new)~~ — ✅ **RESOLVED by AB#125 (2026-06-03): use `servicenow.itsm.api`** (the collection's Table API module, already in the EE + in use for the CMDB CI patch), not raw `uri`. Live PoC: the `SN_*` user has **admin** (full write to `sys_rest_message` / `sys_rest_message_fn` / `sys_properties`); the existing `Ames - DC1.Azure EDA Event Stream` REST Message + `dc1.eda_event_stream_token` (`password2`) records are reachable. **Blast-radius caution STANDS** — the shared instance holds 33 REST Messages from other SEs, so every write must target the exact `sys_id` (never a broad name query) and stay namespaced `Ames - …`. See Decisions Log.
- **`aap.dailydemo.windows` role compatibility with Azure VMs** (Phase 4 reaffirmation) — roles assume an AWS-provisioned Windows box (likely AWS-specific tags or metadata service calls). Mitigation: review each of the 4 roles' tasks before importing; vendor + adapt locally if upstream isn't cloud-agnostic.
- **RHEL 9 Azure Marketplace image licensing** (Phase 16 new) — RHEL PAYG images include the subscription cost in the compute price; BYOS (Bring Your Own Subscription) images use an existing RH subscription. For a demo, PAYG is simpler (no activation key needed), but CDN registration (Phase 17) with RHSM credentials on a PAYG image may conflict. Mitigation: test early; if PAYG already registers, skip the explicit RHSM step.
- **Multi-OS Terraform state complexity** (Phase 16 new) — conditional `count` on VM resources means `terraform plan` output changes shape depending on `os_type`. Mitigation: use named resources (`azurerm_linux_virtual_machine.demo[0]`) and stable addressing so `os_type` changes don't force-replace the other OS's VM.
- **F5 Marketplace term acceptance on RHDP** (Phase 19 new) — `az vm image terms accept` is a subscription-level operation; RHDP open environments typically grant Contributor on the RG only, not Owner on the subscription. If blocked, F5 deployment requires a more permissive environment or pre-accepted terms. Mitigation: test immediately after RHDP env activation; document the fallback.
- **F5 vCPU quota alongside VMs** (Phase 19 new) — F5 BIG-IP VE needs ≥2 vCPUs on top of the Linux + Windows VMs. With `os_type=both` + F5, total vCPU demand could hit 12–18 depending on tiers. Mitigation: verify RHDP quota covers the sum; document a "demo-lite" tier set if not.

---

## Reference Repositories

| Repo | Role in dc1.azure |
|------|--------------------|
| [demo.datacenter](https://github.com/ericcames/demo.datacenter) | AWS sibling — source for Terraform patterns and overall DC1 conventions |
| [aap.as.code](https://github.com/ericcames/aap.as.code) | Pattern reference only — dc1.azure stands independent (Decisions Log 2026-05-26). The `infra.aap_configuration` collection's own docs are the primary CaC guide |
| [infra.aap_configuration](https://github.com/redhat-cop/infra.aap_configuration) | **Primary CaC guide** — pinned 4.4.0; `aap_config/` follows its recommended layout; var files named per its roles |
| [aap.dailydemo.windows](https://github.com/ericcames/aap.dailydemo.windows) | Source of the reused post-provision Windows roles (pinned git reference, not vendored) |
| [aap.dailydemo.F5](https://github.com/ericcames/aap.dailydemo.F5) | Pattern source for Linux web-server build (rhsm → post-install → website_setup) and F5 patching workflow (disable pool member → patch → re-enable) |
| [aap.dailydemo.linux](https://github.com/ericcames/aap.dailydemo.linux) | Reference for Linux VM configuration roles (lamp_setup, linux_post_install, rhsm, website_setup) |
| [aap.eda.dynatrace.push](https://github.com/ericcames/aap.eda.dynatrace.push) | Dynatrace EDA push-model demo; dc1.azure provisions hosts into the same tenant so Dynatrace pushes real problem events to AAP EDA |
| [aap.aws.infrastructure](https://github.com/ericcames/aap.aws.infrastructure) | Reference for AWS-side IaaS structure being replaced by Azure equivalents |

---

## Status Legend

- ✅ Complete
- 🔄 In progress
- ⬜ Not started

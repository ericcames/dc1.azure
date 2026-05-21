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

### Phase 0 — Azure DevOps Account Setup  ⬜
*Manual browser work, ~15 min, blocks all subsequent phases.*

- ⬜ Create ADO org `ericcames` at https://dev.azure.com
- ⬜ Create project `dc1.azure` (Private, Git, Agile process)
- ⬜ Initialize default `dc1.azure` repo with README + VisualStudio gitignore
- ⬜ Create Personal Access Token scoped to Code (RW), Build (RX), Work Items (RW); save to password manager
- ⬜ Create ADO Boards Epic: *Bootstrap dc1.azure demo*
- ⬜ Clone repo to `/home/eames/git-repos/dc1.azure/` using PAT for auth

**Exit criteria:** local clone of an empty (README-only) ADO repo at the expected path; PAT stored; epic exists.

### Phase 1 — Repo Skeleton  ⬜
- ⬜ Top-level files: `README.md`, `CHANGELOG.md`, `CLAUDE.md`, `CODE_OF_CONDUCT.md`, `CONTRIBUTING.md`, `LICENSE`
- ⬜ Directory scaffolding: `terraform/`, `playbooks/`, `inventories/dc1-azure/`, `docs/`, `docs/images/`, `meta/`, `collections/`
- ⬜ `galaxy.yml`, `meta/runtime.yml`
- ⬜ `collections/requirements.yml` pinning `infra.aap_configuration` 4.2.0, plus `azure.azcollection`, `ansible.windows`, `community.windows`
- ⬜ **No** project-local `ansible.cfg`
- ⬜ `.gitignore` covering `*.tfstate*`, `.terraform/`, `*.tfvars` (except `*.tfvars.example`), `__pycache__`, `.DS_Store`

**Exit criteria:** repo opens cleanly in VS Code, `ansible-galaxy collection install -r collections/requirements.yml` succeeds against Eric's `~/.ansible.cfg`.

### Phase 2 — Terraform: Azure Windows VM  ⬜
- ⬜ `providers.tf` — `azurerm` provider + `azurerm` remote state backend
- ⬜ `backend.tf` — Storage Account / container / key for state
- ⬜ `variables.tf` — `vm_size_tier`, `location`, `resource_group_name`, `admin_username`, `admin_password` (sensitive), `tags`
- ⬜ `locals.tf` — t-shirt → SKU map (see table above)
- ⬜ `main.tf` — VNet, Subnet, NSG (5986 + 3389), Public IP, NIC, `azurerm_windows_virtual_machine` (image `MicrosoftWindowsServer:WindowsServer:2025-datacenter-azure-edition:latest`), `custom_data` cloudbase-init to enable WinRM-HTTPS + open firewall
- ⬜ `outputs.tf` — `public_ip`, `fqdn`, `admin_username`, `vm_size_chosen`
- ⬜ `terraform.tfvars.example` documenting required inputs
- ⬜ Manual smoke test from Eric's laptop: `terraform init && plan && apply` with `vm_size_tier=small`, confirm WinRM reachable, `destroy`

**Exit criteria:** `terraform apply` from Eric's laptop produces a reachable Windows VM in the RHDP open env; `destroy` cleans it up; state lives in Azure Storage.

### Phase 3 — AAP Bootstrap (Azure flavor of `aap.as.code`)  🔄
- 🔄 `playbooks/bootstrap_aap.yml` — mirrors `aap.as.code/playbooks/bootstrap_dev.yml`: `ansible.platform.token` for token lifecycle, `ansible.controller.*` for credential/project. Future iterations will add a `main.yml` + `playbooks/files/config_as_code/` data files dispatched via `infra.aap_configuration.dispatch` for full CaC.
- Credentials (all prefixed `DC1.Azure -` to avoid collision with AWS DC1):
  - 🔄 `DC1.Azure - Azure RM` (Microsoft Azure Resource Manager type) — task written, awaiting live-run verification
  - 🔄 `DC1.Azure - ADO Source Control` (Source Control type, PAT) — task written, awaiting live-run verification
  - ⬜ `DC1.Azure - Windows Machine` (Machine type, WinRM)
  - 🔄 `DC1.Azure - Vault` — task written, awaiting live-run verification
- 🔄 Project `DC1.Azure` syncing from the ADO repo on `main` — task written, awaiting live-run verification
- ⬜ Inventory `dc1-azure` with empty `windows` group (populated by Provision JT via `add_host` + `set_stats`)
- ⬜ Job templates with surveys:
  - ⬜ `DC1.Azure - Provision VM` (survey: `vm_size_tier`)
  - ⬜ `DC1.Azure - Configure Windows`
  - ⬜ `DC1.Azure - Teardown`
- ⬜ Workflow `DC1.Azure - Provision and Configure` chaining Provision → Configure with artifact passing
- ⬜ Post-bootstrap validation step (per global rule: never exit green without verifying objects exist)

**Exit criteria:** running `bootstrap_aap.yml` against a fresh AAP creates every object listed above; running the validation step returns green; manually launching the workflow with `vm_size_tier=small` reaches the WinRM step.

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
- ⬜ `azure-pipelines.yml` at repo root, PR trigger to `main`
- ⬜ Steps on `ubuntu-latest`: `yamllint`, `ansible-lint`, `terraform fmt -check -recursive`, `terraform validate` (with `-backend=false`)
- ⬜ Branch policy: require pipeline pass + 1 reviewer before merge to `main`

**Exit criteria:** opening a PR triggers the pipeline; a deliberately bad YAML/TF change fails it.

### Phase 6 — Demo Runbook  ⬜
- ⬜ `docs/demo-runbook.md` — SE-facing live-demo script
- ⬜ Persona framing, click-by-click flow, talking points, expected timings
- ⬜ Failure-mode appendix (what to do if Azure quota hit, if WinRM doesn't come up, if AAP project sync fails)
- ⬜ `docs/images/` — screenshots of the AAP survey, the IIS landing page, the ADO Boards epic

**Exit criteria:** Eric runs the demo cold off the runbook end-to-end without consulting the source code.

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

---

## Risks / Open Questions

- **RHDP Azure open-env quota** — needs verification that `D8s_v5` (8 vCPU) fits within open-env quota. Mitigation: slide tiers down one notch (B2s / D2s_v5 / D4s_v5) if not.
- **Windows Server 2025 WinRM bootstrap on Azure** — Azure marketplace image may not have WinRM enabled by default. Mitigation: `custom_data` PowerShell snippet enables WinRM-HTTPS + opens firewall on first boot.
- **`infra.aap_configuration` Azure RM credential support** — collection should support the built-in Azure RM credential type; verify exact module name and parameter shape before writing `bootstrap_aap.yml`.
- **ADO PAT expiration** — 90-day PATs require rotation. Mitigation: documented in runbook + a calendar reminder; future enhancement could use a workload-identity federation pattern.
- **Open-env lifespan** — RHDP envs are time-limited. Mitigation: teardown JT keeps Azure spend predictable; demo runbook starts with a "is the env still alive?" check.
- **AAP object collision in shared instances** — multiple SEs may share an AAP instance. Mitigation: `DC1.Azure -` prefix on every named object.

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

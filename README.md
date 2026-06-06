# DC1 Azure — IT Infrastructure on Azure

Self-service IT infrastructure provisioning on Microsoft Azure — Windows Server
2025 and RHEL 9 Linux VMs — orchestrated by Ansible Automation Platform (AAP),
with source code in Azure DevOps Repos.

`dc1.azure` is the Azure counterpart to
[`demo.datacenter`](https://github.com/ericcames/demo.datacenter) (AWS). It
started as a single Windows VM demo and has grown into a multi-OS
infrastructure provisioning story with three sizing tiers and an OS-type
survey — code in Azure DevOps, infrastructure on Azure, AAP as the
orchestrator.

> *"Same automation. Same self-service experience. Your cloud, your tools."*

See [`ROADMAP.md`](ROADMAP.md) for the full architecture, phase plan, and
decisions log.

## Story (the demo)

1. An app-developer persona logs into AAP self-service
2. Picks an OS type — `windows`, `linux`, or `both` — and a t-shirt size
3. Watches the workflow run for ~10 minutes
4. Lands on a provisioned VM: Windows Server 2025 (PowerShell 7, IIS, Windows
   Update, RDP) and/or RHEL 9 Linux (Apache, Chrony, Insights, security-hardened,
   SSH) — fully configured, patched, and serving a branded landing page

**One workflow, four front doors.** The same `DC1.Azure - Provision and Configure`
workflow is launched from **four** triggers — the AAP web UI, the AAP Self-Service
Portal, a ServiceNow catalog request, and an Azure DevOps pipeline — each a thin
adapter, no parallel re-implementations. All four are live and validated. See the
[demo runbook](docs/demo-runbook.md) for the click-by-click of each.

## Sizing tiers

| Tier (survey choice) | Azure SKU       | vCPU | RAM   | Family |
|----------------------|-----------------|------|-------|--------|
| `small-2cpu-4gb`     | `Standard_B2s`  | 2    | 4 GB  | B-series (burstable) |
| `medium-2cpu-8gb`    | `Standard_B2ms` | 2    | 8 GB  | B-series (burstable) |
| `large-4cpu-16gb`    | `Standard_B4ms` | 4    | 16 GB | B-series (burstable) |

## Repo layout

```
dc1.azure/
├── ROADMAP.md            ← strategic plan + decisions log (read this first)
├── CHANGELOG.md
├── CLAUDE.md             ← Claude Code working guidelines for this repo
├── CONTRIBUTING.md       ← workflow, branch naming, ADO Boards conventions
├── azure-pipelines.yml   ← ADO Pipeline: lint + validate + GitHub mirror (Phase 5)
├── azure-pipelines-launch.yml ← ADO trigger: launches the AAP workflow on demand (Phase 10)
├── execution-environment.yml ← custom EE (Terraform + collections) for the JTs (Phase 4)
├── terraform/            ← Azure infra (Phase 2)
├── aap_config/           ← AAP Config-as-Code — the canonical install path (Phase 3)
├── playbooks/            ← provision + configure + teardown playbooks (Phase 4)
│   ├── configure_linux.yml ← Linux post-provision: Apache, firewalld, MOTD (Phase 17)
│   ├── roles/linux_configure/ ← combined Linux configure role
│   ├── servicenow/       ← ServiceNow callback playbooks (Phase 8)
│   └── ado/              ← ADO trigger automation (Phase 12)
├── servicenow/           ← ServiceNow-side artifacts (Business Rule, REST Message docs)
├── rulebooks/            ← EDA rulebook for ServiceNow events (Phase 8)
├── ansible.cfg.example   ← Hub galaxy_server template → ~/.ansible.cfg (Phase 7)
├── .claude/skills/       ← repo-based Claude skills (install-dc1-azure, servicenow)
├── docs/
│   ├── INSTALL.md        ← manual install guide (Phase 7)
│   ├── demo-runbook.md   ← SE-facing live-demo script (Phase 6 — AAP-driven flow)
│   ├── servicenow-integration.md ← ServiceNow design + build spec (Phase 8)
│   ├── ee-security-remediation.md ← EE security-scan remediation story (talking track + engineering record)
│   ├── ee-why-custom-ee.md  ← rationale for shipping a purpose-built EE (Phase 8)
│   ├── ee-versioning.md     ← EE deliberate-update model + bump runbook (AB#95)
│   ├── ado-conventions.md ← ADO operating model: Boards, branch policies, Library (Phase 0.5)
│   └── images/
├── collections/requirements.yml
├── galaxy.yml
└── meta/runtime.yml
```

## Getting started

Installing dc1.azure means applying the [`aap_config/`](aap_config/README.md)
Configuration-as-Code onto a working AAP — it creates every credential,
project, inventory, job template, and the provision-and-configure workflow.
Two ways to do it:

- **Manual** — follow **[`docs/INSTALL.md`](docs/INSTALL.md)**: prerequisites,
  the env-var table, `ansible-galaxy collection install -r aap_config/requirements.yml`,
  then `ansible-playbook -i aap_config/inventory/ aap_config/load.yml` (which
  self-verifies via `validate.yml`).
- **AI-driven** — if you use Claude Code, run **`/install-dc1-azure`** (shipped
  in [`.claude/skills/`](.claude/skills/install-dc1-azure/SKILL.md)). It checks
  prerequisites, prompts for any missing values, runs the install, and reports
  each created object.

Prerequisites in brief (full list in `docs/INSTALL.md`): an AAP instance with
admin username/password (the install **mints its own short-lived token** and
deletes it — no stored personal token needed; an SSO/MFA AAP uses a UI-minted
`AAP_TOKEN` escape hatch instead), an RHDP Azure Service Principal + resource
group, an Azure DevOps PAT, a Windows admin password (and/or Linux SSH key pair
for Linux VMs), and an Automation Hub token
for collection install (seed `~/.ansible.cfg` from
[`ansible.cfg.example`](ansible.cfg.example)).

> **End-to-end status:** all four triggers are live and validated (2026-06-03).
> The provision→configure→teardown automation stands up reachable VMs — Windows
> (IIS, PowerShell 7, Windows Update, RDP) and/or Linux (Apache, SSH) — launchable
> from the AAP UI, the Self-Service Portal, ServiceNow, or an Azure DevOps
> pipeline. The `os_type` survey parameter controls which VMs are created.
> ServiceNow runs additionally auto-fulfil the RITM and create the CMDB CI.
> `load.yml` creates the execution environment via CaC, so a fresh AAP needs only
> the credentials/env vars in `docs/INSTALL.md`. See [`ROADMAP.md`](ROADMAP.md)
> for the per-phase detail.

### Mirror to GitHub (automatic — Phase 5)

The ADO Pipeline auto-mirrors `main` to GitHub on every merge (the **Mirror**
stage in `azure-pipelines.yml`, using the `github-ericcames` service connection).
No manual `git push github main` is needed — push to ADO `origin` and the GitHub
mirror follows within ~1 minute.

## Related repos

| Repo | Role |
|------|------|
| [demo.datacenter](https://github.com/ericcames/demo.datacenter) | AWS sibling — source for Terraform patterns |
| [aap.as.code](https://github.com/ericcames/aap.as.code) | Source for AAP bootstrap patterns |
| [aap.dailydemo.windows](https://github.com/ericcames/aap.dailydemo.windows) | Source of post-provision Windows roles |
| [aap.dailydemo.F5](https://github.com/ericcames/aap.dailydemo.F5) | Source of Linux configure pattern (Apache web server) |

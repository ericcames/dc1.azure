# DC1 Azure — Windows on Azure Demo

Self-service Windows VM provisioning on Microsoft Azure, orchestrated by Ansible
Automation Platform (AAP), with source code in Azure DevOps Repos.

`dc1.azure` is the Azure counterpart to
[`demo.datacenter`](https://github.com/ericcames/demo.datacenter) (AWS). It is
intentionally smaller in scope — a single Windows Server 2025 VM with three
sizing tiers — and serves as a presentable Microsoft-stack demo: code in Azure
DevOps, infrastructure on Azure, AAP as the orchestrator.

> *"Same automation. Same self-service experience. Your cloud, your tools."*

See [`ROADMAP.md`](ROADMAP.md) for the full architecture, phase plan, and
decisions log.

## Story (the demo)

1. An app-developer persona logs into AAP self-service
2. Picks a t-shirt size — `small`, `medium`, or `large`
3. Watches the workflow run for ~10 minutes
4. Lands on a Windows Server 2025 VM with PowerShell 7, a demo account, an
   IIS landing page, and Windows Update applied — reachable via RDP and HTTP

## Sizing tiers

| Tier   | Azure SKU         | vCPU | RAM   |
|--------|-------------------|------|-------|
| small  | `Standard_D2s_v5` | 2    | 8 GB  |
| medium | `Standard_D4s_v5` | 4    | 16 GB |
| large  | `Standard_D8s_v5` | 8    | 32 GB |

## Repo layout

```
dc1.azure/
├── ROADMAP.md            ← strategic plan + decisions log (read this first)
├── CHANGELOG.md
├── CLAUDE.md             ← Claude Code working guidelines for this repo
├── CONTRIBUTING.md       ← workflow, branch naming, ADO Boards conventions
├── azure-pipelines.yml   ← ADO Pipeline: lint + validate on PR (Phase 5)
├── terraform/            ← Azure infra (Phase 2)
├── aap_config/           ← AAP Config-as-Code — the canonical install path (Phase 3)
├── playbooks/            ← provision + teardown playbooks (Phase 4); deprecated bootstrap
├── inventories/dc1-azure/
├── ansible.cfg.example   ← Hub galaxy_server template → ~/.ansible.cfg (Phase 7)
├── .claude/skills/       ← repo-based Claude skills (install-dc1-azure)
├── docs/
│   ├── INSTALL.md        ← manual install guide (Phase 7)
│   ├── demo-runbook.md   ← SE-facing live-demo script (Phase 6)
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

Prerequisites in brief (full list in `docs/INSTALL.md`): an AAP instance + a
personal API token, an RHDP Azure Service Principal + resource group, an Azure
DevOps PAT, a Windows admin password, and an Automation Hub token for collection
install (seed `~/.ansible.cfg` from [`ansible.cfg.example`](ansible.cfg.example)).

> **End-to-end status:** all objects and the provision→configure→teardown
> automation are defined; a green *live* run still needs the target execution
> environment + credentials wired on your AAP — see `docs/INSTALL.md` and
> [`ROADMAP.md`](ROADMAP.md) Phase 4.

### Mirror to GitHub (Phase 5 — manual today)

Today the GitHub remote is pushed by hand after every push to ADO:

```bash
git push origin main
git push github main   # until Phase 5 pipeline auto-mirrors
```

## Related repos

| Repo | Role |
|------|------|
| [demo.datacenter](https://github.com/ericcames/demo.datacenter) | AWS sibling — source for Terraform patterns |
| [aap.as.code](https://github.com/ericcames/aap.as.code) | Source for AAP bootstrap patterns |
| [aap.dailydemo.windows](https://github.com/ericcames/aap.dailydemo.windows) | Source of post-provision Windows roles |

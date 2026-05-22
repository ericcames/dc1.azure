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
├── playbooks/            ← AAP bootstrap + provision + configure + teardown (Phase 3-4)
├── inventories/dc1-azure/
├── docs/
│   ├── demo-runbook.md   ← SE-facing live-demo script (Phase 6)
│   └── images/
├── collections/requirements.yml
├── galaxy.yml
└── meta/runtime.yml
```

## Getting started

> The end-to-end demo isn't fully wired up yet — see
> [`ROADMAP.md`](ROADMAP.md) for current phase status. The pieces below work
> today; the rest is in progress.

### Prerequisites
- Red Hat Demo Platform (RHDP) Azure open environment (provides subscription, RG, SP)
- AAP instance from RHDP (bootstrapped per [`aap.as.code`](https://github.com/ericcames/aap.as.code) conventions)
- Azure DevOps account at `dev.azure.com/ericcames` with PAT scoped to Code (RW), Build (RX), Work Items (RW)
- Local: `terraform` ≥ 1.6, `ansible-core` ≥ 2.16, `ansible-galaxy` configured per [`aap.as.code/CLAUDE.md`](https://github.com/ericcames/aap.as.code/blob/main/CLAUDE.md)

### Install collections
```bash
ANSIBLE_CONFIG=~/.ansible/ansible.cfg \
  ansible-galaxy collection install -r collections/requirements.yml -p ./collections
```

### Local Terraform smoke test (Phase 2 exit criteria — pending)
```bash
cd terraform/
cp terraform.tfvars.example terraform.tfvars
# fill in subscription_id, resource_group_name, location, etc.
terraform init
terraform plan -var="vm_size_tier=small"
terraform apply -var="vm_size_tier=small"
# ... verify VM, then ...
terraform destroy -var="vm_size_tier=small"
```

### AAP Configuration as Code (Phase 3 — building)

The canonical install path will be a self-contained `aap_config/` directory
at the repo root, run via `infra.aap_configuration.dispatch`:

```bash
# Once Phase 3 lands (aap_config/ not on disk yet — see ROADMAP):
ansible-playbook -i aap_config/inventory/ aap_config/load.yml
```

This is the only entry point a first-time installer should ever need. It
creates every dc1.azure AAP object (credentials, project, inventory, job
templates, workflow) and is idempotent.

**Transitional stopgap (will be removed):** `playbooks/bootstrap_aap.yml`
exists from earlier work and can create a partial set of AAP objects (Vault +
Azure RM credentials are verified in live RHDP AAP; ADO SCM credential
pending an AAP-scoped PAT). This playbook is **deprecated** — use it only if
you need partial bootstrap before `aap_config/load.yml` is end-to-end ready.
It will be deleted once the CaC path is verified. See ROADMAP Phase 3.

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

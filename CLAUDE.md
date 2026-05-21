# dc1.azure — Claude Guidelines

This repo is the Azure counterpart to
[`demo.datacenter`](https://github.com/ericcames/demo.datacenter). It is the
canonical home for the DC1 Azure Windows-VM demo. Read [`ROADMAP.md`](ROADMAP.md)
first — it has the architecture, phase plan, naming conventions, and decisions
log.

## Working with a New AAP Environment

When the user provides a new AAP URL and password, store them in
`docs/dev-environment.md`. That file is gitignored — never commit credentials
and never paste them into chat.

```
docs/dev-environment.md
├── URL      → new AAP instance URL
├── Username → admin (default)
└── Password → provided password
```

## Working with a New Azure Open Environment

When the user activates an RHDP Azure open env, they will hand over:

- `subscription_id`
- `tenant_id`
- `client_id` / `client_secret` (Service Principal)
- `resource_group_name` (RHDP-provisioned)
- `location` (Azure region)
- `storage_account_name` for Terraform state backend (may need to create)

Place these in `terraform/terraform.tfvars` (gitignored — only the `.example`
is committed) and in an AAP "Microsoft Azure Resource Manager" credential named
`DC1.Azure - Azure RM`. Never commit them.

## Bootstrapping (planned — Phase 3)

`playbooks/bootstrap_aap.yml` will use the `infra.aap_configuration` collection
to create credentials, project, inventory, job templates, and the workflow.
Pattern mirrors `aap.as.code/playbooks/bootstrap_dev.yml`. Until Phase 3 lands,
use `aap.as.code` to bootstrap the AAP base, then add `dc1.azure` objects
manually for testing.

## Project Conventions

- **No project-local `ansible.cfg`** — the user's `~/.ansible/ansible.cfg`
  holds the Automation Hub `galaxy_server` token. A project-local cfg shadows
  it and breaks `ansible-galaxy collection install` for Red Hat certified
  content. Set inventory/options via CLI flags or env vars.
- **`ansible.platform` over `ansible.controller`** — `ansible.controller` is
  legacy; never use it in new code.
- **Always delete tokens** — any playbook that creates an AAP token via
  `ansible.platform.token` must delete it in an `always:` block.
- **Namespace AAP objects** — every credential, project, JT, and workflow name
  is prefixed `DC1.Azure -` to coexist with `demo.datacenter` AWS objects in
  shared AAP instances. See the naming-conventions table in `ROADMAP.md`.
- **Terraform state lives in Azure Storage** — never commit `*.tfstate*`.
- **Images go in `docs/images/`** (committed, not gitignored).
  `docs/dev-environment.md` is the only gitignored file under `docs/`.
- **CHANGELOG.md** — every PR adds an entry under Added / Changed / Fixed /
  Removed.
- **Additive only** — don't remove old capabilities until replacements are
  proven.

## Issue Tracking (ADO Boards)

This repo lives in Azure DevOps, so issue tracking uses ADO Boards work items
(not GitHub Issues). Convention:

- One **Epic** per phase from `ROADMAP.md` (e.g. *Phase 2 — Terraform: Azure
  Windows VM*)
- **Features** group related work-streams under an epic
- **User Stories** / **Tasks** for individual changes
- Title prefix: `[Phase N] <action>` for fast filtering
- Reference work items in commits with `AB#<id>` (ADO's autolink syntax) —
  the work item closes automatically on merge to `main` if its state is set to
  *Resolved* in the PR

## Key Files

| File | Purpose |
|------|---------|
| [`ROADMAP.md`](ROADMAP.md) | Architecture, phases, decisions log — read first |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | Workflow, branch naming, commit message format |
| `terraform/main.tf` | Azure infra: VNet, NSG, Win 2025 VM |
| `terraform/locals.tf` | t-shirt-size → SKU map |
| `collections/requirements.yml` | Pinned Ansible collection versions |
| `playbooks/bootstrap_aap.yml` | (Phase 3) AAP CaC bootstrap |

## When in doubt

- Mirror conventions from `demo.datacenter` and `aap.as.code` before inventing
  new ones.
- Surface placeholder values explicitly (e.g. `REPLACE_ME_RHDP_RG`) so they're
  trivially `grep`-able when real values arrive.
- Eric is new to Azure DevOps — explain ADO concepts the first time they come
  up (Projects vs Repos vs Pipelines, PATs vs Service Connections, Boards work
  item types).

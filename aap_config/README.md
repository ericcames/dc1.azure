# `aap_config/` — DC1.Azure AAP Configuration as Code

Self-contained Configuration-as-Code for every dc1.azure AAP object, applied
via the upstream [`infra.aap_configuration`](https://github.com/redhat-cop/infra.aap_configuration)
collection (pinned **4.4.0**). This is the canonical install path.

## Layout

| Path | Purpose |
|------|---------|
| `load.yml` | Entry point — applies `files/` via `infra.aap_configuration.dispatch`, then runs `validate.yml` |
| `validate.yml` | Post-load check — asserts every object exists in AAP (never exit green on a partial apply) |
| `requirements.yml` | Collection pins (4.4.0) + note on the reused Windows project |
| `inventory/aap.yml` | localhost only — CaC runs locally and talks to AAP over the API |
| `group_vars/all.yml` | Connection + secret references (env-var lookups) + object names |
| `files/controller_settings.yml` | Platform-wide Controller settings — enables Automation Analytics / Insights (the **Automation Calculator** data feed); var is `controller_settings` |
| `files/controller_credentials.yml` | 8 credentials (Vault, Azure RM, ADO SCM, Windows Machine, Controller, Hub Registry, Windows Admin Password, Demo Account Password) |
| `files/controller_projects.yml` | `DC1.Azure` (ADO) + reused `aap.dailydemo.windows` (pinned v1.0.1) + `aap.dailydemo.F5` (Linux configure roles) |
| `files/controller_inventories.yml` | `dc1-azure` inventory (`windemo` group for WinRM, `linuxweb` group for SSH; hosts added at runtime) + `dc1-azure-control` (empty; the Teardown JT runs here so it can deregister `dc1-azure` hosts) |
| `files/controller_job_templates.yml` | 6 JTs — var is `controller_templates` |
| `files/controller_workflow_job_templates.yml` | The core workflow — var is `controller_workflows` |

> **File-naming convention:** each `files/controller_*.yml` is named after the
> `infra.aap_configuration` role that consumes it, so the authoritative variable
> schema for any file is that role's README in the collection. (Two roles use a
> legacy list-variable name — noted at the top of those files.)

## The one workflow, four triggers

`files/controller_workflow_job_templates.yml` defines **one** survey-driven
workflow, `DC1.Azure - Provision and Configure`:

```
Provision VM ─► Powershell Improvement ─┬─► Website Setup ───┐
                                        └─► Provision Access ┴─► Patching
```

The four demo triggers (AAP UI, Self-Service Portal, ServiceNow, Azure DevOps)
all launch this same workflow — see ROADMAP Phases 6/8/9/10. The `os_type`
survey parameter (windows / linux / both) controls which VMs are provisioned.
Windows configure steps reuse roles from the pinned `aap.dailydemo.windows`
project; Linux uses the Apache pattern from `aap.dailydemo.F5`. Only the
Provision/Teardown playbooks are dc1.azure-native (built in Phase 4, extended
in Phase 16).

## Run it

The full environment-variable list and one-time prerequisites (Hub Galaxy
credentials, the AAP admin username/password — the run mints + deletes its own
short-lived token, AB#85 — the Terraform state Storage Account) live
in [`../docs/INSTALL.md`](../docs/INSTALL.md). The canonical invocation sources
the gitignored env file so every export and the playbook run share one shell:

```bash
# 1. Install collections (uses the Hub token — see ../ansible.cfg.example)
ansible-galaxy collection install -r requirements.yml

# 2. Copy the env template, fill it in, then source + run (idempotent):
cp ../docs/dev-environment.sh.example ../docs/dev-environment.sh
# edit ../docs/dev-environment.sh — never commit it
source ../docs/dev-environment.sh && ansible-playbook -i inventory/ load.yml
```

No secrets live in this directory — every sensitive value is an environment
lookup resolved at runtime (the Phase 7 setup skill, or `dev-environment.sh`,
exports them). See [`../docs/INSTALL.md`](../docs/INSTALL.md) for the env-var
table and [`../ROADMAP.md`](../ROADMAP.md) Phase 3 for the full design.

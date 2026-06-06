# IT Controls — dc1.azure

Control statements mapped to their technical enforcement in the dc1.azure
AAP workflow. Each control references the specific workflow node, playbook
task, and evidence artifact that satisfies it.

---

## CTL-001: Dynatrace OneAgent on all provisioned infrastructure

**Control statement:** Dynatrace OneAgent must be installed on all provisioned
Windows and Linux infrastructure. Installation must be verified by querying
the installed agent version, confirming active communication with the
Dynatrace SaaS tenant, and recording proof in the originating service request.

| Attribute | Value |
|-----------|-------|
| Category | Monitoring / Observability |
| Frequency | Every provision |
| Enforcement | Automated (AAP workflow) |
| Evidence location | ServiceNow RITM work note |

**Technical enforcement:**

| Step | Mechanism | Evidence |
|------|-----------|----------|
| 1. Agent is installed | Workflow nodes `install-dynatrace-windows` / `install-dynatrace-linux` run on every provision — they are non-optional nodes in the `DC1.Azure - Provision and Configure` workflow | AAP job log (green node = installed) |
| 2. Version is captured | `oneagentctl --get-version` runs on each VM after install | Version string published via `set_stats` (`dt_windows_oneagent_version` / `dt_linux_oneagent_version`) |
| 3. Communication is confirmed | `oneagentctl --get-server` returns the active Dynatrace server endpoint | Connection info published via `set_stats` (`dt_windows_connection_info` / `dt_linux_connection_info`) |
| 4. Tenant-side verification | Dynatrace `/api/v2/entities` API queried to confirm the host appeared in the tenant (Linux) | `dt_linux_host_verified` = `yes` in RITM |
| 5. Proof recorded on ticket | `DC1.Azure - Update RITM (success)` writes a "Dynatrace OneAgent" section to the RITM work note | RITM work note contains: tenant URL, host group, version per OS, connection info, tenant verification |

**Failure behavior:** if OneAgent installation fails, the workflow node fails
and the RITM is marked with the failure outcome — the ticket cannot be closed
as fulfilled without a successful OneAgent install.

**Playbooks:**
- `playbooks/install_dynatrace_oneagent_windows.yml`
- `playbooks/install_dynatrace_oneagent_linux.yml`
- `playbooks/servicenow/update_ritm.yml`

**Example RITM work note (success):**

```
Your Windows Server + Linux (RHEL 9) on Azure is ready.

Windows VM:
  FQDN:      dc1az-medium-abc123.eastus.cloudapp.azure.com
  Public IP:  20.121.194.187
  Admin user: demoadmin

Linux VM:
  FQDN:      dc1az-medium-def456.eastus.cloudapp.azure.com
  Public IP:  20.121.194.188
  Admin user: azureuser

Dynatrace OneAgent:
  Tenant:      https://ybz84624.live.dynatrace.com
  Host group:  dc1-azure
  Windows:     v1.301.0.20250520-140000 — https://ybz84624.live.dynatrace.com
  Linux:       v1.301.0.20250520-140000 — https://ybz84624.live.dynatrace.com
  Tenant verified: yes

(The admin password is held securely in Ansible Automation Platform — it is
intentionally NOT recorded on this ticket.)
```

---

## CTL-002: Nightly teardown of non-production infrastructure

**Control statement:** All provisioned VMs must be automatically destroyed at
end of day to prevent cost overrun and reduce attack surface. A safety-net
schedule must catch VMs that outlast the primary teardown.

| Attribute | Value |
|-----------|-------|
| Category | Cost management / Security |
| Frequency | Daily |
| Enforcement | Automated (AAP schedule) |
| Evidence location | AAP job history |

**Technical enforcement:**

| Step | Mechanism | Evidence |
|------|-----------|----------|
| 1. Primary teardown | `DC1.Azure - Nightly Teardown (6 PM)` schedule fires daily at 18:00 America/Phoenix | AAP schedule + job log |
| 2. Safety-net teardown | `DC1.Azure - Nightly Teardown (10 PM)` schedule fires daily at 22:00 America/Phoenix | AAP schedule + job log |
| 3. Idempotent | `terraform destroy` no-ops on empty state — the 10 PM run costs nothing if 6 PM already cleaned up | Zero-change job log |

---

## CTL-003: Credential lifecycle — no long-lived API tokens

**Control statement:** CaC and validation runs must not leave long-lived API
tokens on the platform. Tokens must be minted at the start of a run and
deleted in an `always:` block.

| Attribute | Value |
|-----------|-------|
| Category | Access management |
| Frequency | Every CaC apply |
| Enforcement | Automated (playbook `always:` block) |
| Evidence location | AAP gateway token list (no stale CaC tokens) |

**Technical enforcement:**
- `aap_config/load.yml` and `aap_config/validate.yml` mint a short-lived
  write/read token via `ansible.platform.token` and delete it in `always:`
- The only long-lived token is the ADO pipeline token (minted by
  `DC1.Azure - Configure ADO Trigger`, intentionally persistent)

---

## CTL-004: Cross-system traceability — RITM ↔ AAP linkage

**Control statement:** Every ServiceNow-triggered provision must record the
AAP workflow job ID on the RITM (forward link) and the RITM number in the AAP
job artifacts (reverse link), enabling end-to-end audit trail across systems.

| Attribute | Value |
|-----------|-------|
| Category | Audit trail / Traceability |
| Frequency | Every ServiceNow-triggered provision |
| Enforcement | Automated (workflow nodes) |
| Evidence location | RITM work notes + AAP job artifacts |

**Technical enforcement:**

| Step | Mechanism | Evidence |
|------|-----------|----------|
| 1. RITM → AAP link | `DC1.Azure - RITM Start Notice` posts the AAP workflow job ID + deep link to the RITM as a work note | RITM work note |
| 2. AAP → RITM link | EDA rulebook passes `ticket_number` + `ticket_sys_id` as extra vars; `set_stats` publishes `snow_ritm_number` + `snow_ritm_url` | AAP job artifacts |
| 3. Outcome recorded | `DC1.Azure - Update RITM (success/failure)` closes the RITM with the full provisioning report or incident reference | RITM final state + work note |

---

## CTL-005: CMDB CI registration and business application relationship

**Control statement:** Every provisioned server must be registered as a
Configuration Item (CI) in the ServiceNow CMDB with the correct OS class
(`cmdb_ci_win_server` or `cmdb_ci_linux_server`). Each server CI must be
related to the business application it supports via a `Uses::Used by`
relationship in the `cmdb_rel_ci` table.

| Attribute | Value |
|-----------|-------|
| Category | Configuration management / Asset tracking |
| Frequency | Every ServiceNow-triggered provision |
| Enforcement | Automated (workflow nodes) |
| Evidence location | ServiceNow CMDB (CI record + relationship) |

**Technical enforcement:**

| Step | Mechanism | Evidence |
|------|-----------|----------|
| 1. CI created with correct class | `DC1.Azure - Create CMDB CI` workflow node runs `playbooks/servicenow/create_ci.yml` — creates a CI using `servicenow.itsm.configuration_item` with class `cmdb_ci_win_server` (Windows) or `cmdb_ci_linux_server` (Linux). When `os_type=both`, creates one CI per OS. | CMDB CI record with correct class, name (FQDN), IP address, and environment |
| 2. CI linked to originating RITM | `playbooks/servicenow/create_ci.yml` uses `task_ci` table to link each CI to the RITM, enabling the CI to be traced back to the request that created it | `task_ci` record associating RITM sys_id ↔ CI sys_id |
| 3. CI related to business application | `DC1.Azure - Create CMDB Relationship` workflow node runs `playbooks/servicenow/create_cmdb_relationship.yml` — creates a `Uses::Used by` relationship in `cmdb_rel_ci` between the server CI (parent) and the `Ansible Demonstrations` business application (child) | `cmdb_rel_ci` record |
| 4. Multi-OS coverage | When `os_type=both`, both Windows and Linux CIs are created and both are independently related to the business application | Two CI records + two `cmdb_rel_ci` records |

**Failure behavior:** CMDB creation runs on a parallel branch off Provision VM
(not blocking the configure chain). A CMDB failure does not block the RITM from
being fulfilled — the CI + relationship are best-effort. The workflow graph
isolates CMDB from configure/patching so a ServiceNow API timeout cannot block
VM delivery.

**Playbooks:**
- `playbooks/servicenow/create_ci.yml`
- `playbooks/servicenow/create_cmdb_relationship.yml`

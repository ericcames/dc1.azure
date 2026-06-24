# IT Controls — dc1.azure

Control statements mapped to their technical enforcement in the dc1.azure
AAP workflow. Each control references the specific workflow node, playbook
task, and evidence artifact that satisfies it.

> **Looking for the ServiceNow GRC attestation of these controls?** Start at the
> [GRC documentation index](servicenow-grc-README.md) — it orders the design,
> install, build, attestation, and dashboard docs and tracks which controls are
> built vs designed.

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
| 1. Agent is installed | Workflow nodes `install-dynatrace-windows` / `install-dynatrace-linux` fire in parallel with the configure chain immediately after Provision VM — they are non-optional nodes in the `DC1.Azure - Provision and Configure` workflow | AAP job log (green node = installed) |
| 2. Install logged to ticket in real-time | The [`snow_log`](snow-log.md) role posts a work note to the RITM the moment the install completes — per host, with hostname and host group | RITM work note (timestamped, posted during the DT job) |
| 3. Version + connection captured | `oneagentctl --version` and `oneagentctl --get-server` run on each VM after install | Version + connected status posted to RITM via `snow_log` |
| 4. Audit proof recorded on ticket | `snow_log` posts a structured audit proof note with version, tenant URL, host group, and connection status — **in real-time during the Dynatrace JT**, not deferred to a final workflow node | RITM work note per host containing: version, tenant, host group, connected |

**Task-level, per-host logging:** each host in a multi-host group posts its
own work note with its specific hostname, version, and connection status. For
a `both` (Windows + Linux) provision, the RITM receives 6 work notes from the
Dynatrace playbooks alone — 3 per OS (install check, install result, audit
proof). All are timestamped and posted by `AAP ServiceAccount` as the tasks
execute.

**Failure behavior:** if OneAgent installation fails, the workflow node fails
and the RITM is marked with the failure outcome — the ticket cannot be closed
as fulfilled without a successful OneAgent install. The `snow_log` role is
non-breaking (failures are logged but don't block the provisioning workflow).

**Playbooks:**
- [`playbooks/install_dynatrace_oneagent_windows.yml`](https://github.com/ericcames/dc1.azure/blob/main/playbooks/install_dynatrace_oneagent_windows.yml)
- [`playbooks/install_dynatrace_oneagent_linux.yml`](https://github.com/ericcames/dc1.azure/blob/main/playbooks/install_dynatrace_oneagent_linux.yml)
- [`playbooks/roles/snow_log/`](https://github.com/ericcames/dc1.azure/tree/main/playbooks/roles/snow_log)

**Example RITM work notes (real-time, per task):**

```
17:59:04  dc1az-lnx-small (Linux): OneAgent not found — starting installation.
17:59:13  dc1az-win-small (Windows): OneAgent service not found — starting installation.
18:00:35  dc1az-lnx-small (Linux): OneAgent installed successfully (host group: dc1-azure).
18:01:21  dc1az-win-small (Windows): OneAgent installed successfully (host group: dc1-azure).
18:02:23  dc1az-lnx-small (Linux) — OneAgent audit proof:
          Version:    1.337.51.20260520-164208
          Tenant:     https://<env-id>.live.dynatrace.com
          Host group: dc1-azure
          Connected:  yes
18:05:03  dc1az-win-small (Windows) — OneAgent audit proof:
          Version:    1.337.51.20260520-164208
          Tenant:     https://<env-id>.live.dynatrace.com
          Host group: dc1-azure
          Connected:  yes
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

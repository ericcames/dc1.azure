# snow_log — Real-Time ServiceNow Ticket Logging

## Executive Summary

The `snow_log` role gives any Ansible playbook the ability to post work notes
to a ServiceNow ticket **in real-time, as each task completes**. Instead of
waiting until the end of a workflow to summarize what happened, every
meaningful step — install, configure, verify — writes its result directly to
the ticket the moment it finishes. Each host in a multi-host play posts its
own note, giving auditors and fulfillers a per-host, timestamped record of
exactly what happened and when.

**Key capability:** task-level, per-host logging to any ServiceNow ticket type
(RITM, incident, change request) from any playbook — with zero boilerplate.

### Why It Matters

| Before | After |
|--------|-------|
| One summary note posted at the end of the workflow | Individual notes posted as each task completes |
| If a mid-workflow task failed silently, the ticket showed nothing until the end | Every step is recorded — failures are visible immediately |
| Proof was routed through `set_stats` → a final update node (unreliable on retries) | Proof is written directly by the playbook that produces it |
| One monolithic message covering all tasks | Per-host, per-task notes with timestamps |

### Live Example (RITM0011974)

A ServiceNow order for a Windows + Linux VM produced these real-time work
notes on the RITM — each posted by the Dynatrace OneAgent playbook as it ran:

```
17:59:04  dc1az-lnx-small (Linux): OneAgent not found — starting installation.
17:59:13  dc1az-win-small (Windows): OneAgent service not found — starting installation.
18:00:35  dc1az-lnx-small (Linux): OneAgent installed successfully (host group: dc1-azure).
18:01:21  dc1az-win-small (Windows): OneAgent installed successfully (host group: dc1-azure).
18:02:23  dc1az-lnx-small (Linux) — OneAgent audit proof:
          Version:    1.337.51.20260520-164208
          Tenant:     https://ybz84624.live.dynatrace.com
          Host group: dc1-azure
          Connected:  yes
18:05:03  dc1az-win-small (Windows) — OneAgent audit proof:
          Version:    1.337.51.20260520-164208
          Tenant:     https://ybz84624.live.dynatrace.com
          Host group: dc1-azure
          Connected:  yes
```

Each note was posted by `AAP ServiceAccount` with a ServiceNow timestamp —
the fulfiller watching the ticket sees progress unfold in real-time.

## Usage

One `include_role` call with a message:

```yaml
- name: Log install result to ServiceNow
  ansible.builtin.include_role:
    name: snow_log
  vars:
    snow_log_message: >-
      {{ inventory_hostname }} (Linux): OneAgent installed successfully
      (host group: {{ dt_host_group }}).
```

### Defaults (override any of these)

| Variable | Default | Purpose |
|----------|---------|---------|
| `snow_log_message` | `""` | Text to post (required — empty = no-op) |
| `snow_log_resource` | `sc_req_item` | SNow table (`incident`, `change_request`, `sc_task`, etc.) |
| `snow_log_field` | `work_notes` | `work_notes` (IT-internal) or `comments` (customer-visible) |
| `snow_log_ticket_number` | `{{ ticket_number }}` | Auto-inherited from workflow |
| `snow_log_ticket_sys_id` | `{{ ticket_sys_id }}` | Skips lookup when available |

### Different ticket types

```yaml
# Log to an incident
- ansible.builtin.include_role:
    name: snow_log
  vars:
    snow_log_message: "Remediation applied."
    snow_log_resource: incident
    snow_log_ticket_number: "{{ incident_number }}"

# Post a customer-visible comment
- ansible.builtin.include_role:
    name: snow_log
  vars:
    snow_log_message: "Your VM is being configured."
    snow_log_field: comments
```

## Design

### Guard pattern

The role no-ops when `ticket_number` is empty. Non-ServiceNow launches (AAP
UI, Self-Service Portal, Azure DevOps) produce zero SNow calls and zero
errors. This preserves the "one workflow, four triggers" architecture.

### Non-breaking

If ServiceNow is unreachable or returns an error, a `rescue` block logs the
failure as a debug message and the playbook continues. Audit logging never
breaks the provisioning workflow.

### Per-host logging

The role does NOT use `run_once`. When a play targets multiple hosts (e.g.,
two Linux VMs in the `linuxweb` group), each host posts its own work note
with its specific hostname, version, and status. This gives auditors a
per-host record.

### Credential requirement

Any job template whose playbook calls `snow_log` must include the
`DC1.Azure - ServiceNow` credential in its credential list. This injects
`SN_HOST`, `SN_USERNAME`, `SN_PASSWORD` as environment variables. The role's
tasks delegate to localhost, so it works from plays targeting remote hosts.

## Source Code

| File | Purpose |
|------|---------|
| [`playbooks/roles/snow_log/defaults/main.yml`](https://github.com/ericcames/dc1.azure/blob/main/playbooks/roles/snow_log/defaults/main.yml) | Role API — variables and defaults |
| [`playbooks/roles/snow_log/tasks/main.yml`](https://github.com/ericcames/dc1.azure/blob/main/playbooks/roles/snow_log/tasks/main.yml) | Guard → resolve sys_id → patch → rescue |
| [`playbooks/roles/snow_log/meta/main.yml`](https://github.com/ericcames/dc1.azure/blob/main/playbooks/roles/snow_log/meta/main.yml) | Galaxy metadata |

### First consumers (Dynatrace OneAgent playbooks)

| File | snow_log calls |
|------|---------------|
| [`playbooks/install_dynatrace_oneagent_linux.yml`](https://github.com/ericcames/dc1.azure/blob/main/playbooks/install_dynatrace_oneagent_linux.yml) | 3 (install check, install result, audit proof) |
| [`playbooks/install_dynatrace_oneagent_windows.yml`](https://github.com/ericcames/dc1.azure/blob/main/playbooks/install_dynatrace_oneagent_windows.yml) | 3 (install check, install result, audit proof) |

## Related

- [IT Controls](controls.md) — CTL-001 references `snow_log` as the audit
  proof mechanism
- [ServiceNow Integration](servicenow-integration.md) — full SNow
  architecture (EDA inbound, callback outbound)
- [`aap.eda.dynatrace.push`](https://github.com/ericcames/aap.eda.dynatrace.push) —
  the EDA demo that consumes Dynatrace problem events from hosts instrumented
  by this workflow

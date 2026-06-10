# dt_web_availability

Ensure Dynatrace **process-group availability alerting** is enabled for the web
tier so a process outage raises a Davis **problem** — which is what fires the
DT→EDA self-heal push. Driven entirely through the Dynatrace API from the
control node: **no SSH/WinRM access to the hosts** is required.

## Why this exists

Dynatrace only opens a "process unavailable" **problem** (not just an
informational event) for a process group that has a
`builtin:availability.process-group-alerting` rule with
`alertingMode: ON_PGI_UNAVAILABILITY`. That rule was previously a **manual
runbook step** done only for Apache `httpd`, so the **Windows/IIS** self-heal
loop silently never fired — the integration looked installed but no problem was
ever raised. This role codifies the rule for **every** web process group, so
detection is OS-symmetric and can't be forgotten on a rebuild. See **AB#160**.

## What it does

1. **Skips cleanly** when `DT_API_HOST` / `DT_API_TOKEN` are not set.
2. **Resolves** each configured web process-group *name* to its `PROCESS_GROUP`
   entity id, scoped to the host group via the
   `PROCESS_GROUP_INSTANCE → HOST` relationship — so it only touches **this**
   demo's process groups, never another tenant user's generic `httpd`/`IIS`.
3. **Idempotently ensures** a `builtin:availability.process-group-alerting`
   object (`enabled: true`, `ON_PGI_UNAVAILABILITY`) exists for each resolved
   process group — process groups that already have a rule are skipped.

## Requirements

- A classic Dynatrace access token (`dt0c01.*`) with **`settings.read`,
  `settings.write`, `entities.read`**, in `DT_API_TOKEN`.
- The web service must be **running and detected by Dynatrace** when the role
  runs — a process group only exists once OneAgent has seen the process. Run
  this *after* OneAgent install + website setup.

## Key variables (see `defaults/main.yml`)

| Variable | Default | Purpose |
|----------|---------|---------|
| `dt_web_availability_api_host` | `$DT_API_HOST` | Dynatrace tenant URL |
| `dt_web_availability_api_token` | `$DT_API_TOKEN` | classic access token |
| `dt_web_availability_host_group` | `dc1-azure` | scope: only PGs on hosts in this group |
| `dt_web_availability_process_group_names` | `["Apache Web Server httpd", "IIS app pool DefaultAppPool"]` | web PGs to alert on |
| `dt_web_availability_alerting_mode` | `ON_PGI_UNAVAILABILITY` | alert when a running PGI goes down |
| `dt_web_availability_validate_certs` | `true` | Dynatrace SaaS has valid certs |

## Usage

```yaml
- hosts: localhost
  connection: local
  gather_facts: false
  roles:
    - role: dt_web_availability
```

Or run the bundled playbook: `playbooks/configure_dt_web_availability.yml`.

## Notes

- **Idempotent** — safe to run every configure; it only creates rules that are
  missing.
- **Related:** the Windows host must report a unique Dynatrace identity for
  attribution to be correct (Windows truncates the computer name to 15 chars) —
  see the `--set-host-name` fix in `install_dynatrace_oneagent_windows.yml`
  (**AB#161**). This role enables *detection*; that fix ensures the problem is
  attributed to the right host.

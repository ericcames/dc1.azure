# dt_decommission

Cleanly remove monitored hosts from **active Dynatrace problem detection** when
they are being decommissioned (VM teardown, scale-down, host retirement), so you
don't leave **stale "host unavailable" / "process unavailable" problems** open
forever on the Dynatrace Problems page.

It runs **entirely through the Dynatrace API from the control node** — it needs
**no SSH/WinRM access to the hosts** being destroyed. That makes it safe to run
*before* (or as part of) a teardown, even when the hosts are already
unreachable.

## What it does

1. **Garbage-collects** its own expired maintenance windows (so they don't pile
   up in *Settings → Maintenance* over repeated runs).
2. **Resolves** your scope (host group / hostnames / tags / raw selector) to
   concrete Dynatrace `HOST` entity IDs **and the `PROCESS_GROUP_INSTANCE`
   entities running on those hosts**. (A host-only window does **not** suppress
   process-group *availability* problems — e.g. "Apache process unavailable" —
   so the process groups must be in the filter too.)
3. **Opens a maintenance window** (suppression `DONT_DETECT_PROBLEMS`) scoped to
   exactly those entity IDs, so Dynatrace does **not** open new problems for them
   (or their processes) while they go away. The window is filtered by **entity
   ID only** — never by host group or tag — so it can never accidentally
   suppress a *future* host that reuses the same group/tag/name.
4. **Closes** any problems already open for the in-scope entities. Scoped — it
   never does a blanket close-all.

For teardown you typically call it **twice**: once before destroying the hosts
(window + close), and once after (`dt_decommission_create_window: false`,
close-only) to mop up anything Dynatrace opened in the gap. See the dc1.azure
`playbooks/teardown.yml` for a working example.

## Requirements

- A Dynatrace SaaS/Managed tenant reachable from the control node.
- A **classic access token** (`dt0c01.*`) with these scopes:

  | Scope | Used for |
  |-------|----------|
  | `entities.read` | resolve scope → host entity IDs |
  | `settings.read`, `settings.write` | create / GC the maintenance window |
  | `problems.read`, `problems.write` | close open problems |

  > **Security note:** Dynatrace has no maintenance-window-only scope —
  > `settings.write` grants tenant-wide settings write. For production tenants,
  > the **recommended** pattern is a **dedicated least-privilege token** used
  > only by this role. Reusing a broader existing token is a convenience
  > trade-off, acceptable for ephemeral/demo tenants.

## Role variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `dt_decommission_api_host` | `$DT_API_HOST` | Tenant URL, e.g. `https://abc12345.live.dynatrace.com` |
| `dt_decommission_api_token` | `$DT_API_TOKEN` | Classic access token (`dt0c01.*`) |
| `dt_decommission_validate_certs` | `true` | TLS verification for the DT API |
| `dt_decommission_entity_selector` | `""` | Advanced: raw entity selector (overrides the builders below) |
| `dt_decommission_host_group` | `""` | Scope by OneAgent host group |
| `dt_decommission_hostnames` | `[]` | Scope by detected host name(s) |
| `dt_decommission_entity_tags` | `[]` | Scope by entity tag(s), e.g. `["env:dev"]` |
| `dt_decommission_window_minutes` | `30` | Maintenance-window length |
| `dt_decommission_create_window` | `true` | Set `false` for a close-only sweep |
| `dt_decommission_close_problems` | `true` | Close already-open in-scope problems |

Provide **at least one** scope input. Precedence:
`entity_selector` > `host_group` > `hostnames` > `entity_tags`.

If the scope resolves to **zero** entities (e.g. the hosts are already gone on a
re-run), the role **skips** window creation — it will **never** create an
unfiltered window (which would suppress your whole environment) — and still
attempts the scoped problem close.

## Usage

### Standalone (any environment, env-var driven)

```bash
export DT_API_HOST=https://abc12345.live.dynatrace.com
export DT_API_TOKEN=dt0c01.XXXX...

ansible-playbook -i localhost, -c local decommission.yml \
  -e dt_decommission_host_group=my-host-group
```

```yaml
# decommission.yml
- hosts: localhost
  connection: local
  gather_facts: false
  roles:
    - role: dt_decommission
```

### Inside a teardown (AAP), bracketing the destroy

```yaml
- name: Suppress Dynatrace monitoring before destroy
  ansible.builtin.include_role:
    name: dt_decommission
  vars:
    dt_decommission_host_group: "my-host-group"

# ... destroy the hosts ...

- name: Close anything that slipped through (close-only sweep)
  ansible.builtin.include_role:
    name: dt_decommission
  vars:
    dt_decommission_host_group: "my-host-group"
    dt_decommission_create_window: false
```

## Notes

- Maintenance-window timestamps are sent as `local_date_time`
  (`YYYY-MM-DDTHH:MM:SS`, no offset) with a separate `timeZone: UTC` field, per
  the Dynatrace Settings 2.0 schema.
- The maintenance window suppresses problem *creation* only for its duration;
  the post-destroy close-only sweep is what guarantees the Problems page is
  clean even if Dynatrace opens a problem just as the window ends.

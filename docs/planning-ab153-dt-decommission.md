# AB#153 — Prevent stale Dynatrace problems during teardown

> **Status:** Reviewed 2026-06-09 (Claude); mitigations from the review are
> folded into the design and the residual-risks section. Ready to implement.
> Self-contained — includes a Dynatrace primer because the author (Eric) is
> new to DT.

## Context

When `playbooks/teardown.yml` destroys the Azure VMs, Dynatrace keeps
"host/process unavailable" problems open **indefinitely**: the VM (and its
OneAgent) vanishes, Dynatrace reads that as a sudden host loss, opens a problem,
and because the host never returns the problem never auto-closes. These stale
problems pile up on the Dynatrace Problems page after every demo cycle (and the
teardown runs on a nightly schedule, so they accumulate fast).

**Two goals, ranked:**
1. **Primary (Eric's ask):** ship a **reusable, customer-usable artifact** —
   not a dc1.azure-only patch. Any customer retiring monitored hosts hits this
   same stale-problem issue; the fix should be a drop-in they can run in their
   own environment.
2. **Secondary:** consume that artifact inside dc1.azure's `teardown.yml` so our
   own demo teardown stops leaving stale problems.

**Chosen mechanism (confirmed with Eric):** Dynatrace **Maintenance Windows**
(DT's native "maintenance mode"), driven entirely through the Dynatrace API from
the control node — **no SSH/WinRM access to the target hosts required**. This
sidesteps a hard architectural blocker (below) and is the DT-recommended way to
suppress alerting during planned maintenance.

### Why not the original story's approach (`delegate_to` → stop OneAgent)

Investigated and rejected. The Teardown JT
(`aap_config/files/controller_job_templates.yml:255`) is deliberately built so a
host-level graceful OneAgent stop cannot work from inside it:
- It runs against the **control inventory**, not `dc1-azure` (comment at
  `:258` — AAP locks the hosts of a running job's inventory, which would block
  the job from deregistering the VM it just destroyed). The target hosts aren't
  in the play.
- It carries **no machine credential**, and **AAP allows only one machine
  credential per JT** (the documented reason the Dynatrace *install* step is
  already split into separate Windows + Linux JTs, `:280-281`).
- Teardown is a **standalone JT with nightly schedules** — there is no workflow
  wrapper to hang per-OS pre-stop steps on.

So `delegate_to: {{ fqdn }}` would never authenticate and would be dead code.
The maintenance-window approach needs none of that — it's pure API.

---

## Dynatrace primer (for a DT newcomer)

- **Entity** — DT models everything it monitors as an entity with an ID:
  `HOST-1A2B…`, `PROCESS_GROUP_INSTANCE-…`, `SERVICE-…`. A VM is a `HOST` entity.
- **Entity selector** — DT's query language for picking entities, e.g.
  `type("HOST"),hostGroupName("dc1-azure")`. Used by both the Entities API and
  the Problems API.
- **Host group** — a logical label set on OneAgent at install
  (`oneagentctl --set-host-group=dc1-azure`, see
  `playbooks/install_dynatrace_oneagent_linux.yml:66`). Our VMs all land in host
  group **`dc1-azure`** (`aap_config/group_vars/all.yml:229`).
- **Problem** — DT's auto-correlated incident object. Has states `OPEN`/`CLOSED`.
  The Problems API can close one: `POST /api/v2/problems/{id}/close`.
- **Maintenance window** — a scheduled period that changes how DT alerts/detects
  for a chosen set of entities. The suppression mode
  **`DONT_DETECT_PROBLEMS`** = "Disable problem detection" → DT will **not open
  problems** for the in-scope entities during the window. This is the
  prevention lever.
- **Settings 2.0 API** — modern config API:
  `POST /api/v2/settings/objects` with a `schemaId`. Maintenance windows use
  `schemaId: builtin:alerting.maintenance-window`. (The old dedicated
  maintenance-window API is deprecated since DT 1.240.)
- **Access token** (classic `dt0c01.*`) — a scoped bearer token sent as
  `Authorization: Api-Token <token>`. Each API needs specific **scopes** (see
  Prerequisites).

---

## Design — reusable role `dt_decommission`

A self-contained, fully parameterized role at
**`playbooks/roles/dt_decommission/`**. Hardcodes nothing dc1-specific, so it
lifts cleanly into its own repo/collection later (the
[`aap.eda.dynatrace.push`](https://github.com/ericcames/aap.eda.dynatrace.push)
pattern). It runs entirely via the DT API from `localhost` — works in any AAP/
Ansible environment with network access to a DT tenant.

**What it does, in order:**
1. **Guard / skip** — if `DT_API_HOST` or `DT_API_TOKEN` is unset, skip cleanly
   (so teardown still works in environments with no Dynatrace). Assert that at
   least one scope input is provided when it does run.
2. **Garbage-collect expired windows** — list
   `builtin:alerting.maintenance-window` settings objects whose name matches
   this role's `Decommission - ` prefix and whose `endTime` is in the past;
   DELETE them. Keeps Settings → Maintenance clean across nightly runs without
   trusting any single run to clean up after itself (see residual risk 3).
3. **Resolve scope → entity IDs** — `GET /api/v2/entities` with an entity
   selector to turn the caller's scope (host group, hostnames, tags, or a raw
   selector) into a concrete list of `HOST-…` IDs. Used for both the window
   filter and problem scoping. **If zero entities resolve** (hosts already
   gone — e.g. a teardown re-run), skip window creation with a debug message —
   **never create an unfiltered window**, which would suppress the whole
   environment — but still run step 5.
4. **Open a maintenance window (prevention)** —
   `POST /api/v2/settings/objects`, `schemaId
   builtin:alerting.maintenance-window`, `suppression: DONT_DETECT_PROBLEMS`,
   `scheduleType: ONCE` from now to now + `window_minutes` (default 30),
   `filters` scoped to the resolved entity IDs — **always IDs, never
   group/tag filters** (residual risk 2). Register the created object id.
   Skipped when `dt_decommission_create_window: false` (close-only sweep mode).
5. **Close already-open in-scope problems (cleanup)** — if enabled,
   `GET /api/v2/problems?problemSelector=status("OPEN")` filtered by the
   in-scope `entitySelector`, then `POST /api/v2/problems/{id}/close` for each.
   **Scoped — never a blanket close-all**, so it can't touch unrelated tenants/
   hosts. API mechanics: the close call requires a JSON body
   (`{"message": "..."}`); the problems list paginates via `nextPageKey`;
   a 4xx on an already-closing/closed problem is success, not failure.
6. Debug summary: window id + counts (windows GC'd, problems closed).

The role is called **twice** per teardown: once pre-destroy (window + close of
pre-existing problems) and once post-destroy in close-only sweep mode
(`dt_decommission_create_window: false`) to mop up anything DT opened despite —
or after — the window (see residual risk 1).

### Role variables (`defaults/main.yml`)

| Variable | Default | Purpose |
|----------|---------|---------|
| `dt_decommission_api_host` | `{{ lookup('env','DT_API_HOST') }}` | DT tenant URL |
| `dt_decommission_api_token` | `{{ lookup('env','DT_API_TOKEN') }}` | classic token |
| `dt_decommission_host_group` | `""` | scope by host group (dc1.azure uses `dc1-azure`) |
| `dt_decommission_hostnames` | `[]` | scope by detected name / FQDN list |
| `dt_decommission_entity_tags` | `[]` | scope by entity tags |
| `dt_decommission_entity_selector` | `""` | advanced: raw selector override |
| `dt_decommission_window_minutes` | `30` | window length |
| `dt_decommission_create_window` | `true` | set `false` for a close-only sweep (post-destroy) |
| `dt_decommission_close_problems` | `true` | run the cleanup step |
| `dt_decommission_validate_certs` | `true` | uri TLS verification |

Scope precedence: `entity_selector` > `host_group` > `hostnames` >
`entity_tags`. Assert at least one is set.

### Reuse note
Mirror the existing DT API patterns already in the repo so the role feels native:
`Authorization: Api-Token …`, `lookup('ansible.builtin.env', 'DT_API_HOST'|'DT_API_TOKEN')`,
and the `uri` + `until`/`retries` polling shape in
`playbooks/dt_close_incident.yml:72-98`. All tasks use builtin modules
(`uri`, `set_fact`, `assert`, `debug`) — no new collection dependency, no
`.ansible-lint` mock additions needed.

### Maintenance-window payload (concrete shape)

```json
{
  "schemaId": "builtin:alerting.maintenance-window",
  "scope": "environment",
  "value": {
    "enabled": true,
    "generalProperties": {
      "name": "Decommission - dc1-azure - <UTC timestamp>",
      "description": "Opened by dt_decommission role during host teardown",
      "maintenanceType": "PLANNED",
      "suppression": "DONT_DETECT_PROBLEMS",
      "disableSyntheticMonitorExecution": false
    },
    "schedule": {
      "scheduleType": "ONCE",
      "onceRecurrence": {
        "startTime": "2026-06-09T20:00:00",
        "endTime":   "2026-06-09T20:30:00",
        "timeZone":  "UTC"
      }
    },
    "filters": [
      { "entityType": "HOST", "entityId": "HOST-XXXX" }
    ]
  }
}
```

**Known gotcha to validate:** `startTime`/`endTime` must be `local_date_time`
format — `YYYY-MM-DDTHH:MM:SS` with **no** trailing `Z`/offset; the zone goes in
the separate `timeZone` field. (DT community reports a "Must be of type
local_date_time" 400 when an offset is included.)

---

## dc1.azure integration

### 1. `playbooks/teardown.yml`
Two insertions:

**Pre-destroy** — after "Record VM FQDNs before destroy" (`:84-98`) and
**before** "Destroy Terraform-managed resources" (`:100`):

```yaml
- name: Suppress Dynatrace monitoring for hosts being decommissioned
  ansible.builtin.include_role:
    name: dt_decommission
  vars:
    dt_decommission_host_group: "{{ dt_host_group | default('dc1-azure') }}"
  when: lookup('ansible.builtin.env', 'DT_API_TOKEN') | default('') | length > 0
```

**Post-destroy sweep** — after the destroy task succeeds, the same include with
`dt_decommission_create_window: false` (close-only), to mop up any problem DT
opened despite the window (residual risk 1).

Gated on `DT_API_TOKEN` so teardown still runs green where DT isn't configured
(matches the existing optional-DT pattern). Scopes by host group `dc1-azure` —
no dependency on the FQDN extraction succeeding. Note: **no
`validate_certs: false`** — the repo's existing `validate_certs: false` usages
target the self-signed AAP controller, not Dynatrace; DT SaaS has valid certs
and `dt_close_incident.yml` already verifies them. Leave the role default
(`true`) so the committed example stays customer-clean.

### 2. `aap_config/files/controller_job_templates.yml` (Teardown JT, `:255-278`)
Add both DT credentials to the JT's `credentials:` list (both are
**non-machine** creds → no conflict with the one-machine-cred rule):
```yaml
      - "{{ cred_dynatrace }}"      # DT_API_HOST + DT_PAAS_TOKEN
      - "{{ cred_dynatrace_api }}"  # DT_API_TOKEN (classic, problems/settings scope)
```
(`cred_dynatrace` → `DC1.Azure - Dynatrace`, `cred_dynatrace_api` →
`DC1.Azure - Dynatrace API`; defined `aap_config/group_vars/all.yml:145-146`,
credential inputs `aap_config/files/controller_credentials.yml:97-106`.)

### 3. `docs/dev-environment.sh.example`
`DT_API_TOKEN` placeholder already exists (`:107`). Update its comment to list
the **expanded scopes** now required (see Prerequisites).

### 4. `CHANGELOG.md`
Add an `[Unreleased] → Added` entry for the `dt_decommission` role + teardown
integration; note the DT token scope expansion under a `Changed`/notes line.

### 5. Role README (`playbooks/roles/dt_decommission/README.md`)
Customer-facing: what it solves, the required token scopes, every variable, and
copy-paste standalone usage (env-var driven) **and** AAP usage. This is the
"artifact customers can use in their environment" deliverable.

---

## Prerequisites — DT token scopes (action required)

The classic `DT_API_TOKEN` (cred `DC1.Azure - Dynatrace API`, created for
AB#154 with `problems.read`/`problems.write`) must gain settings + entities
scopes. In DT: **Settings → Access tokens → (the token) → add scopes:**

- `settings.read`, `settings.write`  ← create/read the maintenance window
- `entities.read`                    ← resolve host group → entity IDs
- `problems.read`, `problems.write`  ← already present (close problems)

Then update `DT_API_TOKEN` in `docs/dev-environment.sh` and re-apply the
credential via `load.yml` so AAP injects the new value.

> Resolved (see residual risk 6): reuse the single broadened token for
> dc1.azure's demo tenant — simpler, one secret. The customer-facing role
> README recommends the opposite for production tenants: a dedicated
> least-privilege token, since `settings.write` is tenant-wide.

---

## Verification (end-to-end)

1. **Provision** Windows + Linux VMs, run the two OneAgent install JTs, confirm
   both hosts show in DT under host group `dc1-azure`.
2. **Scoped-close unit check:** stop `httpd` on the Linux host to open a problem;
   run the role standalone with `close_problems: true` scoped to one host;
   confirm only that host's problem closes and unrelated entities are untouched.
3. **Full teardown:** run the Teardown JT. Confirm in DT
   **Settings → Maintenance** a window named `Decommission - dc1-azure - …`,
   suppression "Disable problem detection", scope = the 2 hosts. Confirm
   `terraform destroy` completes and hosts deregister.
4. **The actual goal:** check the DT **Problems** page ~5–10 min after
   teardown **and again after the window expires** (~35+ min) — no new
   host/process-unavailable problems for the torn-down hosts at either point.
   Note whether the post-destroy sweep closed anything (residual risk 1's data
   point for window length).
5. **Negative test:** unset `DT_API_TOKEN`, run teardown → still green, role
   skips cleanly.
6. **Portability test (proves the artifact):** run the role from a plain
   playbook against an arbitrary host group using only env vars, in a
   non-dc1.azure context → window is created. Confirms it's environment-agnostic.
7. **GC test:** run teardown twice; the second run deletes the first run's
   expired `Decommission - ` window object (or leaves it if still active).
8. **Zero-entity test:** re-run teardown with the hosts already destroyed →
   role logs 0 entities resolved, creates **no** window, still exits green.
9. **Lint before push:** `yamllint .`, `ansible-lint`, `terraform fmt -check
   terraform/` (no TF change expected).

A live AAP env + DT tenant are available for validation (identifiers live in
`docs/dev-environment.sh`, never in this committed doc; the AAP env
auto-destroys 2026-06-20).

---

## Residual risks (reviewed 2026-06-09 — resolutions folded into the plan)

Ordered by severity. Each former open question now has a decided mitigation;
what remains "open" is only live confirmation.

1. **Problems can open *after* the window expires — the window alone is not
   sufficient.** `DONT_DETECT_PROBLEMS` suppresses problem *creation* during
   the window, but the underlying condition (host gone, never returning)
   outlives any window we pick. If DT still "expects" the host when the `ONCE`
   window ends, it can open the unavailability problem at that moment — right
   back to the original symptom, just 30 minutes later. **Decision: don't try
   to out-guess DT's host-aging timing.** Keep the 30-min window as the first
   line *and* run the post-destroy close-only sweep (already in the design) in
   the same teardown run. The sweep needs no extra scopes and is immune to DT
   timing internals. During live validation, record whether the sweep ever
   finds anything — if it reliably does, that's the data point for lengthening
   the window.

2. **A long window with broad filters would suppress the *next* provision —
   silently.** Teardown runs nightly; provision follows in the morning. If the
   window were lengthened (per risk 1) and its `filters` scoped by host group
   or tag, the freshly provisioned VMs would land in host group `dc1-azure`
   *inside a still-open window* — DT would detect no problems on them and the
   AB#154 incident-response demo would silently die, with no error anywhere in
   AAP or DT. **Decision: window `filters` always use resolved entity IDs**
   (new VMs get new entity IDs, so an old window can never capture them);
   group/tag inputs are accepted for *scoping the resolve*, never passed
   through as window filters. This also answers the old "filter granularity"
   question. The role README must call this out — customers recycling
   hostnames hit the same trap.

3. **Expired windows accumulate as settings-object clutter.** A `ONCE` window
   stops *applying* at `endTime`, but its settings object persists in
   Settings → Maintenance indefinitely — nightly teardown ≈ 30 dead objects a
   month. Deleting at end-of-play is wrong (the window must outlive the play,
   per risk 1). **Decision: garbage-collect on entry** — each role run DELETEs
   prior `Decommission - ` objects whose `endTime` is past (now design step 2).
   Idempotent, uses only the already-requested `settings.write` scope, and no
   single run is responsible for its own cleanup.

4. **Zero-entity resolution must be a clean skip — and never an unfiltered
   window.** Re-running teardown when hosts are already destroyed (or aged out
   of DT's entity visibility) resolves zero entities. Failing would break the
   "teardown always runs green" contract; worse, creating a window with empty
   `filters` could suppress problem detection for the **entire environment**.
   **Decision:** 0 entities → log it, skip window creation, still attempt the
   scoped problem close (problems can outlive their entities' visibility in
   the entities API). This is an explicit, tested code path (Verification #8).

5. **Entity-selector syntax for host group.** `type("HOST"),
   hostGroupName("dc1-azure")` is the documented host-attribute form and is
   expected to work; confirm against the live tenant before building on it.
   Fallback if it doesn't:
   `fromRelationships.isInstanceOf(type("HOST_GROUP"),entityName("dc1-azure"))`.

6. **Token scope breadth.** `settings.write` is tenant-wide settings write —
   it can modify far more than maintenance windows; DT has no
   maintenance-window-only scope. Acceptable on a demo tenant. For the
   customer-facing README, invert the Prerequisites recommendation: a
   **dedicated least-privilege token for this role is the recommended
   pattern**, with reuse of an existing token as the convenience option.

## Files touched (summary)

| File | Change |
|------|--------|
| `playbooks/roles/dt_decommission/{tasks,defaults,meta}/main.yml` | **New** reusable role |
| `playbooks/roles/dt_decommission/README.md` | **New** customer-facing usage |
| `playbooks/teardown.yml` | include the role pre-destroy + post-destroy sweep (gated) |
| `aap_config/files/controller_job_templates.yml` | add 2 DT creds to Teardown JT |
| `docs/dev-environment.sh.example` | document expanded `DT_API_TOKEN` scopes |
| `CHANGELOG.md` | Unreleased entry |

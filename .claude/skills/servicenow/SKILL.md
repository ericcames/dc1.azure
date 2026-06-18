---
name: servicenow
description: >-
  Work with the dc1.azure ServiceNow integration — catalog item updates,
  REST Message configuration, EDA trigger debugging, CMDB/RITM operations.
  TRIGGER when the user mentions ServiceNow, SNow, catalog item, RITM,
  CMDB CI, EDA trigger, Business Rule, or the SNow→AAP event flow.
  SKIP for general AAP config (use /install-dc1-azure) or code-only changes
  that don't touch the ServiceNow integration surface.
---

# ServiceNow Integration — dc1.azure

Reference context for working with the ServiceNow side of dc1.azure. The
integration is event-driven (Phase 8): a ServiceNow catalog request triggers
an AAP workflow via EDA, and the workflow calls ServiceNow back with results.

## Architecture (read this first)

```
ServiceNow catalog order
  → Business Rule (fire_eda_on_ritm.js)
  → Outbound REST Message (Ames - DC1.Azure EDA Event Stream)
  → AAP EDA event stream (DC1.Azure - ServiceNow Event Stream)
  → Rulebook (rulebooks/servicenow_events.yml) matches on short_description
  → Workflow: DC1.Azure - Provision and Configure
  → Callback playbooks (playbooks/servicenow/*.yml) update RITM + CMDB
```

Full design doc: `docs/servicenow-integration.md`.
SNow-side setup instructions: `servicenow/README.md`.

## Guardrails

- **Never print `SN_PASSWORD` or `EDA_EVENT_STREAM_TOKEN`** — check by name
  only (`printenv SN_PASSWORD >/dev/null && echo set`). Suggest `! export`
  for user-entered secrets.
- **Confirm `SN_HOST`** before any mutation — this is a shared instance with
  33 other SEs' REST Messages. Scope all writes by `sys_id`, never by name
  alone. Namespace objects with `Ames -` prefix and properties with `dc1.*`.
- **The short_description is the trigger** — it must match
  `my_azure_catalog_short_description` in `aap_config/group_vars/all.yml`
  byte-for-byte. If either side changes alone, orders silently fail.
- **Bearer token is a matched pair** — the same random value must be in both
  the SNow encrypted property (`dc1.eda_event_stream_token`) and the AAP
  EDA event-stream credential. No trailing newline.
  Generate: `openssl rand -hex 32`.

## Key files

| File | Purpose |
|------|---------|
| `rulebooks/servicenow_events.yml` | EDA rulebook — matches `short_description`, launches workflow |
| `servicenow/business_rules/fire_eda_on_ritm.js` | SNow Business Rule — posts payload to EDA |
| `servicenow/README.md` | SNow-side setup (catalog item, REST Message, Business Rule) |
| `docs/servicenow-integration.md` | Full design doc + as-built record |
| `playbooks/servicenow/update_catalog_item.yml` | API playbook — update catalog item text fields |
| `playbooks/servicenow/update_ritm.yml` | Callback — update RITM (success/failure) |
| `playbooks/servicenow/create_ci.yml` | Callback — register VM as CMDB CI |
| `playbooks/servicenow/create_cmdb_relationship.yml` | Callback — link CI to business app |
| `playbooks/servicenow/create_incident.yml` | Callback — open incident on failure |
| `playbooks/servicenow/notice_ritm_started.yml` | Callback — start notice on RITM |
| `playbooks/servicenow/create_user.yml` | API playbook — create a SNow user + assign roles and group memberships |
| `aap_config/files/eda_credentials.yml` | EDA credentials (controller, event stream, SCM) |
| `aap_config/files/eda_event_streams.yml` | EDA event stream definition |
| `aap_config/files/eda_rulebook_activations.yml` | Rulebook activation + extra_vars |
| `aap_config/group_vars/all.yml` | `my_azure_catalog_short_description` + `eda_*` vars |

## Credentials

| Env var | Purpose |
|---------|---------|
| `SN_HOST` | ServiceNow instance URL (`https://….service-now.com`) |
| `SN_USERNAME` | ServiceNow API user (needs admin role for REST Message writes) |
| `SN_PASSWORD` | ServiceNow API password |
| `EDA_EVENT_STREAM_TOKEN` | Bearer token for the SNow→EDA webhook (matched pair) |

All are in `docs/dev-environment.sh` (gitignored). Template:
`docs/dev-environment.sh.example`.

## Common tasks

### Update the catalog item (text fields)
```bash
source docs/dev-environment.sh && \
ansible-playbook playbooks/servicenow/update_catalog_item.yml \
  -e catalog_short_description="DC1.Azure Infrastructure Provisioning"
```
The picture (icon) must be uploaded manually in the SNow UI — drag-drop the
PNG onto the catalog item form. File: `docs/images/catalog-it-infrastructure.png`.

### Verify the EDA trigger fires
1. Check the EDA activation is running (AAP UI → Automation Decisions → Rulebook Activations)
2. Check the match string matches: `grep my_azure_catalog_short_description aap_config/group_vars/all.yml` vs the SNow catalog item's Short description
3. Place a test order in ServiceNow
4. Check AAP Jobs for the workflow launch
5. If no launch: check EDA Rule Audit log, then the SNow System Log for the BR's HTTP status

### Business Rule "Requested for" allowlist
The BR filter includes a **"Requested for" allowlist** (Eric Ames, Mark
Lowcher, AAP ServiceAccount). Only orders placed by these users trigger the
EDA event. This is intentional — the shared SNow instance has 33 other SEs,
and their orders must NOT fire this workflow. **If a new demo user needs to
place orders, add them to the BR filter conditions in the ServiceNow UI**
(Business Rule → "Ames - Service Catalog - dc1.azure" → When to run →
Filter Conditions → add an OR "Requested for is \<user\>").

API-placed orders (e.g. via `servicenow.itsm.api` or the Order Now API) run
as `AAP ServiceAccount` — that's why it's in the allowlist.

### Read an incident's work notes / comments (debugging the self-heal)
Work notes and comments are NOT columns on `incident` — they live in the
`sys_journal_field` table, keyed by the incident's `sys_id`:
```bash
# 1. get the incident sys_id
GET /api/now/table/incident?sysparm_query=number=INC0011380&sysparm_fields=sys_id
# 2. read its journal entries in order (element = work_notes | comments)
GET /api/now/table/sys_journal_field?sysparm_query=element_id=<sys_id>^ORDERBYsys_created_on&sysparm_fields=element,value,sys_created_on
```
This is how you verify what each self-heal node actually posted (triage →
remediate → close → confirm) and catch attribution mismatches between
`short_description` and the remediation notes (see AB#166).

### Create a ServiceNow user with roles and groups
```bash
source docs/dev-environment.sh && \
ansible-playbook playbooks/servicenow/create_user.yml \
  2>&1 | tee /tmp/snow-create-user-$(date +%Y%m%d-%H%M%S).log
```
Creates the `sys_user`, then assigns roles (`sys_user_has_role`) and group
memberships (`sys_user_grmember`). Defaults provision Brian Hoppus as an
exact-access clone of Eric; override the `user_*` vars (incl. `user_roles`,
`user_groups`) with `-e` for a different user. Notes:

- **No password is set** — login won't work until someone sets it in the SNow
  UI (User record → Set Password). The account is created `active` so role/group
  assignment works regardless.
- **Idempotent / re-run safe** — skips creation if a user with that email
  already exists, and skips any role grant / group membership already present.
- **`admin` auto-inherits** hundreds of roles, so only the directly-granted set
  needs listing. `snc_basic_auth_api_access` = REST API (basic-auth) access.
- To find a group's `sys_id`: query `sys_user_group?name=<group>`. To clone
  another user's directly-granted roles: query
  `sys_user_has_role?user=<sys_id>^inherited=false`.
- This does **not** add the user to the catalog-order allowlist — see the
  "Business Rule Requested for allowlist" task above if they need to place
  orders that fire the EDA workflow.

### Update the REST Message endpoint (Phase 13 — not yet automated)
Currently manual: update the `Ames - DC1.Azure EDA Event Stream` Outbound REST
Message endpoint URL in the ServiceNow UI when the AAP environment changes.
Phase 13 will automate this with a `configure_outbound_rest.yml` playbook.

### Rotate the bearer token
1. Generate: `openssl rand -hex 32`
2. Update SNow: System Properties → `dc1.eda_event_stream_token` → paste
3. Update AAP: `DC1.Azure - ServiceNow Event Stream` credential → Token → paste
4. Test: place an order → verify EDA fires

## Module patterns

- **`servicenow.itsm.api`** — generic Table API (PATCH/POST). Default for
  updating catalog items, REST Messages, RITMs, CMDB relationships.
- **`servicenow.itsm.api_info`** — read-only query. Use for lookups.
- **`servicenow.itsm.configuration_item`** — specialized CMDB CI create/update.
- **`servicenow.itsm.incident`** — specialized incident create.

All consume `SN_*` env vars from the `DC1.Azure - ServiceNow` credential
(ServiceNow ITSM Credential type) automatically.

## CMDB CI classes

The CI class is OS-conditional (`create_ci.yml`):
- `os_type == 'windows'` or `'both'` → `cmdb_ci_win_server`
- `os_type == 'linux'` → `cmdb_ci_linux_server`

## CMDB CI lifecycle & `install_status` (AB#166)

**Convention (decided 2026-06-10): the automation owns `install_status` end to
end.** Provision creates the CI as `Installed`; teardown must retire it. Without
that, torn-down hosts pile up as live-looking CIs and poison host→CI lookups.

`install_status` values (verified live in this instance):

| Value | Label | Value | Label |
|------:|-------|------:|-------|
| 1 | **Installed** (live host) | 6 | In Stock |
| 2 | On Order | 7 | **Retired** ← set at teardown |
| 3 | In Maintenance | 8 | Stolen |
| 4 | Pending Install | 100 | Absent (Discovery "not found") |
| 5 | Pending Repair | | |

- **Teardown → set the destroyed host's CI to `install_status=7` (Retired), not
  delete** — keeps audit history (additive). **Implemented in AB#170:**
  `teardown.yml` retires the CI(s) — both `install_status` AND
  `operational_status` = Retired — in the same cleanup block that deregisters
  the host + cleans up Dynatrace. Looked up by name (the FQDN), update-only-if-
  exists, gated on `SN_HOST`.

### Resolving a host → its CMDB CI (DON'T use bare `nameLIKE` + record[0])

**AB#166 root cause:** `dt_triage.yml` resolved the affected host by taking the
Dynatrace problem event's `host.name` (a **truncated 15-char NetBIOS** string,
e.g. `dc1az-win-mediu`) and running `sysparm_query: nameLIKE<that>`, then using
`record[0]`. That substring is ambiguous across every medium Windows host ever
provisioned — a live query returned **5** matches and `record[0]` was a stale,
non-operational CI. The incident got attributed to the **wrong host** while
remediation (which targets the live `windemo` inventory) hit the right one.

When resolving a host to a CI:
- Prefer an **exact** name match on the **full FQDN** — and get the FQDN from the
  authoritative source (the live AAP inventory, or the DT *entities* API:
  problem → affected PGI → HOST scoped to `hostGroupName("dc1-azure")` and
  currently reporting), **not** the truncated DT problem-*event* string. (AB#161
  fixed the DT host *entity* name for Windows; **AB#169 did the same for Linux**,
  so the Azure public FQDN is now the single canonical identity across the DT
  host, AAP inventory, and CMDB `name` for both OSes — which makes the exact-FQDN
  match viable. Neither changed the truncated event *payload*.)
- If you must `LIKE`, at minimum filter `install_status=1` and
  `^ORDERBYDESCsys_created_on` so an ambiguous match can never pick a retired or
  stale CI.

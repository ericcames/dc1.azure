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

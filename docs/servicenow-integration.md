# ServiceNow Integration — Design (Phase 8, Demo v2)

**Status:** ✅ **Built and live-validated end-to-end (Phase 8 complete,
2026-06-02)** — design v2 (event-driven), superseding the v1 direct-REST design.
This document is both the design rationale and the as-built record; the
component inventory below reflects the shipped state. Secrets
(`SN_HOST`/`SN_USERNAME`/`SN_PASSWORD` + the shared `EDA_EVENT_STREAM_TOKEN`) live
in the gitignored `docs/dev-environment.sh`.

> **What changed from v1:** the inbound trigger is no longer ServiceNow Flow
> Designer doing a direct REST `launch/` of the workflow. Instead a ServiceNow
> **Business Rule** fires an **Outbound REST Message** at an **AAP Event-Driven
> Ansible (EDA) event stream**; a dc1.azure-owned **rulebook** matches the
> request and runs the workflow with `run_workflow_template`. This mirrors the
> proven `aap.dailydemo.windows` pattern. The AAP→ServiceNow callback half is
> unchanged in spirit (now expanded to full Windows parity).

## Goal

A business user opens the **ServiceNow self-service catalog**, requests a
VM on Azure (Windows or Linux), picks a t-shirt size, and submits. A ServiceNow Business
Rule posts the request to an AAP EDA event stream. EDA matches it and launches
the existing **`DC1.Azure - Provision and Configure`** workflow. When the
workflow finishes, **AAP calls ServiceNow back** to update the request item
(RITM) with the outcome — state, public IP, FQDN, admin user — register the VM
as a **CMDB CI** (with a relationship to its business app), and on failure open
an **Incident**. The user closes the ticket. No AAP login, no Azure knowledge
required of the requester.

This is **Demo v2**. It reuses the *exact* Phase 4 provisioning chain; the
ServiceNow-specific work is the EDA ingress in front and the callback/CMDB/
incident nodes appended behind — the same core workflow the AAP-UI (Phase 6),
Self-Service Portal (Phase 9), and ADO (Phase 10) triggers all drive.

---

## Decisions

| Question | Decision | Why |
|----------|----------|-----|
| **Inbound trigger** — direct REST `launch/` vs EDA event stream | **EDA event stream** (Business Rule → Outbound REST Message → event stream → rulebook → `run_workflow_template`) | ServiceNow holds **no workflow ID and no launch-scoped OAuth token** — only the event-stream URL + a bearer token. EDA decides *which* workflow runs by `short_description`, so one ingress serves every SNow-driven demo. Matches the proven `aap.dailydemo.windows` pattern. |
| **Rulebook home** — extend the shared `event.driven.ansible` rulebook vs a dc1.azure-owned rulebook | **dc1.azure-owned rulebook** | Keeps every Azure asset in this repo — no cross-repo PR into `ericcames/event.driven.ansible`, consistent with the repo-standalone principle. dc1.azure registers itself as an EDA project and ships its own rulebook + activation. |
| **Result-reporting direction** — SNow polls AAP vs AAP calls SNow back | **AAP calls SNow back** | Richer payoff: the RITM auto-fills with IP/FQDN on screen and the CMDB updates. Keeps polling/status logic out of ServiceNow. Uses the existing `ServiceNow ITSM Credential` type. |
| **Callback scope** | **Full Windows parity** — RITM update (success + failure) + CMDB CI + CMDB relationship + Incident-on-failure | Mirrors the `aap.dailydemo.windows` node graph. Most complete demo; built mostly by *wiring* the already-synced Windows ServiceNow playbooks, not new code. |
| **Auth from SNow → EDA** — direct outbound vs MID Server | **Direct Outbound REST Message** (token-auth) | Demo on the Red Hat shared SNow dev instance, not enterprise prod. *MID Server documented below as the enterprise-standard alternative.* |
| **Timeout behavior** — what does the RITM show if provisioning hangs? | **Callback runs on both success and failure paths** | The RITM always reaches a terminal state (Fulfilled or a failure note + Incident) — never hangs silently. See [Failure & timeout behavior](#failure--timeout-behavior). |

---

## Architecture & sequence

```
 ServiceNow                          AAP / EDA                          AAP Controller + Azure
 ──────────                          ─────────                          ──────────────────────
 1. User submits catalog item
    "Request VM (Azure)"
    (size, justification)
        │
        │ 2. Business Rule (on sc_req_item
        │    insert/approve) fires an
        │    Outbound REST Message:
        │      POST <event-stream URL>
        │      Authorization: Bearer <token>
        │      body: { number, sys_id,
        │              short_description,
        │              vm_size_tier }
        ▼
                            3. Event Stream (type: snow) feeds
                               the rulebook source __SOURCE_1.
                               Rulebook rule:
                                 condition: event.payload.short_description
                                            == my_azure_catalog_short_description
                                 action: run_workflow_template ─────────► 4. Workflow runs (Phase 4 chain):
                                   extra_vars:                               Provision VM ─► Powershell ─►
                                     ticket_number = event.payload.number    Website Setup ─► Provision Access ─►
                                     ticket_sys_id = event.payload.sys_id     Patching ──────────────► VM live
                                     vm_size_tier  = event.payload.vm_size_tier
                                                                            5. NEW nodes (full parity):
                                                                               Provision VM success ► Create CMDB CI
                                                                                        ► Relationship  (parallel, early)
                                                                               Patching always ► Update RITM (Fulfilled)
                                                                               failure ► Create Incident
                                                                                        ► Update RITM (failed + incident #)
        ┌───────────────────────────────────────────────────────────────────────┘
        │ 6. servicenow.itsm PATCHes sc_req_item (state, work note w/ FQDN+IP+admin),
        │    creates the cmdb_ci_* record + rel_ci relationship, opens incident on failure
        ▼
 7. RITM shows Fulfilled + connection details, CMDB has the new CI; user closes the ticket
```

`ticket_number` (e.g. `RITM0012345`) and `ticket_sys_id` thread into the launch.
They serve three purposes:
- `ticket_number` flows to the IIS landing page (already templated in
  `website_setup_azure/templates/index.html.j2` — today shows `N/A`; this closes
  that loop),
- `ticket_sys_id` tells the callback nodes **which** record to PATCH (no second
  lookup needed — though the Windows `update_requested_item` role also resolves
  by `numberSTARTSWITH` as a fallback), and
- `vm_size_tier` drives the Provision VM node (the catalog dropdown maps to the
  same survey choices).

---

## Component inventory

> **✅ As-built — everything below is implemented, merged, and live-validated
> (Phase 8 complete, 2026-06-02).** This inventory was the original build plan;
> the Status column now reflects the shipped state. See `CHANGELOG.md` and
> `ROADMAP.md` Phase 8 for the per-component PRs.

### Inbound — EDA ingress (new)

| Component | Status | Where |
|-----------|--------|-------|
| `ansible.eda` collection | ✅ done | `aap_config/requirements.yml` |
| dc1.azure EDA project (this repo, hosting the rulebook) | ✅ done | `aap_config/files/eda_projects.yml` (already has `event.driven.ansible`; add a `DC1.Azure - EDA` entry → this repo) |
| `rulebooks/servicenow_events.yml` (Azure-owned rulebook) | ✅ done | new `rulebooks/` dir in this repo |
| `ServiceNow Event Stream` credential (built-in type; token auth) | ✅ done | `aap_config/files/eda_credentials.yml` |
| `Controller Credential` (so EDA can launch the workflow) | ✅ done | `aap_config/files/eda_credentials.yml` |
| Decision Environment | ✅ done | `aap_config/files/eda_decision_environments.yml` |
| Event Stream (`event_stream_type: snow`, `forward_events: true`) | ✅ done | `aap_config/files/eda_event_streams.yml` |
| Rulebook Activation (binds event stream → source `__SOURCE_1`) | ✅ done | `aap_config/files/eda_rulebook_activations.yml` |

### Outbound — callback / CMDB / incident (full parity)

| Component | Status | Where |
|-----------|--------|-------|
| `servicenow.itsm` collection | ✅ done | `aap_config/requirements.yml` + EE rebuild |
| `ServiceNow ITSM Credential` **type** | ✅ exists | `aap_config/files/controller_credential_types.yml` |
| `DC1.Azure - ServiceNow` credential **instance** | ✅ done | `aap_config/files/controller_credentials.yml` |
| `Update RITM (success)` / `Update RITM (failure)` JTs | ✅ done | `aap_config/files/controller_job_templates.yml` |
| `Create CMDB CI` / `Create CMDB Relationship` / `Create Incident` JTs | ✅ done | `aap_config/files/controller_job_templates.yml` |
| Workflow nodes (success → CMDB → RITM; failure → Incident → RITM) | ✅ done | `aap_config/files/controller_workflow_job_templates.yml` |
| `validate.yml` assertions (creds + JTs + EDA objects) | ✅ done | `aap_config/validate.yml` |
| SNow secrets placeholders | ✅ done | `docs/dev-environment.sh.example` |

> **Playbook sourcing (as-built):** the ServiceNow callback JTs — *RITM Start
> Notice, Create CMDB CI, Create CMDB Relationship, Update RITM (success/failure),
> Create Incident* — run **dc1.azure-owned** playbooks under
> `playbooks/servicenow/` (`notice_ritm_started.yml`, `create_ci.yml`,
> `create_cmdb_relationship.yml`, `update_ritm.yml`, `create_incident.yml`) on the
> **dc1.azure project** (`project_name`). They *model* the `aap.dailydemo.windows`
> ServiceNow roles (same modules/fields) but are dc1.azure-owned and **guarded on
> `ticket_number`** so non-ServiceNow launches (AAP UI / Self-Service / ADO) no-op
> — see [Threading](#threading-provisioning-details-to-the-callback). Only the
> OS-configure JTs (Powershell Improvement, Provision Access, Patching) reuse the
> already-synced `aap.dailydemo.windows` project (`windows_project_name`, pinned
> `v1.0.1`); the rest run dc1.azure's own project.

---

## Inbound: ServiceNow → EDA (trigger)

### Catalog item — "Request VM (Azure)"
Variables:
- `vm_size_tier` — dropdown, choices `small-2cpu-8gb` / `medium-4cpu-16gb` /
  `large-8cpu-32gb` (mirror the AAP survey exactly; default `medium-4cpu-16gb`).
- `justification` — single-line text (for the demo narrative).
- `requestor` — reference to `sys_user`, auto-populated.

The catalog item's **`short_description`** must be a unique, stable string —
this is what the rulebook matches on. Pin it as the var
`my_azure_catalog_short_description` (e.g. `"DC1.Azure Infrastructure Provisioning"`)
used in *both* the rulebook condition and the activation `extra_vars`.

### Business Rule + Outbound REST Message
On `sc_req_item` insert (or on approval, matching the demo narrative), a
**Business Rule** triggers an **Outbound REST Message**:
- Method `POST`, endpoint = the **EDA event-stream URL** (AAP shows it after the
  event stream is created).
- Header `Authorization: Bearer <token>` — the same token configured on the
  `ServiceNow Event Stream` credential (`http_header_key: Authorization`,
  `auth_type: token`). Stored as a SNow credential/secret, **not** inline.
- Body (JSON): `number`, `sys_id`, `short_description`, and `vm_size_tier`
  from the catalog variables.

> **Auth alternative (enterprise):** route the Outbound REST Message through a
> **MID Server** rather than direct outbound. Standard in regulated environments
> (no direct SNow→internet path) but requires standing up + registering a MID
> Server. Out of scope for the demo; noted for customer conversations.

### EDA objects (CaC, consumed by `infra.aap_configuration.dispatch`)

`eda_credentials.yml`:
```yaml
eda_credentials:
  - name: Controller Credential          # lets EDA launch the workflow
    credential_type: 'Red Hat Ansible Automation Platform'
    organization: "{{ my_organization }}"
    inputs:
      host: "{{ aap_hostname }}/api/controller/"
      username: "admin"
      password: "{{ aap_password }}"
      verify_ssl: true
  - name: DC1.Azure - ServiceNow Event Stream
    credential_type: 'ServiceNow Event Stream'   # built-in EDA type
    organization: "{{ my_organization }}"
    inputs:
      auth_type: token
      http_header_key: Authorization
      token: "{{ eda_event_stream_token }}"      # shared secret w/ SNow Outbound REST
```

`eda_decision_environments.yml`: a `Default Decision Environment`
(`de-supported-rhel8:latest` from `registry.redhat.io`) — needs a
`registry.redhat.io` Container Registry credential.

`eda_event_streams.yml`:
```yaml
eda_event_streams:
  - name: DC1.Azure - ServiceNow Event Stream
    credential_name: DC1.Azure - ServiceNow Event Stream
    organization: "{{ my_organization }}"
    event_stream_type: snow
    forward_events: true
```

`eda_projects.yml`: add a dc1.azure EDA project pointing at **this repo's Azure
DevOps git URL** (the rulebook's home). EDA needs an SCM credential that can
reach the ADO repo (a PAT-backed Source Control credential) — reuse the same
auth the controller `DC1.Azure` project already uses against ADO.

`eda_rulebook_activations.yml`:
```yaml
eda_rulebook_activations:
  - name: DC1.Azure - Catch ServiceNow Events
    project: DC1.Azure - EDA
    organization: "{{ my_organization }}"
    rulebook: servicenow_events.yml
    decision_environment: Default Decision Environment
    extra_vars:
      my_azure_catalog_short_description: "{{ my_azure_catalog_short_description }}"
    event_streams:
      - event_stream: DC1.Azure - ServiceNow Event Stream
        source_name: __SOURCE_1
    eda_credentials: Controller Credential
    state: present
```

### Rulebook — `rulebooks/servicenow_events.yml`
Pattern from `event.driven.ansible/rulebooks/servicenow/servicenow_events.yml`,
scoped to the one Azure rule:
```yaml
---
- name: Listen for approved requested items from ServiceNow
  hosts: all
  sources:
    - ansible.eda.webhook:
        host: 0.0.0.0
        port: 5000
  rules:
    - name: Run the DC1.Azure provision-and-configure workflow
      condition: event.payload.short_description == vars.my_azure_catalog_short_description
      action:
        run_workflow_template:
          name: "DC1.Azure - Provision and Configure"
          organization: "{{ my_organization }}"
          job_args:
            extra_vars:
              ticket_number: "{{ event.payload.number }}"
              ticket_sys_id: "{{ event.payload.sys_id }}"
              vm_size_tier: "{{ event.payload.vm_size_tier }}"
```
The event stream wraps this `webhook` source via `source_name: __SOURCE_1` in
the activation — AAP exposes the external URL and enforces the bearer token.

---

## ServiceNow UI setup — click-by-click (as built)

The inbound trigger, exactly as configured on the ServiceNow side. The
copy-paste artifacts (Business Rule script) are version-controlled under
[`servicenow/`](../servicenow/) — see [`servicenow/README.md`](../servicenow/README.md)
for the same steps in install order. **Placeholders:** `<your-snow-instance>`, the
AAP event-stream URL/UUID, and the bearer token are deployment-/secret-specific —
never commit the live values. The token lives only in `docs/dev-environment.sh` as
`EDA_EVENT_STREAM_TOKEN`; copy the event-stream URL from AAP at run time.

### 1. Catalog item
*Service Catalog → Catalog Definitions → Maintain Items → New*
- **Name:** any friendly label (e.g. `Request VM (Azure)`)
- **Short description:** `DC1.Azure Infrastructure Provisioning` — **the exact match string**
  the rulebook keys on (`my_azure_catalog_short_description`). The RITM inherits
  this field, so it must match byte-for-byte (no trailing space).
- Catalog: Service Catalog · Category: your choice · Active: ✓

### 2. Variable — `vm_size_tier`
On the item, add a variable:
- **Type:** Multiple Choice
- **Name:** `vm_size_tier` (matches the REST body field **and** `event.payload.vm_size_tier`)
- **Default value:** `medium-4cpu-16gb` (mirrors the AAP survey default)
- **Question Choices** (Text = Value), optional monthly `Recurring price` (Windows
  PAYG, `eastus`, ~730 h/mo — see ROADMAP Sizing Tiers):

  | Text / Value | Recurring price |
  |---|---|
  | `small-2cpu-8gb` | 137.24 |
  | `medium-4cpu-16gb` | 274.48 |
  | `large-8cpu-32gb` | 548.96 |

### 3. Outbound REST Message
*System Web Services → Outbound → REST Message → New*
- **Name:** `Ames - DC1.Azure EDA Event Stream`
- **Endpoint:** the AAP event-stream external URL — copy from *Automation Decisions →
  Event Streams → `DC1.Azure - ServiceNow Event Stream` → URL*. Shape:
  ```
  https://<aap-host>/eda-event-streams/api/eda/v1/external_event_stream/<stream-uuid>/post/
  ```

HTTP Method (the **HTTP Methods** related list → New):
- **HTTP method:** POST · **Name:** `POST`
- **HTTP Headers:**
  - `Content-Type: application/json`
  - `Authorization: Bearer <token>` — **static header**; matched pair with
    `EDA_EVENT_STREAM_TOKEN` (no trailing newline → the #1 cause of a 401)
- **No Content/body template** — the Business Rule builds the JSON and sets it with
  `setRequestBody()`, so there are **no** `${...}` parameters to define here.

### 4. Business Rule — fire the REST message
*System Definition → Business Rules → New*
- **Table:** Requested Item [`sc_req_item`] · **Advanced:** ✓ *(required — the script
  tab is silently ignored without it)*
- **When:** after · **Insert:** ✓
- **Filter:** Catalog Item *is* your item (so only this request type POSTs to EDA)
- **Script:** paste [`servicenow/business_rules/fire_eda_on_ritm.js`](../servicenow/business_rules/fire_eda_on_ritm.js)
  verbatim — kept as a file so it's the single source of truth, not duplicated here.
  It builds the payload (number, sys_id, short_description, **all** catalog variables,
  requester), **trims every value** via a `clean()` helper (prevents the
  `vm_size_tier "medium-4cpu-16gb "` trailing-space survey-validation failure), POSTs
  via the REST Message, and logs the HTTP status to *System Logs → All*.

> **Token handling — two options.** As-built uses the **static `Authorization`
> header** in step 3 (simplest; the token sits readable in the REST Message record).
> To keep it out of that record, instead store it as an encrypted system property
> (`sys_properties` → `dc1.eda_event_stream_token`, type `password2 (Encrypted)`,
> value = `EDA_EVENT_STREAM_TOKEN`) and inject it in the script with
> `r.setRequestHeader('Authorization', 'Bearer ' + gs.getProperty('dc1.eda_event_stream_token'))`.
> Either way it's a matched pair with the AAP `ServiceNow Event Stream` credential.

### Verify
- **ServiceNow:** *System Logs → All* → look for `DC1.Azure EDA trigger [RITM...] -> HTTP 200`.
- **AAP:** the event stream's *events received* count increments and the
  `DC1.Azure - Catch ServiceNow Events` activation launches
  `DC1.Azure - Provision and Configure`.
- **401?** The property value drifted from `EDA_EVENT_STREAM_TOKEN` (usually a
  trailing newline). They are a matched pair — same value on both sides.
- **Workflow launches but no RITM/CMDB update?** That's the **outbound** half
  (below) — it needs the rebuilt `DC1.Azure - EE` carrying `servicenow.itsm`.

> **Pre-flight without ServiceNow.** You can prove the AAP side independently by
> POSTing the same 4-field JSON (with the bearer header) to the event-stream URL
> via `curl` — if the workflow launches, any remaining issue is ServiceNow-side.

---

## Outbound: AAP → ServiceNow (callback, CMDB, incident)

### Credential instance — `DC1.Azure - ServiceNow`
Of type `ServiceNow ITSM Credential` (already defined). Injects
`SN_HOST`/`SN_USERNAME`/`SN_PASSWORD` from `docs/dev-environment.sh`
(gitignored). Namespaced `DC1.Azure -`.

### Job templates (dc1.azure-owned callback playbooks)
- `DC1.Azure - Create CMDB CI` → `playbooks/servicenow/create_ci.yml`
  (dc1.azure-owned; modeled on the upstream Windows `create_configuration_item`
  role — CI class **`cmdb_ci_win_server`**, fields as in that role's `vars/main.yml`). The role's AWS-flavored fields —
  `serial_number` (`my_instance_id`), `asset_tag` (`my_ami_id`), `model_number`
  (`my_instance_type`) — need Azure equivalents threaded via `set_stats` (Azure
  VM ID, resource ID/omit, and `vm_size_tier`/SKU respectively). **AB#93:** after
  registering the CI, the same playbook links it back to the originating request
  by patching `sc_req_item.configuration_item = <CI sys_id>` (the RITM's
  *Configuration item* field), so the ticket and the CMDB record reference each
  other. The patch lives here — not in `update_ritm.yml` — because the CI sys_id
  is only known on this branch (Create CMDB CI and Update RITM run on sibling
  branches, so a `set_stats` artifact would not reach Update RITM).
- `DC1.Azure - Create CMDB Relationship` → `playbooks/servicenow/create_cmdb_relationship.yml`
- `DC1.Azure - Update RITM (success)` → `playbooks/servicenow/update_ritm.yml`
  (state Fulfilled, work note w/ FQDN + public IP + admin user)
- `DC1.Azure - Update RITM (failure)` → same playbook, failure vars (state 4 +
  the incident number + error message — `update_ritm.yml` drives both outcomes
  via the `ritm_outcome` extra-var)
- `DC1.Azure - Create Incident` → `playbooks/servicenow/create_incident.yml`

All carry the `DC1.Azure - ServiceNow` credential. Inventory: `dc1-azure-control`
(localhost plays; same reasoning as the Teardown JT — keep them off `dc1-azure`).

### Workflow wiring — append to `DC1.Azure - Provision and Configure`
Mirror the Windows graph (`controller_templates_workflow.yml`):
- **Provision VM** `success_nodes` → **Create CMDB CI** → `success_nodes` →
  **Create CMDB Relationship** (parallel, early — runs alongside the configure
  chain; mirrors DDW branching CMDB off Get Instance Info). Terminal at the
  relationship node.
- **Patching** `always_nodes` → **Update RITM (success)** (decoupled from CMDB,
  mirrors DDW *Update request ticket - success* — fires whenever the workflow
  reaches Patching).
- **Provision VM** `failure_nodes` → **Create Incident** → `always_nodes` →
  **Update RITM (failure)**.

In `infra.aap_configuration` workflow nodes this is `success_nodes` /
`failure_nodes` / `always_nodes` under each node's `related:`. Verify exact keys
against the collection's `controller_workflows` schema when wiring (the Windows
file is the working reference).

---

## Threading provisioning details to the callback

The callback + CMDB nodes need FQDN / public IP / admin user / vm_size_tier /
ticket_number / ticket_sys_id, plus the CMDB CI fields the
`create_configuration_item` role expects (`my_server`, `my_public_ip`, and the
Azure stand-ins for `my_instance_id` / `my_ami_id` / `my_instance_type`).
`provision_vm.yml` already parses the Terraform `ansible_inventory` output;
extend it to `set_stats` those fields so they propagate as workflow artifacts to
the later nodes. No new Azure calls — reuse values already in hand. The Windows
`get_instance_info` role (which queries the cloud) is **not** needed for Azure;
`set_stats` from Provision VM replaces it.

---

## Failure & timeout behavior

- The workflow has a finite run (~10 min; Provision VM ~7 min). If a node fails
  or the workflow times out, the **failure path** routes to **Create Incident**
  then **Update RITM (failure)** — a failure work note + non-Fulfilled state +
  the incident number. The requester never sees a silently-stuck ticket.
- If `ticket_number` is missing (non-SNow trigger — AAP UI / Self-Service / ADO),
  the callback/CMDB/incident nodes no-op or are skipped so the workflow stays
  green for those paths. (Guard in the playbooks on `ticket_number is defined`.)
- Azure quota / SP-auth failures surface in the RITM work note + Incident via the
  failure path, mirroring the runbook's failure-mode appendix.

---

## Required secrets (add to `docs/dev-environment.sh.example`)

```bash
# --- ServiceNow (Phase 8) ---
export SN_HOST="https://<instance>.service-now.com"   # ServiceNow instance URL
export SN_USERNAME="REPLACE_ME_SNOW_USER"             # integration user (callback)
export SN_PASSWORD="REPLACE_ME_SNOW_PASSWORD"
# Shared bearer token for the EDA event stream. ServiceNow's Outbound REST
# Message sends it as `Authorization: Bearer <token>`; the ServiceNow Event
# Stream credential validates it. Mint a strong random value.
export EDA_EVENT_STREAM_TOKEN="REPLACE_ME_EVENT_STREAM_TOKEN"
```

Real values go in `docs/dev-environment.sh` only (gitignored), never committed.
The `SN_*` callback creds are **already populated** in `docs/dev-environment.sh`;
`EDA_EVENT_STREAM_TOKEN` is the one value still to mint and add there.

---

## Build & test plan

The ServiceNow instance + callback creds are live (in `docs/dev-environment.sh`);
mint `EDA_EVENT_STREAM_TOKEN` first, then work the steps.

1. **EE + collections** — add `ansible.eda` and `servicenow.itsm` to
   `requirements.yml` and the EE build; rebuild/push the EE; re-sync in AAP.
2. **Rulebook** — add `rulebooks/servicenow_events.yml` to this repo; register the
   `DC1.Azure - EDA` project so AAP/EDA syncs it.
3. **EDA CaC** — add `eda_credentials.yml`, `eda_decision_environments.yml`,
   `eda_event_streams.yml`, `eda_rulebook_activations.yml`; add them to
   `load.yml` vars_files; extend `validate.yml`. Activate the rulebook; capture
   the event-stream URL.
4. **Controller CaC** — add the `DC1.Azure - ServiceNow` credential and the five
   JTs (CMDB CI, CMDB Relationship, Update RITM success/failure, Create Incident)
   pointing at the Windows project; wire the workflow success/failure/always
   nodes; extend `validate.yml`.
5. **`provision_vm.yml`** — add the `set_stats` fields the callback + CMDB nodes
   consume.
6. **ServiceNow** — build the catalog item (with the pinned `short_description`),
   the Business Rule, and the Outbound REST Message → event-stream URL; store the
   bearer token as a SNow secret.
7. **End-to-end** — file a catalog request → watch EDA receive the event and
   launch the workflow → confirm the VM exists and the landing page shows the real
   RITM number → confirm the RITM auto-fills + CMDB CI/relationship appear → force
   a failure and confirm the Incident opens + RITM reflects it → close the ticket.
8. **Runbook** — add the v2 (SNow/EDA-driven) section to `docs/demo-runbook.md`.

Each CaC change follows the established flow (work item → branch → PR →
self-approve → squash-merge), validated against the live AAP per the project's
real-run preference.

---

## Resolved

- **EDA project git URL** → the **Azure DevOps repo** (PAT-backed SCM credential,
  same auth as the controller `DC1.Azure` project).
- **CMDB CI class** → **`cmdb_ci_win_server`**, as-is from the
  `create_configuration_item` role (Azure field-mapping caveat noted above).

## Open items still to decide during implementation

- **Webhook port** in the rulebook source — confirm the port AAP's event-stream
  proxy expects for this DE (Windows uses `5003`; pick per the DE/activation).
- Exact `servicenow.itsm` module per record — the Windows roles use
  `servicenow.itsm.api` / `api_info` generically; reuse as-is.
- RITM `state` integer mapping (which value = Fulfilled in the shared dev
  instance) — the Windows role uses `state: 4` for the failure path; confirm the
  success value on the live instance.
- **Admin password on the RITM** — **DECIDED (2026-05-29): omit it entirely.**
  The RITM work note carries FQDN + public IP + admin username only; the password
  stays in the AAP credential (Provision Access sets it). No plaintext secret in
  ServiceNow.

## As-built deltas — PR1 (AB#81, inbound EDA trigger)

The inbound half shipped; these refine the spec above against the
`infra.aap_configuration` 4.4.0 / `ansible.eda` 2.11.0 contracts verified at
build time:

- **`event_stream_type: snow` dropped.** `ansible.eda.event_stream` deprecates
  and ignores that field — the stream's type is inferred from its credential type
  (`ServiceNow Event Stream`). `eda_event_streams.yml` omits it.
- **Activation `eda_credentials` is a list of names**, not a scalar — corrected in
  `eda_rulebook_activations.yml` (`- "{{ eda_controller_credential }}"`).
- **EDA needs its own SCM credential.** EDA keeps a credential store separate from
  the controller's, so the EDA project can't reuse `DC1.Azure - ADO Source
  Control`; PR1 adds `DC1.Azure - EDA Source Control` (type `Source Control`, same
  ADO PAT).
- **Decision Environment reused, not created.** The activation points at the
  platform's built-in *Default Decision Environment* (overridable via
  `DC1_AZURE_EDA_DE`) so we don't have to mint a `registry.redhat.io` EDA registry
  credential; the stock DE already ships `ansible.eda`. No `eda_decision_environments.yml`.
- **Webhook port = 5000** (the rulebook's internal source port; the event-stream
  proxy forwards to it — value is isolated to the activation pod).
- **Apply-order note:** the EDA project syncs `sync: true` on apply, but if the
  rulebook activation is created before the sync finishes pulling
  `servicenow_events.yml`, re-run `load.yml` (idempotent) so the activation finds
  the rulebook.

See [`ROADMAP.md`](../ROADMAP.md) Phase 8 and [`demo-runbook.md`](demo-runbook.md).

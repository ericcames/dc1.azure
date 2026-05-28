# ServiceNow Integration — Design (Phase 8, Demo v2)

**Status:** Design approved 2026-05-28 · implementation deferred until the live
ServiceNow instance is wired (decision: design-doc-first). This document is the
build spec — when the instance credentials land in `docs/dev-environment.sh`,
implementation should be mechanical.

## Goal

A business user opens the **ServiceNow self-service catalog**, requests a
Windows VM on Azure, picks a t-shirt size, and submits. ServiceNow triggers the
existing **`DC1.Azure - Provision and Configure`** workflow in AAP. When the
workflow finishes, **AAP calls ServiceNow back** to update the request item
(RITM) with the outcome — status, public IP, FQDN, admin user. The user closes
the ticket. No AAP login, no Azure knowledge required of the requester.

This is **Demo v2**. It reuses the *exact* Phase 4 workflow unchanged except for
one appended callback node — the same workflow the AAP-UI (Phase 6),
Self-Service Portal (Phase 9), and ADO (Phase 10) triggers all drive.

---

## Decisions (resolves the three ROADMAP open questions)

| Open question | Decision | Why |
|---------------|----------|-----|
| **Result-reporting direction** — SNow polls AAP vs AAP calls SNow back | **AAP calls SNow back** | Richer demo payoff: the RITM auto-fills with IP/FQDN on screen. Keeps the polling/status logic out of ServiceNow. Uses the existing `ServiceNow ITSM Credential` type. |
| **Auth from SNow → AAP** — mid-server vs direct REST | **Direct REST** (no mid-server) | This is a demo on the Red Hat shared SNow dev instance, not enterprise prod. Direct REST from Flow Designer to the AAP launch endpoint is far less setup. *Mid-server documented below as the enterprise-standard alternative.* |
| **Timeout behavior** — what does the RITM show if provisioning hangs? | **The callback node runs on both success and failure paths** | The RITM always reaches a terminal state (Fulfilled or a failure note) — never hangs silently. See [Failure & timeout behavior](#failure--timeout-behavior). |

---

## Architecture & sequence

```
 ServiceNow                         AAP (Controller)                 Azure
 ──────────                         ────────────────                 ─────
 1. User submits catalog
    item "Request Windows
    VM (Azure)" (size,
    justification)
        │
        │ 2. Flow Designer: REST POST
        │    /api/controller/v2/workflow_job_templates/<id>/launch/
        │    Bearer <AAP token>
        │    extra_vars: { vm_size_tier, ticket_number: <RITM number> }
        ▼
                                   3. Workflow runs (Phase 4, unchanged):
                                      Provision VM ─► Powershell ─►
                                      Website Setup ─► Provision Access ─►
                                      Patching ──────────────────────► VM live
                                                                         in Azure
                                   4. NEW final node: "Update ServiceNow RITM"
                                      runs servicenow_update_ritm.yml
        ┌───────────────────────────────┘
        │ 5. servicenow.itsm PATCHes the RITM (Table API):
        │    state, public IP, FQDN, admin user, work note
        ▼
 6. RITM shows Fulfilled +
    connection details; user
    closes the ticket
```

The `ticket_number` (the RITM number, e.g. `RITM0012345`) is passed **into** the
launch as an extra var. It serves two purposes:
- it flows to the IIS landing page (`ticket_number` already templated in
  `website_setup_azure/templates/index.html.j2` — today it shows `N/A`; this
  closes that loop), and
- it tells the callback node **which** RITM to update.

---

## Component inventory

| Component | Status | Where |
|-----------|--------|-------|
| `ServiceNow ITSM Credential` **type** (injects `SN_HOST`/`SN_USERNAME`/`SN_PASSWORD`) | ✅ exists (from `aap.as.code`) | `aap_config/files/controller_credential_types.yml` |
| `servicenow.itsm` collection | ⬜ add | `aap_config/requirements.yml` + `execution-environment.yml` (EE rebuild) |
| `DC1.Azure - ServiceNow` credential **instance** | ⬜ add | `aap_config/files/controller_credentials.yml` |
| `playbooks/servicenow_update_ritm.yml` | ⬜ write | `playbooks/` |
| `DC1.Azure - Update ServiceNow RITM` JT | ⬜ add | `aap_config/files/controller_job_templates.yml` |
| Workflow callback node (success + failure) | ⬜ wire | `aap_config/files/controller_workflow_job_templates.yml` |
| `validate.yml` assertions (new cred + JT) | ⬜ extend | `aap_config/validate.yml` |
| ServiceNow catalog item + Flow Designer flow | ⬜ build in SNow | ServiceNow instance |
| SNow secrets placeholders | ⬜ add | `docs/dev-environment.sh.example` |

---

## Inbound: ServiceNow → AAP (trigger)

### Catalog item — "Request Windows VM (Azure)"
Variables:
- `vm_size_tier` — dropdown, choices `small-2cpu-8gb` / `medium-4cpu-16gb` /
  `large-8cpu-32gb` (mirror the AAP survey exactly; default `medium-4cpu-16gb`).
- `justification` — single-line text (free text; for the demo narrative).
- `requestor` — reference to `sys_user`, auto-populated from the logged-in user.

### Flow Designer flow
On catalog request submission:
1. Create/Use the generated RITM (`sc_req_item`).
2. **REST step** → AAP:
   - Method: `POST`
   - URL: `https://<aap-host>/api/controller/v2/workflow_job_templates/<WF_ID>/launch/`
     *(look up `<WF_ID>` for `DC1.Azure - Provision and Configure` per env)*
   - Header: `Authorization: Bearer <AAP_OAUTH_TOKEN>` (stored as a SNow
     Connection & Credential alias — **not** inline)
   - Body:
     ```json
     { "extra_vars": { "vm_size_tier": "${vm_size_tier}", "ticket_number": "${number}" } }
     ```
   - `Content-Type: application/json`, TLS verify on.
3. Post a work note on the RITM: "Provisioning requested — AAP job launched."

> **Auth alternative (enterprise):** route the REST call through a **MID Server**
> instead of direct outbound REST. Standard in regulated environments (no direct
> SNow→internet path) but requires standing up + registering a MID Server. Out of
> scope for the demo; noted for customer conversations.

---

## Outbound: AAP → ServiceNow (callback)

### Credential instance — `DC1.Azure - ServiceNow`
Of type `ServiceNow ITSM Credential` (already defined). Injects:
- `SN_HOST` ← `lookup(env, 'SN_HOST')`
- `SN_USERNAME` ← `lookup(env, 'SN_USERNAME')`
- `SN_PASSWORD` ← `lookup(env, 'SN_PASSWORD')`

Sourced at load time from `docs/dev-environment.sh` (gitignored). Namespaced
`DC1.Azure -` per repo convention.

### Playbook — `playbooks/servicenow_update_ritm.yml`
- `hosts: localhost`, `connection: local`, `gather_facts: false`.
- Reads `ticket_number`, plus the Terraform outputs threaded via `set_stats`
  from the Provision VM node (FQDN, public IP, admin user, vm_size_tier).
- Uses `servicenow.itsm.api` (or `servicenow.itsm.<table>` module) to PATCH the
  `sc_req_item` record matching `number == ticket_number`:
  - `state` → Fulfilled (success) / a failure state (on failure path)
  - a **work note** with FQDN + public IP + admin user, or the failure reason
- Auth: `SN_HOST`/`SN_USERNAME`/`SN_PASSWORD` from the injected credential.
- Guard: skip gracefully (no-op + debug) if `ticket_number` is absent — so the
  same workflow still runs cleanly when launched from the AAP UI / Self-Service
  (Phase 6/9), which don't supply a ticket.

### Update-RITM JT — `DC1.Azure - Update ServiceNow RITM`
- `project: DC1.Azure`, `playbook: playbooks/servicenow_update_ritm.yml`
- credentials: `DC1.Azure - ServiceNow`
- inventory: the `dc1-azure-control` inventory (localhost play; same reasoning as
  the Teardown JT — keep it off `dc1-azure`).

### Workflow wiring
Append to `DC1.Azure - Provision and Configure` **after Patching**:
- **on success** → `Update ServiceNow RITM` (sets Fulfilled + details)
- **on failure** (from any prior node) → `Update ServiceNow RITM` with a
  failure-path var so the RITM gets a failure note instead of hanging.

Implementation note: in `infra.aap_configuration` workflow nodes this is
`success_nodes` / `failure_nodes` (or `always_nodes`) on the relevant nodes.
Verify the exact key against the collection's `controller_workflows` schema when
wiring.

---

## Threading provisioning details to the callback

The callback needs FQDN / public IP / admin user. `provision_vm.yml` already
parses the Terraform `ansible_inventory` output; extend it to `set_stats` the
fields the callback reports (FQDN, public IP, admin user, vm_size_tier,
ticket_number) so they propagate as workflow artifacts to the final node. No new
Azure calls — reuse the values already in hand.

---

## Failure & timeout behavior

- The workflow has a finite run (~10 min; Provision VM ~7 min). If a node fails
  or the workflow hits its timeout, the **failure path** still routes to
  `Update ServiceNow RITM`, which writes a failure work note + a non-Fulfilled
  state. The requester never sees a silently-stuck ticket.
- If `ticket_number` is missing (non-SNow trigger), the callback no-ops — the
  workflow stays green for the AAP-UI / Self-Service / ADO paths.
- Azure quota / SP-auth failures surface in the RITM work note via the failure
  path, mirroring the runbook's failure-mode appendix.

---

## Required secrets (add to `docs/dev-environment.sh.example`)

```bash
# --- ServiceNow (Phase 8) ---
export SN_HOST="https://<instance>.service-now.com"   # ServiceNow instance URL
export SN_USERNAME="REPLACE_ME_SNOW_USER"             # integration user
export SN_PASSWORD="REPLACE_ME_SNOW_PASSWORD"
# AAP OAuth token for SNow→AAP launch is stored IN ServiceNow (Connection &
# Credential alias), not here — mint a dedicated token scoped to launch.
```

Real values go in `docs/dev-environment.sh` only (gitignored), never committed.

---

## Build & test plan (when the instance is live)

1. **EE + collection** — add `servicenow.itsm` to `requirements.yml` and the EE
   build; rebuild/push the EE; re-sync in AAP.
2. **CaC** — add the `DC1.Azure - ServiceNow` credential, the Update-RITM JT, and
   the workflow node (success + failure); extend `validate.yml`.
3. **Playbook** — write `servicenow_update_ritm.yml`; test it standalone against
   a hand-created RITM (pass `ticket_number` directly) before wiring the workflow.
4. **`provision_vm.yml`** — add the `set_stats` fields the callback consumes.
5. **ServiceNow** — build the catalog item + Flow Designer flow; store the AAP
   token as a SNow credential alias.
6. **End-to-end** — file a catalog request → watch the AAP workflow launch →
   confirm the VM exists and the landing page shows the real RITM number → confirm
   the RITM auto-fills with IP/FQDN/admin → close the ticket.
7. **Runbook** — add the v2 (SNow-driven) section to `docs/demo-runbook.md`.

Each CaC change follows the established flow (work item → branch → PR →
self-approve → squash-merge), validated against the live AAP per the project's
real-run preference.

---

## Open items still to decide during implementation

- Exact `servicenow.itsm` module for the PATCH (`api` generic vs a table-specific
  module) — pick when testing against the live instance schema.
- RITM state value mapping (which `state` integer = Fulfilled in the shared dev
  instance's workflow).
- Whether to also attach the admin **password** to the RITM (likely a secure
  work note or omit for the demo — avoid plaintext secrets in the ticket).

See [`ROADMAP.md`](../ROADMAP.md) Phase 8 and [`demo-runbook.md`](demo-runbook.md).

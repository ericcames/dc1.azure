# ServiceNow-side artifacts (DC1.Azure)

Source-of-truth copies of the **ServiceNow** configuration that drives the DC1.Azure
demo's inbound trigger. These are pasted *into* ServiceNow — they are **not** executed
from this repo. Versioning them here means the integration survives a ServiceNow PDI
reset and is reproducible on a fresh instance.

> **Two systems, two folders.** This folder holds the **ServiceNow side** (Business
> Rules, REST Message config). The **AAP side** — the callbacks AAP makes *back* into
> ServiceNow (RITM updates, CMDB CI, Incident) — lives in
> [`../playbooks/servicenow/`](../playbooks/servicenow/). The end-to-end design is in
> [`../docs/servicenow-integration.md`](../docs/servicenow-integration.md).

## Placeholders (never commit live values)

`<your-snow-instance>`, the AAP event-stream URL/UUID, and the bearer token are
deployment-/secret-specific. The token lives only in `docs/dev-environment.sh` as
`EDA_EVENT_STREAM_TOKEN`; copy the event-stream URL from AAP at setup time.

## Inbound trigger — the pieces (in install order)

1. **Catalog item** — *Request Windows VM (Azure)*. **Short description must be exactly
   `DC1.Azure Windows VM on Azure`** — the rulebook matches on this string, and the RITM
   inherits it.
2. **Variable `vm_size_tier`** — Multiple Choice; choices `small-2cpu-8gb` /
   `medium-4cpu-16gb` / `large-8cpu-32gb`; default `medium-4cpu-16gb`. (Optional monthly
   `Recurring price` per the ROADMAP Sizing Tiers.)
3. **Encrypted token property** *(optional — only if you set the bearer via script
   instead of a static header)* — `sys_properties` `dc1.eda_event_stream_token`,
   type `password2 (Encrypted)`, value = `EDA_EVENT_STREAM_TOKEN`.
4. **Outbound REST Message** — `Ames - DC1.Azure EDA Event Stream`:
   - **Endpoint:** the AAP event-stream external URL (copy from *Automation Decisions →
     Event Streams → DC1.Azure - ServiceNow Event Stream → URL*); shape:
     `https://<aap-host>/eda-event-streams/api/eda/v1/external_event_stream/<stream-uuid>/post/`
   - **POST** HTTP method named `POST`, with headers:
     - `Content-Type: application/json`
     - `Authorization: Bearer <token>`  ← static header (matched pair with `EDA_EVENT_STREAM_TOKEN`)
   - **No Content/body template needed** — the Business Rule builds the JSON and sets it
     with `setRequestBody()`.
5. **Business Rule** — [`business_rules/fire_eda_on_ritm.js`](business_rules/fire_eda_on_ritm.js):
   table `sc_req_item`, **Advanced ✓**, *after / Insert*, filtered to the catalog item.
   Builds the payload (number, sys_id, short_description, all catalog variables,
   requester) and POSTs it via the REST Message above.

## Verify

- **ServiceNow:** *System Logs → All* → `DC1.Azure EDA trigger [...] -> HTTP 200`.
- **AAP:** the event stream's *events received* increments and
  `DC1.Azure - Catch ServiceNow Events` launches `DC1.Azure - Provision and Configure`.
- **Pre-flight without ordering:** `curl -X POST <event-stream-url> -H 'Authorization: Bearer <token>'
  -H 'Content-Type: application/json' -d '{"short_description":"DC1.Azure Windows VM on Azure","vm_size_tier":"small-2cpu-8gb","number":"TEST","sys_id":"x"}'`
  → if the workflow launches, any remaining issue is ServiceNow-side.

## Gotchas we hit (so you don't)

- **Business Rule "Advanced" must be checked** or the script tab is silently ignored.
- **Trim variable values** (`clean()` in the script) — a trailing space on a Question
  Choice value (`"medium-4cpu-16gb "`) fails the workflow survey's exact-match check.
- **Bearer token is a matched pair** — identical on the REST Message header and the AAP
  `ServiceNow Event Stream` credential; a trailing newline on paste → 401.

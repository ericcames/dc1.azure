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

1. **Catalog item** — *Ames - Request Infrastructure (Azure)*. **Short description must be exactly
   `DC1.Azure Infrastructure Provisioning`** — the rulebook matches on this string,
   and the RITM inherits it.
   Use `playbooks/servicenow/update_catalog_item.yml` to update text fields via API.
   Upload the icon (`docs/images/catalog-it-infrastructure.png`) manually in the
   ServiceNow UI (drag-drop on the catalog item form).
2. **Variable `os_type`** — Multiple Choice; choices `windows` / `linux` / `both`;
   default `windows`. Controls which VMs are provisioned.
3. **Variable `vm_size_tier`** — Multiple Choice; choices `small-2cpu-8gb` /
   `medium-4cpu-16gb` / `large-8cpu-32gb`; default `medium-4cpu-16gb`. (Optional monthly
   `Recurring price` per the ROADMAP Sizing Tiers.)
3. **Encrypted token property** *(required — AB#92)* — the EDA bearer token is held
   here, **not** as a plaintext header on the REST Message:
   - **Name:** `dc1.eda_event_stream_token` (System Properties → `sys_properties`)
   - **Type:** `password2 (Encrypted)` — stored encrypted at rest; the raw token is
     never visible in the property list or the REST Message config.
   - **Value:** the AAP EDA event-stream bearer token = `EDA_EVENT_STREAM_TOKEN`
     (`docs/dev-environment.sh`) == the AAP *ServiceNow Event Stream* credential
     token. **Matched pair** — ServiceNow and AAP must hold the *same* token.
   - **Consumed by** the Business Rule (#5) at send time via
     `gs.getProperty('dc1.eda_event_stream_token')` (returns the decrypted value
     server-side), which sets the `Authorization: Bearer …` header on the POST.
   - **Rotate:** update this property's Value *and* the AAP credential to the same
     new token. No trailing newline on paste (the #1 cause of a 401). If the
     property is missing/empty the header becomes `Bearer ` → 401.
4. **Outbound REST Message** — `Ames - DC1.Azure EDA Event Stream`:
   - **Endpoint:** the AAP event-stream external URL (copy from *Automation Decisions →
     Event Streams → DC1.Azure - ServiceNow Event Stream → URL*); shape:
     `https://<aap-host>/eda-event-streams/api/eda/v1/external_event_stream/<stream-uuid>/post/`
   - **POST** HTTP method named `POST`, with a single header:
     - `Content-Type: application/json`
   - **No `Authorization` header here** — the bearer is set at runtime by the
     Business Rule from the encrypted property (#3), so the token never sits in
     plaintext in the REST Message config (AB#92).
   - **No Content/body template needed** — the Business Rule builds the JSON and sets it
     with `setRequestBody()`.
5. **Business Rule** — [`business_rules/fire_eda_on_ritm.js`](business_rules/fire_eda_on_ritm.js):
   table `sc_req_item`, **Advanced ✓**, *before / Update*, filtered to fire once the
   RITM is **approved** (`stage=request_approved ^ state=2`) for the demo
   requester(s), with `sys_updated_by != service.ansible` so AAP's own write-backs
   (RITM updates / CMDB) don't re-fire it. Reads the bearer from the encrypted
   property (#3), then builds the payload (number, sys_id, short_description, all
   catalog variables, requester) and POSTs it via the REST Message above.

## Verify

- **ServiceNow:** *System Logs → All* → `DC1.Azure EDA trigger [...] -> HTTP 200`.
- **AAP:** the event stream's *events received* increments and
  `DC1.Azure - Catch ServiceNow Events` launches `DC1.Azure - Provision and Configure`.
- **Pre-flight without ordering:** `curl -X POST <event-stream-url> -H 'Authorization: Bearer <token>'
  -H 'Content-Type: application/json' -d '{"short_description":"DC1.Azure Infrastructure Provisioning","vm_size_tier":"small-2cpu-8gb","number":"TEST","sys_id":"x"}'`
  → if the workflow launches, any remaining issue is ServiceNow-side.

## Gotchas we hit (so you don't)

- **Business Rule "Advanced" must be checked** or the script tab is silently ignored.
- **Trim variable values** (`clean()` in the script) — a trailing space on a Question
  Choice value (`"medium-4cpu-16gb "`) fails the workflow survey's exact-match check.
- **Bearer token is a matched pair** — identical in the encrypted property
  `dc1.eda_event_stream_token` and the AAP `ServiceNow Event Stream` credential;
  a trailing newline on paste → 401.

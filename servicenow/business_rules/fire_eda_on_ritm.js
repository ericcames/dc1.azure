/**
 * DC1.Azure — ServiceNow Business Rule: fire the AAP EDA event stream on RITM creation
 * ----------------------------------------------------------------------------------
 * WHERE THIS RUNS (ServiceNow side — paste into ServiceNow, NOT executed from this repo):
 *   System Definition -> Business Rules -> New
 *     Table:    Requested Item [sc_req_item]
 *     Advanced: true            (REQUIRED — the script tab is ignored without it)
 *     When:     before,  Update: true   (as-built: fire once the RITM is APPROVED,
 *               not on raw insert — so the requester's choices are final)
 *     Filter:   stage=request_approved AND state=2 (Work in Progress) for the demo
 *               requester(s), AND sys_updated_by != service.ansible  — the last
 *               clause stops AAP's own write-backs (RITM updates / CMDB) from
 *               re-firing this rule.
 *     Script:  this file
 *
 * WHAT IT DOES:
 *   Builds a JSON payload from the RITM (number, sys_id, short_description, catalog
 *   variables incl. vm_size_tier, requester, ...) and POSTs it to the AAP EDA event
 *   stream via the Outbound REST Message named below. EDA matches on short_description
 *   and launches "DC1.Azure - Provision and Configure".
 *
 * AUTH — encrypted token, set at runtime (hardened, AB#92):
 *   The bearer token is NOT stored as a plaintext header on the REST Message.
 *   It lives in an ENCRYPTED ServiceNow system property and this script reads it
 *   at send time and sets the Authorization header itself:
 *
 *       Property:  dc1.eda_event_stream_token   (System Properties [sys_properties])
 *       Type:      password2  (Encrypted)        — stored encrypted at rest; the
 *                                                  raw token is never visible in the
 *                                                  property list or the REST Message.
 *       Value:     the AAP EDA event-stream bearer token, i.e. EDA_EVENT_STREAM_TOKEN
 *                  in docs/dev-environment.sh == the AAP "ServiceNow Event Stream"
 *                  credential token.  MATCHED PAIR: ServiceNow and AAP must hold the
 *                  exact same token or the event stream returns 401.
 *
 *   How it is consumed (below):
 *       r.setRequestHeader('Authorization',
 *                          'Bearer ' + gs.getProperty('dc1.eda_event_stream_token'));
 *   gs.getProperty() returns the DECRYPTED value server-side, so the cleartext token
 *   exists only transiently in memory during the POST. The Outbound REST Message
 *   therefore carries ONLY a Content-Type header — no Authorization header at all.
 *
 *   To set or rotate the token (do BOTH sides together):
 *     1. ServiceNow: sys_properties.list -> dc1.eda_event_stream_token -> set Value
 *        (paste the token; NO trailing newline — that is the #1 cause of a 401).
 *     2. AAP: update the "ServiceNow Event Stream" credential to the same token.
 *   If the property is missing/empty, gs.getProperty returns '' and the header
 *   becomes "Bearer " -> the event stream 401s (watch the gs.info log line below).
 *
 * NOTES:
 *   - clean() trims every value — prevents the survey-validation failure we hit when a
 *     Question Choice value carried a trailing space (e.g. "medium-4cpu-16gb ").
 *   - The variables loop auto-forwards any future catalog variable with no edits here.
 *   - gs.info logs the HTTP status to System Logs -> All for SNOW-side observability.
 *
 * See ../README.md and ../../docs/servicenow-integration.md for the full design.
 */
(function executeRule(current, previous) {
  var REST_MESSAGE_NAME = 'Ames - DC1.Azure EDA Event Stream';
  var EVENT_NAME = 'SERVICE_CATALOG';

  try {
    function clean(v) { return (v == null) ? v : String(v).trim(); }

    var json = { event: EVENT_NAME };
    if (current.cat_item)          json.catalog_item     = clean(current.cat_item.getDisplayValue());
    if (current.number)            json.number           = clean(current.number.getDisplayValue());
    if (current.sys_id)            json.sys_id           = current.sys_id.toString();
    if (current.state)             json.state            = clean(current.state.getDisplayValue());
    if (current.short_description) json.short_description = clean(current.short_description.getValue('short_description'));
    if (current.stage)             json.stage            = clean(current.stage.getDisplayValue());

    if (current.opened_by) {
      var requester = current.opened_by.getRefRecord();
      if (requester.isValidRecord()) json.requester = requester.getValue('email');
    }

    for (var key in current.variables) {
      if (current.variables.hasOwnProperty(key)) {
        json[key] = clean(current.variables[key].getDisplayValue());
      }
    }

    var r = new sn_ws.RESTMessageV2(REST_MESSAGE_NAME, 'POST');
    // Bearer token from the encrypted property (NOT a plaintext REST Message header) — AB#92.
    r.setRequestHeader('Authorization', 'Bearer ' + gs.getProperty('dc1.eda_event_stream_token'));
    r.setRequestBody(JSON.stringify(json));
    r.setTimeout(10000);
    var resp = r.execute();
    gs.info('DC1.Azure EDA trigger [' + json.number + '] -> HTTP ' + resp.getStatusCode());
  } catch (ex) {
    gs.error('DC1.Azure EDA trigger failed: ' + ex.message);
  }
})(current, previous);

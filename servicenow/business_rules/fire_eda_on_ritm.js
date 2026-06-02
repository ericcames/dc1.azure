/**
 * DC1.Azure — ServiceNow Business Rule: fire the AAP EDA event stream on RITM creation
 * ----------------------------------------------------------------------------------
 * WHERE THIS RUNS (ServiceNow side — paste into ServiceNow, NOT executed from this repo):
 *   System Definition -> Business Rules -> New
 *     Table:   Requested Item [sc_req_item]
 *     Advanced: true            (REQUIRED — the script tab is ignored without it)
 *     When:    after,  Insert: true
 *     Filter:  Catalog Item is <your "Request Windows VM (Azure)" item>
 *     Script:  this file
 *
 * WHAT IT DOES:
 *   Builds a JSON payload from the RITM (number, sys_id, short_description, catalog
 *   variables incl. vm_size_tier, requester, ...) and POSTs it to the AAP EDA event
 *   stream via the Outbound REST Message named below. EDA matches on short_description
 *   and launches "DC1.Azure - Provision and Configure".
 *
 * AUTH (matched pair — keep both sides identical):
 *   The bearer token is set as a STATIC header on the Outbound REST Message's POST
 *   method (Authorization: Bearer <token>), NOT in this script. That token must equal
 *   EDA_EVENT_STREAM_TOKEN (docs/dev-environment.sh) / the AAP "ServiceNow Event
 *   Stream" credential. A trailing newline on paste is the #1 cause of a 401.
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
    r.setRequestBody(JSON.stringify(json));
    r.setTimeout(10000);
    var resp = r.execute();
    gs.info('DC1.Azure EDA trigger [' + json.number + '] -> HTTP ' + resp.getStatusCode());
  } catch (ex) {
    gs.error('DC1.Azure EDA trigger failed: ' + ex.message);
  }
})(current, previous);

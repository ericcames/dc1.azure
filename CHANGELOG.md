# Changelog

All notable changes to this project will be documented in this file.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Unreleased

### Fixed
- **AB#174 — correct the Windows OneAgent uninstaller path.** AB#171 ran
  `…\dynatrace\oneagent\agent\uninstall.exe`, which doesn't exist — the
  uninstaller is in the install root (`…\dynatrace\oneagent\uninstall.exe`),
  not under `agent\`. The first live teardown failed the Windows uninstall node
  with Win32 error 2 (file not found); the always-edge meant destroy still
  completed, and the `dt_decommission` backstop covered the Windows DT problem.
  Path corrected.

### Added
- **AB#171 — teardown is now a workflow that uninstalls OneAgent before
  destroy.** New `DC1.Azure - Teardown and Decommission` workflow brackets the
  existing `DC1.Azure - Teardown` JT with a first stage that gracefully
  uninstalls Dynatrace OneAgent on the live VMs (new
  `DC1.Azure - Uninstall Dynatrace OneAgent (Windows)`/`(Linux)` JTs +
  `playbooks/uninstall_dynatrace_oneagent_{windows,linux}.yml`). Removing
  OneAgent before destroy lets Dynatrace drop the host cleanly, so the VMs
  vanishing never raise stale "process/host unavailable" problems — the
  root-cause fix for the AB#165 leak (`dt_decommission` inside the Teardown JT
  stays as a backstop). The two uninstall nodes converge on the Teardown node
  via always-edges (empty OS group = clean skip), and complete before it (so the
  inventory host lock is released for the AB#73 control-inventory deregister).
  Both nightly teardown schedules now launch the workflow instead of the JT;
  launch the workflow from the UI for manual teardowns.
- **AB#173 — open Azure NSG port 9090 for Cockpit.** New inbound `Allow-Cockpit`
  NSG rule (TCP 9090, priority 1060, scoped to `var.allowed_source_cidrs` like
  the other rules) so the Cockpit web console enabled in AB#172 is reachable
  over the Linux VM's public FQDN. Pairs with the `cockpit` firewalld service
  opened on the host.
- **AB#170 — retire the ServiceNow CMDB CI at teardown.** `teardown.yml` now
  marks the CMDB CI(s) for the destroyed VM(s) as **retired** — both
  `install_status` and `operational_status` — looking them up by name (the
  public FQDN) and updating only records that already exist (a non-ServiceNow
  teardown with no CI cleanly no-ops). Gated on the ServiceNow credential
  (`SN_HOST`), so the `DC1.Azure - Teardown` job template now also carries
  `cred_servicenow`. Closes the CMDB CI lifecycle: installed/operational on
  create → retired on decommission.

### Changed
- **AB#172 — Configure Linux: faster + correct.** The `linux_configure` role
  now: applies **security-only** updates (dropped `bugfix`, the slow part with
  little demo value); gates the reboot on the RHEL-correct
  `needs-restarting -r` (the old `/var/run/reboot-required` stat is a
  Debian/Ubuntu path that never exists on RHEL, so it never rebooted); runs
  `insights-client` **async/fire-and-forget** (`poll: 0`) after any reboot so
  the play no longer blocks ~30-60s on the upload; installs NTP + Apache +
  firewall + Cockpit in a **single dnf transaction** with `update_cache` (warms
  metadata once, reused by the patch task) and `install_weak_deps: false`. It
  also **stops removing Cockpit** and now installs + enables `cockpit.socket`
  (and opens the `cockpit` firewalld service) so the web console is demoable —
  external access still needs an Azure NSG rule for 9090 (or an SSH tunnel).

### Fixed
- **AB#169 — pin the Linux OneAgent DT host name to the Azure public FQDN.**
  `install_dynatrace_oneagent_linux.yml` now passes
  `--set-host-name={{ inventory_hostname }}` on both the OneAgent install and
  the `oneagentctl` re-apply (idempotent path), mirroring the Windows fix
  (AB#161). `inventory_hostname` is the Azure public IP FQDN, so Dynatrace now
  reports the Linux host under the same name AAP inventory and the ServiceNow
  CMDB CI use — instead of the Azure *internal* FQDN it defaulted to. This makes
  the public FQDN the single canonical host identity across DT, AAP, and CMDB
  for both OSes, and removes the cross-OS DNS-suffix mismatch that broke
  triage's CMDB lookup (AB#166).

- **AB#164 — guard the Configure DT Web Availability JT in CaC validation.**
  `aap_config/validate_tasks.yml` asserts every expected AAP object exists so
  `load.yml` can't exit green on a partial apply, but the new
  `DC1.Azure - Configure DT Web Availability` job template (AB#163) was missing
  from the `job_templates` expected list. Added it so the JT is now asserted on
  every apply.

### Added
- **Document when/how to use the AAP MCP server operationally.** Added a *When to
  use it (operationally, not just to deploy)* section to
  `.claude/skills/mcp-server/SKILL.md` and a *Prefer the AAP MCP server for reads*
  convention to `CLAUDE.md`: prefer the read-only `ansible-aap` MCP for AAP
  health/job/workflow/inventory/EDA queries; it's safe to use freely
  (`allow_write_operations: false`, read-scope token); backgrounded polling falls
  back to a read-only `curl` GET (admin basic-auth, since `CONTROLLER_OAUTH_TOKEN`
  may be blank); write/execute stays out of scope until the Phase 21 MCP write path.
- **AB#163 — wire `dt_web_availability` into the provision workflow.**
  Completes the AB#160 follow-up noted in that entry. New
  `DC1.Azure - Configure DT Web Availability` job template
  (`playbooks/configure_dt_web_availability.yml`, DT API only on the control
  inventory; `cred_dynatrace` + `cred_dynatrace_api`) and a new
  `configure-dt-web-availability` node in the `DC1.Azure - Provision and
  Configure` workflow. The node converges four always-parents — both OneAgent
  installs and both web-setup nodes (Website Setup / Configure Linux) — so it
  runs only once Dynatrace is reporting AND the web process exists, then feeds
  `Update RITM (success)` (now a 2-parent converge: Patching + this node) so
  fulfillment isn't reported until availability alerting is armed. The role now
  **retries each web-PG lookup until Dynatrace has detected it**
  (`dt_web_availability_detection_retries` × `dt_web_availability_detection_delay`,
  default 10 × 30s), then skips cleanly — so it reliably arms alerting on a fresh
  provision without ever hard-failing the workflow. The Windows/IIS self-heal now
  works out-of-the-box on every provision instead of needing a manual step.
- **AB#162 — `scripts/cleanup-aap-tokens.sh`: prune stale AAP gateway tokens.**
  Ad-hoc AAP gateway OAuth2 tokens accumulate (51 found 2026-06-10) and slow the
  gateway. Keep-list-based helper that deletes every token except the in-use set
  (MCP, `aap-selfservice-portal` service + jr-dev portal tokens), reads creds
  from `docs/dev-environment.sh`, and self-verifies the remaining count.
- **AB#160 — `dt_web_availability` role: codify Dynatrace web-tier availability
  alerting (OS-symmetric self-heal detection).** Dynatrace only raises a Davis
  "process unavailable" *problem* (which fires the DT→EDA self-heal) for a
  process group that has a `builtin:availability.process-group-alerting` rule.
  That rule was a manual runbook step done only for Apache `httpd`, so the
  Windows/IIS self-heal silently never fired. New reusable, environment-agnostic
  role (`playbooks/roles/dt_web_availability/`) + playbook
  (`playbooks/configure_dt_web_availability.yml`) that, via the Dynatrace API
  only (no host access), resolves the web process groups by name
  (`Apache Web Server httpd` + `IIS app pool DefaultAppPool`) scoped to host
  group `dc1-azure`, and idempotently ensures an `ON_PGI_UNAVAILABILITY` rule on
  each. Entity IDs are resolved at run time (never hardcoded) and scoped to the
  host group so a shared tenant's other `httpd`/`IIS` groups are untouched.
  `docs/demo-runbook.md` updated to mark the formerly-manual checklist item as
  codified and covering IIS. (Wiring into the provision workflow is a separate
  follow-up.) Complements AB#161 (unique Windows DT host identity).
- **`/ado-workflow` skill + `open_pr.py` helper — repeatable ADO PR flow across
  models.** New repo-based skill (`.claude/skills/ado-workflow/`) that
  consolidates the Azure DevOps PR procedure (branch → PR → link work item →
  self-approve → arm auto-complete → verify merge) into a vetted, stdlib-only
  helper so every Claude model and anyone who clones gets identical, gotcha-free
  behavior. Bakes in the hard-won gotchas: the WI→PR artifact link must use the
  project/repo **GUIDs** (the name form silently links zero work items), and
  *Work item linking* is a hard merge gate even on a green, approved PR.
  Complements the conventions already in `CLAUDE.md`. First skill in this repo to
  bundle an executable script alongside its `SKILL.md`.
- **AB#153 — `dt_decommission` role: prevent stale Dynatrace problems during
  teardown.** New reusable, environment-agnostic role
  (`playbooks/roles/dt_decommission/`) that, via the Dynatrace API only (no host
  access), opens a scoped maintenance window (`DONT_DETECT_PROBLEMS`) and closes
  any already-open problems for the hosts being decommissioned — so destroyed
  VMs stop leaving "host/process unavailable" problems open forever. Designed as
  a drop-in artifact customers can use in their own environments (see the role
  `README.md`). `playbooks/teardown.yml` now brackets `terraform destroy` with
  the role: a window + close before destroy, and a close-only sweep after. The
  window is filtered by resolved **entity IDs only** (never host group/tag, so it
  can't suppress the next provision), expired windows are garbage-collected on
  entry, and a zero-entity resolve is a clean skip (never an unfiltered window).
- **AAP MCP server deployment + skill + guide** — AAP upgraded to 2.7
  (Controller 4.8.0, EDA 1.2.8, Hub 4.12.1); MCP server deployed in
  read-only mode. New `/mcp-server` skill
  (`.claude/skills/mcp-server/SKILL.md`) covers the full deploy-to-configure
  lifecycle including the 2.6→2.7 upgrade path and known gotchas. New
  `docs/mcp-server-guide.md` explains the value proposition in layperson
  terms with customer demo scenarios and SE productivity use cases.
- `docs/dev-environment.sh.example` gains `AAP_MCP_URL` and `AAP_MCP_TOKEN`
  placeholders for MCP server configuration.

### Fixed
- **AB#161 — Windows hosts now get a unique Dynatrace identity (NetBIOS
  truncation fix).** Windows caps the OS computer name at 15 chars, so
  `dc1az-win-small-2cpu-4gb-<suffix>` truncated to `dc1az-win-small` and every
  small Windows build collided on one Dynatrace host identity — a self-heal
  problem/incident then resolved the affected host to a *stale prior instance*
  (e.g. an `iuhd2` host torn down days earlier), even though remediation
  correctly fixed the live host. `install_dynatrace_oneagent_windows.yml` now
  passes `--set-host-name={{ inventory_hostname }}` (the full Azure FQDN, mirroring
  Linux) to both the installer and `oneagentctl` (the latter runs every time, so
  already-installed agents are corrected). Linux was unaffected. Discovered while
  validating the Windows self-heal path end-to-end (DT P-260621 → EDA → IIS
  restart on the live host).
- **AB#158 — empty request-timeout no longer breaks AAP-API tasks (token *and*
  controller modules).** The `DC1.Azure - Controller` credential injects empty
  `CONTROLLER_REQUEST_TIMEOUT` / `AAP_REQUEST_TIMEOUT` into the job env. Both
  `ansible.platform.token` (`gateway_request_timeout`) and every
  `ansible.controller.*` task (`request_timeout`) are float params with an
  `env_fallback` on those vars, so the empty string failed to coerce (`''
  cannot be converted to a float`). In teardown this aborted the deregistration
  `block:` *after* `terraform destroy` — VMs were gone but their inventory hosts
  and `host_metrics` were left behind (job 701). In provision, live SNow order
  RITM0011988 (job 712) proved a VM is created but registration then fails at
  the first `ansible.controller.group` task — leaving an unregistered VM and
  starving the configure nodes. Both `playbooks/provision_vm.yml` and
  `playbooks/teardown.yml` now pass `request_timeout` explicitly (new
  `request_timeout` extra-var, default 30) on **every** controller/platform
  task. (A play-level `module_defaults` action-group default would be cleaner
  but CI `ansible-lint` runs offline and can't resolve action groups, so the
  value is set per task.) In teardown this also unblocks the already-merged host
  removal (AB#156) and `host_metrics` cleanup (AB#152), which sit after the
  failing token step and had therefore never run.
- **AB#157 — `dt_decommission` now suppresses process-group problems, not just
  host problems.** Live teardown proved a HOST-scoped `DONT_DETECT_PROBLEMS`
  window does **not** suppress process-group-instance *availability* problems
  (the Phase 19 "Apache process unavailable" alert), so destroying a web VM
  still opened a problem and triggered the EDA remediation workflow. The role
  now also resolves the `PROCESS_GROUP_INSTANCE` entities running on the
  in-scope hosts (`fromRelationships.isProcessOf`) and includes them in both the
  maintenance-window filter and the scoped problem-close. Still entity-ID-based,
  so a future provision (new IDs) is never suppressed.
- **AB#156 — Teardown JT aborted at load: `ansible.platform.host` is not a
  valid module.** `teardown.yml` deregistered hosts with
  `ansible.platform.host`, but `ansible.platform` (the gateway collection) has
  no `host` module — inventory hosts are a Controller resource. The play failed
  to compile (`couldn't resolve module/action ansible.platform.host`) so
  teardown never ran. Switched both deregister tasks to `ansible.controller.host`
  (matching `provision_vm.yml`). Removed the misleading `ansible.platform.host`
  entry from `.ansible-lint` `mock_modules` — it had been masking the bad module
  reference in offline CI.

### Changed
- **AB#153 — `DT_API_TOKEN` now needs broader scopes.** The classic Dynatrace
  access token must add `settings.read`, `settings.write`, and `entities.read`
  (on top of the existing `problems.read`/`problems.write`) for the
  `dt_decommission` role to manage maintenance windows and resolve entities.
  `docs/dev-environment.sh.example` documents the full scope list. The Teardown
  job template (`aap_config/files/controller_job_templates.yml`) now attaches the
  `DC1.Azure - Dynatrace` and `DC1.Azure - Dynatrace API` credentials.
- `.gitignore` — added `.mcp.json` (contains bearer token, must not be
  committed).

- **AB#154 — Dynatrace incident enrichment + closed-loop confirmation**
  - Credential type `DC1.Azure - Dynatrace` gains an optional `dt_api_token`
    field (classic `dt0c01.*` access token with `problems.read` scope) for
    Problems API v2 queries.
  - `dt_triage.yml` enrichments: Davis AI narrative (`event.description`) and
    Dynatrace problem URL posted to incident at creation; problem ID added to
    incident `short_description` for reliable cross-reference.
  - `dt_close_incident.yml` enrichments: polls Dynatrace Problems API v2 for
    Davis root cause analysis (root cause entity, evidence, impacted entities)
    with 5-minute retry window; adds AAP workflow job URL and Dynatrace problem
    URL to executive summary.
  - New playbook `dt_confirm_resolution.yml` and JT
    `DC1.Azure - Confirm Resolution (DT)` — receives Dynatrace CLOSED events
    via EDA, finds the corresponding ServiceNow incident, posts a confirmation
    work note closing the detect→remediate→confirm loop.
  - Close Incident JT gains `cred_dynatrace` and `cred_controller` credentials.
  - `validate_tasks.yml` now asserts all Phase 19 JTs + the remediation workflow.

- **Phase 19 — EDA incident response (Dynatrace website-down demo)** — new
  `DC1.Azure - Remediate Website` workflow launched by the existing
  `DT-EDA-PUSH - Service Remediation` EDA activation when Dynatrace pushes a
  problem event. Four-node graph: Triage DT Alert → Remediate (Linux/Windows
  parallel) → Close Incident. The triage node checks CMDB for the CI, queries
  `task_ci` for change requests in the Implement phase, and creates an incident
  if no active maintenance found. Remediation restarts the web service, verifies
  HTTP 200, and gathers RCA data (journal, uptime, packages, disk). All actions
  logged to the ServiceNow incident in real time via `snow_log`.
- **`webserver_manage` role** — service lifecycle management for both Linux
  (httpd) and Windows (IIS/W3SVC). Actions: break, restart, verify, status.
  OS auto-detected via inventory group membership.
- **`DC1.Azure - Break Website (Linux/Windows)` JTs** — survey-driven service
  management for demo setup (intentionally stop the web service to trigger
  Dynatrace).
- **`DC1.Azure - Gather and Display Facts (Linux)` JT** — Linux counterpart
  to the Windows gather_facts JT. Targets `linuxweb` group over SSH.

- **Demo runbook** (`docs/demo-runbook.md`) — full SE script covering all four
  trigger variants (AAP UI, ServiceNow, Self-Service Portal, ADO), pre-flight
  checklists, talk-tracks, EDA incident response demo (Phase 19), Automation
  Calculator, failure recovery, and screenshot appendix.
- **`snow_log` docs expanded** (`docs/snow-log.md`) — added incident ticket
  usage patterns (Phase 19) with live INC0011360 example, showing how the
  remediation workflow logs a real-time investigation narrative.

### Changed
- **Teardown cleans up host_metrics** — `teardown.yml` now deletes
  host_metrics entries for destroyed VMs so they stop counting against the
  Red Hat managed-node subscription. Also migrated `ansible.controller.host`
  → `ansible.platform.host` per project conventions.
- **Gather and Display Facts JT renamed** — `DC1.Azure - Gather and Display
  Facts` → `DC1.Azure - Gather and Display Facts (Windows)` for OS clarity.
- **F5 phase renumbered** — Phase 19 (F5 Load Balancing) → Phase 20 to make
  room for the incident response demo.
- **`.ansible-lint` mock_modules** — added `win_service_info` and
  `win_powershell` for CI compatibility.

### Added
- **`snow_log` role** — reusable role for real-time ServiceNow ticket logging
  from any playbook. Posts work notes (or comments) to any ticket type (RITM,
  incident, change request). Guarded on `ticket_number` (no-ops on non-SNow
  runs), non-breaking (rescue on failure), and delegates to localhost so it
  works from plays targeting remote hosts. Dynatrace OneAgent playbooks are the
  first consumers.

### Changed
- **Dynatrace audit proof → real-time SNow logging** (AB#148) — replaced the
  `set_stats` → `update_ritm.yml` path with direct `snow_log` role calls in
  both OneAgent playbooks. Audit proof now posts to the RITM in real-time
  during the Dynatrace JT, not deferred to the final workflow summary.
  Removed the Dynatrace Jinja block from `update_ritm.yml`. Added
  `cred_servicenow` to both Dynatrace JTs.
- **DT nodes moved parallel with config chain** (AB#148) — Dynatrace OneAgent
  installs immediately after Provision VM, alongside Powershell Improvement /
  Configure Linux / CMDB CI. Earlier monitoring coverage + more time for
  host registration. Update RITM (success) now converges 4 always-parents.
- **Audit proof format cleaned up** (AB#148) — replaced raw `oneagentctl
  --get-server` CDN endpoint dump with tenant URL, host group, and connected
  status.
- **Host group set via `oneagentctl --set-host-group --restart-service`**
  (AB#148) — explicit post-install step on both OS playbooks.

### Removed
- **Dynatrace tenant verification task** (AB#148) — the `/api/v2/entities`
  API check never succeeded within the retry window (host registration takes
  >6 min). The audit proof (version, tenant, host group, connected status)
  is sufficient evidence. Removed from both OS playbooks.

### Added
- **Phase 18 — Dynatrace OneAgent integration** (AB#147) — new
  `DC1.Azure - Install Dynatrace OneAgent` JT running
  `playbooks/install_dynatrace_oneagent.yml`. Downloads and installs the
  OneAgent from the Dynatrace deployment API on both Windows (`windemo`) and
  Linux (`linuxweb`) VMs. Tags hosts into the `dc1-azure` host group so the
  `aap.eda.dynatrace.push` EDA demo can scope problem events to dc1.azure-
  provisioned infrastructure. New `DC1.Azure - Dynatrace` custom credential
  type injecting `DT_API_HOST` + `DT_PAAS_TOKEN` as env vars. Workflow node
  inserted after Patching + Configure Linux (converges both OS paths), before
  Update RITM (success).

### Added
- **Dynatrace OneAgent audit proof in RITM** (AB#147) — both OneAgent
  playbooks now query `oneagentctl` for version and server connection info,
  publish the results via `set_stats`, and the RITM success work note
  includes a "Dynatrace OneAgent" section showing tenant, host group,
  version per OS, connection info, and tenant-side host verification
  (Linux only, via Dynatrace `/api/v2/entities` — best-effort).
- **IT controls document** (`docs/controls.md`) — maps audit control
  requirements (CTL-001 through CTL-004) to their technical enforcement in
  the AAP workflow: Dynatrace OneAgent deployment, nightly teardown, token
  lifecycle, and cross-system RITM ↔ AAP traceability.

### Changed
- **Install docs: ADO Trigger post-install step** — `INSTALL.md` §7 and the
  `/install-dc1-azure` skill now mention running the `DC1.Azure - Configure
  ADO Trigger` JT after a green `load.yml` (once per RHDP env, idempotent).
- **Install docs: stale object counts** — updated credential count (8 → 10;
  added Linux Machine + ServiceNow), JT count (6 → 16), added EDA objects to
  the post-install inventory list.
- **Install skill: auto-token** — replaced manual token creation/deletion
  steps (old steps 4 + 8) with a note that `load.yml` mints + deletes its
  own token automatically; moved `AAP_TOKEN` / `CONTROLLER_OAUTH_TOKEN` to
  optional (SSO/MFA escape hatch only).

### Added
- **Phase 17 — Linux post-provision configuration** — new
  `DC1.Azure - Configure Linux` JT running `playbooks/configure_linux.yml`
  with the `linux_configure` role. Apache httpd + firewalld (port 80) +
  dc1.azure-branded website ("This website is running on Red Hat Enterprise
  Linux Server" + hostname). Post-install hardening from `aap.dailydemo.F5`
  `linux_post_install` pattern: Chrony NTP, Cockpit removal, Insights
  client, security SSH/MOTD/issue banners, Cockpit config, dnf
  security+bugfix updates (`update_only`, `skip_broken`, exclude
  `sudo.x86_64`), conditional reboot. RHSM/CDN registration deferred
  (activation key ready).
- **Always-create inventory groups** — `provision_vm.yml` now creates both
  `windemo` and `linuxweb` groups unconditionally; publishes
  `linux_admin_username` via `set_stats` for the RITM callback.

### Changed
- **Workflow convergence + limit cleanup** — removed `limit:` from all
  configure workflow nodes (playbooks already target `hosts: windemo` /
  `hosts: linuxweb` directly); explicit `limit: ""` clears stale limits on
  AAP. `all_parents_must_converge: true` on `update-ritm-success` ensures
  both OS paths complete before the RITM is marked fulfilled. Empty group =
  clean skip (rc=0), not an error.
- **`ask_limit_on_launch: true`** on all configure JTs (Windows + Linux) so
  CaC is authoritative for the setting.

### Fixed
- **RITM success message formatting** — literal `\n` in the ServiceNow work
  note replaced with proper Jinja2 block template. Per-OS sections now show
  the correct admin user (Windows: `demoadmin`, Linux: `azureuser`) instead
  of hardcoded `demoadmin`.

### Added
- **Phase 12 — Automate ADO trigger setup** (AB#144) — new
  `DC1.Azure - Configure ADO Trigger` JT running
  `playbooks/ado/configure_ado_trigger.yml`. Mints a long-lived AAP API token,
  creates/updates the `dc1-azure-aap` Variable Group in the ADO Library with
  the current AAP hostname + token, and authorizes the launch pipeline — zero
  ADO-UI clicks on a fresh env. Uses the ADO REST API via `ansible.builtin.uri`
  (decision AB#121). Launch pipeline renamed from "DC1.Azure — Launch Windows
  VM" to "DC1.Azure — Launch Infrastructure" and tier choices updated to
  B-series.

### Changed
- **VM tiers restructured — DSv5 → B-series burstable** (AB#143) — moved all
  three t-shirt tiers from DSv5 (`D2s_v5`/`D4s_v5`/`D8s_v5`) to B-series
  burstable (`B2s`/`B2ms`/`B4ms`). B-series is cheaper (~60-70% less),
  sufficient for demo workloads, and uses its own separate vCPU quota — freeing
  the DSv5 quota for the Phase 19 F5 appliance. Tier names updated to reflect
  new specs: `small-2cpu-4gb`, `medium-2cpu-8gb`, `large-4cpu-16gb`.
  `os_type=both` at large now fits in the 10-vCPU quota (8 total). Updated
  Terraform, playbook asserts, CaC surveys, and all docs.
- **OS-aware ServiceNow callback messages** — the start notice and RITM
  success messages now reflect the actual OS type (Windows Server / Linux
  (RHEL 9) / Windows Server + Linux (RHEL 9)) instead of hardcoded "Windows
  Server VM."

### Added
- **`/servicenow` Claude skill** (AB#142) — new repo-based skill
  (`.claude/skills/servicenow/SKILL.md`) for working with the dc1.azure
  ServiceNow integration. Covers architecture, credentials, key files,
  common tasks (catalog updates, trigger debugging, token rotation), module
  patterns, and CMDB CI classes. Living reference — updated with new
  patterns as they're discovered.
- **`playbooks/servicenow/update_catalog_item.yml`** (AB#142) — operational
  playbook to update the ServiceNow catalog item text fields (name,
  short_description, description) via `servicenow.itsm.api`. Picture upload
  is manual (SNow Attachment API requires multipart).
- **Catalog icon** (AB#142) — Red Hat-themed IT infrastructure SVG/PNG icon
  for the ServiceNow catalog item (`docs/images/catalog-it-infrastructure.*`).

### Fixed
- **CMDB CI class now OS-conditional** (AB#142) —
  `playbooks/servicenow/create_ci.yml` was hardcoded to `cmdb_ci_win_server`.
  Now uses `cmdb_ci_linux_server` when `os_type == 'linux'`, so Linux VMs
  get the correct CMDB class. Customer-visible fix.

### Changed
- **ServiceNow catalog pivot — Windows VM → IT infrastructure** (AB#142) —
  renamed the catalog match string from `DC1.Azure Windows VM on Azure` to
  `DC1.Azure Infrastructure Provisioning` (`my_azure_catalog_short_description`
  in `group_vars/all.yml`). Updated `servicenow/README.md` and
  `docs/servicenow-integration.md` to reflect the new catalog item name,
  os_type variable, and icon. The EDA rulebook and activation template off
  the variable, so no rulebook code changes needed.
- **Documentation pivot — Windows VM → IT infrastructure provisioning**
  (AB#141) — updated all repo documentation to reflect the multi-OS capability
  merged in Phase 16. The repo is now framed as "AAP-orchestrated IT
  infrastructure provisioning on Azure" (Windows Server 2025 and RHEL 9 Linux),
  showing the evolution from Windows-first to multi-OS. Touched `README.md`
  (title, story, end-to-end status), `galaxy.yml` (description + tags),
  `ROADMAP.md` (guiding principles), `docs/INSTALL.md` (Linux SSH prerequisites),
  `aap_config/README.md` (multi-OS workflow, Linux project), `docs/demo-runbook.md`
  (multi-OS survey, Linux variant note), `docs/servicenow-integration.md` (goal
  statement), and the install skill. Docs-only — no code changes.

### Fixed
- **`load.yml` EDA activation re-apply failure** (AB#140) — every re-run of
  `load.yml` failed at the `eda_rulebook_activations` role with *"Activation
  is not in disabled mode and in stopped status"* because the dispatch role
  tried to update a RUNNING activation. `load.yml` now disables the EDA
  rulebook activation before dispatch (no-op on a fresh env) and re-enables
  it after, so re-applies run clean. Also updated the `# Run:` comment to
  show the `tee` log-capture pattern (`/tmp/load-<timestamp>.log`) so failures
  are reviewable without re-running.

### Changed
- **Nightly teardown — added 10 PM safety-net schedule** — a second daily
  teardown schedule (`DC1.Azure - Nightly Teardown (10 PM)`) fires at 22:00
  America/Phoenix, catching VMs left running by late work sessions that outlast
  the primary 6 PM teardown. The teardown JT is idempotent (`terraform destroy`
  no-ops on an empty state), so the 10 PM run costs nothing when the 6 PM run
  already cleaned up. The original schedule is renamed to
  `DC1.Azure - Nightly Teardown (6 PM)` for clarity. New
  `teardown_schedule_name_late` var in `group_vars/all.yml`.

### Added
- **Phase 16: Linux VM provisioning with multi-OS survey** — extends dc1.azure
  to provision RHEL 9 Linux VMs alongside Windows Server 2025 VMs. A new
  `os_type` survey parameter on the workflow (windows / linux / both, default
  windows) controls which VMs are created via conditional Terraform resources.
  Linux VMs use SSH key auth (user's own key pair from `LINUX_SSH_PUBLIC_KEY` /
  `LINUX_SSH_PRIVATE_KEY` env vars). New `DC1.Azure - Linux Machine` credential
  (CaC-managed). Inventory connection vars moved from inventory level to group
  level (`windemo` = WinRM, `linuxweb` = SSH). Windows configure workflow nodes
  scoped with `limit: windemo` so they succeed vacuously with `os_type=linux`.
  Terraform error output now surfaced in AAP job logs (was hidden by `no_log`).
- **Roadmap Phases 16–19** — Linux VM provisioning (Phase 16), Linux
  post-provision configuration with Apache web server (Phase 17, pattern from
  `aap.dailydemo.F5`), Dynatrace OneAgent push-model integration (Phase 18),
  and F5 BIG-IP load balancing on Azure (Phase 19).
- **Dynatrace env vars** — `DT_API_HOST` and `DT_PAAS_TOKEN` added to
  `docs/dev-environment.sh.example` for Phase 18 OneAgent integration.
- **Automation Analytics / Insights — Automation Calculator** — new
  `aap_config/files/controller_settings.yml` (consumed by the
  `infra.aap_configuration.controller_settings` role, wired into `load.yml`)
  turns on `INSIGHTS_TRACKING_STATE` and authenticates the console.redhat.com
  upload with a Red Hat **service account** (`SUBSCRIPTIONS_CLIENT_ID/SECRET`),
  feeding the Automation Calculator (ROI / planner) for customer demos. Legacy
  `REDHAT_USERNAME/PASSWORD` are explicitly cleared so the service account is the
  single analytics identity. Creds resolve at runtime from new env vars
  `REDHAT_SUBSCRIPTIONS_CLIENT_ID` / `REDHAT_SUBSCRIPTIONS_CLIENT_SECRET`
  (added to `group_vars/all.yml` + `docs/dev-environment.sh.example`; never
  committed). `validate_tasks.yml` now asserts tracking is enabled (and that the
  client ID landed, when supplied). Adapted from `aap.as.code`'s
  `controller_settings.yml`.
- **Phase 13 SNow-driver spike resolved (AB#125)** — chose **`servicenow.itsm.api`**
  (the collection's generic Table API module, already in the EE + already used for the
  Phase 8 CMDB CI patch) over raw `ansible.builtin.uri` for updating the ServiceNow
  Outbound REST Message. The "servicenow.itsm can't reach `sys_rest_message`" concern
  was a false dichotomy — the `api` module *is* the Table API. Live read-only PoC
  confirmed the shared-instance `SN_*` user has the **admin** role (write access to
  `sys_rest_message` / `sys_rest_message_fn` / the `dc1.eda_event_stream_token`
  `password2` property) and the existing `Ames - DC1.Azure EDA Event Stream` record is
  reachable (the endpoint lives on the `_fn` function record). Blast-radius caveat: 33
  other-SE REST Messages share the instance → writes must be `sys_id`-scoped + `Ames -`
  namespaced. Updated ROADMAP Phase 13 (driver ✅) + Risks (resolved) + Decisions Log;
  CHANGELOG. No code yet.
- **Phase 12 ADO-driver spike resolved (AB#121)** — chose the **ADO REST API via
  `ansible.builtin.uri`** over the `az devops` CLI for the Phase 12 trigger
  automation. Rationale (Decisions Log 2026-06-03): the pipeline→variable-group
  authorization step (`pipelinePermissions`) has no `az devops` command, so REST is
  unavoidable for at least one step — using it for all three operations beats mixing
  tools; `uri` is built-in (no `azure-devops` EE extension to add/maintain) and
  matches the repo's existing playbook→API pattern. Verified with a read-only REST
  GET of the live variable groups (`dc1-azure-aap` id 2, `dc1-azure-shared` id 1).
  Updated ROADMAP Phase 12 (driver now ✅), the Risks entry (marked resolved), and
  added a Decisions Log row. No code yet.
- **Roadmap — Phases 12–15 (post-demo planning)** — captured four new phases in
  `ROADMAP.md` after the successful demo: **Phase 12** automates the ADO trigger
  wiring from AAP (a `DC1.Azure - Configure ADO Trigger` JT that creates *and*
  idempotently re-points the `dc1-azure-aap` Variable Group + launch pipeline on a
  fresh env — replacing the Phase 10 manual ADO-UI build); **Phase 13** automates
  the ServiceNow Outbound REST Message from AAP (a `DC1.Azure - Configure SNow
  Trigger` JT that sets the `sys_rest_message` endpoint + encrypted bearer
  `sys_property` to the freshly-installed EDA event-stream URL/token — replacing the
  Phase 8 manual SNow-UI build); **Phase 14** is a fresh-env end-to-end validation
  (spin a new Product Demo env, run install + the two config JTs, prove all four
  triggers green, teardown clean); **Phase 15** expands the repo-based Claude skills
  beyond `install-dc1-azure` with `first-time-setup`, `spin-env`, `demo-readiness`,
  and `teardown`. Added two Decisions Log rows and two Risks/Open-Questions entries
  (ADO driver: `az devops` CLI vs REST; SNow driver: `servicenow.itsm` vs Table API).
  No code changes yet — planning only.
- **Phase 10 — Azure DevOps trigger (launch pipeline)** (AB#110) — the fourth
  and final trigger. New `azure-pipelines-launch.yml`: a manual-run pipeline
  (`trigger:`/`pr: none`) with a `vm_size_tier` queue-time parameter
  (small/medium/large dropdown) that **launches** the existing
  `DC1.Azure - Provision and Configure` workflow on demand — no parallel
  definition. Distinct from `azure-pipelines.yml` (Phase 5 CI lint/mirror), which
  never provisions. The step resolves the workflow **by name**
  (`GET …/workflow_job_templates/?name=…`, not a hardcoded env-specific id),
  POSTs `extra_vars: {vm_size_tier}` to the launch endpoint, then prints the
  workflow-job deep link and uploads it to the ADO run summary
  (`task.uploadsummary`) — fire-and-forget (mirrors the Phase 9 launcher's
  `wait: false`). AAP auth via the new ADO **Variable Group** `dc1-azure-aap`
  (`AAP_HOSTNAME` + secret `AAP_TOKEN`, UI-minted; SSO AAP can't basic-auth-mint),
  referenced with `variables: - group:` and the secret mapped to the script env —
  no inline creds (Phase 0.5 rule). Docs: `docs/demo-runbook.md` §9 (ADO variant),
  `docs/ado-conventions.md` §7 (Variable Group entry), ROADMAP Phase 10.
  **Validated live 2026-06-03** (AB#109): ADO run *DC1.Azure — Launch Windows VM*
  (`large-8cpu-32gb`) → AAP launch API → workflow job 163
  (`DC1.Azure - Provision and Configure`, id 28 — the same workflow the other
  three triggers use); all nodes green, guarded ServiceNow nodes no-op'd on the
  ticket-less ADO launch. This completes the **one-workflow / four-triggers**
  pattern (AAP UI · ServiceNow · Self-Service · ADO).
- **Phase 9 — Self-Service Portal trigger (RBAC + launcher JT)** (AB#107) —
  Config-as-Code for the Self-Service Portal trigger. **Finding:** the AAP
  Self-Service Portal (RHDH) surfaces **job templates only, not workflows**
  (proven live + Red Hat 2.6 docs), so a thin **launcher job template**
  `DC1.Azure - Request Windows VM` (`vm_size_tier` survey) runs new
  `playbooks/launch_workflow.yml` (`ansible.controller.workflow_launch`) to fire
  the existing `DC1.Azure - Provision and Configure` workflow — no parallel
  implementation. RBAC: new `DC1.Azure - Developers` team (`gateway_teams.yml`) +
  two demo users (`gateway_users.yml`) `dev-lead` (Organization Admin) and
  `jr-dev` (least-privilege); `gateway_role_user_assignments.yml` grants org-admin
  + team membership; `controller_role_team_assignments.yml` grants the team
  **JobTemplate Execute** on the launcher JT **and** the `Gather and Display Facts`
  JT (so jr-dev can self-serve both from the portal). `load.yml` resolves the
  env-specific JT ids at runtime and runs the controller role-team-assignment
  explicitly (the dispatcher omits controller_* assignment roles). Passwords from
  env (`DC1_AZURE_DEV_ADMIN_PASSWORD` / `DC1_AZURE_JR_DEV_PASSWORD`; `.example`
  updated). The portal itself (RHDH on OpenShift) stays in the `aap.selfservice`
  repo — referenced, not vendored (see that repo's issue on the workflow limitation).

### Changed
- **EE deliberate-update model — immutable semver tags + `pull: missing`**
  (AB#95) — replaced the floating `:latest` + `pull: always` workaround (AB#91)
  with a deliberate-promotion model. The Controller EE now pins to an immutable
  semver tag via the new `ee_version` var (`aap_config/group_vars/all.yml`,
  default **`v1.0.0`**) and uses **`pull: missing`** — pulled once, then the
  cached layer is reused instead of re-pulling ~521 MB on every job run. Safe
  because the tag is immutable. `hub_ee_repositories.yml` `include_tags` now
  templates off `ee_version` (`[latest, "{{ ee_version }}"]`) so a bump
  auto-syncs the new tag to PAH; `latest` is retained only as the Hub-less
  smoke-test escape hatch. `v1.0.0` is the 2026-06-01 hardened image (quay digest
  `sha256:4423a10…`), minted from the existing digest via `skopeo copy` (no
  rebuild). New runbook `docs/ee-versioning.md` documents the bump rule
  (CVE-only → patch · +collection → minor · new base → major) and the
  build→push→bump→re-apply loop; provenance recorded in `execution-environment.yml`.

### Added
- **Custom EE rationale doc** (AB#95) — `docs/ee-why-custom-ee.md` explains why
  DC1.Azure ships a purpose-built execution environment (Terraform binary on
  PATH, baked + version-pinned collections/Python deps, OS-errata hardening,
  air-gapped PAH delivery, reproducibility) rather than relying on a bare
  `collections/requirements.yml` against a stock EE at run time.
- **Fact caching & inventory visibility — v1 standalone JT** (Phase 11) — new
  `DC1.Azure - Gather and Display Facts` job template (`use_fact_cache: true`)
  running this repo's new `playbooks/gather_facts.yml` against the provisioned
  Windows VM (`windemo` group, WinRM via `DC1.Azure - Windows Machine`). Surfaces
  facts two ways: the full set is **persisted in the AAP database** (per-host
  Facts tab, re-stamped each run) and a **curated summary** (OS, CPU, memory,
  IPs, domain, last boot) prints to the job log. A `show_full_facts` survey
  toggle (default `false`) optionally dumps the complete `ansible_facts` dict.
  Workflow-node wiring (v2) and ServiceNow CMDB enrichment (v3) are tracked
  under Phase 11 in `ROADMAP.md`.

### Removed
- **Deprecated bootstrap path** (AB#102) — deleted `playbooks/bootstrap_aap.yml`
  and its dedicated `inventories/dc1-azure/` bootstrap inventory. The
  `aap_config/load.yml` Config-as-Code path is the proven canonical replacement
  (run live via the `install-dc1-azure` skill), so the transitional bootstrap is
  retired per ROADMAP's Transition/deprecation plan. No functional includes
  referenced it (only doc/comment mentions, all scrubbed: `CLAUDE.md`,
  `README.md`, `aap_config/README.md`, `ROADMAP.md`,
  `aap_config/tasks/aap_token_acquire.yml`). The CaC path uses its own
  `aap_config/inventory/`.

### Fixed
- **Phase 10 launch pipeline — wrong Controller API base** (AB#111) — found in
  live validation: `azure-pipelines-launch.yml` hardcoded the legacy
  standalone-Controller path `/api/v2`, which **404s (HTML)** on the AAP 2.5
  unified gateway, so the workflow-resolve `curl` returned non-JSON and the launch
  step died with a `JSONDecodeError`. Switched to **`/api/controller/v2`** — the
  path used everywhere else in this repo (group_vars/all.yml, demo-runbook).
- **Docs accuracy — ServiceNow callback narrative** (AB#103) — reconciled
  `docs/servicenow-integration.md` with as-built: the design blockquote and the
  "Job templates (point at the synced Windows project)" header wrongly stated the
  ServiceNow callback JTs reuse the Windows project's playbooks with "no new
  playbooks in dc1.azure." As-built (per `aap_config/files/controller_job_templates.yml`),
  the callback JTs run **dc1.azure-owned** playbooks under `playbooks/servicenow/`
  on `project_name`; only Powershell/Provision-Access/Patching reuse
  `windows_project_name`. Reworded both, plus the Update-RITM-failure bullet
  (`update_ritm.yml` drives both outcomes via `ritm_outcome`).
- **Docs accuracy — ServiceNow playbook filenames** (AB#101) — `docs/servicenow-integration.md`
  referenced stale playbook names that don't exist in the repo; corrected to the
  as-built dc1.azure-owned files: `update_sn_req_itm.yml` → **`update_ritm.yml`**
  and `incident_create.yml` → **`create_incident.yml`** (verified against
  `aap_config/files/controller_job_templates.yml`, where the RITM/Incident JTs run
  `playbooks/servicenow/update_ritm.yml` / `create_incident.yml`).

### Security
- **ServiceNow EDA bearer token moved off the plaintext REST header** (AB#92) —
  hardened the live ServiceNow inbound config and the committed source-of-truth.
  The bearer token is now held in an **encrypted** system property
  `dc1.eda_event_stream_token` (`password2`) and read at runtime by the Business
  Rule via `gs.getProperty()`, which sets the `Authorization` header on the POST;
  the static plaintext `Authorization` header was removed from the
  `Ames - DC1.Azure EDA Event Stream` REST Message (only `Content-Type` remains).
  Also deployed the hardened BR script (`clean()`/trim on every value + `gs.info`
  HTTP-status logging + safe variables loop). Updated
  `servicenow/business_rules/fire_eda_on_ritm.js` + `servicenow/README.md` to the
  property-based auth and the as-built *before/Update on approval* trigger.
  **Validated live 2026-06-02:** order RITM0011940 → BR logged `HTTP 200` (token
  read from the encrypted property accepted) → workflow launched (job 120).
- **Scrubbed leaked RHDP/Azure identifiers** (AB#98) — replaced live deployment
  values that had been committed in `CHANGELOG.md` and `ROADMAP.md` with grep-able
  placeholders, per the no-RHDP-URLs rule: the AAP cluster URL
  (`aap-aap.apps.<rhdp-cluster>.redhatworkshops.io`), RHDP resource group
  (`<rhdp-resource-group>`), TF-state storage account
  (`<tf-state-storage-account>`), Service-Principal appId (`<rhdp-sp-app-id>`),
  and the smoke-test VM's public IP (`<vm-public-ip>`) + FQDN
  (`dc1az-small-<suffix>.…`). Note: these remain in **git history** — a true purge
  would need a history rewrite, deferred (repo is private).

### Added
- **Demo-runbook screenshots demo-00 → demo-05** (AB#100, Epic AB#3 Phase 6) —
  captured the core AAP-driven demo flow live and embedded it in
  `docs/demo-runbook.md`, replacing the inline 📸 placeholders and ticking
  Appendix B: `demo-00-templates` (Templates list), `demo-01-workflow-template-{1,2,3}`
  (the 11-node visualizer in three panned tiles), `demo-02-survey` (`vm_size_tier`),
  `demo-03-workflow-success` (Jobs list — workflow + all child jobs Success),
  `demo-04-landing-page-{1,2}` (live IIS page + Provisioning Details),
  `demo-05-teardown-success` (empty `dc1-azure` inventory after teardown job 119).
  Also rewords the stale "five nodes" line (the graph is 11 nodes; callbacks no-op
  on a UI launch). No redaction needed on these (no browser chrome / live
  identifiers, except the ephemeral Azure FQDN already shown in demo-07/08).
- **ServiceNow catalog screenshot** (AB#99, Epic AB#77) — adds
  `docs/images/demo-06-snow-catalog.png` (the *DC1.Azure Windows VM on Azure*
  catalog item with its `vm_size_tier` choices) and embeds it in
  `docs/demo-runbook.md` ahead of the RITM/CMDB shots (catalog → RITM → CMDB
  order); Appendix B checklist ticked. Completes the demo-06/07/08 ServiceNow
  screenshot set. No redaction needed (no browser chrome / identifiers in frame).
- **ServiceNow demo screenshots** (AB#97, Epic AB#77) — captured from the live
  AB#93 validation run (RITM0011939) and wired into `docs/demo-runbook.md`:
  `demo-07-snow-ritm.png` (RITM auto-updated — *Configuration item* linked to the
  new CMDB CI, *Closed Complete*) and `demo-08-snow-cmdb-ci.png` (the new *Windows
  Server* CI with its *Uses → Ansible Demonstrations* relationship). Inline 📸
  placeholder replaced with real `![](images/…)` embeds; Appendix B checklist
  ticked. Live identifiers **redacted** before commit (browser URL bar / ServiceNow
  instance, public IP) per the no-RHDP-URLs rule. `demo-06-snow-catalog.png` still
  pending (no live run needed).
- **RITM ↔ CMDB CI link** (AB#93, Epic AB#77) — closes the loop between the
  requested item and the configuration item it produced. After registering the
  CI, **`playbooks/servicenow/create_ci.yml`** now patches
  `sc_req_item.configuration_item = <CI sys_id>` (the RITM's *Configuration item*
  field), so the ticket and the CMDB record reference each other. The patch lives
  in `create_ci.yml` (not `update_ritm.yml`) because the CI sys_id is only known
  on the CMDB branch — Create CMDB CI and Update RITM run on sibling workflow
  branches, so a `set_stats` artifact would never reach Update RITM. The RITM is
  resolved from the threaded `ticket_sys_id` (falls back to a `numberSTARTSWITH`
  lookup), mirroring the start-notice; the new CI sys_id is also published via
  `set_stats` (`vm_ci_sys_id`) for observability. Guarded on `ticket_number`, so
  non-ServiceNow launches (AAP UI / Self-Service / ADO) no-op and stay green.
  Test: launch from ServiceNow → after provisioning, open the RITM → its
  *Configuration item* field points at the new `cmdb_ci_win_server` CI.
- **RITM start-notice — two-way link at launch** (AB#94, Epic AB#77) — ties
  ServiceNow and AAP together the moment provisioning starts (not just at the end).
  New root workflow node **`DC1.Azure - RITM Start Notice`** (parallel to Provision
  VM) runs **`playbooks/servicenow/notice_ritm_started.yml`** (guarded on
  `ticket_number`), which writes back to the originating `sc_req_item`: a
  customer-visible **comment** ("provisioning started") and a fulfiller **work
  note** carrying the **AAP workflow job ID + a deep link** to the job output
  (`awx_workflow_job_id`). It also publishes the **reverse link** (AAP job →
  the RITM) via `set_stats` (`snow_ritm_url`/`snow_ritm_number`) — fully
  bidirectional. New JT on `dc1-azure-control` with the `DC1.Azure - ServiceNow`
  **and** `DC1.Azure - Controller` creds (the latter for `CONTROLLER_HOST`);
  `validate.yml` asserts it. Uses the threaded `ticket_sys_id` (falls back to a
  number lookup). Test: launch from ServiceNow → the RITM gets a start comment +
  work-note link within seconds, and the AAP job carries a clickable `snow_ritm_url`.
- **ServiceNow-side artifacts + as-built setup** (AB#90, Epic AB#77) — version-controls
  the ServiceNow side of the inbound trigger so it survives a PDI reset and is
  reproducible. New **`servicenow/`** folder: `business_rules/fire_eda_on_ritm.js`
  (the hardened, **as-built** Business Rule — builds the payload from all catalog
  variables, `clean()`-trims every value to avoid the `vm_size_tier` trailing-space
  survey failure, logs HTTP status) + `README.md` (install order, REST Message +
  catalog/variable config, gotchas). Distinct from `playbooks/servicenow/` (the
  AAP-side callbacks). Adds a concrete "ServiceNow UI setup (as built)" section to
  `docs/servicenow-integration.md` — catalog item (exact `DC1.Azure Windows VM on
  Azure` match string), `vm_size_tier` Multiple Choice variable + monthly recurring
  prices, the `Ames - DC1.Azure EDA Event Stream` Outbound REST Message (static
  `Authorization` header, body via `setRequestBody()` — no `${...}` template), and
  the `sc_req_item` Business Rule referencing the script file (single source of
  truth). Instance URL, AAP event-stream URL/UUID, and the bearer token are
  placeholdered (RHDP/secret values never committed).
- **`docs/ee-security-remediation.md`** (AB#87, Epic AB#77) — the SE story of how
  we inspected the `DC1.Azure - EE` Quay security scan (351 CVEs / 24 High,
  inherited from a ~8-month-stale base), traced the High findings to base RPMs,
  and remediated at build time (AB#86) — clearing `openssl`/`openssh`/`libnghttp2`
  to el9_8 errata — while **deliberately deferring** the `pyOpenSSL`→`cryptography`
  37→48 cascade and the 2.18.x ansible-core base bump (each its own work item).
  One doc, two layers: a customer-facing talking track up top, the engineering
  record below. Hooked from `docs/demo-runbook.md` (optional deeper talking track)
  and the ROADMAP Decisions Log. *(Before/after scan table has placeholders for the
  "after" counts pending the Quay rescan of the pushed hardened image.)*
- **Phase 8 ServiceNow outbound callback** (AB#83, Epic AB#77) — when the
  *DC1.Azure - Provision and Configure* workflow runs from a ServiceNow request,
  AAP now calls ServiceNow back: updates the requested item (RITM), registers the
  VM as a CMDB CI with a business-app relationship, and opens an Incident on
  failure. Adds **four dc1.azure-owned guarded playbooks** under
  `playbooks/servicenow/` (`create_ci.yml`, `create_cmdb_relationship.yml`,
  `update_ritm.yml`, `create_incident.yml`) that call `servicenow.itsm` and
  **no-op when `ticket_number` is absent**, so AAP-UI / Self-Service / ADO
  launches stay green (single shared workflow preserved). Adds five JTs
  (Create CMDB CI / Create CMDB Relationship / Update RITM success+failure /
  Create Incident) on the `dc1-azure-control` inventory, the
  `DC1.Azure - ServiceNow` credential (ServiceNow ITSM type, `SN_*` from
  `dev-environment.sh`), and wires the workflow nodes (Patching `always`→CMDB CI→
  Relationship→Update RITM success; Provision VM `failure`→Incident→`always`→
  Update RITM failure). `provision_vm.yml` now `set_stats` the FQDN/IP/SKU/admin-
  user the callback consumes and wraps provisioning in a `rescue` that captures
  `vm_my_error`/`vm_my_job_id`/`vm_my_job_template_name` for the Incident.
  `validate.yml` asserts the new credential + 5 JTs. **The admin password is
  never written to the RITM** (decision 2026-05-29). Adds `servicenow.itsm`
  (2.13.0) to the EE manifest — **requires an EE rebuild** (see
  `execution-environment.yml` build provenance). Test: run the workflow with a
  `ticket_number` → RITM/CMDB update; force a failure → Incident opens + RITM
  reflects it.
- **Phase 8 EDA inbound trigger** (AB#81, Epic AB#77) — a ServiceNow-shaped event
  posted to an AAP EDA event stream now launches the existing
  *DC1.Azure - Provision and Configure* workflow. Adds the dc1.azure-owned
  rulebook **`rulebooks/servicenow_events.yml`** (matches on
  `short_description == my_azure_catalog_short_description`, runs
  `run_workflow_template` threading `ticket_number`/`ticket_sys_id`/`vm_size_tier`)
  and its EDA Config-as-Code: **`eda_credentials.yml`** (`DC1.Azure - EDA Controller`
  Red Hat AAP cred, `DC1.Azure - ServiceNow Event Stream` event-stream cred,
  `DC1.Azure - EDA Source Control` ADO-PAT SCM cred), **`eda_event_streams.yml`**,
  **`eda_rulebook_activations.yml`** (`DC1.Azure - Catch ServiceNow Events`), and a
  `DC1.Azure - EDA` entry in **`eda_projects.yml`** syncing this repo's rulebook
  from the ADO git URL. Wires all four into `load.yml`, extends `validate.yml`
  with EDA-object assertions (`/api/eda/v1/`), and adds `ansible.eda` (2.11.0) to
  `aap_config/requirements.yml`. Reuses the platform's built-in *Default Decision
  Environment* (no new registry credential). Test: POST a synthetic payload to the
  event-stream URL with the bearer token → the workflow launches.
- **`docs/servicenow-integration.md`** (AB#78 origin → **AB#79 redesign**, Epic
  AB#77) — Phase 8 ServiceNow integration design + build spec, **event-driven
  (Demo v2)**. Inbound: a ServiceNow **Business Rule** fires an **Outbound REST
  Message** at an **AAP EDA event stream**; a dc1.azure-owned **rulebook**
  (`rulebooks/servicenow_events.yml`) matches on `short_description` and runs the
  workflow with `run_workflow_template` (ServiceNow holds no workflow ID / launch
  token), mirroring the proven `aap.dailydemo.windows` pattern. Outbound: **AAP
  calls ServiceNow back** with **full Windows parity** — RITM update (success +
  failure) + CMDB CI (`cmdb_ci_win_server`) + relationship + Incident-on-failure,
  built by wiring the already-synced Windows ServiceNow playbooks. Documents the
  architecture/sequence, catalog item, the EDA CaC building blocks (event-stream +
  ITSM credentials, decision environment, event stream, rulebook activation,
  `ansible.eda`), the `DC1.Azure - ServiceNow` callback credential, threading
  provisioning details via `set_stats`, and the build/test plan. Resolves the EDA
  project git URL (the Azure DevOps repo) and the CMDB CI class. Status: **ready
  to implement** — `SN_*` creds + a minted `EDA_EVENT_STREAM_TOKEN` are in
  `docs/dev-environment.sh`; `docs/dev-environment.sh.example` carries the
  commented placeholders. EDA verified enabled on the AAP.
  *(History: v1 used ServiceNow Flow Designer + a direct REST `launch/`; replaced
  by the event-driven design above in AB#79 before any code shipped.)*
- **`docs/demo-runbook.md`** (AB#76) — SE-facing live-demo runbook for the v1
  AAP-driven flow: pre-flight checklist, talking track, click-by-click through
  the AAP UI (launch *DC1.Azure - Provision and Configure* + the `vm_size_tier`
  survey), per-node talking points with timings observed from live runs
  (provision ~10 min, teardown ~7 min), the IIS landing-page payoff, the
  self-cleaning teardown story (nightly 18:00 America/Phoenix = 01:00 UTC, plus
  the manual JT), a failure-mode appendix, a screenshot-capture checklist
  (Appendix B), and a quick-reference table. README + ROADMAP Phase 6 updated;
  screenshot capture remains.

### Removed
- **Stale `event.driven.ansible` EDA project** (AB#82) — removed the boilerplate
  EDA project entry carried over from `aap.as.code` (description "my awesome
  project") from `aap_config/files/eda_projects.yml`. Nothing in dc1.azure
  referenced it; the `DC1.Azure - EDA` project (AB#81) covers the rulebook-hosting
  role. Aligns with the repo-standalone principle. (Declarative removal: it is no
  longer managed by CaC; set `state: absent` if it must also be deleted from a
  live AAP it was previously applied to.)
- **Legacy `docs/dev-environment.md`** (AB#75) — fully superseded by the
  sourceable `docs/dev-environment.sh` (template `docs/dev-environment.sh.example`)
  since AB#61. Purged the remaining stale references from `CLAUDE.md`, `.gitignore`,
  `ROADMAP.md` (the Phase 8 ServiceNow credential-capture target is now
  `dev-environment.sh`), `playbooks/bootstrap_aap.yml`,
  `inventories/dc1-azure/group_vars/all.yml`, and the ADO pull-request template
  checklist. Historical changelog entries referencing the old file are left intact.

### Changed
- **Phase 8 marked validated end-to-end** (AB#96, Epic AB#77) — ROADMAP Phase 8 →
  ✅: flipped the remaining checklist items (catalog item, Business Rule/REST,
  EE rebuild+push, end-to-end test) to done, recorded the live validation
  (2026-06-02 — success: RITM → Closed Complete w/ IP/FQDN; failure: forced
  Provision VM fail → INC0011350 + RITM → Closed Incomplete), and added
  decisions-log entries (AB#94 start-notice, AB#91 live CaC fixes, AB#95 EE
  deliberate-update direction). Dropped the "CONFIRM the live value" caveat from
  `update_ritm.yml` — request-state `3`=Closed Complete / `4`=Closed Incomplete
  are confirmed for the instance.
- **Correct ROADMAP Sizing Tiers pricing to Windows PAYG rates** (AB#89) — the
  `Approx $/hr` column (~$0.10/$0.19/$0.38) was the *Linux* base-compute rate;
  these are Windows Server VMs, so the OS license ~doubles it. Updated to the
  Windows PAYG figures (`eastus`, Azure Retail Prices API 2026-06-01): D2s_v5
  ~$0.19, D4s_v5 ~$0.38, D8s_v5 ~$0.75, with a note that Azure Hybrid Benefit
  reverts to the Linux rates and that the figures are compute-only. Docs-only.
- **Docs accuracy sweep — Phase 8 status + token model** (AB#88, Epic AB#77) —
  caught the docs up to merged code. `ROADMAP.md` Phase 8: flipped the shipped
  checklist items to ✅ with AB# refs (EDA ingress AB#81, callback/CMDB/incident
  + 5 JTs AB#83, workflow wiring AB#83/AB#84, `provision_vm.yml` set_stats AB#83,
  `validate.yml` AB#81, runbook v2 §7), kept the genuinely-open items (catalog
  item, Business Rule, EE rebuild/push, end-to-end test), and rewrote the Progress
  block from "ready to implement" to "implementation merged; remaining =
  operational." `README.md` + `aap_config/README.md`: replaced the stale "personal
  API token" prerequisite with the AB#85 admin-username/password mint model.
  `README.md` repo-layout: added `docs/ee-security-remediation.md` +
  `docs/ado-conventions.md`. Docs-only.
- **Harden `DC1.Azure - EE`: apply OS errata at build time** (AB#86, Epic AB#77) —
  added `microdnf upgrade` as the first `prepend_base` step in
  `execution-environment.yml`, so every rebuild pulls all ubi9-available RHEL
  errata onto the base layer. The base (`ee-minimal-rhel9:2.17.14`, verified ==
  `2.17.14-4`, cut 2025-09-21) predated ~8 months of fixes; the Quay scan flagged
  351 CVEs (24 High), mostly base RPMs. Verified the rebuilt image moves
  `openssl-libs`/`openssh`/`libnghttp2` to el9_8 errata, clearing all three High
  RPM CVEs. **Deferred (own work items):** `pyOpenSSL 22.0.0` (a pip dep
  required-by `azure-cli-core`; bumping to ≥26 drags `cryptography` 37→48 under a
  pinned `azure-cli-core`) and the 2.18.x base line (ansible-core minor bump).
  Build-only change — no collection or base-image bump. Test: `rpm -q` the three
  packages in the rebuilt image shows el9_8 versions; Quay rescan shows a lower
  CVE count than the 351 baseline.
- **`DC1.Azure` project `scm_update_on_launch` → `false`** (AB#74) — with
  update-on-launch enabled, every workflow node that uses the `DC1.Azure` project
  fired a blocking SCM sync before its job ran, adding minutes to each
  Provision/Configure run. Disabled it to match the `aap.dailydemo.windows`
  project. Trade-off: the project no longer auto-syncs on job launch, so a manual
  project sync (`POST /api/controller/v2/projects/<id>/update/`) is required after
  merging playbook/role changes — already the established workflow.
- **`DC1.Azure - Provision and Configure` workflow layout — mirror DDW** (AB#84,
  Epic AB#77) — two node-graph changes to match the proven `aap.dailydemo.windows`
  shape: (1) **Create CMDB CI now runs early, on a parallel branch off Provision
  VM** (alongside Powershell Improvement) instead of being gated behind Patching,
  so the CI is registered while the configure chain runs — the `set_stats` from
  `provision_vm.yml` are available the moment Provision VM finishes; (2) **Update
  RITM (success) now hangs off Patching `always`** (mirrors DDW *Update request
  ticket - success*) instead of the tail of the CMDB chain, so a CMDB failure no
  longer blocks the request being marked fulfilled. Create CMDB Relationship is
  now a terminal leaf. No JT, credential, or playbook changes; `validate.yml`
  unchanged (asserts JTs + workflow by name, not topology). Test: apply
  `load.yml`, inspect the live workflow node graph — `provision-vm` success
  fans out to `create-cmdb-ci`, `patching` always → `update-ritm-success`,
  `create-cmdb-relationship` has no outgoing edge.
- **Self-managing CaC token — `load.yml`/`validate.yml` mint→use→delete** (AB#85)
  — the CaC path no longer depends on a stored `AAP_TOKEN` that expires and 401s.
  `load.yml` now runs as a single play that mints a short-lived **write** token
  from `AAP_CONTROLLER_USERNAME`/`PASSWORD`, applies the dispatch role + the
  validation checks under it, and **deletes the token in an `always:` block** —
  the same dance as `playbooks/provision_vm.yml`/`teardown.yml`/`bootstrap_aap.yml`.
  Adds shared `aap_config/tasks/aap_token_acquire.yml` + `aap_token_release.yml`,
  and splits the validation body into `aap_config/validate_tasks.yml` (imported
  inline by `load.yml` and by the now-thin standalone `validate.yml`, which mints
  its own **read** token). If `AAP_TOKEN` is exported (e.g. a UI-minted token for
  an SSO/MFA AAP where username/password minting is blocked) it is used **as-is
  and never deleted** — the escape hatch. `AAP_TOKEN` is now optional in
  `dev-environment.sh.example` + INSTALL.md. Test: `source dev-environment.sh`
  **without** exporting `AAP_TOKEN`, run `load.yml` → green; `GET /tokens/` shows
  no leftover token afterward.

### Fixed
- **Inbound EDA-trigger CaC — three live-validation bugs** (AB#91, Epic AB#77) —
  found while driving the ServiceNow→EDA→workflow path to a green end-to-end run
  (workflow job 78). All three lived only on the running AAP after manual fixes; a
  `load.yml` re-apply would have reverted them. (1) **`eda_rulebook_activations.yml`**
  — the activation's `extra_vars` didn't pass `my_organization`, so the rulebook's
  `run_workflow_template` action errored *"'my_organization' is undefined"* and no
  workflow launched (added `my_organization` to `extra_vars`). (2)
  **`controller_workflow_job_templates.yml`** — *DC1.Azure - Provision and Configure*
  lacked `ask_variables_on_launch: true`, so the API launch was rejected `400`
  *"Variables ticket_number, ticket_sys_id, ansible_eda are not allowed on launch"*
  (added the flag). (3) **`controller_execution_environments.yml`** — *DC1.Azure - EE*
  used `pull: missing`, so after an EE rebuild the execution node kept running the
  stale cached `:latest` (changed to `pull: always`; revisit when the EE adopts
  immutable version tags). Test: re-apply `load.yml`, fire a ServiceNow request →
  the workflow launches and the callbacks (CMDB CI/relationship/RITM) run green.
- **`DC1.Azure - Teardown` deregistration self-block** (AB#73) — the Teardown JT
  ran against the `dc1-azure` inventory, so AAP locked that inventory's hosts for
  the duration of the job and refused to let the job delete the very host it had
  just destroyed; the "Remove host from inventory" step failed and the JT reported
  **failed even though `terraform destroy` succeeded** (and stale hosts accumulated,
  one per random VM FQDN). Added a small, empty `dc1-azure-control` inventory and
  pointed the Teardown JT at it. The play already runs on `localhost` and the
  deregistration step targets `dc1-azure` over the API regardless, so the host is
  no longer "in use". `validate.yml` now asserts both inventories exist.
- **`DC1.Azure - Teardown` terraform init backend config** (AB#71) — the teardown
  playbook ran a bare `terraform init` (no `-backend-config`) and the Teardown JT
  never passed `dc1_azure_tf_storage_account`, so the azurerm backend initialized
  with an empty `container_name`; the nightly teardown failed every run (job 54:
  `containerName cannot be an empty string`) and provisioned VMs were never
  destroyed. `teardown.yml` now passes the same four `-backend-config` flags as
  `provision_vm.yml` (with `dc1_azure_tf_container` / `dc1_azure_tf_key` defaults),
  and the Teardown JT supplies `dc1_azure_tf_storage_account`.
- **`DC1.Azure - Teardown` stale `vm_size_tier` default** (AB#72) — `teardown.yml`'s
  destroy step defaulted `vm_size_tier` to `small`, a pre-AB#62 name the
  `terraform/variables.tf` validation now rejects, so `terraform destroy` failed at
  variable validation (job 56, hidden by `no_log`). Default changed to a valid tier
  (`medium-4cpu-16gb`); the value is irrelevant to destroy (config comes from state).
  Sibling of AB#65 / AB#66.

## 0.3.0 — 2026-05-27

### Changed
- **`ROADMAP.md` Sizing Tiers table** — tier names updated from `small / medium / large`
  to `small-2cpu-8gb / medium-4cpu-16gb / large-8cpu-32gb` to match the AB#62 rename
  that landed in the Terraform and AAP CaC layers.
- **`ROADMAP.md` Decisions Log** — added three 2026-05-27 entries for AB#59:
  `website_setup_azure` role must live in `playbooks/roles/` (AWX EE search path);
  `DC1.Azure - Demo Account Password` custom credential type (JT surveys don't fire
  inside workflows); Azure-native IIS template replaces AWS-only upstream role.
- **Documentation accuracy sweep — docs catching up to Phases 4 & 5** (AB#68):
  - `README.md` — updated the story step and Sizing-tiers table to the AB#62 tier
    names (`small-2cpu-8gb / medium-4cpu-16gb / large-8cpu-32gb`, companion to the
    ROADMAP fix above); rewrote the stale "End-to-end status" callout (Phase 4 is
    complete — workflow job 46 green, EE created by CaC); rewrote the "Mirror to
    GitHub" section (Phase 5 auto-mirror is live; manual `git push github main`
    retired); added `execution-environment.yml` to the repo layout and flagged
    `docs/demo-runbook.md` as not-yet-written.
  - `docs/INSTALL.md` — corrected the post-install credential count (6 → 8); updated
    the password-sync callout to reflect the AB#60 Windows Admin Password credential
    type (no manual vaulted extra var needed).
  - `aap_config/README.md` — credential count 4 → 8; replaced the drifting partial
    env-var list in "Run it" with the canonical `source dev-environment.sh` flow and
    a pointer to `docs/INSTALL.md` for the full table.
  - `aap_config/files/controller_credentials.yml` — header comment 4 → 8 credentials.
  - `CONTRIBUTING.md` — direct push to `main` is now blocked (Phase 0.5 complete, no
    longer "not blocked yet"); replaced the vestigial `.envrc` / `.envrc.example` and
    legacy `docs/dev-environment.md` references with `docs/dev-environment.sh`.
  - `docs/ado-conventions.md` — removed the stale "until Phase 0.5 lands, push is not
    blocked" note; extended the phase-tag list to `phase-10`.
  - `.gitignore` — corrected the `.envrc` comment (no `.envrc.example` exists; the
    canonical secret file is `docs/dev-environment.sh`).

### Fixed
- **`docs/INSTALL.md` §5 env-var table** (AB#68) — added the **required**
  `DC1_AZURE_DEFAULT_PASSWD` variable, which feeds the `DC1.Azure - Demo Account
  Password` credential (the `devops` / `ansible-svc` demo accounts the Provision
  Access JT creates). It was present in `docs/dev-environment.sh.example` but
  missing from the manual-install table, so a doc-only installer would have left
  the credential empty and broken the Provision Access step.
- **`aap_config/validate.yml` credential coverage** (AB#69) — the post-load
  validation asserted only 6 of the 8 credentials `load.yml` creates; it now also
  checks `DC1.Azure - Windows Admin Password` and `DC1.Azure - Demo Account
  Password` (the custom credential-type creds added in Phase 4). Previously a
  partial apply that dropped either could still exit green.

## 0.2.0 — 2026-05-27

### Fixed
- **`roles/website_setup_azure` moved to `playbooks/roles/`** (AB#67) — AWX EE
  searches `<playbook_dir>/roles/` not the project root `roles/`, so the role
  was not found at runtime. Moved to `playbooks/roles/website_setup_azure/`.
- **`terraform/variables.tf` vm_size_tier validation** (AB#66) — validation rule
  and default still used `small|medium|large` after AB#62 renamed them to
  `small-2cpu-8gb|medium-4cpu-16gb|large-8cpu-32gb`, causing `terraform apply`
  to fail with a variable validation error.
- **`playbooks/provision_vm.yml` assert** (AB#65) — vm_size_tier values in the
  assert still said `small|medium|large` after AB#62 renamed them to
  `small-2cpu-8gb|medium-4cpu-16gb|large-8cpu-32gb`, failing every workflow run.

### Added
- **`roles/website_setup_azure/`** (AB#59) — Azure-specific IIS website role replacing
  the AWS-only `website_setup` role from `aap.dailydemo.windows`. Template uses
  `inventory_hostname`, `vm_size_tier`, `dc1_azure_location`, and
  `ticket_number | default('N/A')` (placeholder until ServiceNow integration).
- **`playbooks/website_setup.yml`** (AB#59) — thin playbook calling `website_setup_azure`
  on the `windemo` group; "DC1.Azure - Website Setup" JT now points here.
- **`DC1.Azure - Demo Account Password` credential type** (AB#59) — injects
  `default_passwd` extra var for the Provision Access JT so demo user accounts
  are created without a survey prompt. Sourced from `DC1_AZURE_DEFAULT_PASSWD`
  in `docs/dev-environment.sh`.

### Changed
- **`docs/dev-environment.sh.example` comment** (AB#64) — adds explicit `cp` command to the header comment so users can copy-paste to create their local file without constructing the command themselves.
- **"DC1.Azure - Website Setup" JT** (AB#59) — now uses `dc1.azure` project and
  `playbooks/website_setup.yml` instead of `aap.dailydemo.windows`; adds
  `dc1_azure_location` extra var for the template.
- **"DC1.Azure - Provision Access" JT** (AB#59) — replaces `default_passwd` survey
  with `DC1.Azure - Demo Account Password` credential so the password is supplied
  automatically in workflow context.
- **ROADMAP.md Phase 4** (AB#63) — updated to reflect live run results (provision
  green, configure chain blocked on AB#59), all PRs from sessions 2026-05-27,
  and three new decisions log entries (AB#60 credential type, AB#62 tier labels,
  AB#61 dev-environment.sh).
- **CLAUDE.md** (AB#63) — removed stale Phase 3 bootstrap note (Phase 3 is
  complete); added `terraform fmt` convention so CI doesn't catch formatting
  issues after the fact.


- **VM size tier choices now carry spec info** (AB#62) — renamed from `small /
  medium / large` to `small-2cpu-8gb / medium-4cpu-16gb / large-8cpu-32gb` so
  the spec is visible in the AAP survey Multiple Choice Options field. Updated
  `terraform/locals.tf` map keys and survey defaults to match. The format is
  DNS-label-safe so `vm_name` and `dns_label` remain valid Azure resource names.

### Added
- **`docs/dev-environment.sh.example`** (AB#61) — committed placeholder template
  for the gitignored `docs/dev-environment.sh` env file. Copy it, fill in real
  values, then `source docs/dev-environment.sh && ansible-playbook -i aap_config/inventory/ aap_config/load.yml`.
  Replaces the previous `docs/dev-environment.md` approach with a directly
  sourceable shell script.

### Changed
- **`docs/INSTALL.md` §6** (AB#61) — `source docs/dev-environment.sh &&
  ansible-playbook …` is now the recommended run pattern; inline-export block
  kept as an alternative. One-shell-call requirement is explicitly called out.
- **`CLAUDE.md`** (AB#61) — updated dev-environment file references and added
  the one-shell-call rule so future Claude instances know to bundle exports with
  the playbook run or use `source`.
- **`.gitignore`** (AB#61) — added `docs/dev-environment.sh`; kept
  `docs/dev-environment.md` entry for backwards compatibility.
- **Install skill** (AB#61) — steps 5 and 7 now check for `docs/dev-environment.sh`
  and prefer `source` over a manually built compound export command.

- **`DC1.Azure - Windows Admin Password` custom credential type** — replaces the
  workflow survey prompt for `dc1_azure_windows_admin_password`. The new credential
  type injects the password as an extra var directly into the `DC1.Azure - Provision VM`
  JT so Terraform receives it without requiring any user input at launch time.
  Value sourced from `WINDOWS_ADMIN_PASSWORD` (same env var as the Machine
  credential), so a single `load.yml` run wires both credentials from one export.
  The password survey question has been removed from the `DC1.Azure - Provision
  and Configure` workflow.

- **Nightly teardown schedule** (AB#58) — `aap_config/files/controller_schedules.yml`
  creates a `DC1.Azure - Nightly Teardown` schedule on the `DC1.Azure - Teardown`
  job template that runs every day at 18:00 `America/Phoenix` (no DST → fixed
  01:00 UTC), so the demo VM never runs overnight. Wired into `load.yml` and
  asserted by `validate.yml`. The teardown JT now bakes a non-secret placeholder
  `dc1_azure_windows_admin_password` (`teardown_admin_password_placeholder`):
  terraform requires the var (12-72 chars) and `teardown.yml` asserts its length,
  but the value is unused on destroy — so scheduled/manual teardown runs need no
  password input and no secret is committed. Added `teardown_template` /
  `teardown_schedule_name` name vars (single source of truth for the JT + schedule).

### Fixed
- **Terraform now authenticates to Azure as the Service Principal** (AB#57).
  The Provision VM workflow node failed at `terraform init` with
  `could not configure AzureCli Authorizer ... "az": executable file not found`.
  AAP's `DC1.Azure - Azure RM` credential injects `AZURE_*` env vars, but
  Terraform's azurerm provider and the azurerm state backend read `ARM_*` —
  nothing mapped them, so the backend (`use_azuread_auth = true`) fell back to
  Azure CLI auth, which the EE has no `az` binary for. `provision_vm.yml` and
  `teardown.yml` now define an `arm_env` mapping (`ARM_CLIENT_ID`←`AZURE_CLIENT_ID`,
  `ARM_CLIENT_SECRET`←`AZURE_SECRET`, `ARM_TENANT_ID`←`AZURE_TENANT`,
  `ARM_SUBSCRIPTION_ID`←`AZURE_SUBSCRIPTION_ID`) applied as a play-level
  `environment`, combined into the `apply`/`destroy` tasks' own environment so
  the SP creds reach every `terraform` invocation (init/apply/output/destroy).
- **EE now syncs into Private Automation Hub and Controller pulls it from
  there, not quay.io** (AB#56). Getting the EE image into Hub requires
  satisfying two independent gates that the original CaC got wrong, so the
  `dc1_azure_ee` Hub repository stayed empty (0 tags): (a) the *dispatch* gate —
  dispatch includes the `hub_ee_repository_sync` role only when a variable named
  `hub_ee_repository_sync` is *defined* (`vars[__role.var] is defined`); and
  (b) the *role* gate — once included, the role loops `hub_ee_repositories` and
  syncs only items whose `sync` sub-option is true. The original CaC put
  `sync`/`wait` in a separate `hub_ee_repository_sync:` *list* (satisfied (a) but
  not (b) — sync silently skipped). Fix: keep `hub_ee_repository_sync` defined as
  a trigger flag **and** move `sync: true`/`wait: true` onto the
  `hub_ee_repositories` item. Then added a `DC1.Azure - Hub Registry` Container
  Registry credential, attached it to the `DC1.Azure - EE` execution
  environment, and changed the `ee_image` default from
  `quay.io/zigfreed/dc1-azure-ee:latest` to `{{ ah_hostname }}/dc1_azure_ee:latest`
  so Controller authenticates to the internal Hub registry and pulls the EE from
  PAH. `validate.yml` now also asserts the `DC1.Azure - EE` execution
  environment and the new credential exist.

### Added
- `execution-environment.yml` — custom EE definition (ansible-builder v3) that
  extends `ee-minimal-rhel9:2.17.14` with Terraform 1.15.4. Installs all
  collections from `collections/requirements.yml` (azure.azcollection,
  ansible.windows, infra.aap_configuration, etc.) so one EE covers both the
  Provision/Teardown JTs (need `terraform`) and the Windows Configure JTs (need
  pywinrm). Three fixes from the user's source EE: (1) Terraform bumped from
  1.14.0 → 1.15.4 (latest with available binary), (2) `galaxy:` path corrected
  to `collections/requirements.yml`, (3) `prepend_galaxy` ADD path fixed from
  `_build/configs/ansible.cfg` → `_build/configs/.ansible.cfg` (ansible-builder
  preserves the leading dot). Build:
  `ansible-builder build -f execution-environment.yml -t dc1-azure-ee:latest`.
- `aap_config/files/hub_ee_registries.yml` — registers `quay.io` as a remote
  container registry on Private Automation Hub. Triggers registry creation,
  catalog index, and initial sync via the dispatch role (all three
  `hub_ee_registry*` roles fire from the single `hub_ee_registries` variable).
- `aap_config/files/hub_ee_repositories.yml` — creates a Hub EE repository
  (`dc1_azure_ee`) that mirrors `quay.io/zigfreed/dc1-azure-ee:latest` from
  the `quay_io` remote registry, then immediately syncs it (`hub_ee_repository_sync`
  with `wait: true`) so the image is in Hub before Controller registers it.
- `aap_config/files/controller_execution_environments.yml` — registers the
  `DC1.Azure - EE` execution environment in AAP Controller (image URL from
  `ee_image`, defaults to public quay.io; override `DC1_AZURE_EE_IMAGE` to use
  Hub URL after sync). Closes the Phase 4 live-run blocker: no more manual EE
  setup required.
- `aap_config/group_vars/all.yml` — added `ee_name` (`DC1.Azure - EE`),
  `ee_image` (env-driven, defaults to quay.io), `ah_hostname` (env-driven,
  defaults to gateway hostname — correct for AAP 2.5 unified platform); updated
  `my_execution_environment` to default to `ee_name` instead of the generic
  "Default execution environment".
- `.gitignore` — added `context/` (ansible-builder build-context directory).
- `.claude/skills/install-dc1-azure/SKILL.md` — updated env-var table: `DC1_AZURE_EE`
  is now optional (defaults to the EE load.yml creates); added `DC1_AZURE_EE_IMAGE`
  and `AH_HOSTNAME` as optional overrides.
- `docs/INSTALL.md` — (1) Added `AZURE_TF_STORAGE_ACCOUNT` (required) and
  `DC1_AZURE_EE_IMAGE` / `AH_HOSTNAME` (optional) to the env var table; updated
  `DC1_AZURE_EE` default from `Default execution environment` → `DC1.Azure - EE`;
  replaced outdated EE callout with note that `load.yml` creates the EE via CaC
  automatically. (2) Added §2.6 documenting the Terraform state Storage Account
  bootstrap (az CLI commands + role assignment). (3) Updated §6 example command:
  added `AZURE_TF_STORAGE_ACCOUNT`, removed `DC1_AZURE_EE='Product Demos EE'`.
  (4) Replaced single `terraform: not found` troubleshooting row with two rows
  covering the new EE CaC path.
- `ROADMAP.md` — Phase 4 live-run item updated to reflect EE blocker resolved;
  three 2026-05-27 entries added to Decisions Log (custom EE, quay.io hosting
  strategy, CaC EE registration).
- Azure Storage Account `<tf-state-storage-account>` bootstrapped in `<rhdp-resource-group>`; SP granted `Storage Blob Data Contributor` for Azure AD auth (`use_azuread_auth = true`). Documented in `docs/dev-environment.md`.

### Changed
- `playbooks/provision_vm.yml` — `terraform init` now passes `-backend-config` flags for `resource_group_name`, `storage_account_name`, `container_name`, and `key`. Backend values flow in via JT extra_vars; `dc1_azure_tf_container` and `dc1_azure_tf_key` default to `tfstate` / `dc1.azure.tfstate`.
- `aap_config/files/controller_job_templates.yml` — Provision VM JT extra_vars now includes `dc1_azure_tf_storage_account` (sourced from `azure_tf_storage_account` in `group_vars/all.yml`).
- `aap_config/files/controller_workflow_job_templates.yml` — workflow survey now includes a `password` type question for `dc1_azure_windows_admin_password` (required, 12–72 chars); this is the delivery path for the Windows VM admin password into `provision_vm.yml`.
- `aap_config/group_vars/all.yml` — added `azure_tf_storage_account` sourced from `AZURE_TF_STORAGE_ACCOUNT` env var (default `REPLACE_ME_TF_STATE_SA`).
- `.claude/skills/install-dc1-azure/SKILL.md` — added `AZURE_TF_STORAGE_ACCOUNT` to required env var list.

---

- `aap_config/files/gateway_settings.yml` — platform-wide AAP gateway settings (token name, expiration, proxy URL, login banner). Sourced from `aap.as.code`.
- `aap_config/files/gateway_organizations.yml` — six AAP organizations (`IT Service Automation`, `Network`, `Storage`, `Online Shopping`, `Data Center Operations`, `Security Operations Center`), each pre-populated with the three standard Galaxy credentials. Sourced from `aap.as.code`.
- `aap_config/files/gateway_teams.yml` — four teams (`Network`, `Server`, `Storage`, `ITO`) scoped under `my_organization`. Sourced from `aap.as.code`.
- `aap_config/files/eda_projects.yml` — EDA project pointing at `ericcames/event.driven.ansible`. Sourced from `aap.as.code`.
- `aap_config/files/controller_credential_types.yml` — `ServiceNow ITSM Credential` custom type (injects `SN_HOST`, `SN_USERNAME`, `SN_PASSWORD` env vars). Sourced from `aap.as.code`.

### Changed
- `ROADMAP.md` — marked Phases 0.5, 3, 5, and 7 ✅ complete. Updated individual checklist items to reflect as-built state, added completion dates and verification notes. Phase 4 remains 🔄 (code merged; live workflow run pending).
- `aap_config/group_vars/all.yml` — `my_organization` changed from `Default` to `IT Service Automation` to match the aap.as.code standard org name.
- `aap_config/load.yml` — added the five new vars_files (gateway_settings, gateway_organizations, gateway_teams, eda_projects, controller_credential_types) before the existing controller_* files so dispatch picks them all up in one run.

### Fixed
- `ansible.cfg.example` — two corrections: (1) renamed `[galaxy_server.automation_hub]` → `[galaxy_server.rh_certified]` to match the actual section name the install skill greps for (the wrong name caused silent empty-token extraction during the first live run); (2) added `[galaxy_server.rh_validated]` section (URL: `.../content/validated/`, same token) and added it to `server_list`. Also updated `server_list` entry `release_galaxy` → `community` and added inline comments explaining the token reuse and section-name dependency.
- `docs/INSTALL.md` — added troubleshooting row: if `my_organization` is changed and `load.yml` fails with "returned N items, expected 1", the old org's objects must be deleted manually before rerunning (the `infra.aap_configuration` role queries by name only, not name+org, so duplicates across orgs cause a fatal).
- `docs/INSTALL.md` + `.claude/skills/install-dc1-azure/SKILL.md` — captured all lessons from the first live `load.yml` run (2026-05-26):
  - **§2.5 (new)** — "Automation Hub - certified" and "Automation Hub - validated" Galaxy credentials must be created and attached to the Default org *before* running `load.yml`. Without them, `infra.aap_configuration` async workers fall back to `127.0.0.1` and fail with `Connection refused` on every credential creation task. Includes API-scriptable creation steps and the correct `~/.ansible.cfg` section names (`rh_certified` / `rh_validated`, not `automation_hub`).
  - **§2 callout** — `~/.ansible.cfg` must be a real file, not a symlink. Symlinks can cause Ansible to skip loading the cfg in some contexts. Fix: `rm ~/.ansible.cfg && cp ~/.ansible/ansible.cfg ~/.ansible.cfg`.
  - **§4 (token creation)** — AAP 2.5 uses `POST /api/gateway/v1/tokens/` (not `/api/controller/v2/tokens/`). Token must be deleted via the same gateway endpoint after install.
  - **§5 (env vars)** — added three required variables: `CONTROLLER_HOST`, `CONTROLLER_OAUTH_TOKEN`, `CONTROLLER_VERIFY_SSL`. The `ansible.controller.*` collection modules read these env vars directly in async worker processes, independently of the `aap_hostname`/`aap_token` Jinja2 lookups. Both sets must be set to the same values.
  - **§6 callout** — all `export` statements and the `ansible-playbook` command must be in a single shell process. Shell state does not persist across separate terminal commands or tool invocations; splitting them leaves the playbook with empty env vars.
  - **Troubleshooting table** — added rows for `Connection refused to 127.0.0.1`, censored `no_log` credential failures, and the wrong Galaxy credential token extraction pattern.

- `terraform/main.tf` — added `patch_mode = "AutomaticByPlatform"` + `hotpatching_enabled = true` to `azurerm_windows_virtual_machine.demo`. Required by azurerm provider v4.x for hotpatch-enabled images (Windows Server 2025 Azure Edition). Without it, `terraform apply` fails on the VM resource with *"patch_mode must always be set to AutomaticByPlatform when source_image_reference points to a hotpatch enabled image"*. Discovered during Phase 2 smoke test 2026-05-21.
- `terraform/main.tf` — added `azurerm_virtual_machine_extension.winrm_bootstrap` (CustomScriptExtension) that copies `C:\AzureData\CustomData.bin` to `bootstrap.ps1` and executes it via PowerShell. Azure does **not** auto-execute `custom_data` on Windows VMs (unlike Linux cloud-init); the binary is deposited but never run. Without the extension, the WinRM-HTTPS listener was never configured and port 5986 stayed closed after `terraform apply`. Discovered during Phase 2 smoke test 2026-05-21.
- `terraform/scripts/winrm_bootstrap.ps1` — replaced `cmd.exe /c "winrm create winrm/config/Listener?Address=*+Transport=HTTPS '@{Hostname=...; CertificateThumbprint=...}'"` with PowerShell-native `New-WSManInstance`. When the bootstrap script runs as SYSTEM via the Azure CustomScriptExtension, the nested cmd.exe quoting collapses and the resulting HTTPS listener is created with an empty `CertificateThumbprint`. The `New-WSManInstance` invocation passes the hash table natively and avoids cmd.exe entirely. Discovered during Phase 2 smoke test 2026-05-21.

### Changed
- `ROADMAP.md` — Phase 5 advanced ⬜ → 🔄: lint/validate pipeline built; build-validation branch policy is a post-merge step; auto-mirror deferred (needs a GitHub PAT). Notes ADO hosted parallelism is available (Free tier).
- `terraform/main.tf` — `terraform fmt` normalization (1 line) so the new `terraform fmt -check` CI gate passes. (Phase 5.)
- `README.md` (Phase 7) — Getting Started now points at both install paths (manual `docs/INSTALL.md` + the `/install-dc1-azure` skill); removed the stale "not wired up / `aap_config/` not on disk yet" notes; refreshed the repo-layout block (adds `aap_config/`, `ansible.cfg.example`, `.claude/skills/`, `docs/INSTALL.md`).
- `ROADMAP.md` — Phase 7 advanced ⬜ → 🔄 (INSTALL.md, install skill, README done; acceptance test gated on the Phase 4 live run).
- `aap_config/group_vars/all.yml` — aligned the `WINDOWS_ADMIN_USERNAME` default from `azureuser` to **`demoadmin`** to match Terraform's `admin_username` default, so the Windows Machine credential and the VM's local admin line up. (Phase 7.)
- `aap_config/files/controller_credentials.yml` — added the **`DC1.Azure - Controller`** (Red Hat Ansible Automation Platform) credential so `provision_vm.yml`/`teardown.yml` can register/deregister the VM in the inventory via the controller API (5 credentials now). `aap_config/files/controller_job_templates.yml` — attached it (plus Vault) to the Provision/Teardown JTs and added `dc1_azure_resource_group` / `dc1_azure_location` `extra_vars`. `aap_config/group_vars/all.yml` — added the Controller-credential inputs and `azure_resource_group`/`azure_location` (env-baked). `aap_config/validate.yml` — now also verifies the Controller credential. `aap_config/files/controller_inventories.yml` — comment corrected to the `windemo` group the reused playbooks target. (Phase 4.)
- `ROADMAP.md` — Phase 4 advanced ⬜ → 🔄: documents the as-built design (provision registers the host into the `windemo` group; configure reuses the pinned Windows JTs rather than a new `configure_windows.yml`; teardown deregisters; new Controller credential) and the deferred live run + dynamic-inventory alternative. (Phase 4.)
- `ROADMAP.md` — captured the Phase 3+ strategic direction (2026-05-26): pin `infra.aap_configuration` **4.4.0** (the Automation Hub release); dc1.azure now **stands independent of `aap.as.code`** with the collection's own docs as the CaC guide and CaC var files named per role/module; runtime target is the **Ansible Product Demo** RHDP catalog item's AAP (install additively, namespaced — not the `ansible/product-demos` repo layout); **one core workflow, four triggers** — added **Phase 9 (AAP Self-Service Portal)** and **Phase 10 (Azure DevOps trigger)**, additive with no renumbering; reuse `aap.dailydemo.windows` roles via a **pinned git reference** (not rewritten); vault password from a **dc1.azure-owned source** (not the borrowed `~/.ansible/secrets2`); ship **`ansible.cfg.example`** (never a live cfg) + **repo-based Claude skills**. Added 8 Decisions Log entries; reworked Guiding Principles, Architecture (four-trigger fan-in + Product-Demo-AAP note), Phase 3 (file names → `controller_job_templates.yml` / `controller_workflow_job_templates.yml`, 4.4.0, vault/cfg/skill prereqs), Phase 4 (role-sourcing decided), and Reference Repositories.
- `collections/requirements.yml` — bumped `infra.aap_configuration` pin 4.2.0 → **4.4.0** (the Automation Hub release; dc1.azure stands independent of aap.as.code's 4.2.0 pin). Decision 2026-05-26.
- `.gitignore` — carved `.claude/skills/` out of the `.claude/` ignore (`.claude/*` + `!.claude/skills/`) so repo-based Claude skills can ship with the repo. Per-project Claude state (memory, transcripts, settings) stays ignored. Decision 2026-05-26.
- `ROADMAP.md` — synced Phase status indicators to actual repo state: **Phase 0** ⬜→✅ (ADO org/project/repo/PAT/clone all in place since 2026-05-21); **Phase 1** ⬜→✅ (all scaffolding committed in 2848f54); **Phase 2** ⬜→🔄 (Terraform code complete; manual `apply`/`destroy` smoke test still pending).
- `ROADMAP.md` — added **Phase 0.5 — ADO Operating Conventions** between Phase 0 and Phase 1. Covers Boards Epic→Feature→Story→Task hierarchy backfill, branch policies on `main`, PR template at `.azuredevops/pull_request_template.md`, Service Connections + Variable Group in the ADO Library, CODEOWNERS, and AB# linking enforcement. Driven by the upcoming customer demo to an ADO-fluent audience — needs to read as "mature dev team," not "one person pushing to main."
- `ROADMAP.md` — **Phase 5** now documents the current manual GitHub mirror workflow (`git push github main` after every push to ADO `origin`) and frames the auto-mirror pipeline stage as the enhancement that retires the manual step. Cross-links to the `github-ericcames` Service Connection added in Phase 0.5.
- `README.md` — rewrote "Getting started": removed the misleading "Bootstrap is not yet wired up" banner; framed `aap_config/load.yml` as the canonical install path (Phase 3, building) and de-emphasized `playbooks/bootstrap_aap.yml` as a deprecated stopgap; added the current manual GitHub mirror workflow as a documented step.

### Added
- `azure-pipelines.yml` (Phase 5) — ADO CI on `ubuntu-latest`: `yamllint`, `ansible-lint`, `terraform fmt -check -recursive`, `terraform validate -backend=false`. Refactored flat `steps:` into two stages: **Lint** (always runs) and **Mirror** (CI on `main` only, skipped during PR builds via `Build.Reason != 'PullRequest'`). Mirror stage pushes to `github.com/ericcames/dc1.azure` using the `GITHUB_PAT` secret pipeline variable; `trigger: [main]` enables post-merge CI. Service connection `github-ericcames` registered in ADO (GitHub PAT, `repo` scope) as the credential store. Previously omitted the auto-mirror stage pending a GitHub PAT.
- `.yamllint` + `.ansible-lint` (Phase 5) — codify the lint standard the pipeline enforces (replacing the informal "relaxed line-length warnings"). yamllint: line-length warning at 200, kept consistent with ansible-lint's embedded yamllint. ansible-lint: **`production`** profile, `offline` with mocked AAP/Azure modules so CI needs no Hub token. Both pass repo-wide as-is.
- `docs/INSTALL.md` (Phase 7) — manual install guide: prerequisites table, `ansible.cfg.example` → `~/.ansible.cfg` Hub setup, collection install, the full runtime env-var table, `aap_config/load.yml` run (self-verifies via `validate.yml`), post-install workflow launch, and a troubleshooting table. Calls out the execution-environment requirement and the Windows admin-password sync.
- `.claude/skills/install-dc1-azure/SKILL.md` (Phase 7) — repo-based Claude skill that drives the install interactively (checks prereqs, prompts for missing env vars **by name only** — never echoing secrets, runs `load.yml`, reports each created object). Ships via the `.gitignore` carve-out; replaces the marketplace `/aap-first-time` flow.
- `playbooks/provision_vm.yml` (Phase 4) — runs `terraform init/apply` (CLI + `output -json`) for the survey's `vm_size_tier`, parses the `ansible_inventory` Terraform output, and registers the new VM into the `dc1-azure` inventory's `windemo` group via the controller API (short-lived token created + deleted in `always:`, mirroring the `aap.dailydemo.windows` `inventory` role), then `set_stats` the public IP/FQDN for the workflow. Terraform auths via the Azure RM credential's `ARM_*` env; inventory registration via the new Controller credential's `CONTROLLER_*`; admin password passed via `TF_VAR_admin_password` (no_log).
- `playbooks/teardown.yml` (Phase 4) — `terraform destroy` plus deregistration of the host from the `dc1-azure` inventory (token lifecycle in `always:`).
- `aap_config/` — canonical AAP Configuration-as-Code scaffold (Phase 3), applied via `infra.aap_configuration.dispatch`: `load.yml` (entry point) + `validate.yml` (post-load API verification so it never exits green on a partial apply); `requirements.yml` (pins 4.4.0); `inventory/aap.yml` (localhost); `group_vars/all.yml` (connection + env-var secret refs + object names; vault password from the dc1.azure-owned `DC1_AZURE_VAULT_PASSWORD`, not the borrowed `secrets2`); and `files/controller_{credentials,projects,inventories,job_templates,workflow_job_templates}.yml` (each named after the role it feeds). Defines 4 credentials, 2 projects (`DC1.Azure` from ADO + reused `aap.dailydemo.windows` pinned to v1.0.1), the `dc1-azure` inventory, 6 JTs, and the single `DC1.Azure - Provision and Configure` workflow that all four triggers launch. The Configure JTs reuse the pinned Windows project's proven playbooks (retains the upstream workflow); Provision/Teardown playbooks land in Phase 4. Includes `aap_config/README.md`.
- `ansible.cfg.example` at repo root — committed template (never auto-loaded, so it can't shadow the home cfg) encoding the canonical Automation Hub `galaxy_server` stanza. The Phase 7 setup skill copies it to the user's standard local path. Supports the standalone-setup / repo-based-skill direction.
- `.azuredevops/pull_request_template.md` — ADO-auto-applied PR template with sections for Summary, Work item (AB# autolink field), Test plan, and Risk / rollback, plus a CONTRIBUTING-aligned checklist. Satisfies Phase 0.5 ⬜ PR-template item.
- `CODEOWNERS` at repo root — path → owner mapping for `/terraform/`, `/playbooks/`, `/aap_config/`, `/.azuredevops/`, and governance docs. Catch-all `*` falls back to @ericcames. File works AS-IS on the GitHub mirror; on ADO the same mapping must be re-entered into the "Automatically include code reviewers" branch policy (canonical mapping lives in `docs/ado-conventions.md`). Satisfies Phase 0.5 ⬜ CODEOWNERS item.
- `docs/ado-conventions.md` — single-page reference for the ADO operating model: Boards Epic→Feature→Story→Task hierarchy + area/iteration paths + tags, branch-policy table, reviewers-by-path mapping, PR template section guide, AB# autolink mechanics, Service Connections (`dc1-azure-rhdp-sp`, `github-ericcames`), Variable Group (`dc1-azure-shared`), and Wiki landing page. Acts as the customer-facing audit reference for Phase 0.5. Satisfies Phase 0.5 ⬜ ado-conventions.md item.
- `playbooks/bootstrap_aap.yml` — DEPRECATED banner at top of file explaining (a) why it still exists today, (b) when it will be removed, and (c) that new AAP objects belong in `aap_config/files/controller_*.yml`, not here. Satisfies the Phase 3 ⬜ "Add deprecation banner" item.

### Changed
- `CONTRIBUTING.md` — clarified step 4 (work-item reference) to point at the new `.azuredevops/pull_request_template.md` AB# field; clarified step 5 to note that direct-push blocking on `main` is a Phase 0.5 branch-policy item, not yet enforced; added a dedicated **`AB#<id>` autolink syntax** section explaining how ADO renders the shorthand and pointing at `docs/ado-conventions.md` for the full operating model. Satisfies Phase 0.5 ⬜ "Document AB# autolink syntax in CONTRIBUTING.md" item.
- `ROADMAP.md` — marked four Phase 0.5 items ✅: PR template, CONTRIBUTING AB# documentation, CODEOWNERS, and the `docs/ado-conventions.md` reference. The remaining ⬜ items in Phase 0.5 require ADO web UI / `az devops` CLI work (Boards backfill, branch policies, Service Connections, Variable Group).
- `ROADMAP.md` — Phase 0.5 advanced from ⬜ to 🔄. Chunk B (ADO UI / `az devops` CLI work) executed via the CLI: 10 Epics, 13 Features, 11 Stories backfilled with full Epic→Feature→Story parentage and `phase-N` + topic tags; iterations renamed `Sprint 1/2/3` with rolling 2-week date ranges starting 2026-05-21; Azure RM Service Connection `dc1-azure-rhdp-sp` created from RHDP SP (id `<rhdp-sp-app-id>`); Variable Group `dc1-azure-shared` (4 vars, authorized for all pipelines); project Wiki `dc1.azure.wiki` with `/Home` landing page; project description set on ADO landing page; four blocking branch policies on `main` (reviewers, work-item linking, comment resolution, squash-only merge — build validation policy deferred to Phase 5). Remaining ⬜ items intentionally deferred (GitHub SC → Phase 5, build validation → Phase 5, auto-include reviewers → when a teammate joins).
- `ROADMAP.md` — **Phase 2 advanced from 🔄 to ✅.** Manual smoke test passed against RHDP env (`<rhdp-resource-group>`, `eastus`) on 2026-05-21 with `vm_size_tier=small`. Three real Phase 2 design bugs found + fixed during the test (see `### Fixed` above). Apply produced a reachable Windows Server 2025 VM at `<vm-public-ip>`; WinRM-HTTPS port 5986 verified open + TLS handshake succeeds + WinRM listener responds with HTTP 405 to a GET on `/wsman`; `terraform destroy` cleaned all 9 resources. Storage-backend bootstrap remains as a separate follow-up (local state used for this smoke test per the documented escape hatch in `backend.tf`).
- `ROADMAP.md` — restructured **Phase 3** to adopt `url_checker`-style self-contained `aap_config/` directory pattern (chosen over `aap.as.code`'s `playbooks/files/config_as_code/` for new-user discoverability and parity with the upstream `infra.aap_configuration` recommended layout). Marks `playbooks/bootstrap_aap.yml` as transitional pending the `aap_config/load.yml` replacement.
- `ROADMAP.md` — added **Phase 7** (Install Documentation) covering two install paths: `docs/INSTALL.md` for manual install, `.claude/skills/install-dc1-azure/` Claude Code skill for AI-driven install.
- `ROADMAP.md` — added **Phase 8** (ServiceNow Integration) covering the v2 demo flow: SNow self-service catalog → AAP workflow → AAP→SNow RITM callback. Instance = Red Hat shared SNow dev (URL TBD).
- `ROADMAP.md` — renamed Phase 6 to "Demo Runbook (v1 — AAP-driven)" to distinguish from the Phase 8 v2 SNow-driven flow.
- `ROADMAP.md` — added 5 new Decisions Log entries covering CaC pattern, install paths, bootstrap deprecation, SNow instance, and the dc1.azure-as-canonical-Windows-on-Azure framing.
- `ROADMAP.md` — added 4 new Risks/Open Questions for Phase 3/4/8 (AAP token expiration, shared SNow availability, AAP→SNow callback time-outs, `aap.dailydemo.windows` role compatibility with Azure VMs).

### Added
- `playbooks/bootstrap_aap.yml` — Phase 3 bootstrap playbook: creates Vault credential, Azure RM credential (Service Principal), ADO Source Control credential (PAT), and the `DC1.Azure` project syncing from the ADO repo. Pattern mirrors `aap.as.code/playbooks/bootstrap_dev.yml`: `ansible.platform.token` for token lifecycle (created + deleted in `always:` block); `ansible.controller` modules for credential/project (no `ansible.platform` equivalents yet). **Marked transitional 2026-05-21 — will be replaced by `aap_config/load.yml` per restructured Phase 3.**
- `inventories/dc1-azure/hosts` — localhost-only inventory for the bootstrap playbook.
- `inventories/dc1-azure/group_vars/all.yml` — runtime variable resolution via env-var / file lookups. No secrets in version control.

### Changed
- `playbooks/bootstrap_aap.yml` — added `tags: ado` to the ADO PAT assertion, the ADO Source Control credential task, and the Project task so the playbook can run partial without an ADO PAT (`--skip-tags ado` creates just Vault + Azure RM credentials). Use case: bootstrap the Azure-side credentials before the ADO PAT is in place.
- Removed `playbooks/.gitkeep` and `inventories/dc1-azure/group_vars/.gitkeep` placeholders now that real files exist in those directories.

### Verified
- `DC1.Azure - Vault` and `DC1.Azure - Azure RM` credentials created in live RHDP AAP (`aap-aap.apps.<rhdp-cluster>.redhatworkshops.io`) via `--skip-tags ado` partial run on 2026-05-21. Azure RM credential confirmed via API: subscription/tenant/client fields all correct; client_secret encrypted at rest.

## 0.1.0 — 2026-05-21

### Added
- `ROADMAP.md` — DC1 Azure strategic roadmap: vision, architecture, 7 phases, naming conventions, decisions log, risks
- `README.md` — project overview, story, repo layout, getting-started outline
- `CLAUDE.md` — Claude-specific guidelines for working in this repo
- `CODE_OF_CONDUCT.md` — Contributor Covenant 2.0
- `CONTRIBUTING.md` — workflow, branch naming, commit messages, conventions; ADO Boards work items replace GitHub issues
- `LICENSE` — MIT
- `.gitignore` — Terraform state, Ansible collections, vault files, `.claude/`, OS cruft
- `galaxy.yml`, `meta/runtime.yml` — collection metadata
- `collections/requirements.yml` — pinned dependencies (`infra.aap_configuration` 4.2.0, `azure.azcollection`, `ansible.windows`, `community.windows`, plus `ansible.platform` / `ansible.controller` / `ansible.utils` / `ansible.posix` / `ansible.hub`)
- `terraform/` — Phase 2 Azure Terraform with placeholders: `providers.tf`, `backend.tf`, `variables.tf`, `locals.tf` (size-tier map), `main.tf` (VNet, Subnet, NSG, Public IP, NIC, Windows Server 2025 VM with WinRM bootstrap via `custom_data`), `outputs.tf`, `terraform.tfvars.example`
- Directory scaffolding: `playbooks/`, `inventories/dc1-azure/group_vars/`, `docs/images/` with `.gitkeep` placeholders

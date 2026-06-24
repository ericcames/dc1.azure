# IT Controls → ServiceNow Attestation (design + as-built record)

How the dc1.azure IT controls (`docs/controls.md`, CTL-001…005) map into
ServiceNow's **Policy and Compliance Management** (part of IRM/GRC) so that
auditors can pull evidence of compliance on demand — the design rationale, and
the record of what has since been built against it.

> **Start at the [GRC documentation index](servicenow-grc-README.md)** for the
> reading order and the control-coverage matrix.

> **Status: design realized.** The GRC module is **installed**
> (`sn_compliance` v22.0.2 on Yokohama, Demo Available entitlement; all target
> tables verified `HTTP 200`), and the design has been **built for CTL-005** —
> Control + automated Indicator ([`servicenow-grc-controls-build.md`](servicenow-grc-controls-build.md)),
> a human attestation lifecycle ([`servicenow-grc-auditor-walkthrough.md`](servicenow-grc-auditor-walkthrough.md)),
> and the auditor posture dashboard ([`servicenow-grc-dashboard.md`](servicenow-grc-dashboard.md)).
> The remaining controls are designed (§3) but not yet built; see the coverage
> matrix in the [index](servicenow-grc-README.md#whats-actually-built-control-coverage).
> This doc keeps the original design intact so the *why* travels with the *what*.

---

## 1. Purpose & audience

Auditors don't want a screenshot tour — they want **repeatable, timestamped,
tamper-evident proof** that each control is operating, ideally without a human
having to assemble it by hand. ServiceNow's compliance module exists to be that
single pane: each control has a **test**, the test produces a **result**, and the
result links to **evidence**.

The differentiator for this demo is the *source* of that evidence. Most GRC
programs lean on **manual attestation** — a control owner periodically answers a
survey ("yes, we patch nightly") and attaches a screenshot. We instead show
**automated, continuous attestation**: AAP automation already produces the
evidence as a side effect of doing the work (CMDB CI records, RITM/incident work
notes, AAP job history), and a ServiceNow **continuous-monitoring Indicator**
reads that evidence on a schedule to auto Pass/Fail the control. The auditor sees
a green control backed by machine-generated, timestamped records — and a
**Control Issue** is raised automatically the moment a control drifts.

**The key insight:** the evidence already exists today. GRC adds an *attestation
layer on top* of the dc1.azure integration — it does not require new
instrumentation in the playbooks.

---

## 2. Concept mapping — dc1.azure today → ServiceNow GRC

| dc1.azure artifact (exists today) | ServiceNow GRC construct | Notes |
|---|---|---|
| A `docs/controls.md` control statement (CTL-xxx) | **Control** (`sn_compliance_control`) | one Control record per CTL-xxx |
| The control's named *evidence location* | **Control Test Definition → Indicator** (`sn_grc_indicator`) | automated, scheduled, threshold-based |
| `snow_log` work notes (immutable `sys_journal_field`) | **Evidence** | already timestamped & append-only |
| CMDB CI + `task_ci` + `cmdb_rel_ci` | **Evidence** (queryable asset state) | already populated on every provision |
| AAP job / schedule history | **Evidence** (external, queried via AAP API/MCP) | proves automated enforcement ran |
| A control failing its check | **Control Issue** (`sn_grc_issue`) | auto-created when an indicator breaches threshold |
| (future) named framework, e.g. NIST/SOC 2 | **Authority Document → Citation** | out of scope this round — we stay internal CTL-xxx |

> **Table names verified** on Yokohama / `sn_compliance` 22.0.2 (2026-06-17):
> `sn_compliance_control`, `sn_compliance_policy`, `sn_grc_indicator`,
> `sn_grc_issue`, and `sn_grc_profile` all return `HTTP 200`. Note ServiceNow can
> rename GRC tables across releases (e.g. Smart Assessment Engine uses
> `sn_smart_asmt_instance`; the legacy survey table is `asmt_assessment_instance`)
> — re-confirm on a different release before building there.

GRC's full top-down hierarchy is *Authority Document → Citation → Control
Objective → Control → Control Test*. Because we're keeping the internal CTL-xxx
framing, we enter at the **Control** level and attach an automated **Control
Test** to each — skipping the framework-citation layers for now.

---

## 3. Per-control mapping (CTL-001…005)

Each control becomes one **Control** record with one **automated Indicator** as
its test. The indicator query targets evidence that dc1.azure *already writes*.

### CTL-001 — Dynatrace OneAgent on all provisioned infrastructure
- **Indicator:** % of in-scope server CIs whose originating RITM carries a
  OneAgent **audit-proof** work note (version + tenant + connected=yes).
- **Evidence source (exists):** `snow_log` posts the audit-proof note per host
  (see CTL-001 in `controls.md`); CIs created by `create_ci.yml`, linked via
  `task_ci`.
- **Pass threshold:** 100% of in-scope CIs.
- **Auditor sees:** green control + the exact per-host work notes (version,
  tenant, host group, connected) with timestamps.

### CTL-002 — Nightly teardown of non-production infrastructure
- **Indicator:** the teardown schedule ran within the last 24h and ended with
  zero live VMs.
- **Evidence source (exists):** AAP job history for
  `DC1.Azure - Nightly Teardown (6 PM / 10 PM)` — queried via the AAP API / MCP.
  CMDB corroborates: CIs `install_status` = Retired (7) after teardown (AB#170).
- **Pass threshold:** a successful teardown job in the trailing 24h.
- **Auditor sees:** green control + the schedule definition and the most recent
  zero-change destroy job log.

### CTL-003 — Credential lifecycle (no long-lived API tokens)
- **Indicator:** no stale CaC tokens on the AAP gateway token list (only the
  intentional ADO pipeline token persists).
- **Evidence source (exists):** AAP gateway token list (API/MCP); `load.yml` /
  `validate.yml` delete their token in `always:`.
- **Pass threshold:** zero unexpected long-lived tokens.
- **Auditor sees:** green control + the current token inventory.

### CTL-004 — Cross-system traceability (RITM ↔ AAP)
- **Indicator:** every recent provision RITM has **both** the forward link (AAP
  workflow job ID work note) and the reverse link (`snow_ritm_*` job artifact).
- **Evidence source (exists):** `notice_ritm_started.yml` (forward), EDA extra
  vars + `set_stats` (reverse), `update_ritm.yml` (outcome).
- **Pass threshold:** 100% of in-window provision RITMs linked both directions.
- **Auditor sees:** green control + a sample RITM with the AAP deep link and the
  job's `snow_ritm_number`/`snow_ritm_url` artifacts.

### CTL-005 — CMDB CI registration & business-app relationship
- **Indicator:** every provision RITM has a linked CI (`task_ci`) of the correct
  OS class **and** a `cmdb_rel_ci` relationship to the `Ansible Demonstrations`
  business application.
- **Evidence source (exists):** `create_ci.yml` (CI + `task_ci`),
  `create_cmdb_relationship.yml` (`cmdb_rel_ci`).
- **Pass threshold:** 100% of in-window provision RITMs fully registered.
- **Auditor sees:** green control + the CI record, its class, and the relationship.

---

## 4. Evidence-flow architecture (the closed loop)

```
   AAP provision / teardown workflow
            │  (already happens today)
            ▼
   ┌─────────────────────────────────────────────┐
   │  snow_log work notes  →  sys_journal_field    │  immutable, timestamped
   │  create_ci / rel_ci   →  CMDB CI + task_ci    │  queryable asset state
   │  AAP job + schedule history                   │  enforcement proof (API/MCP)
   └─────────────────────────────────────────────┘
            │
            │   GRC Indicator runs on a schedule, queries the above
            ▼
   Control Test result  ──►  Compliance dashboard / auditor view
            │
            └─ threshold breached ──►  Control Issue (sn_grc_issue) auto-created
```

The left box is **what dc1.azure already produces**. The arrow into GRC is the
only new part: scheduled Indicators that read existing records and roll them up
into a control posture. No changes to the provisioning playbooks are required for
the happy path; at most we'd add a queryable CI attribute if an indicator needs a
faster lookup than scanning work notes.

> **Built:** the *"Compliance dashboard / auditor view"* at the end of this flow
> now exists — a profile-scoped **DC1.Azure - GRC Posture** dashboard (control
> posture + attestation status). See
> [`servicenow-grc-dashboard.md`](servicenow-grc-dashboard.md).

---

## 5. Plugin dependency & how to detect it

Policy and Compliance Management / IRM is **separately licensed**. It was **absent
when this design was first written**, then installed the same day — the before /
after captured read-only on 2026-06-17:

| Probe | Before install | After install |
|---|---|---|
| `GET /api/now/table/sc_req_item` | HTTP 200 | HTTP 200 |
| `GET /api/now/table/sn_compliance_control` | HTTP 400 *"Invalid table"* | **HTTP 200** |
| `GET /api/now/table/sn_grc_indicator` | HTTP 400 | **HTTP 200** |
| `GET /api/now/table/sn_grc_issue` | HTTP 400 | **HTTP 200** |

**Repeatable detection** (use the established `servicenow.itsm.api_info` / curl
pattern from the `/servicenow` skill): probe `sn_compliance_control`. HTTP 200 ⇒
GRC present; HTTP 400 *"Invalid table"* ⇒ absent.

**Why it can't be turned on by automation:** installation is an admin action in
the ServiceNow **Store / Application Manager** (or a HI request), and the module
needs a paid entitlement (here, a *Demo Available* entitlement let us install
without a separate purchase). It cannot be installed via the Table API. Full
step-by-step walkthrough: [`servicenow-grc-setup.md`](servicenow-grc-setup.md).

> GRC apps are Store-delivered scoped applications, so they do **not** appear in
> the classic `sys_plugins` table — don't use that as a presence check; probe a
> table instead.

---

## 6. Building it (real GRC)

GRC is installed on this instance, so we build against the real module — the
authentic auditor story, no approximations.

1. Confirm IRM / Policy & Compliance entitlement (or move the demo to an instance
   that ships GRC). A step-by-step, screenshot-driven install walkthrough is in
   [`servicenow-grc-setup.md`](servicenow-grc-setup.md).
2. Build per [§3](#3-per-control-mapping-ctl-001005): create the Control records,
   define the Indicators against the existing evidence queries, schedule them, and
   wire Control Issues on breach. **The CTL-005 working slice is built** —
   idempotent playbook (`playbooks/servicenow/create_grc_controls.yml`) +
   reproduction guide with the data model and gotchas:
   [`servicenow-grc-controls-build.md`](servicenow-grc-controls-build.md).
3. Take the human attestation and walk the control lifecycle
   ([`servicenow-grc-auditor-walkthrough.md`](servicenow-grc-auditor-walkthrough.md)),
   then surface it on the posture dashboard
   ([`servicenow-grc-dashboard.md`](servicenow-grc-dashboard.md)).

> **No licensed module?** An instance without GRC could only *approximate* this
> (custom tables, or a Performance Analytics report over the existing RITM/CMDB
> data) — clearly labelled as the *concept*, not real GRC. Out of scope here: the
> instance ships the module, so we build the genuine article.

---

## 7. Remaining work

Delivered as ADO Phase 23 (Epic "GRC — Continuous Attestation & Auditor
Dashboard", AB#178–182): the GRC install, the **CTL-005** Control + Indicator +
attestation, and the posture dashboard. Still open:
- Build the **CTL-001** and **CTL-004** Indicators (ServiceNow-native — give them
  a `criteria` over the RITM evidence, same pattern as CTL-005).
- For **CTL-002 / CTL-003**, push an AAP signal into a readable ServiceNow table
  first, then read it with a basic Indicator (their evidence lives in AAP).
- Schedule the indicator collection job (align cadence with provision/teardown)
  and wire **Control Issue** auto-creation on breach + assignment group.
- (Optional) add a queryable CI attribute (e.g. `oneagent_audit_ok`) if scanning
  work notes per CI proves too slow at the indicator level.
- (Later) map CTL-xxx to a named framework (NIST 800-53 / SOC 2 / CIS) via
  Authority Document → Citation, for an externally-recognizable audit story.

---

## Related

- [`controls.md`](controls.md) — the 5 control statements + evidence locations (source of truth)
- [`servicenow-integration.md`](servicenow-integration.md) — the AAP ↔ ServiceNow integration this builds on
- [`snow-log.md`](snow-log.md) — the immutable work-note evidence mechanism
- `/servicenow` skill — REST/table API patterns, CMDB lifecycle, journal querying

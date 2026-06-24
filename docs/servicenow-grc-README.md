# GRC on dc1.azure — documentation index

The dc1.azure demo turns the automation it already runs into **continuous,
audit-ready compliance evidence** in ServiceNow Policy & Compliance Management
(GRC). AAP provisioning produces the evidence as a side effect of doing the work
(CMDB CIs, RITM work notes, job history); a ServiceNow **Indicator** reads that
evidence on a schedule and auto Pass/Fails a **Control**; an auditor **attests**
the control; and a **posture dashboard** shows it all at a glance.

This is the entry point. Read the docs in this order:

| # | Doc | What it covers | Audience |
|---|-----|----------------|----------|
| 1 | [`controls.md`](controls.md) | The 5 IT control statements (CTL-001…005) + their technical enforcement and evidence locations — the source of truth | Everyone |
| 2 | [`controls-attestation-servicenow.md`](controls-attestation-servicenow.md) | Design: how the controls map onto ServiceNow GRC, the evidence-flow architecture, and the as-built record | Architects |
| 3 | [`servicenow-grc-setup.md`](servicenow-grc-setup.md) | Installing the GRC (`sn_compliance`) module — entitlement, install, verify | ServiceNow admins |
| 4 | [`servicenow-grc-controls-build.md`](servicenow-grc-controls-build.md) | Building a Control + automated Indicator (the CTL-005 slice) — playbook + manual step + gotchas | SEs / automation |
| 5 | [`servicenow-grc-auditor-walkthrough.md`](servicenow-grc-auditor-walkthrough.md) | Taking an attestation and walking the Draft→Attest→Review→Monitor lifecycle | Auditors / control owners |
| 6 | [`servicenow-grc-dashboard.md`](servicenow-grc-dashboard.md) | Assembling the profile-scoped **DC1.Azure - GRC Posture** dashboard | Admins / demo |

## What's actually built (control coverage)

The CTL-005 slice is built and live-validated end to end. The other controls
are designed with a known indicator recipe but not yet built as GRC objects.

| Control | What it asserts | GRC construct | Status |
|---------|-----------------|---------------|--------|
| **CTL-005** | Every server is a CMDB CI linked to its business app | Control + automated Indicator + attestation + dashboard | ✅ **Built & live-validated** |
| **CTL-001** | Dynatrace OneAgent on all provisioned infra | ServiceNow-native — indicator over RITM audit-proof work notes | ⬜ Designed, recipe ready |
| **CTL-004** | RITM ↔ AAP cross-system traceability | ServiceNow-native — indicator over RITM forward/reverse links | ⬜ Designed, recipe ready |
| **CTL-002** | Nightly teardown of non-prod infra | Evidence lives in AAP — needs an AAP→ServiceNow push first | ⬜ Design only |
| **CTL-003** | No long-lived API tokens | Evidence lives in AAP — needs an AAP→ServiceNow push first | ⬜ Design only |

Extending to the next control is documented at the end of
[`servicenow-grc-controls-build.md`](servicenow-grc-controls-build.md#extending-to-the-other-controls).

## Build artifacts

- **Playbook:** `playbooks/servicenow/create_grc_controls.yml` (+ `grc_control_tasks.yml`)
  — idempotent build of the Profile, Control Objective, Control, and Indicator.
- **Environment captured on:** Now Platform **Yokohama**, GRC: Policy and
  Compliance Management `sn_compliance` **22.0.2** (Demo Available entitlement).
  GRC table names/behaviour shift across releases — re-verify on yours.

> **Captured-on / version notes** live in each doc's header. ServiceNow renames
> GRC tables across releases; the *concepts* (control → indicator → result →
> issue; attest → review → monitor) are stable.

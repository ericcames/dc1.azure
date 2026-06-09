# Demo Talk Track: Automated Incident Response

*For the DC1.Azure EDA Incident Response demo (Phase 19 / AB#154).
Use this to frame the demo for CIOs, IT directors, ops managers, and anyone
who needs to understand **why** — not just what.*

---

## The Story in 30 Seconds

A web server went down. Nobody called. Nobody paged. Nobody opened a ticket.
Nobody logged in to check. Nobody restarted anything. Nobody wrote up what
happened.

And yet — five minutes later, the service was back up, the incident ticket
told the complete story from detection to resolution, and the monitoring
system independently confirmed the fix worked.

**Zero human intervention. Full audit trail. Complete closed loop.**

---

## What Happened, Step by Step

1. **Dynatrace detected the failure.** Its AI engine (Davis) continuously
   monitors every process on every server. When the web server process
   stopped, Davis opened a problem within two minutes — not because we told
   it to check, but because it's always watching.

2. **Event-Driven Ansible received the alert and made a decision.** Is this
   expected maintenance? It checked ServiceNow for open change tickets
   linked to that server. There were none — so this is an unplanned outage.
   It created an incident ticket automatically.

3. **Ansible Automation Platform restored the service.** It restarted the
   web server, verified the website was back (HTTP 200), and then gathered
   forensic evidence: who was logged in, what stopped the service, disk
   usage, recent system changes, and application logs. All of it posted to
   the incident ticket in real time — as it happened, not after the fact.

4. **Ansible queried Dynatrace for the AI root cause analysis.** Davis AI
   determines what actually caused the problem — which entity, what
   evidence, what was impacted. That root cause analysis was posted to the
   ticket alongside the local forensics.

5. **Dynatrace independently confirmed the recovery.** A few minutes later,
   Davis AI verified the process was healthy again and sent a second event
   back to Ansible. A confirmation work note was posted to the ticket:
   *"Dynatrace has confirmed the problem is resolved."*

The ticket tells the entire story. An auditor, a manager, or a post-incident
reviewer can read it top to bottom and know exactly what happened — without
asking anyone.

---

## Why Should People Care?

### Mean Time to Restore drops from hours to minutes

In most organizations, a web server going down at 2 AM means: a monitoring
alert fires, someone gets paged, they wake up, VPN in, figure out which
server, SSH in, check logs, restart the service, verify it's back, write up
what happened, and update the ticket. That's 30-60 minutes if you're lucky —
and that's for a *simple* service restart.

Here, it took five minutes with zero human involvement.

### The on-call engineer sleeps through the night

The service is restored before anyone even sees the alert. The humans review
the completed ticket in the morning — the forensic evidence is already there.
The on-call team shifts from *reactive firefighting* to *morning review*.

### Root cause analysis happens automatically

The two hardest questions after any outage are *"What happened?"* and *"Who
did it?"* Both are answered in the ticket:

- **Dynatrace Davis AI** identifies the root cause entity — which process,
  which component, what evidence led to that conclusion.
- **Local forensics** show exactly which user account or automation process
  stopped the service, who was logged in at the time, and what changed on
  the system recently.

No more "we don't know what happened" post-mortems.

### The monitoring system confirms the fix — not the person who applied it

This is critical for audit and compliance. The fix isn't marked "done" just
because the automation says it restarted the service. An **independent
system** (Dynatrace) verifies recovery and posts that confirmation to the
ticket.

That's the closed loop: **Detect, Remediate, Confirm.** Three independent
systems (Dynatrace, Ansible, ServiceNow) all agree the problem is fixed.

### Every action is auditable

The ServiceNow incident has timestamped work notes from every step:

| Timestamp | What happened |
|-----------|---------------|
| 12:15:21 | Incident created — remediation in progress |
| 12:15:23 | Davis AI narrative posted (what Dynatrace detected) |
| 12:15:40 | Remediation started on the affected host |
| 12:15:47 | Service restored, website verified (HTTP 200) |
| 12:15:55 | Local forensics: who stopped the service, system state, logs |
| 12:16:11 | Dynatrace root cause analysis posted |
| 12:16:13 | Executive summary with links to Dynatrace and AAP |
| 12:17:39 | Dynatrace confirmation: problem resolved |

This is the kind of documentation that organizations spend hours producing
manually after an incident — and here it's generated automatically, in real
time, as the work happens.

### It scales without adding headcount

This isn't a script for one server. The same workflow handles Linux (Apache)
and Windows (IIS), any server monitored by Dynatrace. Add 100 servers, and
the automation handles all of them the same way. The humans focus on problems
that actually need human judgment — architecture decisions, capacity
planning, customer communication — not restarting a crashed web server at
2 AM.

### It knows when NOT to act

If there's an open change ticket on that server — someone is doing planned
maintenance — the system recognizes it and doesn't create an incident. It
logs the correlation to the change ticket instead: *"Dynatrace detected a
problem on this server. An active change ticket exists — this may be expected
maintenance. No incident created."*

That's the difference between automation and a script. It understands
context.

---

## The Architecture (for the Technically Curious)

```
Dynatrace                 Event-Driven Ansible           ServiceNow
    |                            |                           |
    | Davis AI detects           |                           |
    | process failure            |                           |
    |   (~2 min)                 |                           |
    |                            |                           |
    |--- problem event --------->|                           |
    |    (push, not poll)        |                           |
    |                            | Check: is there an        |
    |                            | open change ticket? ----->|
    |                            |                    <------|
    |                            | No change found.          |
    |                            | Create incident --------->|
    |                            |                           | INC created
    |                            |                           |
    |                            | Restart service           |
    |                            | Verify HTTP 200           |
    |                            | Gather forensics          |
    |                            | Post to incident -------->|
    |                            |                           | Work notes
    |                            |                           |
    |                            | Query DT Problems API     |
    |<-- root cause analysis ----|                           |
    |                            | Post RCA to incident ---->|
    |                            |                           | RCA + links
    |                            | Resolve incident -------->|
    |                            |                           | Resolved
    |                            |                           |
    | Davis AI confirms          |                           |
    | problem cleared            |                           |
    |   (~2-5 min later)         |                           |
    |                            |                           |
    |--- closed event ---------> |                           |
    |                            | Post confirmation ------->|
    |                            |                           | Confirmed
    |                            |                           |
    ====== CLOSED LOOP: Detect -> Remediate -> Confirm ======
```

**Key design choice: push, not poll.** Dynatrace pushes events to Ansible
the moment they happen. Ansible doesn't poll Dynatrace every N seconds
asking "anything wrong?" This means detection-to-action is measured in
seconds, not polling intervals.

---

## The Bottom Line

*"We built a system where the monitoring tool, the automation platform, and
the ticketing system work together without human intervention. When a service
fails, it's detected in under two minutes, restored in under five, and the
incident ticket documents everything — the root cause, the forensics, and an
independent confirmation that the fix worked. Our on-call team reviews the
completed ticket instead of being woken up to do the work."*

---

## Common Questions

**Q: What if the automated fix doesn't work?**
A: The workflow verifies the fix (HTTP 200 check). If the service doesn't
come back, the incident stays open with all the forensic data already
collected — the on-call engineer starts with evidence, not from scratch.

**Q: What about more complex failures?**
A: This handles the high-volume, low-complexity incidents — the ones that
wake people up at 2 AM for a service restart. Complex failures (data
corruption, cascading outages, capacity exhaustion) still need human
judgment. The point is to free those humans from the simple ones.

**Q: How do we know the automation won't make things worse?**
A: Three safeguards: (1) It checks for active change tickets before acting —
if maintenance is in progress, it stands down. (2) It verifies the fix
worked before marking it resolved. (3) Dynatrace independently confirms
recovery — if the fix didn't hold, Davis would open a new problem.

**Q: What does this cost?**
A: The components are Red Hat Ansible Automation Platform (automation),
Dynatrace (monitoring), and ServiceNow (ticketing) — all enterprise tools
most large organizations already own. The integration is configuration, not
custom code. The real cost savings come from reduced MTTR and fewer 2 AM
pages.

**Q: Can we extend this to other services?**
A: Yes. The workflow is service-agnostic — it handles any process Dynatrace
monitors. Adding a new service means adding a Dynatrace monitoring rule and
a remediation playbook. The triage logic (CMDB lookup, change ticket check,
incident creation) is reusable as-is.

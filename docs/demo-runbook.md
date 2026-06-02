# DC1.Azure — Demo Runbook (v1, AAP-driven)

The Solutions-Engineer script for running the **DC1.Azure Windows-on-Azure**
demo straight from the **AAP web UI**. The goal: a customer watches Ansible
Automation Platform stand up a real Windows Server 2025 VM in Azure, configure
it, and serve a live web page — in about ten minutes, from a single survey
click.

> **This is the v1 (AAP-driven) flow.** The same workflow is later surfaced
> through the AAP Self-Service Portal (Phase 9), ServiceNow (Phase 8), and Azure
> DevOps (Phase 10). Those triggers reuse the *exact* workflow documented here —
> only the front door changes. See [`ROADMAP.md`](../ROADMAP.md).

---

## At a glance

| | |
|---|---|
| **Front door** | AAP web UI → Templates → *DC1.Azure - Provision and Configure* |
| **One input** | `vm_size_tier` survey: `small-2cpu-8gb` / `medium-4cpu-16gb` / `large-8cpu-32gb` |
| **Run time** | ~10 min provision + configure (Provision VM dominates at ~7 min) |
| **Payoff** | Browse `http://<vm-fqdn>` → live IIS page on Windows Server 2025; optional RDP |
| **Cleanup** | Auto-destroys nightly at **18:00 America/Phoenix (01:00 UTC)**; or run *DC1.Azure - Teardown* manually |
| **Cost guardrail** | The nightly teardown means a forgotten VM costs at most one evening |

**Observed timings (live workflow job 60, `medium-4cpu-16gb`):**

| Node | Typical | What's happening |
|------|---------|------------------|
| Provision VM | ~7 min | `terraform apply` builds VNet/NSG/public IP/VM, then registers the host into the `dc1-azure` inventory |
| Powershell Improvement | <1 min | Installs PowerShell 7 |
| Website Setup | ~2 min | Installs IIS + deploys the Azure demo landing page |
| Provision Access | <1 min | Creates the demo Windows account |
| Patching | ~1 min | Applies Windows Updates |
| **Total** | **~10 min** | end-to-end, green |

---

## Personas

- **You (the SE / platform engineer)** — narrate the platform's value while it
  works. You drive the AAP UI.
- **The customer's app developer / requester** — the person who, in the
  end-state demo, would self-serve a VM. In v1 you *speak as if* you are them
  ("I need a Windows box, medium size, now"), then show the platform deliver it.
- **The customer's platform/ops team** — the audience who cares that this is
  governed, repeatable, and self-cleaning (one workflow, one survey, audited
  jobs, nightly teardown).

---

## 1. Pre-flight checklist (do this before the customer is watching)

Run through this 15–20 minutes ahead. Most failures are environmental, not
demo-logic.

- [ ] **RHDP Azure open env is alive** — not expired. Confirm the resource
      group still exists and the Service Principal still authenticates.
- [ ] **AAP is reachable** — log into the AAP UI in a browser tab and leave it
      open. (URL + creds live in your gitignored `docs/dev-environment.sh`.)
- [ ] **The DC1.Azure project is synced to the latest `main`** — Projects →
      *DC1.Azure* → sync. The project no longer auto-syncs on launch (AB#74, for
      speed), so a manual sync after any code change is on you. API shortcut:
      `POST /api/controller/v2/projects/21/update/`.
- [ ] **`dc1-azure` inventory is empty (0 hosts)** — a leftover host from a prior
      run is cosmetic but looks sloppy on screen. If the nightly teardown ran,
      it's already clean.
- [ ] **Azure quota headroom** — `medium-4cpu-16gb` (4 vCPU) is the safe default.
      Only pick `large-8cpu-32gb` (8 vCPU) if you've confirmed the RHDP
      subscription's regional vCPU quota allows it.
- [ ] **Nightly teardown schedule is enabled** — Schedules → *DC1.Azure -
      Nightly Teardown*, next run 18:00 America/Phoenix. (Leave it on — it's part
      of the story.)
- [ ] **Decide your tier** up front so you're not hesitating on the survey.

The AAP **Automation Templates** list filtered to `DC1` — every DC1.Azure job
template plus the *DC1.Azure - Provision and Configure* workflow:

![AAP Automation Templates list filtered to the DC1.Azure objects](images/demo-00-templates.png)

---

## 2. Set the scene (≈60 seconds of talking before you click)

> "Say I'm an application developer and I need a Windows server in Azure —
> today, not next week. Traditionally that's a ticket, a wait, a hand-off
> between teams. With Ansible Automation Platform, the platform team has turned
> that whole process into **one self-service action**. I pick a size, I click
> launch, and the platform does the rest — provision the cloud infrastructure,
> harden and configure the OS, stand up the app, and even clean itself up
> overnight so we're not paying for idle VMs."

Key points to land:
- **One workflow, many front doors.** Today I'm in the AAP UI; the same workflow
  is exposed via Self-Service, ServiceNow, and Azure DevOps — identical result.
- **Infrastructure *and* configuration.** Terraform builds the Azure resources;
  Ansible configures the OS. One platform orchestrates both.
- **Governed and repeatable.** Every run is an audited job. Same inputs → same
  result, every time.

---

## 3. Run it — click-by-click (AAP web UI)

### 3.1 Log in
Open the AAP UI. You should already be authenticated from pre-flight.

### 3.2 Open the workflow template
Left nav → **Automation Execution → Templates**. Find
**`DC1.Azure - Provision and Configure`** (type: *Workflow Job Template*).

The **Workflow Visualizer** for *DC1.Azure - Provision and Configure* (11 nodes).
The graph is wide, so it's shown in panned sections, left → right:

![Workflow topology (left) — Start fans out to provision-vm and the ritm-start-notice branch; Provision VM's Run-on-success / Run-on-fail edges drive the configure and incident paths](images/demo-01-workflow-template-1.png)

![Workflow topology (middle) — powershell-improvement → website-setup / provision-access, the CMDB branch (create-cmdb-ci → relationship), and the failure path (create-incident → update-ritm-failure)](images/demo-01-workflow-template-2.png)

![Workflow topology (right) — the configure branches converge on patching, then Run-always → update-ritm-success](images/demo-01-workflow-template-3.png)

### 3.3 Launch and answer the survey
Click **Launch**. A single-question survey appears:

- **VM size tier** — choose your pre-decided tier. Default is
  `medium-4cpu-16gb`. Narrate: *"This is the only decision the requester
  makes — t-shirt sizing, no Azure SKU knowledge required."*

Submit the survey to start the run.

The **`vm_size_tier` survey** — the three t-shirt tiers (small / medium / large,
all Dsv5), with `medium-4cpu-16gb` as the default:

![AAP vm_size_tier survey question — small/medium/large tiers, medium default](images/demo-02-survey.png)

### 3.4 Watch the workflow graph
The workflow visualizer shows the run unfold left-to-right. Narrate these five
**configure** nodes as they go green — on an AAP-UI launch the other (ServiceNow
callback) nodes in the 11-node graph also run but no-op without a ticket (see §7):

| # | Node | What to say |
|---|------|-------------|
| 1 | **Provision VM** | "Terraform is building the Azure footprint — virtual network, security group, public IP with a DNS name, and the Windows Server 2025 VM at the size I picked. When it finishes, the platform registers the new host into its own inventory so the next steps can reach it." *(This is the long one — ~7 min. Good moment for Q&A or to talk architecture.)* |
| 2 | **Powershell Improvement** | "Now we're configuring the OS — installing PowerShell 7, a modern shell for whatever the app team runs next." |
| 3 | **Website Setup** | "Installing IIS and deploying a demo web app — so we end on something the customer can actually see in a browser." |
| 4 | **Provision Access** | "Creating the demo user account — access provisioning is part of the same automated flow, not a separate ticket." |
| 5 | **Patching** | "Applying Windows Updates. The VM is born already patched — no drift, no manual hardening step." |

The **Jobs list** after a clean run — the *DC1.Azure - Provision and Configure*
workflow job and every child playbook (Provision VM, Powershell Improvement,
Website Setup, Provision Access, Patching, the CMDB + RITM callbacks) all
**Success**:

![AAP Jobs list — the DC1.Azure workflow job and all child jobs Success](images/demo-03-workflow-success.png)

---

## 4. The payoff — show the running machine

### 4.1 Get the VM's address
The DNS name follows the pattern:

```
dc1az-<tier>-<random>.<region>.cloudapp.azure.com
```

e.g. `dc1az-medium-4cpu-16gb-z8crz.eastus.cloudapp.azure.com`. Get the exact
value from either:
- the **Provision VM** job output (the `fqdn` / `ansible_inventory` Terraform
  output), or
- the host's name in the **`dc1-azure` inventory** (Inventories → *dc1-azure* →
  Hosts), or
- the Azure portal (public IP resource).

### 4.2 Browse to it
Open `http://<vm-fqdn>` in a browser. The IIS landing page shows:

- A welcome header and the AAP logo
- **"This website is running on Microsoft Windows Server 2025 Datacenter on Azure"**
- A **Provisioning Details** panel: Request Number, Server DNS Name, Azure
  Region, VM Size, Platform
- A red note: *"The DC1.Azure Windows Demo will auto destruct at 01:00 hrs UTC time."*

Narrate: *"This page is served by the VM the platform just built and
configured. Everything you see — the OS, IIS, this app, the patch level — was
done by that one workflow, from one survey click."*

> **Note:** the **Request Number** field shows `N/A` in v1 — it's wired to the
> ServiceNow RITM number, which arrives with the Phase 8 ServiceNow integration.
> That's expected; don't apologize for it.

The live **IIS landing page** the workflow stands up, served from the Windows VM
itself (the address bar shows the VM's FQDN):

![Live IIS landing page (top) — AAP Windows Demo banner, running on Windows Server 2025 on Azure](images/demo-04-landing-page-1.png)

…and the **Provisioning Details** lower on the page. Note the **Request Number**
is populated here (`RITM0011939`) because this run was triggered from ServiceNow
(Phase 8) — a v1 AAP-UI launch shows `N/A` (see the note above):

![Live IIS landing page (lower) — QR code, red.ht link, and Provisioning Details: RITM number, DNS name, region, VM size, auto-destruct notice](images/demo-04-landing-page-2.png)

### 4.3 (Optional) RDP in
If the room wants to see a real desktop: RDP to the same FQDN as
**`demoadmin`** (the admin password is the one you set via
`WINDOWS_ADMIN_PASSWORD` at install). Show PowerShell 7 and the demo account to
prove the configuration steps landed.

---

## 5. Teardown — the self-cleaning story

This is a selling point, not an afterthought — say it out loud.

- **Automatic:** the **`DC1.Azure - Nightly Teardown`** schedule runs the
  *DC1.Azure - Teardown* job template every night at **18:00 America/Phoenix
  (01:00 UTC)** — exactly the time the landing page advertises. It runs
  `terraform destroy` and deregisters the host, returning the `dc1-azure`
  inventory to zero. *"A VM someone forgets about costs at most one evening."*
- **Manual:** to tear down on demand (e.g. right after the demo), launch
  **Templates → `DC1.Azure - Teardown`**. No survey, no inputs — it reads the
  Terraform state and destroys what's there. ~7 minutes.

> The Teardown JT deliberately runs against a small **`dc1-azure-control`**
> inventory (not `dc1-azure`) so it can deregister the VM's host without AAP
> locking it as "in use" (AB#73). You don't need to mention this on stage — it's
> just why teardown reliably goes green.

The **`dc1-azure` inventory empty** after the Teardown job — no leftover hosts,
proving the self-cleaning story (the *DC1.Azure - Teardown* job itself reports
*Success*):

![dc1-azure inventory empty after teardown — no hosts remain](images/demo-05-teardown-success.png)

---

## 6. Reset between back-to-back demos

If you're running the demo more than once in a day:

1. Run **`DC1.Azure - Teardown`** (or wait for the nightly).
2. Confirm **`dc1-azure`** is back to **0 hosts**.
3. Re-launch the workflow for the next audience.

There's no other state to clear — Terraform state lives in Azure Storage and is
reused; the next provision starts clean.

---

## 7. The ServiceNow-driven variant (Demo v2 — event-driven)

Same workflow, different front door: a business user requests the VM from the
**ServiceNow self-service catalog** and never touches AAP. This is the higher-value
story for an ITSM audience — *"your existing request process, now fulfilled by
automation, with the ticket and CMDB updated automatically."* Full design:
[`servicenow-integration.md`](servicenow-integration.md).

**How it flows**

```
ServiceNow catalog request  →  Business Rule → Outbound REST Message
   →  AAP EDA event stream  →  rulebook (matches short_description)
   →  DC1.Azure - Provision and Configure  (the same v1 workflow)
   →  Provision VM success → Create CMDB CI → Relationship (parallel, early)
      Patching always → Update RITM (Fulfilled, with FQDN/IP)
      failure: Create Incident → Update RITM (failed, cites the incident #)
```

The requester sees the RITM auto-fill with the VM's FQDN + public IP + admin
**username** (never the password) and the new CMDB CI appear — then closes the
ticket. No AAP login required.

**One-time setup (before the first ServiceNow demo)**

1. **Rebuild the EE.** PR2 added `servicenow.itsm` to the EE — rebuild + push
   `DC1.Azure - EE` and re-sync it in AAP (see `execution-environment.yml` build
   provenance). Without this the callback JTs fail to find the collection.
2. **Apply the CaC** — `load.yml` creates the `DC1.Azure - ServiceNow` credential,
   the five callback JTs, and the workflow nodes (and the Phase-8 EDA inbound
   objects). Confirm `validate.yml` is green and the rulebook activation is
   *running*.
3. **In ServiceNow** (one-time):
   - Catalog item **"Request Windows VM (Azure)"** whose **Short description** is
     exactly `DC1.Azure Windows VM on Azure` (the rulebook matches this string),
     with a `vm_size_tier` choice variable mirroring the survey.
   - A **Business Rule** on `sc_req_item` that fires an **Outbound REST Message**
     `POST`ing to the EDA **event-stream URL** with
     `Authorization: Bearer <EDA_EVENT_STREAM_TOKEN>` and a JSON body of
     `number`, `sys_id`, `short_description`, `vm_size_tier`.

**Smoke-test the trigger without ServiceNow** (proves the inbound half):

```bash
source docs/dev-environment.sh && \
curl -sk -X POST '<event-stream-url-from-AAP>' \
  -H "Authorization: Bearer $EDA_EVENT_STREAM_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"number":"RITM0099999","sys_id":"test","short_description":"DC1.Azure Windows VM on Azure","vm_size_tier":"medium-4cpu-16gb"}'
```

The workflow should launch within a few seconds (Automation Decisions → Rulebook
Activations → *DC1.Azure - Catch ServiceNow Events* shows the event; Templates
shows the new job).

**Running it live**

1. Open the ServiceNow catalog item, pick a size, submit.
2. Show the RITM moving as the workflow runs; narrate the same node story as §3.4.
3. Payoff: the RITM work note fills with the connection details and the **CMDB CI**
   appears with its relationship — *the ticket closed itself out with real data.*
4. **Failure demo (optional but powerful):** force a Provision VM failure (e.g.
   request `large` against exhausted quota) and show the **Incident** opening
   automatically with the job ID + error, and the RITM citing the incident number.

The **catalog item** the requester orders from — *DC1.Azure Windows VM on Azure*,
with the `vm_size_tier` choice:

![ServiceNow catalog item — DC1.Azure Windows VM on Azure with the vm_size_tier choices](images/demo-06-snow-catalog.png)

The auto-updated **RITM** — its *Configuration item* now linked to the new CMDB
CI (AB#93) and State *Closed Complete*, with the connection details posted as a
work note:

![ServiceNow RITM auto-updated by the workflow — Configuration item linked, Closed Complete](images/demo-07-snow-ritm.png)

The new **CMDB CI** (class *Windows Server*) with its *Uses → Ansible
Demonstrations* business-application relationship:

![ServiceNow CMDB CI created by the workflow, related to its business application](images/demo-08-snow-cmdb-ci.png)

> **Non-ServiceNow triggers stay green:** the callback JTs no-op when there's no
> `ticket_number`, so launching the *same* workflow from the AAP UI (§3),
> Self-Service Portal (Phase 9), or ADO (Phase 10) skips the ServiceNow nodes.

---

## Appendix A — Failure modes & recovery

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| **Provision VM fails fast at `terraform apply`**, error mentions quota/`SkuNotAvailable` | RHDP subscription is out of regional vCPU quota for the chosen tier | Re-launch with a smaller tier (`small-2cpu-8gb`); for the demo, default to `medium`. Don't pick `large` without confirming quota in pre-flight. |
| **Provision VM fails at auth / `terraform init`** | RHDP env expired, or Service Principal / storage-account backend creds stale | Re-activate the RHDP env; refresh values in `docs/dev-environment.sh`; re-apply `aap_config/load.yml` so the AAP credentials match. |
| **Workflow runs *old* playbook behavior after a code change** | Project didn't sync — update-on-launch is off (AB#74) | Manually sync the *DC1.Azure* project (Projects → sync, or `POST /api/controller/v2/projects/21/update/`) and re-launch. |
| **A configure node (Powershell/Website/Access/Patching) fails to connect** | WinRM not up yet, or the host didn't register into `dc1-azure` | Confirm the host appears in the `dc1-azure` inventory; give the VM a minute and **Retry** the failed node (the workflow supports node-level retry). If WinRM never comes up, tear down and re-provision. |
| **`load.yml` / any API step returns 401** | AAP token expired | Mint a fresh gateway token (the `/install-dc1-azure` skill or the token pattern in the project notes) and re-run. The stored token in `dev-environment.sh` is not long-lived. |
| **Teardown reports failed but the VM is gone** | Pre-fix behavior (AB#71/72/73) | Should not recur — all three are fixed and live-validated (job 68 green, inventory cleared). If it does, delete the orphan host from `dc1-azure` via the API and file a work item. |
| **Landing page won't load** | NSG/port, IIS not finished, or DNS not yet propagated | Confirm the Website Setup node was green; try the public IP directly; give DNS a moment. Port 80 is opened by the NSG in Terraform. |

---

## Appendix B — Screenshots to capture

Capture these once on a clean run and commit them to `docs/images/` (committed,
not gitignored — so they render on GitHub for everyone). Then replace the
inline 📸 placeholders above with real `![alt](images/...)` embeds.

- [x] `demo-00-templates.png` — AAP Templates list showing the DC1.Azure objects — captured 2026-06-02 (no redaction needed)
- [x] `demo-01-workflow-template-{1,2,3}.png` — the *Provision and Configure* workflow visualizer (11-node graph, captured in three panned tiles) — 2026-06-02 (no redaction needed)
- [x] `demo-02-survey.png` — the `vm_size_tier` survey dialog — captured 2026-06-02 (no redaction needed)
- [x] `demo-03-workflow-success.png` — Jobs list, the workflow job + all child jobs Success — captured 2026-06-02 (no redaction needed)
- [x] `demo-04-landing-page-{1,2}.png` — the live IIS landing page in a browser (top + Provisioning Details) — captured 2026-06-02 (no redaction needed)
- [x] `demo-05-teardown-success.png` — successful teardown + empty inventory — captured 2026-06-02 (teardown job 119 Success; no redaction needed)
- [ ] *(optional)* the ADO Boards Phase 6 epic/board, for the "how this was built" aside
- [x] `demo-06-snow-catalog.png` — the ServiceNow "Request Windows VM (Azure)" catalog item *(Demo v2, §7)* — captured 2026-06-02 (no redaction needed)
- [x] `demo-07-snow-ritm.png` — the RITM auto-filled with FQDN/IP + Fulfilled state *(Demo v2)* — captured 2026-06-02 (RITM0011939; URL bar + public IP redacted)
- [x] `demo-08-snow-cmdb-ci.png` — the new CMDB CI with its business-app relationship *(Demo v2)* — captured 2026-06-02 (URL bar redacted)

---

## Appendix C — Quick reference

| Thing | Value |
|-------|-------|
| Workflow | `DC1.Azure - Provision and Configure` |
| Nodes (in order) | Provision VM → Powershell Improvement → Website Setup → Provision Access → Patching |
| ServiceNow nodes (Demo v2) | CMDB (parallel, early): Provision VM→Create CMDB CI→Create CMDB Relationship; success: Patching `always`→Update RITM (success); failure: Provision VM→Create Incident→Update RITM (failure) — all no-op without `ticket_number` |
| ServiceNow match string | catalog item Short description = `DC1.Azure Windows VM on Azure` |
| Survey variable | `vm_size_tier` ∈ {`small-2cpu-8gb`, `medium-4cpu-16gb`, `large-8cpu-32gb`} (default `medium`) |
| Provision JT | `DC1.Azure - Provision VM` |
| Teardown JT | `DC1.Azure - Teardown` (runs against `dc1-azure-control`) |
| Story inventory | `dc1-azure` (VM host registered at runtime) |
| Project | `DC1.Azure` (ADO `main`; manual sync, no update-on-launch) |
| VM FQDN pattern | `dc1az-<tier>-<suffix>.<region>.cloudapp.azure.com` |
| Default region | `eastus` |
| Admin user | `demoadmin` |
| Nightly teardown | 18:00 America/Phoenix = 01:00 UTC, daily |
| Sizing tiers | small=`Standard_D2s_v5`, medium=`Standard_D4s_v5`, large=`Standard_D8s_v5` |

See also: [`INSTALL.md`](INSTALL.md) (how to install the CaC),
[`ROADMAP.md`](../ROADMAP.md) (phases + decisions), [`README.md`](../README.md).

> **Optional deeper talking track — supply-chain / EE security.** For a
> security-minded audience, [`ee-security-remediation.md`](ee-security-remediation.md)
> tells how we inspected the EE's Quay security scan, remediated the inherited
> base-image CVEs at build time, and *deliberately deferred* one risky fix — a
> credible "we own our supply chain" story to layer on top of the provisioning demo.

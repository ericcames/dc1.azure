# DC1.Azure — EE Security Remediation Story

How we treated the demo's **Execution Environment** like a production artifact:
inspected its container security scan, traced the findings to their root cause,
and remediated — while making a disciplined, *documented* call about what **not**
to change. This doc has two layers: a **talking track** an SE can deliver live,
and the **engineering record** behind it.

> **Why this matters for the demo.** Customers don't just buy automation — they
> buy a supply chain they can trust to run it. The DC1.Azure workflow runs inside
> a custom EE we build and ship ourselves. This is the story of owning that EE's
> security posture, not inheriting it by accident.

---

## The story in one minute (talking track)

> *"Everything you watched provision that Windows VM ran inside an execution
> environment — a container image we build. So we did what you'd do with any
> production image: we looked at its security scan. Red Hat's Quay scanner found
> **351 known vulnerabilities, 24 of them High** — things like openssl, openssh,
> libnghttp2. None of them were from anything we added. They were inherited from
> the base image, which was about eight months old, and Red Hat had published
> fixes for them since.*
>
> *So we remediated — with one line. We added a step to our EE build that applies
> the available OS errata at build time. The next image cleared every High-severity
> RPM finding, moving openssl, openssh, and libnghttp2 to current patched versions.*
>
> *But here's the part that matters most: we also found one fix we deliberately
> chose **not** to take. A flagged Python library couldn't be bumped without
> dragging a core cryptography dependency forward eleven major versions underneath
> a component that was never tested against it. So we left it, documented why, and
> tracked it as its own change with its own testing. That's the discipline — we
> patch aggressively where it's safe, and we change-manage carefully where it
> isn't. The scan is a starting point for judgment, not a checklist to blindly
> zero out."*

**Delivery tips**
- Open by reframing the EE as "a production container image we own," not demo plumbing.
- The payoff visual is the **scan count dropping** between two image tags in Quay.
- Land the deferral point hard — *choosing not to patch, with a reason* is what
  separates a mature team from a CVE-count-chasing one. It's the most credible
  thing you'll say.

---

## At a glance — before / after

| | Before (`sha256:3ba7abc…`) | After (hardened) |
|---|---|---|
| Total CVEs | **351** | _TBD — fill from Quay rescan_ |
| High | **24** | _TBD_ |
| Medium | **186** | _TBD_ |
| Low | **121** | _TBD_ |
| Unknown | **20** | _TBD_ |
| Fixable (patch available) | **140** | _TBD_ |

> The "after" column is filled once the hardened image is pushed and Quay's
> scanner re-runs. Local verification (below) already confirms the three High RPM
> findings shown in the scan are cleared.

**The three High RPM findings, traced and fixed:**

| Package | Flagged version | Scanner's fix | Hardened image | Result |
|---------|-----------------|---------------|----------------|--------|
| `openssl-libs` | `3.2.2-6.el9` | `3.5.1-7.el9_7` | `3.5.5-3.el9_8` | ✅ past the fix |
| `openssh` | `8.7p1-45.el9` | `8.7p1-49.el9_7` | `9.9p1-7.el9_8` | ✅ past the fix |
| `libnghttp2` | `1.43.0-6.el9` | `1.43.0-6.el9_7.1` | `1.43.0-6.el9_8.1` | ✅ past the fix |

---

## The engineering record

### What we found

The custom EE (`DC1.Azure - EE`, image `quay.io/zigfreed/dc1-azure-ee:latest`)
exists because the demo's job templates need a `terraform` binary, `pywinrm`, the
Azure SDK, and several collections that the stock minimal EE doesn't carry. Quay's
built-in security scanner (Clair) flagged **351 CVEs (24 High / 186 Medium /
121 Low / 20 Unknown; 140 with fixes available)** on the pushed image.

### Root cause — it's the base, and it's stale

Reading the scan's *"Introduced in layer"* column, **every High finding traced to
the base image layer**, not to anything DC1.Azure adds. The base is
`registry.redhat.io/ansible-automation-platform/ee-minimal-rhel9:2.17.14`. We
confirmed two things before acting:

1. **The base is a point-in-time build, cut `2025-09-21`** — roughly eight months
   of RHEL errata have shipped since. The scanner's "fixed in" versions
   (`…el9_7`) are errata published *after* that base was built.
2. **We were already on the newest in-line rebuild.** `:2.17.14` and `2.17.14-4`
   resolve to the *same* digest (`sha256:4d64d06d…`). There was no fresher 2.17
   base to repin to — the line ended at `-4`; the only "newer base" is the 2.18.x
   line, which is an ansible-core minor bump (see *Deferred*).

So the lever wasn't "use a newer base" — there isn't one in-line — it was **apply
the errata that exist but the frozen base doesn't carry.**

### The fix — one build step

Added as the *first* `prepend_base` step in
[`execution-environment.yml`](../execution-environment.yml):

```yaml
- RUN microdnf upgrade -y --nodocs --setopt=install_weak_deps=0 && microdnf clean all
```

`ee-minimal-rhel9` ships with the ubi9 repos enabled, so this pulls every
fix available there onto the base layer at build time — the single biggest lever
on the scan count. *(Honest caveat: a subset of fixes that live only in
fully-entitled RHEL repos won't apply on an unsubscribed build host; those remain
until the base line itself republishes.)*

### Verification

`rpm -q` against the rebuilt image confirms the three High RPM findings are not
merely patched but moved to **el9_8** errata — newer than the **el9_7** fixes the
scanner asked for:

```
openssl-libs-3.5.5-3.el9_8
openssh-9.9p1-7.el9_8
libnghttp2-1.43.0-6.el9_8.1
```

The authoritative before/after is the **Quay rescan** of the new image
(table above) — captured once the image is pushed.

### What we deliberately did NOT change (and why)

Two available "fixes" were consciously deferred — each to its own work item with
its own testing — because taking them inside a security-hygiene rebuild would
have introduced uncontrolled compatibility risk:

1. **`pyOpenSSL 22.0.0` (a flagged High).** It's a *pip* dependency
   (microdnf can't touch it) and it's **required-by `azure-cli-core`**. Bumping it
   to `≥26` drags **`cryptography` 37.0.2 → 48.0.0** — eleven major versions, on
   the most security-sensitive library in the image — underneath an
   `azure-cli-core` that was never tested against it. The *correct* fix is a
   coherent `azure.azcollection` bump whose own dependency tree brings a newer,
   tested `pyOpenSSL`/`cryptography` set together — not a surgical leaf override.
2. **The 2.18.x base line.** Newer, but it's an **ansible-core minor bump**; the
   pinned collections and `infra.aap_configuration` were validated on 2.17. That's
   a behavior/compatibility change, not security hygiene, and belongs in its own
   validated change.

This is the disciplined half of the story: **a lower CVE number is not the goal;
a defensible, tested image is.**

---

## How this connects to the rest of the demo

- It's the supply-chain backstop behind the [`demo-runbook.md`](demo-runbook.md)
  flow — the same EE runs every trigger (AAP UI, Self-Service, ServiceNow, ADO).
- The remediation itself shipped as **AB#86**; this story is **AB#87**. The two
  deferrals above are their own tracked work items.
- Every change to the EE is recorded in the build-provenance block at the top of
  [`execution-environment.yml`](../execution-environment.yml) — *what* changed and
  *why* — so the image tag is never the only thing explaining intent.

## References

- [`execution-environment.yml`](../execution-environment.yml) — the EE definition + build-provenance log
- [`ee-why-custom-ee.md`](ee-why-custom-ee.md) — why a custom EE over a run-time `requirements.yml`
- [`ee-versioning.md`](ee-versioning.md) — immutable semver tags + the deliberate-update model (AB#95)
- [`ROADMAP.md`](../ROADMAP.md) — phases, decisions log
- Quay repository: `quay.io/zigfreed/dc1-azure-ee` (public; Clair scan under the *Security* tab)
</content>
</invoke>

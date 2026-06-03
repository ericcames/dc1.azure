# DC1.Azure — Why a Custom Execution Environment?

A common question: *why build and ship a purpose-built execution environment
(`DC1.Azure - EE`) when AAP can just install a `collections/requirements.yml`
against a stock EE at run time?* This is the reasoning, both for the engineering
record and as a talking track for customers and sellers.

## TL;DR

The two are **not opposites**. `collections/requirements.yml` is still the
source of truth for *which* collections we need — the custom EE just consumes it
at **build time** and bakes the result (plus things a requirements file can't
express) into one immutable, scanned, air-gapped image. We resolve dependencies
**once, at build time**, instead of **every job run, at run time**.

## What a `requirements.yml` alone can't do

A galaxy requirements file only installs **Ansible collections** (and, via the
EE's own `requirements.txt`/`bindep.txt`, their Python/system deps). Several
hard requirements of this demo fall outside that:

| Need | Why requirements.yml can't cover it | How the EE covers it |
|---|---|---|
| **Terraform binary on `PATH`** | Terraform is a standalone Go binary, not a collection. `provision_vm.yml` / `teardown.yml` shell out to `terraform`. | `prepend_base` downloads + installs the pinned Terraform 1.15.4 into `/usr/local/bin`. |
| **Compiled Python deps** (pywinrm, `azure-mgmt-*`, systemd-python) | Some need a C toolchain + headers to build wheels. | `prepend_builder` adds `python3.11-devel` + `wheel` so they compile cleanly in the builder stage. |
| **System packages** (e.g. `unzip`) | Not addressable from a collections file. | Explicit `microdnf install` steps. |
| **OS errata hardening** | No way to patch the base OS from a requirements file. | `microdnf upgrade` as the first build step (see `ee-security-remediation.md`). |

## Run-time resolution vs. build-time baking

Even for the collections it *can* install, resolving `requirements.yml` at run
time is the wrong trade for a demo platform:

1. **Speed** — run-time install re-resolves and downloads collections on (or
   per-project for) every job. Baking it in means the job starts in a ready
   environment with **zero install step**.
2. **Determinism / reproducibility** — a built, tagged image is a single
   immutable artifact (now `v1.0.0`). Every job, everywhere, runs the **exact
   same bits**. Run-time resolution can drift as upstream versions move unless
   every transitive dep is hard-pinned.
3. **Offline / reliability** — run-time resolution needs the execution node to
   reach Galaxy/Automation Hub *during the demo*; an upstream outage or a
   throttle fails the run live. The EE has everything already inside it.
4. **Air-gapped delivery** — the EE is synced to **Private Automation Hub** and
   pulled internally via `cred_hub_registry`; the image never leaves the
   platform at job-run time. Nothing reaches out to the public internet mid-run.
5. **Security posture** — one image is one scannable artifact. We get a Quay/Clair
   CVE baseline for the *entire runtime* and can harden + re-scan it deliberately
   (see `ee-security-remediation.md`). A run-time-resolved set of collections has
   no single artifact to scan or sign.
6. **Versioned, deliberate updates** — because the runtime is an image, it gets
   an immutable semver tag and a `pull: missing` promotion model
   (`ee-versioning.md`). You know exactly which runtime every job used, and
   updates never happen by surprise.

## So how do the two relate?

```
collections/requirements.yml   ──(build time)──►   DC1.Azure - EE : v1.0.0
   (source of truth for                              (immutable image: collections
    WHICH collections)                                + Terraform + Python/system
                                                       deps + OS errata, baked in)
```

`execution-environment.yml` points `dependencies.galaxy` at
`collections/requirements.yml`, so the requirements file is still where we add or
pin a collection — that change then flows into the **next** EE build and tag (per
the bump rule in `ee-versioning.md`). We keep the convenience and clarity of a
declarative requirements file **and** the reproducibility, speed, security, and
air-gap of a pre-built runtime.

## When a bare requirements.yml *would* be fine

To be fair: if a project used **only pure-Ansible collections**, needed **no
external binaries or compiled deps**, ran in a **connected** environment where a
few extra seconds per job and version drift were acceptable, and had no security
or air-gap requirement — a stock EE + run-time `requirements.yml` is a reasonable,
lower-effort choice. DC1.Azure meets **none** of those: it needs Terraform,
compiled Windows/Azure Python deps, a hardened+scanned runtime, and offline PAH
delivery. That's exactly the profile a custom EE exists for.

## References

- `execution-environment.yml` — the EE definition + BUILD PROVENANCE log
- `collections/requirements.yml` — the collections baked in (per-collection rationale)
- `docs/ee-versioning.md` — immutable semver tags + deliberate updates
- `docs/ee-security-remediation.md` — the hardening + CVE story

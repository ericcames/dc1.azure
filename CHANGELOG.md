# Changelog

All notable changes to this project will be documented in this file.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Unreleased

### Fixed
- `terraform/main.tf` — added `patch_mode = "AutomaticByPlatform"` + `hotpatching_enabled = true` to `azurerm_windows_virtual_machine.demo`. Required by azurerm provider v4.x for hotpatch-enabled images (Windows Server 2025 Azure Edition). Without it, `terraform apply` fails on the VM resource with *"patch_mode must always be set to AutomaticByPlatform when source_image_reference points to a hotpatch enabled image"*. Discovered during Phase 2 smoke test 2026-05-21.
- `terraform/main.tf` — added `azurerm_virtual_machine_extension.winrm_bootstrap` (CustomScriptExtension) that copies `C:\AzureData\CustomData.bin` to `bootstrap.ps1` and executes it via PowerShell. Azure does **not** auto-execute `custom_data` on Windows VMs (unlike Linux cloud-init); the binary is deposited but never run. Without the extension, the WinRM-HTTPS listener was never configured and port 5986 stayed closed after `terraform apply`. Discovered during Phase 2 smoke test 2026-05-21.
- `terraform/scripts/winrm_bootstrap.ps1` — replaced `cmd.exe /c "winrm create winrm/config/Listener?Address=*+Transport=HTTPS '@{Hostname=...; CertificateThumbprint=...}'"` with PowerShell-native `New-WSManInstance`. When the bootstrap script runs as SYSTEM via the Azure CustomScriptExtension, the nested cmd.exe quoting collapses and the resulting HTTPS listener is created with an empty `CertificateThumbprint`. The `New-WSManInstance` invocation passes the hash table natively and avoids cmd.exe entirely. Discovered during Phase 2 smoke test 2026-05-21.

### Changed
- `ROADMAP.md` — captured the Phase 3+ strategic direction (2026-05-26): pin `infra.aap_configuration` **4.4.0** (the Automation Hub release); dc1.azure now **stands independent of `aap.as.code`** with the collection's own docs as the CaC guide and CaC var files named per role/module; runtime target is the **Ansible Product Demo** RHDP catalog item's AAP (install additively, namespaced — not the `ansible/product-demos` repo layout); **one core workflow, four triggers** — added **Phase 9 (AAP Self-Service Portal)** and **Phase 10 (Azure DevOps trigger)**, additive with no renumbering; reuse `aap.dailydemo.windows` roles via a **pinned git reference** (not rewritten); vault password from a **dc1.azure-owned source** (not the borrowed `~/.ansible/secrets2`); ship **`ansible.cfg.example`** (never a live cfg) + **repo-based Claude skills**. Added 8 Decisions Log entries; reworked Guiding Principles, Architecture (four-trigger fan-in + Product-Demo-AAP note), Phase 3 (file names → `controller_job_templates.yml` / `controller_workflow_job_templates.yml`, 4.4.0, vault/cfg/skill prereqs), Phase 4 (role-sourcing decided), and Reference Repositories.
- `ROADMAP.md` — synced Phase status indicators to actual repo state: **Phase 0** ⬜→✅ (ADO org/project/repo/PAT/clone all in place since 2026-05-21); **Phase 1** ⬜→✅ (all scaffolding committed in 2848f54); **Phase 2** ⬜→🔄 (Terraform code complete; manual `apply`/`destroy` smoke test still pending).
- `ROADMAP.md` — added **Phase 0.5 — ADO Operating Conventions** between Phase 0 and Phase 1. Covers Boards Epic→Feature→Story→Task hierarchy backfill, branch policies on `main`, PR template at `.azuredevops/pull_request_template.md`, Service Connections + Variable Group in the ADO Library, CODEOWNERS, and AB# linking enforcement. Driven by the upcoming customer demo to an ADO-fluent audience — needs to read as "mature dev team," not "one person pushing to main."
- `ROADMAP.md` — **Phase 5** now documents the current manual GitHub mirror workflow (`git push github main` after every push to ADO `origin`) and frames the auto-mirror pipeline stage as the enhancement that retires the manual step. Cross-links to the `github-ericcames` Service Connection added in Phase 0.5.
- `README.md` — rewrote "Getting started": removed the misleading "Bootstrap is not yet wired up" banner; framed `aap_config/load.yml` as the canonical install path (Phase 3, building) and de-emphasized `playbooks/bootstrap_aap.yml` as a deprecated stopgap; added the current manual GitHub mirror workflow as a documented step.

### Added
- `.azuredevops/pull_request_template.md` — ADO-auto-applied PR template with sections for Summary, Work item (AB# autolink field), Test plan, and Risk / rollback, plus a CONTRIBUTING-aligned checklist. Satisfies Phase 0.5 ⬜ PR-template item.
- `CODEOWNERS` at repo root — path → owner mapping for `/terraform/`, `/playbooks/`, `/aap_config/`, `/.azuredevops/`, and governance docs. Catch-all `*` falls back to @ericcames. File works AS-IS on the GitHub mirror; on ADO the same mapping must be re-entered into the "Automatically include code reviewers" branch policy (canonical mapping lives in `docs/ado-conventions.md`). Satisfies Phase 0.5 ⬜ CODEOWNERS item.
- `docs/ado-conventions.md` — single-page reference for the ADO operating model: Boards Epic→Feature→Story→Task hierarchy + area/iteration paths + tags, branch-policy table, reviewers-by-path mapping, PR template section guide, AB# autolink mechanics, Service Connections (`dc1-azure-rhdp-sp`, `github-ericcames`), Variable Group (`dc1-azure-shared`), and Wiki landing page. Acts as the customer-facing audit reference for Phase 0.5. Satisfies Phase 0.5 ⬜ ado-conventions.md item.
- `playbooks/bootstrap_aap.yml` — DEPRECATED banner at top of file explaining (a) why it still exists today, (b) when it will be removed, and (c) that new AAP objects belong in `aap_config/files/controller_*.yml`, not here. Satisfies the Phase 3 ⬜ "Add deprecation banner" item.

### Changed
- `CONTRIBUTING.md` — clarified step 4 (work-item reference) to point at the new `.azuredevops/pull_request_template.md` AB# field; clarified step 5 to note that direct-push blocking on `main` is a Phase 0.5 branch-policy item, not yet enforced; added a dedicated **`AB#<id>` autolink syntax** section explaining how ADO renders the shorthand and pointing at `docs/ado-conventions.md` for the full operating model. Satisfies Phase 0.5 ⬜ "Document AB# autolink syntax in CONTRIBUTING.md" item.
- `ROADMAP.md` — marked four Phase 0.5 items ✅: PR template, CONTRIBUTING AB# documentation, CODEOWNERS, and the `docs/ado-conventions.md` reference. The remaining ⬜ items in Phase 0.5 require ADO web UI / `az devops` CLI work (Boards backfill, branch policies, Service Connections, Variable Group).
- `ROADMAP.md` — Phase 0.5 advanced from ⬜ to 🔄. Chunk B (ADO UI / `az devops` CLI work) executed via the CLI: 10 Epics, 13 Features, 11 Stories backfilled with full Epic→Feature→Story parentage and `phase-N` + topic tags; iterations renamed `Sprint 1/2/3` with rolling 2-week date ranges starting 2026-05-21; Azure RM Service Connection `dc1-azure-rhdp-sp` created from RHDP SP (id `86d0df16-75b6-4197-9ddb-4cd097d14245`); Variable Group `dc1-azure-shared` (4 vars, authorized for all pipelines); project Wiki `dc1.azure.wiki` with `/Home` landing page; project description set on ADO landing page; four blocking branch policies on `main` (reviewers, work-item linking, comment resolution, squash-only merge — build validation policy deferred to Phase 5). Remaining ⬜ items intentionally deferred (GitHub SC → Phase 5, build validation → Phase 5, auto-include reviewers → when a teammate joins).
- `ROADMAP.md` — **Phase 2 advanced from 🔄 to ✅.** Manual smoke test passed against RHDP env (`openenv-blsvm-1`, `eastus`) on 2026-05-21 with `vm_size_tier=small`. Three real Phase 2 design bugs found + fixed during the test (see `### Fixed` above). Apply produced a reachable Windows Server 2025 VM at `20.127.118.198`; WinRM-HTTPS port 5986 verified open + TLS handshake succeeds + WinRM listener responds with HTTP 405 to a GET on `/wsman`; `terraform destroy` cleaned all 9 resources. Storage-backend bootstrap remains as a separate follow-up (local state used for this smoke test per the documented escape hatch in `backend.tf`).
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
- `DC1.Azure - Vault` and `DC1.Azure - Azure RM` credentials created in live RHDP AAP (`aap-aap.apps.cluster-blsvm-2.dynamic2.redhatworkshops.io`) via `--skip-tags ado` partial run on 2026-05-21. Azure RM credential confirmed via API: subscription/tenant/client fields all correct; client_secret encrypted at rest.

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

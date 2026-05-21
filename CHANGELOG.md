# Changelog

All notable changes to this project will be documented in this file.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Unreleased

### Added
- `playbooks/bootstrap_aap.yml` — Phase 3 bootstrap playbook: creates Vault credential, Azure RM credential (Service Principal), ADO Source Control credential (PAT), and the `DC1.Azure` project syncing from the ADO repo. Pattern mirrors `aap.as.code/playbooks/bootstrap_dev.yml`: `ansible.platform.token` for token lifecycle (created + deleted in `always:` block); `ansible.controller` modules for credential/project (no `ansible.platform` equivalents yet).
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

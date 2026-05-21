# Changelog

All notable changes to this project will be documented in this file.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Unreleased

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

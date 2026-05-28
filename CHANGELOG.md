# Changelog

All notable changes to this project will be documented in this file.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Unreleased

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
- Azure Storage Account `dc1aztfstate0526` bootstrapped in `openenv-blsvm-1`; SP granted `Storage Blob Data Contributor` for Azure AD auth (`use_azuread_auth = true`). Documented in `docs/dev-environment.md`.

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

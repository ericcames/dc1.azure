---
name: install-dc1-azure
description: >-
  Install (or re-install) the dc1.azure AAP objects into a working Ansible
  Automation Platform via aap_config/load.yml. TRIGGER when the user asks to
  install / bootstrap / set up dc1.azure on AAP, deploy the Config-as-Code, or
  "run load.yml". This is the repo-based replacement for the marketplace
  /aap-first-time + bootstrap flow. SKIP for normal code edits or if the user
  only wants to inspect aap_config/ without applying it.
---

# Install dc1.azure into AAP

Drive the install interactively. The authoritative reference is
[`docs/INSTALL.md`](../../../docs/INSTALL.md) — follow its steps; this skill
adds the interactive checking and reporting around them.

## Guardrails

- **Never print secret values** and never put them in tool-call arguments.
  Check env vars by **name only** (e.g. `printenv NAME >/dev/null && echo set`).
  When a secret is missing, ask the *user* to export it themselves — suggest
  they type `! export NAME=...` in the prompt so it lands in this session's
  shell without you echoing it.
- This **mutates a live AAP** (creates credentials/projects/JTs/workflow).
  Confirm the target `AAP_HOSTNAME` with the user before running `load.yml`.
- Applying is idempotent and additive (objects are namespaced `DC1.Azure -`),
  so a re-run is safe.

## Steps

1. **Confirm prerequisites.** Verify `ansible-galaxy` is available and that the
   repo has `aap_config/`. Confirm the user has: an AAP instance + a personal
   API token (AAP UI → Tokens, write scope), an Azure Service Principal + RHDP
   resource group, an ADO PAT, a chosen Windows admin password, and AAP login
   for the Controller credential. Point them at `docs/INSTALL.md` §1 if not.

2. **Hub-configured ansible.cfg.** If `ansible-galaxy collection list` can't see
   a Hub server, have them seed `~/.ansible.cfg` from `ansible.cfg.example`
   (§2) and paste their offline Hub token. Then install collections:
   `ansible-galaxy collection install -r aap_config/requirements.yml`.

3. **Check the environment.** For each variable in the `docs/INSTALL.md` §5
   table, test presence by name (don't read the value). Build a list of the
   **missing required** ones and the **optional** ones worth setting
   (`DC1_AZURE_EE`, `WINDOWS_ADMIN_USERNAME`, `AZURE_LOCATION`,
   `AAP_VALIDATE_CERTS`). Required: `AAP_HOSTNAME`, `AAP_TOKEN`,
   `DC1_AZURE_VAULT_PASSWORD`, `AZURE_SUBSCRIPTION_ID`, `AZURE_TENANT_ID`,
   `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`, `AZURE_RESOURCE_GROUP`, `ADO_PAT`,
   `WINDOWS_ADMIN_PASSWORD`, `AAP_CONTROLLER_PASSWORD`.

4. **Collect what's missing.** List the missing variables and ask the user to
   export them (`! export NAME=value`). Re-check until all required ones are
   present. Remind them about the **`DC1_AZURE_EE`** (must be Windows + terraform
   capable) and the **admin-password sync** callout from `docs/INSTALL.md` §5
   (the Provision/Teardown JTs need `dc1_azure_windows_admin_password` to equal
   `WINDOWS_ADMIN_PASSWORD`).

5. **Apply.** Confirm `AAP_HOSTNAME` with the user, then run:
   `ansible-playbook -i aap_config/inventory/ aap_config/load.yml`.
   `load.yml` ends by importing `validate.yml`, which asserts every object
   exists. If validation fails on `/api/v2/` not found, re-run with
   `DC1_AZURE_API_BASE=/api/v2`.

6. **Report.** Summarize the created objects (5 credentials, 2 projects, the
   `dc1-azure` inventory, 6 JTs, the `DC1.Azure - Provision and Configure`
   workflow). Tell the user they can launch that workflow and pick a
   `vm_size_tier`. If anything failed, map it to the `docs/INSTALL.md`
   Troubleshooting table.

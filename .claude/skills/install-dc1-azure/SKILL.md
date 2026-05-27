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
- **All exports and the ansible-playbook command must be in one shell call.**
  Shell state does not persist across separate Bash tool invocations. Build a
  single compound command with all exports followed by the playbook run.

## Steps

1. **Confirm prerequisites.** Verify `ansible-galaxy` is available and that the
   repo has `aap_config/`. Confirm the user has: an AAP instance, an Azure
   Service Principal + RHDP resource group, an ADO PAT, a chosen Windows admin
   password, and AAP admin login. Point them at `docs/INSTALL.md` §1 if not.

2. **Hub-configured ansible.cfg.** Check that `~/.ansible.cfg` exists and is a
   real file (not a symlink — symlinks can cause Ansible not to load it). If it
   is a symlink, replace it: `rm ~/.ansible.cfg && cp ~/.ansible/ansible.cfg
   ~/.ansible.cfg`. Then verify collections:
   `ansible-galaxy collection install -r aap_config/requirements.yml`.

3. **Check Automation Hub Galaxy credentials on the Default org.** Query the
   AAP API:
   ```bash
   curl -sk -u admin:<pw> \
     "https://<aap>/api/controller/v2/organizations/1/galaxy_credentials/" \
     | python3 -c "import sys,json; [print(c['name']) for c in json.load(sys.stdin)['results']]"
   ```
   The output must include **"Automation Hub - certified"** and **"Automation
   Hub - validated"**. If either is missing, create them now (see
   `docs/INSTALL.md` §2.5) before proceeding — without them, the
   `infra.aap_configuration` async workers connect to `127.0.0.1` and fail
   with `Connection refused` on credential creation.

4. **Create the AAP personal token.** Use the gateway v1 endpoint (not the old
   controller v2 endpoint) and capture the ID for cleanup:
   ```bash
   curl -sk -u admin:<pw> -X POST -H 'Content-Type: application/json' \
     -d '{"description":"dc1.azure CaC install","scope":"write"}' \
     "https://<aap>/api/gateway/v1/tokens/"
   ```
   Write the token value to `/tmp/.aap_token_dc1` (mode 600). Delete token ID
   after the install: `curl -sk -u admin:<pw> -X DELETE .../gateway/v1/tokens/<id>/`.

5. **Check the environment.** If `docs/dev-environment.sh` exists, suggest the
   user run `source docs/dev-environment.sh` (they type `! source docs/dev-environment.sh`
   in the prompt). Otherwise, for each variable in the `docs/INSTALL.md` §5
   table, test presence by name (don't read the value). Required: `AAP_HOSTNAME`,
   `AAP_TOKEN`, `CONTROLLER_HOST`, `CONTROLLER_OAUTH_TOKEN`,
   `DC1_AZURE_VAULT_PASSWORD`, `AZURE_SUBSCRIPTION_ID`, `AZURE_TENANT_ID`,
   `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`, `AZURE_RESOURCE_GROUP`,
   `AZURE_TF_STORAGE_ACCOUNT`, `ADO_PAT`, `WINDOWS_ADMIN_PASSWORD`,
   `AAP_CONTROLLER_PASSWORD`. Optional with good defaults: `AAP_VALIDATE_CERTS`
   (false), `CONTROLLER_VERIFY_SSL` (false), `DC1_AZURE_EE` (defaults to
   `DC1.Azure - EE` — the EE registered by load.yml), `DC1_AZURE_EE_IMAGE`
   (defaults to `quay.io/zigfreed/dc1-azure-ee:latest`; after Hub syncs set
   to `<ah_hostname>/dc1_azure_ee:latest`), `AH_HOSTNAME` (defaults to gateway
   hostname — correct for AAP 2.5 unified platform), `WINDOWS_ADMIN_USERNAME`
   (demoadmin), `AZURE_LOCATION` (eastus), `AAP_CONTROLLER_USERNAME` (admin).

   Note: `CONTROLLER_HOST` = same value as `AAP_HOSTNAME`, and
   `CONTROLLER_OAUTH_TOKEN` = same value as `AAP_TOKEN`. These are required
   separately because `ansible.controller.*` async workers read them directly
   from the environment and fall back to `127.0.0.1` if absent.

6. **Collect what's missing.** List the missing variables and ask the user to
   export them (`! export NAME=value`). Remind them about:
   - **`DC1_AZURE_EE`** — the EE name that job templates reference. `load.yml`
     now creates `DC1.Azure - EE` in Controller automatically (via
     `controller_execution_environments.yml`), so you normally leave this unset.
     Only override if you want JTs to use a different EE.
   - **admin-password sync** — `WINDOWS_ADMIN_PASSWORD` must equal
     `dc1_azure_windows_admin_password` at workflow launch time
   - **`DC1_AZURE_VAULT_PASSWORD`** — a string you choose now; use the same
     string to ansible-vault encrypt `dc1_azure_windows_admin_password`

7. **Apply.** Confirm `AAP_HOSTNAME` with the user, then run **all exports and
   the playbook in a single shell command** — env vars do not persist across
   separate calls. Preferred form (uses the env file):
   ```bash
   source docs/dev-environment.sh && \
   ansible-playbook -i aap_config/inventory/ aap_config/load.yml
   ```
   If the env file isn't present, build a single compound export + playbook command:
   ```bash
   export AAP_HOSTNAME=... AAP_TOKEN=... CONTROLLER_HOST=$AAP_HOSTNAME
   export CONTROLLER_OAUTH_TOKEN=$AAP_TOKEN CONTROLLER_VERIFY_SSL=false
   export <all other vars> ...
   ansible-playbook -i aap_config/inventory/ aap_config/load.yml
   ```
   `load.yml` ends by importing `validate.yml`, which asserts every object
   exists. If validation fails on `/api/v2/` not found, re-run with
   `DC1_AZURE_API_BASE=/api/v2`.

8. **Delete the token.** After a green run, delete the AAP token created in
   step 4. Then remove `/tmp/.aap_token_dc1`.

9. **Report.** Summarize the created objects (5 credentials, 2 projects, the
   `dc1-azure` inventory, 6 JTs, the `DC1.Azure - Provision and Configure`
   workflow). Tell the user they can launch that workflow and pick a
   `vm_size_tier`. If anything failed, map it to the `docs/INSTALL.md`
   Troubleshooting table.

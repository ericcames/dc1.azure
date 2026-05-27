# Installing dc1.azure into AAP

This guide installs every dc1.azure AAP object (credentials, projects,
inventory, job templates, and the provision-and-configure workflow) onto a
working Ansible Automation Platform via the Configuration-as-Code under
[`aap_config/`](../aap_config/README.md).

There are **two paths**:

- **Manual** (this document) — run the commands yourself.
- **AI-driven** — if you use Claude Code, the repo ships an interactive skill
  (`/install-dc1-azure`) that checks prerequisites, prompts for any missing
  values, runs the install, and verifies it. See
  [`.claude/skills/install-dc1-azure/SKILL.md`](../.claude/skills/install-dc1-azure/SKILL.md).

Both paths converge on the same `ansible-playbook … aap_config/load.yml` run.

---

## 1. Prerequisites

You need access to:

| Thing | Why | Where it comes from |
|-------|-----|---------------------|
| An AAP instance | install target | the **Ansible Product Demo** RHDP catalog item (or any AAP 2.5) |
| AAP personal API token | authenticates the CaC run | create via gateway API or AAP UI (scope: write) — see §4 |
| Two Automation Hub Galaxy credentials on the Default org | `infra.aap_configuration` async workers need them to resolve credential types | create via API or AAP UI **before** running `load.yml` — see §2.5 |
| Azure Service Principal | Azure RM credential + Terraform | RHDP Azure open environment (subscription, tenant, client id/secret) |
| RHDP resource group | where the VM is created | the Azure open environment (e.g. `openenv-…`) |
| Azure DevOps PAT | syncs the `DC1.Azure` project | `dev.azure.com/ericcames` → PAT scoped **Code (Read)** |
| Windows admin password | VM local admin + WinRM | you choose one (Azure complexity: 12–72 chars, 3 of upper/lower/digit/symbol) |
| AAP admin (or service) login | the Controller credential | your AAP login — lets provision register the VM in the inventory |
| Automation Hub offline token | installs the pinned collections locally + populates Galaxy credentials | `console.redhat.com/ansible/automation-hub/token` (also in `~/.ansible.cfg`) |

Local tooling: `ansible-core` ≥ 2.16 and `git`. (The `terraform` binary itself
runs inside the AAP execution environment, not on your laptop.)

---

## 2. Configure Automation Hub (one-time, for collection install)

The pinned collections (`infra.aap_configuration` 4.4.0, etc.) come from Red Hat
Automation Hub. If you don't already have a Hub-configured `ansible.cfg`, seed
one from the committed template:

```bash
cp ansible.cfg.example ~/.ansible.cfg
# edit ~/.ansible.cfg and paste your offline Hub token into the
# galaxy_server.automation_hub `token =` line
```

> **`~/.ansible.cfg` must be a real file, not a symlink.** If it is a symlink
> (e.g. `~/.ansible.cfg → ~/.ansible/ansible.cfg`), some Ansible contexts do
> not follow it. Replace it with a copy:
> ```bash
> rm ~/.ansible.cfg && cp ~/.ansible/ansible.cfg ~/.ansible.cfg
> ```

> Never rename `ansible.cfg.example` to a live `ansible.cfg` *inside the repo* —
> Ansible loads only one cfg, and a project-local one would shadow your home cfg.

## 2.5. Create Automation Hub Galaxy credentials on the Default org

> ⚠️ **Do this before running `load.yml`.** The `infra.aap_configuration`
> collection's async workers look up credential types via the AAP API. Without
> Hub credentials on the Default org they fall back to `127.0.0.1` and fail
> with `Connection refused`.

The Default org needs two **"Ansible Galaxy/Automation Hub API Token"**
credentials attached. Both use the same offline token from `~/.ansible.cfg`.

**Option A — via the AAP UI:**

1. Go to **Resources → Credentials → Add**
2. Create **"Automation Hub - certified"**:
   - Credential Type: `Ansible Galaxy/Automation Hub API Token`
   - Galaxy Server URL: `https://console.redhat.com/api/automation-hub/content/published/`
   - Auth Server URL: `https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token`
   - API Token: your offline token
3. Create **"Automation Hub - validated"** — same settings but URL:
   `https://console.redhat.com/api/automation-hub/content/validated/`
4. Go to **Access → Organizations → Default → Edit** and add both credentials
   to **Galaxy Credentials**.

**Option B — via the API (scriptable):**

```bash
AAP=https://<your-aap>
# Get the Galaxy credential type ID and Default org ID
GALAXY_TYPE=$(curl -sk -u admin:<pw> "$AAP/api/controller/v2/credential_types/?kind=galaxy" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['results'][0]['id'])")

# Extract token from ~/.ansible.cfg (adjust line number if your cfg differs)
# Section order: [galaxy_server.rh_certified] url= auth_url= token= (token is line 3 after header)
HUB_TOKEN=$(grep -A3 'rh_certified' ~/.ansible.cfg | grep '^token=' | cut -d= -f2-)
AUTH_URL="https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token"

# Create certified credential
CERT_ID=$(curl -sk -u admin:<pw> -X POST -H 'Content-Type: application/json' \
  -d "{\"name\":\"Automation Hub - certified\",\"organization\":1,\"credential_type\":$GALAXY_TYPE,
       \"inputs\":{\"url\":\"https://console.redhat.com/api/automation-hub/content/published/\",
       \"auth_url\":\"$AUTH_URL\",\"token\":\"$HUB_TOKEN\"}}" \
  "$AAP/api/controller/v2/credentials/" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")

# Create validated credential
VAL_ID=$(curl -sk -u admin:<pw> -X POST -H 'Content-Type: application/json' \
  -d "{\"name\":\"Automation Hub - validated\",\"organization\":1,\"credential_type\":$GALAXY_TYPE,
       \"inputs\":{\"url\":\"https://console.redhat.com/api/automation-hub/content/validated/\",
       \"auth_url\":\"$AUTH_URL\",\"token\":\"$HUB_TOKEN\"}}" \
  "$AAP/api/controller/v2/credentials/" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")

# Attach both to Default org (org ID 1)
curl -sk -u admin:<pw> -X POST -H 'Content-Type: application/json' \
  -d "{\"id\": $CERT_ID}" "$AAP/api/controller/v2/organizations/1/galaxy_credentials/"
curl -sk -u admin:<pw> -X POST -H 'Content-Type: application/json' \
  -d "{\"id\": $VAL_ID}" "$AAP/api/controller/v2/organizations/1/galaxy_credentials/"
```

Verify in the UI: **Access → Organizations → Default → Details** → Galaxy
Credentials should show `Ansible Galaxy`, `Automation Hub - certified`, and
`Automation Hub - validated`.

## 2.6. Bootstrap the Terraform state Storage Account (one-time per RHDP env)

Terraform uses Azure Blob Storage as its remote state backend. The Storage Account must exist *before* running `load.yml` (the Provision VM JT extra_vars reference it at bake-time).

```bash
# Use the az CLI logged in as the RHDP Service Principal
az storage account create \
  --name <storage-account-name> \       # e.g. dc1aztfstate<date> — globally unique, 3-24 lowercase alphanum
  --resource-group <rhdp-resource-group> \
  --location eastus \
  --sku Standard_LRS \
  --allow-blob-public-access false

az storage container create \
  --name tfstate \
  --account-name <storage-account-name>

# Grant the SP Storage Blob Data Contributor so Terraform can use Azure AD auth
az role assignment create \
  --assignee <service-principal-client-id> \
  --role "Storage Blob Data Contributor" \
  --scope "/subscriptions/<subscription-id>/resourceGroups/<rg>/providers/Microsoft.Storage/storageAccounts/<storage-account-name>"
```

Then export `AZURE_TF_STORAGE_ACCOUNT=<storage-account-name>` before running `load.yml`.

> **One SA per RHDP environment.** Storage Account names must be globally unique. When you activate a new RHDP open environment, create a new SA in the new resource group and update `docs/dev-environment.sh` + the `AZURE_TF_STORAGE_ACCOUNT` export.

## 3. Install the collections

```bash
ansible-galaxy collection install -r aap_config/requirements.yml
```

## 4. Create an AAP personal token

**Option A — AAP UI:** your user → **Tokens → Create token**, scope **Write**.

**Option B — gateway API (scriptable, delete after install):**

```bash
# Create via the new AAP 2.5 gateway endpoint (not /api/v2/tokens/)
TOKEN_VAL=$(curl -sk -u admin:<pw> -X POST -H 'Content-Type: application/json' \
  -d '{"description":"dc1.azure CaC install","scope":"write"}' \
  "https://<your-aap>/api/gateway/v1/tokens/" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['id'],d['token'])")
TOKEN_ID=$(echo $TOKEN_VAL | cut -d' ' -f1)
TOKEN=$(echo $TOKEN_VAL | cut -d' ' -f2)

# ... run load.yml (see §6) ...

# Delete after install
curl -sk -u admin:<pw> -X DELETE "https://<your-aap>/api/gateway/v1/tokens/$TOKEN_ID/"
```

## 5. Set environment variables

The CaC reads every secret from the environment at runtime — nothing is stored
in the repo.

| Variable | Required | Default | Used for |
|----------|----------|---------|----------|
| `AAP_HOSTNAME` | ✅ | — | AAP API base, e.g. `https://aap.example.com` |
| `AAP_TOKEN` | ✅ | — | AAP API auth (the personal token from step 4) |
| `AAP_VALIDATE_CERTS` | — | `false` | set `true` for a trusted cert |
| `CONTROLLER_HOST` | ✅ | — | **Same value as `AAP_HOSTNAME`.** Required separately — `ansible.controller.*` async workers read this env var directly and fall back to `127.0.0.1` if it is absent, regardless of the `aap_hostname` variable. |
| `CONTROLLER_OAUTH_TOKEN` | ✅ | — | **Same value as `AAP_TOKEN`.** Required for the same async-worker reason. |
| `CONTROLLER_VERIFY_SSL` | — | `false` | Same as `AAP_VALIDATE_CERTS`; set both. |
| `DC1_AZURE_VAULT_PASSWORD` | ✅ | — | the `DC1.Azure - Vault` credential — you choose this string; use it again to vault-encrypt `dc1_azure_windows_admin_password` at workflow launch |
| `AZURE_SUBSCRIPTION_ID` | ✅ | — | `DC1.Azure - Azure RM` credential |
| `AZURE_TENANT_ID` | ✅ | — | `DC1.Azure - Azure RM` credential |
| `AZURE_CLIENT_ID` | ✅ | — | Service Principal (Azure RM credential) |
| `AZURE_CLIENT_SECRET` | ✅ | — | Service Principal (Azure RM credential) |
| `AZURE_RESOURCE_GROUP` | ✅ | `REPLACE_ME_RHDP_RG` | baked into Provision/Teardown JT extra_vars |
| `AZURE_LOCATION` | — | `eastus` | Azure region |
| `ADO_PAT` | ✅ | — | `DC1.Azure - ADO Source Control` credential |
| `WINDOWS_ADMIN_USERNAME` | — | `demoadmin` | `DC1.Azure - Windows Machine` (matches Terraform default) |
| `WINDOWS_ADMIN_PASSWORD` | ✅ | — | `DC1.Azure - Windows Machine` credential |
| `AAP_CONTROLLER_USERNAME` | — | `admin` | `DC1.Azure - Controller` (Red Hat AAP) credential |
| `AAP_CONTROLLER_PASSWORD` | ✅ | — | `DC1.Azure - Controller` credential |
| `AZURE_TF_STORAGE_ACCOUNT` | ✅ | `REPLACE_ME_TF_STATE_SA` | Azure Storage Account name for Terraform remote state backend — must exist before `load.yml` runs (see §2.6) |
| `DC1_AZURE_EE` | — | `DC1.Azure - EE` | EE name the JTs reference — `load.yml` creates this EE automatically via CaC; only override if you want JTs to use a different EE |
| `DC1_AZURE_EE_IMAGE` | — | `<AH_HOSTNAME>/dc1_azure_ee:latest` | Container image for the EE — defaults to the **Private Automation Hub** copy (`load.yml` syncs it there from quay.io and Controller pulls it via the `DC1.Azure - Hub Registry` credential). Override with the public quay.io image (`quay.io/zigfreed/dc1-azure-ee:latest`) only for a Hub-less smoke test |
| `AH_HOSTNAME` | — | gateway hostname | Private Automation Hub hostname for EE image URLs. On AAP 2.5 unified platform, Hub is at the same host as the gateway — leave unset unless Hub is on a separate host |

> **Execution environment:** `load.yml` configures Private Automation Hub to
> register quay.io as a remote registry and **sync the image into Hub**
> (`aap_config/files/hub_ee_registries.yml` + `hub_ee_repositories.yml`), creates
> a `DC1.Azure - Hub Registry` Container Registry credential, then registers the
> `DC1.Azure - EE` execution environment in Controller pointing at the **Hub**
> image URL (`<AH_HOSTNAME>/dc1_azure_ee:latest`) with that credential attached
> (`aap_config/files/controller_execution_environments.yml`). So at job-run time
> Controller pulls the EE from the internal Hub, not quay.io — no manual EE setup
> required. The EE includes: Terraform 1.15.4, `azure.azcollection`,
> `ansible.windows`, `community.windows`, `infra.aap_configuration`, and
> `pywinrm` (via collection Python requirements).

> **Password sync (important):** the Windows admin password is needed in **two**
> places that must match — the `DC1.Azure - Windows Machine` credential (set
> from `WINDOWS_ADMIN_PASSWORD` here) and Terraform's `admin_password` at
> provision time. Supply the same value to the **Provision VM** and **Teardown**
> job templates as a vaulted extra var named `dc1_azure_windows_admin_password`
> (JT *Variables* field, or at launch). A future change may unify these.

## 6. Apply the configuration

> ⚠️ **All `export` statements and the `ansible-playbook` command must run in
> the same shell process.** Env vars do not persist across separate terminal
> commands or tool calls (including AI tool calls). Use `source` or a single
> compound command.

**Recommended — source the env file:**

```bash
# First time: copy the template and fill in your values
cp docs/dev-environment.sh.example docs/dev-environment.sh
# edit docs/dev-environment.sh (it is gitignored — never commit it)

# Then run:
source docs/dev-environment.sh && \
ansible-playbook -i aap_config/inventory/ aap_config/load.yml
```

**Alternative — inline exports (useful for one-off runs or CI):**

```bash
export AAP_HOSTNAME=https://<your-aap>
export AAP_TOKEN=<personal token from step 4>
export AAP_VALIDATE_CERTS=false
export CONTROLLER_HOST=$AAP_HOSTNAME
export CONTROLLER_OAUTH_TOKEN=$AAP_TOKEN
export CONTROLLER_VERIFY_SSL=false
export DC1_AZURE_VAULT_PASSWORD='<vault password>'
export AZURE_SUBSCRIPTION_ID=<sub>
export AZURE_TENANT_ID=<tenant>
export AZURE_CLIENT_ID=<client>
export AZURE_CLIENT_SECRET='<secret>'
export AZURE_RESOURCE_GROUP=openenv-xxxxx
export AZURE_LOCATION=eastus
export ADO_PAT=<ado pat>
export WINDOWS_ADMIN_USERNAME=demoadmin
export WINDOWS_ADMIN_PASSWORD='<Azure-complex password>'
export AAP_CONTROLLER_USERNAME=admin
export AAP_CONTROLLER_PASSWORD=<aap admin password>
export AZURE_TF_STORAGE_ACCOUNT=<storage-account-name>  # see §2.6
# Optional overrides (defaults shown):
# export DC1_AZURE_EE='DC1.Azure - EE'            # created by load.yml — only set to override
# export DC1_AZURE_EE_IMAGE='quay.io/zigfreed/dc1-azure-ee:latest'  # or Hub URL after sync

ansible-playbook -i aap_config/inventory/ aap_config/load.yml
```

`load.yml` applies everything via `infra.aap_configuration.dispatch`, then
imports `validate.yml`, which queries the AAP API and **asserts every object
exists** — so a green run means the install is complete. Re-running is
idempotent.

## 7. Confirm and launch

In the AAP UI you should now see (all prefixed `DC1.Azure -`): 6 credentials
(including `DC1.Azure - Hub Registry`), 2 projects (`DC1.Azure`,
`aap.dailydemo.windows`), the `dc1-azure` inventory, 6 job templates, the
`DC1.Azure - EE` execution environment, the **`DC1.Azure - Provision and
Configure`** workflow, and the `DC1.Azure - Nightly Teardown` schedule on the
Teardown job template (runs daily at 18:00 `America/Phoenix`).

Launch that workflow, pick a `vm_size_tier` in the survey, and watch it
provision the Azure VM and run the configure chain.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `401 Unauthorized` during `load.yml` | bad/expired `AAP_TOKEN` | recreate the personal token (step 4) |
| `validate.yml` reports a MISSING object | dispatch skipped it (often a missing env var) | check the failed object's required env var; re-run |
| Validate hits `/api/v2/` not found | older AAP API path | `export DC1_AZURE_API_BASE=/api/v2` and re-run |
| `Connection refused` to `127.0.0.1` during credential creation | `CONTROLLER_HOST` / `CONTROLLER_OAUTH_TOKEN` not set, OR Hub Galaxy credentials missing from Default org | set both `CONTROLLER_*` vars **and** complete §2.5 before re-running |
| Credential creation fails (censored `no_log`) | same root cause as above | expose with `-e controller_configuration_credentials_secure_logging=false` to confirm, then fix |
| Provision job fails: `terraform: not found` | EE image doesn't have Terraform — `DC1.Azure - EE` not yet registered or wrong image pulled | verify `controller_execution_environments.yml` ran (check AAP UI → Execution Environments for `DC1.Azure - EE`); if missing, re-run `load.yml` |
| `DC1.Azure - EE` shows in Controller but Terraform is missing | EE image URL points to a base image without Terraform | check `DC1_AZURE_EE_IMAGE` — the `quay.io/zigfreed/dc1-azure-ee:latest` image has Terraform; if overridden to a Hub URL, confirm Hub synced from quay.io |
| Provision fails on `admin_password` complexity | weak `WINDOWS_ADMIN_PASSWORD` | 12–72 chars, 3 of upper/lower/digit/symbol |
| Configure steps can't authenticate (WinRM) | Windows Machine cred password ≠ Terraform admin_password, or username mismatch | sync the password (step 5 callout); keep `WINDOWS_ADMIN_USERNAME` = Terraform `admin_username` |
| Provision can't register host (`CONTROLLER_*` not set) | Controller credential not attached | confirm `DC1.Azure - Controller` is on the Provision/Teardown JTs |
| `ansible-galaxy` can't find `infra.aap_configuration` 4.4.0 | Hub token not configured | step 2 (`ansible.cfg.example` → `~/.ansible.cfg`) |
| Galaxy credential token missing / empty after API creation | wrong grep pattern when extracting token from `~/.ansible.cfg` | the section is `[galaxy_server.rh_certified]` not `[galaxy_server.automation_hub]`; token is line 3 after the section header |
| `load.yml` fails: "returned N items, expected 1" on any object | `my_organization` was changed and objects from the old org were never cleaned up — `infra.aap_configuration` queries by name only, not name+org, so duplicates across orgs cause a fatal | delete the stale org's objects via the AAP API or UI (query `?name=<obj>&organization=<old-org-id>` for each type: credentials, inventories, projects, job_templates, workflow_job_templates), then re-run |

## Uninstall

The CaC is additive and namespaced `DC1.Azure -`. To remove, delete those named
objects in the AAP UI (or set `state: absent` per object and re-dispatch). The
`DC1.Azure - Teardown` job template destroys the Azure VM itself.

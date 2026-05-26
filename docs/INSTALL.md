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
| AAP personal API token | authenticates the CaC run | create in the AAP UI → *Users → your user → Tokens* (scope: write) |
| Azure Service Principal | Azure RM credential + Terraform | RHDP Azure open environment (subscription, tenant, client id/secret) |
| RHDP resource group | where the VM is created | the Azure open environment (e.g. `openenv-…`) |
| Azure DevOps PAT | syncs the `DC1.Azure` project | `dev.azure.com/ericcames` → PAT scoped **Code (Read)** |
| Windows admin password | VM local admin + WinRM | you choose one (Azure complexity: 12–72 chars, 3 of upper/lower/digit/symbol) |
| AAP admin (or service) login | the Controller credential | your AAP login — lets provision register the VM in the inventory |
| Automation Hub token | installs the pinned collections | `console.redhat.com/ansible/automation-hub/token` |

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

> Never rename `ansible.cfg.example` to a live `ansible.cfg` *inside the repo* —
> Ansible loads only one cfg, and a project-local one would shadow your home cfg.

## 3. Install the collections

```bash
ansible-galaxy collection install -r aap_config/requirements.yml
```

## 4. Create an AAP personal token

In the AAP UI: **your user → Tokens → Add**, scope **Write**. Copy the token —
you'll export it as `AAP_TOKEN` next.

## 5. Set environment variables

The CaC reads every secret from the environment at runtime — nothing is stored
in the repo.

| Variable | Required | Default | Used for |
|----------|----------|---------|----------|
| `AAP_HOSTNAME` | ✅ | — | AAP API base, e.g. `https://aap.example.com` |
| `AAP_TOKEN` | ✅ | — | AAP API auth (the personal token from step 4) |
| `AAP_VALIDATE_CERTS` | — | `false` | set `true` for a trusted cert |
| `DC1_AZURE_VAULT_PASSWORD` | ✅ | — | the `DC1.Azure - Vault` credential |
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
| `DC1_AZURE_EE` | — | `Default execution environment` | the EE the JTs run in — **see callout below** |

```bash
export AAP_HOSTNAME=https://<your-aap>
export AAP_TOKEN=<personal token>
export DC1_AZURE_VAULT_PASSWORD=<a vault password>
export AZURE_SUBSCRIPTION_ID=... AZURE_TENANT_ID=... \
       AZURE_CLIENT_ID=... AZURE_CLIENT_SECRET=...
export AZURE_RESOURCE_GROUP=openenv-xxxxx AZURE_LOCATION=eastus
export ADO_PAT=<azure devops PAT>
export WINDOWS_ADMIN_PASSWORD='<Azure-complex password>'
export AAP_CONTROLLER_PASSWORD=<your AAP password>
# export DC1_AZURE_EE='<Windows-capable EE with terraform>'   # see callout
```

> **Execution environment:** the Provision/Configure/Teardown jobs need an EE
> that has the `terraform` binary, the `ansible.controller`/`ansible.platform`
> collections, and Windows (`pywinrm`) support. Set `DC1_AZURE_EE` to that EE's
> name on your AAP. The default `Default execution environment` will create the
> objects fine but will fail at *run* time if it lacks those tools.

> **Password sync (important):** the Windows admin password is needed in **two**
> places that must match — the `DC1.Azure - Windows Machine` credential (set
> from `WINDOWS_ADMIN_PASSWORD` here) and Terraform's `admin_password` at
> provision time. Supply the same value to the **Provision VM** and **Teardown**
> job templates as a vaulted extra var named `dc1_azure_windows_admin_password`
> (JT *Variables* field, or at launch). A future change may unify these.

## 6. Apply the configuration

```bash
ansible-playbook -i aap_config/inventory/ aap_config/load.yml
```

`load.yml` applies everything via `infra.aap_configuration.dispatch`, then
imports `validate.yml`, which queries the AAP API and **asserts every object
exists** — so a green run means the install is complete. Re-running is
idempotent.

## 7. Confirm and launch

In the AAP UI you should now see (all prefixed `DC1.Azure -`): 5 credentials,
2 projects (`DC1.Azure`, `aap.dailydemo.windows`), the `dc1-azure` inventory,
6 job templates, and the **`DC1.Azure - Provision and Configure`** workflow.

Launch that workflow, pick a `vm_size_tier` in the survey, and watch it
provision the Azure VM and run the configure chain.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `401 Unauthorized` during `load.yml` | bad/expired `AAP_TOKEN` | recreate the personal token (step 4) |
| `validate.yml` reports a MISSING object | dispatch skipped it (often a missing env var) | check the failed object's required env var; re-run |
| Validate hits `/api/v2/` not found | older AAP API path | `export DC1_AZURE_API_BASE=/api/v2` and re-run |
| Provision job fails: `terraform: not found` | EE lacks terraform | set `DC1_AZURE_EE` to a terraform-capable EE |
| Provision fails on `admin_password` complexity | weak `WINDOWS_ADMIN_PASSWORD` | 12–72 chars, 3 of upper/lower/digit/symbol |
| Configure steps can't authenticate (WinRM) | Windows Machine cred password ≠ Terraform admin_password, or username mismatch | sync the password (step 5 callout); keep `WINDOWS_ADMIN_USERNAME` = Terraform `admin_username` |
| Provision can't register host (`CONTROLLER_*` not set) | Controller credential not attached | confirm `DC1.Azure - Controller` is on the Provision/Teardown JTs |
| `ansible-galaxy` can't find `infra.aap_configuration` 4.4.0 | Hub token not configured | step 2 (`ansible.cfg.example` → `~/.ansible.cfg`) |

## Uninstall

The CaC is additive and namespaced `DC1.Azure -`. To remove, delete those named
objects in the AAP UI (or set `state: absent` per object and re-dispatch). The
`DC1.Azure - Teardown` job template destroys the Azure VM itself.

# Remote state backend — Azure Storage.
#
# Backend block is intentionally partial: pass concrete values at `terraform init`
# time so secrets don't land in version control. Example:
#
#   terraform init \
#     -backend-config="resource_group_name=REPLACE_ME_RHDP_RG" \
#     -backend-config="storage_account_name=REPLACE_ME_SA" \
#     -backend-config="container_name=tfstate" \
#     -backend-config="key=dc1.azure.tfstate"
#
# The storage account + container must exist before `init`. One-time bootstrap:
#
#   az group show --name REPLACE_ME_RHDP_RG                        # confirm RG
#   az storage account create \
#       --resource-group REPLACE_ME_RHDP_RG \
#       --name REPLACE_ME_SA --sku Standard_LRS --kind StorageV2
#   az storage container create \
#       --account-name REPLACE_ME_SA --name tfstate --auth-mode login
#
# For initial local smoke testing only, comment out the backend block below and
# state will live in `terraform.tfstate` next to these files (DO NOT commit it —
# `.gitignore` already excludes `*.tfstate*`).

terraform {
  backend "azurerm" {
    # values supplied via `-backend-config=...` at init time
    use_azuread_auth = true
  }
}

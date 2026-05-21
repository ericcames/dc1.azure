locals {
  # T-shirt tier → Azure SKU. All same family (Dsv5) for a clean "more cores" story.
  # Confirm RHDP open-env quota covers Standard_D8s_v5 (8 vCPU) before relying on `large`.
  vm_size_map = {
    small  = "Standard_D2s_v5" # 2 vCPU /  8 GB
    medium = "Standard_D4s_v5" # 4 vCPU / 16 GB
    large  = "Standard_D8s_v5" # 8 vCPU / 32 GB
  }

  vm_size = local.vm_size_map[var.vm_size_tier]

  # Short random suffix keeps names unique across repeated apply/destroy cycles
  # and across multiple SEs sharing the same RHDP env.
  name_suffix = random_string.suffix.result
  vm_name     = "dc1az-win-${var.vm_size_tier}-${local.name_suffix}"

  # Public-IP DNS labels and Azure resource names have tight character rules;
  # this strips anything weird from the suffix.
  dns_label = "dc1az-${var.vm_size_tier}-${local.name_suffix}"

  common_tags = merge(var.tags, {
    Tier     = var.vm_size_tier
    SKU      = local.vm_size
    Hostname = local.vm_name
  })
}

resource "random_string" "suffix" {
  length  = 5
  upper   = false
  special = false
  numeric = true
}

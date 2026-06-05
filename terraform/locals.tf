locals {
  # OS selection — drives count on per-VM resource blocks.
  create_windows = contains(["windows", "both"], var.os_type)
  create_linux   = contains(["linux", "both"], var.os_type)

  # T-shirt tier → Azure SKU. Keys match the AAP survey choices exactly.
  # All same family (Dsv5) for a clean "more cores" story. Same SKUs for both
  # Windows and Linux — the Linux base rate is ~half the Windows PAYG rate.
  # Confirm RHDP open-env quota covers Standard_D8s_v5 (8 vCPU) before relying on `large-8cpu-32gb`.
  vm_size_map = {
    "small-2cpu-8gb"   = "Standard_D2s_v5"
    "medium-4cpu-16gb" = "Standard_D4s_v5"
    "large-8cpu-32gb"  = "Standard_D8s_v5"
  }

  vm_size = local.vm_size_map[var.vm_size_tier]

  # Short random suffix keeps names unique across repeated apply/destroy cycles
  # and across multiple SEs sharing the same RHDP env.
  name_suffix = random_string.suffix.result

  # Windows naming
  vm_name   = "dc1az-win-${var.vm_size_tier}-${local.name_suffix}"
  dns_label = "dc1az-win-${var.vm_size_tier}-${local.name_suffix}"

  # Linux naming
  linux_vm_name   = "dc1az-lnx-${var.vm_size_tier}-${local.name_suffix}"
  linux_dns_label = "dc1az-lnx-${var.vm_size_tier}-${local.name_suffix}"

  common_tags = merge(var.tags, {
    Tier   = var.vm_size_tier
    SKU    = local.vm_size
    OSType = var.os_type
  })
}

resource "random_string" "suffix" {
  length  = 5
  upper   = false
  special = false
  numeric = true
}

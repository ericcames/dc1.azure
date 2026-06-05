output "os_type" {
  description = "OS type requested for this run."
  value       = var.os_type
}

# ---------------------------------------------------------------------------
# Windows outputs — null when os_type excludes windows.
# ---------------------------------------------------------------------------

output "windows_inventory" {
  description = "Windows VM inventory data for AAP host registration. Null when os_type excludes windows."
  value = local.create_windows ? {
    host           = azurerm_public_ip.demo[0].fqdn
    ansible_host   = azurerm_public_ip.demo[0].ip_address
    ansible_user   = var.admin_username
    vm_name        = azurerm_windows_virtual_machine.demo[0].name
    vm_size_tier   = var.vm_size_tier
    vm_size_chosen = local.vm_size
  } : null
}

# ---------------------------------------------------------------------------
# Linux outputs — null when os_type excludes linux.
# ---------------------------------------------------------------------------

output "linux_inventory" {
  description = "Linux VM inventory data for AAP host registration. Null when os_type excludes linux."
  value = local.create_linux ? {
    host           = azurerm_public_ip.linux[0].fqdn
    ansible_host   = azurerm_public_ip.linux[0].ip_address
    ansible_user   = var.linux_admin_username
    vm_name        = azurerm_linux_virtual_machine.linux[0].name
    vm_size_tier   = var.vm_size_tier
    vm_size_chosen = local.vm_size
  } : null
}


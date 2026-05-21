output "vm_name" {
  description = "Hostname assigned to the Windows VM."
  value       = azurerm_windows_virtual_machine.demo.name
}

output "vm_size_tier" {
  description = "T-shirt tier selected for this run."
  value       = var.vm_size_tier
}

output "vm_size_chosen" {
  description = "Resolved Azure SKU for the chosen tier."
  value       = local.vm_size
}

output "public_ip" {
  description = "Public IP address of the VM. Used by AAP to add_host into the windows group."
  value       = azurerm_public_ip.demo.ip_address
}

output "fqdn" {
  description = "Public DNS name of the VM (Azure-managed). Stable across reboots; IP may rotate on stop/start."
  value       = azurerm_public_ip.demo.fqdn
}

output "admin_username" {
  description = "Local Windows administrator username on the VM."
  value       = var.admin_username
}

output "ansible_inventory" {
  description = "JSON inventory snippet ready to pass into AAP via set_stats / add_host."
  value = {
    host           = azurerm_public_ip.demo.fqdn
    ansible_host   = azurerm_public_ip.demo.ip_address
    ansible_user   = var.admin_username
    vm_name        = azurerm_windows_virtual_machine.demo.name
    vm_size_tier   = var.vm_size_tier
    vm_size_chosen = local.vm_size
  }
}

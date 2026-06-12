# RHDP creates the RG for us. Reference it; never own it.
data "azurerm_resource_group" "rhdp" {
  name = var.resource_group_name
}

# ---------------------------------------------------------------------------
# Networking — VNet, single subnet, NSG.
# ---------------------------------------------------------------------------

resource "azurerm_virtual_network" "demo" {
  name                = "dc1az-vnet-${local.name_suffix}"
  address_space       = [var.vnet_cidr]
  location            = data.azurerm_resource_group.rhdp.location
  resource_group_name = data.azurerm_resource_group.rhdp.name
  tags                = local.common_tags
}

resource "azurerm_subnet" "demo" {
  name                 = "dc1az-subnet-${local.name_suffix}"
  resource_group_name  = data.azurerm_resource_group.rhdp.name
  virtual_network_name = azurerm_virtual_network.demo.name
  address_prefixes     = [var.subnet_cidr]
}

resource "azurerm_network_security_group" "demo" {
  name                = "dc1az-nsg-${local.name_suffix}"
  location            = data.azurerm_resource_group.rhdp.location
  resource_group_name = data.azurerm_resource_group.rhdp.name
  tags                = local.common_tags

  security_rule {
    name                       = "Allow-RDP"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefixes    = var.allowed_source_cidrs
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-WinRM-HTTPS"
    priority                   = 1010
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5986"
    source_address_prefixes    = var.allowed_source_cidrs
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-HTTP"
    priority                   = 1020
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefixes    = var.allowed_source_cidrs
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-HTTPS"
    priority                   = 1030
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefixes    = var.allowed_source_cidrs
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-ICMP"
    priority                   = 1040
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Icmp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefixes    = var.allowed_source_cidrs
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-SSH"
    priority                   = 1050
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefixes    = var.allowed_source_cidrs
    destination_address_prefix = "*"
  }

  # Cockpit web console (AB#173) — reachable over the Linux VM's public FQDN.
  # Scoped to allowed_source_cidrs like the other rules; the Linux VM also opens
  # the cockpit firewalld service (linux_configure, AB#172).
  security_rule {
    name                       = "Allow-Cockpit"
    priority                   = 1060
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "9090"
    source_address_prefixes    = var.allowed_source_cidrs
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "demo" {
  subnet_id                 = azurerm_subnet.demo.id
  network_security_group_id = azurerm_network_security_group.demo.id
}

# ---------------------------------------------------------------------------
# Windows — Public IP + NIC + VM + WinRM bootstrap.
# Created only when os_type includes "windows".
# ---------------------------------------------------------------------------

moved {
  from = azurerm_public_ip.demo
  to   = azurerm_public_ip.demo[0]
}

resource "azurerm_public_ip" "demo" {
  count               = local.create_windows ? 1 : 0
  name                = "dc1az-pip-${local.name_suffix}"
  location            = data.azurerm_resource_group.rhdp.location
  resource_group_name = data.azurerm_resource_group.rhdp.name
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = local.dns_label
  tags                = merge(local.common_tags, { OS = "windows", Hostname = local.vm_name })
}

moved {
  from = azurerm_network_interface.demo
  to   = azurerm_network_interface.demo[0]
}

resource "azurerm_network_interface" "demo" {
  count               = local.create_windows ? 1 : 0
  name                = "dc1az-nic-${local.name_suffix}"
  location            = data.azurerm_resource_group.rhdp.location
  resource_group_name = data.azurerm_resource_group.rhdp.name
  tags                = merge(local.common_tags, { OS = "windows" })

  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.demo.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.demo[0].id
  }
}

moved {
  from = azurerm_windows_virtual_machine.demo
  to   = azurerm_windows_virtual_machine.demo[0]
}

resource "azurerm_windows_virtual_machine" "demo" {
  count               = local.create_windows ? 1 : 0
  name                = local.vm_name
  location            = data.azurerm_resource_group.rhdp.location
  resource_group_name = data.azurerm_resource_group.rhdp.name
  size                = local.vm_size
  admin_username      = var.admin_username
  admin_password      = var.admin_password
  computer_name       = substr(replace(local.vm_name, ".", ""), 0, 15)

  network_interface_ids = [
    azurerm_network_interface.demo[0].id,
  ]

  patch_mode          = "AutomaticByPlatform"
  hotpatching_enabled = true

  source_image_reference {
    publisher = var.windows_image.publisher
    offer     = var.windows_image.offer
    sku       = var.windows_image.sku
    version   = var.windows_image.version
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = 128
  }

  custom_data = base64encode(file("${path.module}/scripts/winrm_bootstrap.ps1"))

  tags = merge(local.common_tags, { OS = "windows", Hostname = local.vm_name })
}

moved {
  from = azurerm_virtual_machine_extension.winrm_bootstrap
  to   = azurerm_virtual_machine_extension.winrm_bootstrap[0]
}

resource "azurerm_virtual_machine_extension" "winrm_bootstrap" {
  count                = local.create_windows ? 1 : 0
  name                 = "winrm-bootstrap"
  virtual_machine_id   = azurerm_windows_virtual_machine.demo[0].id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  settings = jsonencode({
    commandToExecute = "powershell -ExecutionPolicy Bypass -Command \"Copy-Item C:\\AzureData\\CustomData.bin C:\\AzureData\\bootstrap.ps1 -Force; & C:\\AzureData\\bootstrap.ps1\""
  })

  tags = merge(local.common_tags, { OS = "windows" })
}

# ---------------------------------------------------------------------------
# Linux — SSH key + Public IP + NIC + RHEL 9 VM.
# Created only when os_type includes "linux".
# ---------------------------------------------------------------------------

resource "azurerm_public_ip" "linux" {
  count               = local.create_linux ? 1 : 0
  name                = "dc1az-lnx-pip-${local.name_suffix}"
  location            = data.azurerm_resource_group.rhdp.location
  resource_group_name = data.azurerm_resource_group.rhdp.name
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = local.linux_dns_label
  tags                = merge(local.common_tags, { OS = "linux", Hostname = local.linux_vm_name })
}

resource "azurerm_network_interface" "linux" {
  count               = local.create_linux ? 1 : 0
  name                = "dc1az-lnx-nic-${local.name_suffix}"
  location            = data.azurerm_resource_group.rhdp.location
  resource_group_name = data.azurerm_resource_group.rhdp.name
  tags                = merge(local.common_tags, { OS = "linux" })

  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.demo.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.linux[0].id
  }
}

resource "azurerm_linux_virtual_machine" "linux" {
  count                           = local.create_linux ? 1 : 0
  name                            = local.linux_vm_name
  location                        = data.azurerm_resource_group.rhdp.location
  resource_group_name             = data.azurerm_resource_group.rhdp.name
  size                            = local.vm_size
  admin_username                  = var.linux_admin_username
  disable_password_authentication = true

  network_interface_ids = [
    azurerm_network_interface.linux[0].id,
  ]

  admin_ssh_key {
    username   = var.linux_admin_username
    public_key = var.linux_ssh_public_key
  }

  source_image_reference {
    publisher = var.linux_image.publisher
    offer     = var.linux_image.offer
    sku       = var.linux_image.sku
    version   = var.linux_image.version
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = 64
  }

  tags = merge(local.common_tags, { OS = "linux", Hostname = local.linux_vm_name })
}

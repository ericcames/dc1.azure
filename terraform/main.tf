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
}

resource "azurerm_subnet_network_security_group_association" "demo" {
  subnet_id                 = azurerm_subnet.demo.id
  network_security_group_id = azurerm_network_security_group.demo.id
}

# ---------------------------------------------------------------------------
# Public IP + NIC.
# ---------------------------------------------------------------------------

resource "azurerm_public_ip" "demo" {
  name                = "dc1az-pip-${local.name_suffix}"
  location            = data.azurerm_resource_group.rhdp.location
  resource_group_name = data.azurerm_resource_group.rhdp.name
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = local.dns_label
  tags                = local.common_tags
}

resource "azurerm_network_interface" "demo" {
  name                = "dc1az-nic-${local.name_suffix}"
  location            = data.azurerm_resource_group.rhdp.location
  resource_group_name = data.azurerm_resource_group.rhdp.name
  tags                = local.common_tags

  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.demo.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.demo.id
  }
}

# ---------------------------------------------------------------------------
# Windows Server 2025 VM with WinRM-HTTPS bootstrap via custom_data.
# ---------------------------------------------------------------------------

resource "azurerm_windows_virtual_machine" "demo" {
  name                = local.vm_name
  location            = data.azurerm_resource_group.rhdp.location
  resource_group_name = data.azurerm_resource_group.rhdp.name
  size                = local.vm_size
  admin_username      = var.admin_username
  admin_password      = var.admin_password
  computer_name       = substr(replace(local.vm_name, ".", ""), 0, 15) # 15-char NetBIOS limit

  network_interface_ids = [
    azurerm_network_interface.demo.id,
  ]

  # Windows Server 2025 Azure Edition is a hotpatch-enabled image. azurerm
  # v4.x requires patch_mode = AutomaticByPlatform for these images.
  patch_mode         = "AutomaticByPlatform"
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

  # Enable WinRM-HTTPS with a self-signed cert on first boot so Ansible can
  # connect. AAP's Windows machine credential should use winrm with
  # ansible_winrm_server_cert_validation=ignore in inventory group_vars.
  #
  # custom_data deposits the bootstrap script at C:\AzureData\CustomData.bin
  # but Azure does NOT auto-execute custom_data on Windows VMs. The
  # CustomScriptExtension below triggers execution.
  custom_data = base64encode(file("${path.module}/scripts/winrm_bootstrap.ps1"))

  tags = local.common_tags
}

# Custom Script Extension — triggers execution of the WinRM bootstrap script
# that custom_data deposited at C:\AzureData\CustomData.bin. The script copies
# the binary file to bootstrap.ps1, then executes it via the call operator.
resource "azurerm_virtual_machine_extension" "winrm_bootstrap" {
  name                 = "winrm-bootstrap"
  virtual_machine_id   = azurerm_windows_virtual_machine.demo.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  settings = jsonencode({
    commandToExecute = "powershell -ExecutionPolicy Bypass -Command \"Copy-Item C:\\AzureData\\CustomData.bin C:\\AzureData\\bootstrap.ps1 -Force; & C:\\AzureData\\bootstrap.ps1\""
  })

  tags = local.common_tags
}

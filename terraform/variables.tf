# ---------------------------------------------------------------------------
# Azure environment — values come from the RHDP Azure open environment.
# Real values go in terraform.tfvars (gitignored). See terraform.tfvars.example.
# ---------------------------------------------------------------------------

variable "resource_group_name" {
  description = "Name of the RHDP-provisioned Azure resource group. The VM and all dependent resources are created here. Never destroyed by terraform."
  type        = string
}

variable "location" {
  description = "Azure region. Use the region the RHDP open env was provisioned in (typically eastus or eastus2)."
  type        = string
  default     = "eastus"
}

# ---------------------------------------------------------------------------
# VM sizing — survey-driven t-shirt tier. Mapped to a real SKU in locals.tf.
# ---------------------------------------------------------------------------

variable "vm_size_tier" {
  description = "T-shirt size selected by the user in the AAP JT survey. Mapped to a Standard_Dsv5 SKU in locals.tf."
  type        = string
  default     = "medium-4cpu-16gb"

  validation {
    condition     = contains(["small-2cpu-8gb", "medium-4cpu-16gb", "large-8cpu-32gb"], var.vm_size_tier)
    error_message = "vm_size_tier must be one of: small-2cpu-8gb, medium-4cpu-16gb, large-8cpu-32gb."
  }
}

# ---------------------------------------------------------------------------
# Windows admin credentials — passed to the VM at create time.
# ---------------------------------------------------------------------------

variable "admin_username" {
  description = "Local Windows administrator username on the new VM."
  type        = string
  default     = "demoadmin"

  validation {
    condition     = !contains(["administrator", "admin", "user", "root", "guest"], lower(var.admin_username))
    error_message = "admin_username cannot be one of the reserved Windows names (administrator, admin, user, root, guest)."
  }
}

variable "admin_password" {
  description = "Local Windows administrator password. Must satisfy Azure password complexity: 12-72 chars, 3 of {upper, lower, digit, symbol}."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.admin_password) >= 12 && length(var.admin_password) <= 72
    error_message = "admin_password must be 12 to 72 characters."
  }
}

# ---------------------------------------------------------------------------
# Networking — kept simple for a single-VM demo.
# ---------------------------------------------------------------------------

variable "vnet_cidr" {
  description = "CIDR for the demo VNet."
  type        = string
  default     = "10.50.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR for the single subnet inside the demo VNet."
  type        = string
  default     = "10.50.1.0/24"
}

variable "allowed_source_cidrs" {
  description = "Source CIDRs allowed inbound to the VM for RDP / WinRM / HTTP. Default is open; tighten to the demo audience's egress IP for real use."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# ---------------------------------------------------------------------------
# Tagging — applied to every resource. Mirrors demo.datacenter conventions.
# ---------------------------------------------------------------------------

variable "tags" {
  description = "Common tags applied to every resource."
  type        = map(string)
  default = {
    Environment = "demo"
    Project     = "dc1.azure"
    Owner       = "ericcames"
    ManagedBy   = "terraform"
  }
}

# ---------------------------------------------------------------------------
# Windows image selection.
# ---------------------------------------------------------------------------

variable "windows_image" {
  description = "Marketplace image reference for the Windows VM. Default = Windows Server 2025 Datacenter Azure Edition."
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })
  default = {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2025-datacenter-azure-edition"
    version   = "latest"
  }
}

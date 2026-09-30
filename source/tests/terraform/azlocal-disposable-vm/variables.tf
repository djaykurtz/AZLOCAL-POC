variable "resource_group_name" {
  description = "Existing POC resource group. Terraform must not manage the resource group."
  type        = string
  default     = "rg-azlocal-poc-001"
}

variable "location" {
  description = "Azure Local control-plane region for the disposable VM resources."
  type        = string
  default     = "southcentralus"
}

variable "custom_location_id" {
  description = "Existing Azure Local custom location resource ID."
  type        = string
  sensitive   = false
}

variable "image_id" {
  description = "Existing Azure Local gallery or Marketplace image resource ID."
  type        = string
  sensitive   = false
}

variable "logical_network_id" {
  description = "Existing Azure Local logical network resource ID."
  type        = string
  sensitive   = false
}

variable "admin_username" {
  description = "Local administrator name for the Terraform-owned disposable VM."
  type        = string
  default     = "pocadmin"
}

variable "admin_password" {
  description = "Local administrator password supplied only at plan/apply time through a secure mechanism."
  type        = string
  sensitive   = true
}

variable "os_type" {
  description = "Guest OS family. The module builds a linuxConfiguration or a windowsConfiguration from this."
  type        = string
  default     = "Linux"

  validation {
    condition     = contains(["Linux", "Windows"], var.os_type)
    error_message = "os_type must be exactly Linux or Windows."
  }
}

variable "vm_name" {
  description = "Terraform-owned disposable VM name."
  type        = string
  default     = "tf-poc-linux-01"

  validation {
    condition     = can(regex("^tf-poc-[a-z0-9-]{1,50}$", var.vm_name))
    error_message = "vm_name must start with tf-poc- and contain only lowercase letters, digits, and hyphens."
  }
}

variable "v_cpu_count" {
  description = "Small disposable VM CPU allocation."
  type        = number
  default     = 1

  validation {
    condition     = var.v_cpu_count >= 1 && var.v_cpu_count <= 2
    error_message = "The first Terraform POC VM must use one or two vCPUs."
  }
}

variable "memory_mb" {
  description = "Small disposable VM memory allocation in MB."
  type        = number
  default     = 2048

  validation {
    condition     = var.memory_mb >= 1024 && var.memory_mb <= 4096
    error_message = "The first Terraform POC VM must use 1024 to 4096 MB of memory."
  }
}
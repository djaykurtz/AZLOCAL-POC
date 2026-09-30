module "disposable_vm" {
  source  = "Azure/avm-res-azurestackhci-virtualmachineinstance/azurerm"
  version = "2.1.1"

  name                = var.vm_name
  resource_group_name = var.resource_group_name
  location            = var.location
  custom_location_id  = var.custom_location_id
  image_id            = var.image_id
  logical_network_id  = var.logical_network_id
  admin_username      = var.admin_username
  admin_password      = var.admin_password

  os_type          = var.os_type
  v_cpu_count      = var.v_cpu_count
  memory_mb        = var.memory_mb
  dynamic_memory   = true
  enable_telemetry = false

  tags = {
    managedBy = "terraform"
    purpose   = "azure-local-poc-capstone"
    ownership = "terraform-only"
  }
}
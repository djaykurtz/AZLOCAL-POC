output "vm_resource" {
  description = "Sanitized module output for the Terraform-owned disposable VM."
  value       = module.disposable_vm.resource_id
}
output "vm_id" {
  description = "Windows VM ID"
  value       = proxmox_virtual_environment_vm.windows_vm[0].vm_id
}

output "vm_name" {
  description = "Windows VM name"
  value       = proxmox_virtual_environment_vm.windows_vm[0].name
}

output "ip_address" {
  description = "Windows management IP"
  value       = split("/", var.ip_address)[0]
}
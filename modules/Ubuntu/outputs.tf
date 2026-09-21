output "vm_id" {
  value = proxmox_virtual_environment_vm.ubuntu_vm[0].vm_id
}

output "vm_name" {
  value = proxmox_virtual_environment_vm.ubuntu_vm[0].name
}

output "ip_address" {
  value = var.ip_address
}
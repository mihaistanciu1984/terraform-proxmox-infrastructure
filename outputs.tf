
output "ubuntu_vm_ids" {
  description = "VM IDs of the Ubuntu virtual machines"

  value = {
    for vm_name, vm in module.ubuntu_server :
    vm_name => vm.vm_id
  }
}

output "ubuntu_vm_names" {
  description = "Names of the Ubuntu virtual machines"

  value = {
    for vm_name, vm in module.ubuntu_server :
    vm_name => vm.vm_name
  }
}

output "ubuntu_management_ips" {
  description = "Management IP addresses of the Ubuntu virtual machines"

  value = {
    for vm_name, vm in module.ubuntu_server :
    vm_name => vm.ip_address
  }
}
output "windows_management_ips" {
  description = "Management IP addresses of Windows virtual machines"

  value = {
    for vm_name, vm in module.windows_server :
    vm_name => vm.ip_address
  }
}

output "windows_vm_ids" {
  description = "VM IDs of Windows virtual machines"

  value = {
    for vm_name, vm in module.windows_server :
    vm_name => vm.vm_id
  }
}

output "windows_vm_names" {
  description = "Names of Windows virtual machines"

  value = {
    for vm_name, vm in module.windows_server :
    vm_name => vm.vm_name
  }
}
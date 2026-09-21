
# ============================================================
# UBUNTU MODULE
# ============================================================

module "ubuntu_server" {
  for_each = var.create_ubuntu ? var.ubuntu_vms : {}

  source = "./modules/Ubuntu"

  vm_name       = each.key
  vm_id         = each.value.vm_id
  ip_address    = each.value.ip_address
  node_name     = "proxmox-lab"
  create_ubuntu = true
}

# ============================================================
# WINDOWS MODULE
# ============================================================

module "windows_server" {
  for_each = var.create_windows ? var.windows_vms : {}

  source = "./modules/Windows"

  vm_name          = each.key
  vm_id            = each.value.vm_id
  template_id      = each.value.template_id
  ip_address       = each.value.ip_address
  windows_username = each.value.windows_username
  windows_password = var.vm_check_password
  create_windows   = true
}

# ============================================================
# ANSIBLE CONFIGURATION - UBUNTU
# ============================================================

resource "terraform_data" "ubuntu_ansible_configuration" {
  for_each = module.ubuntu_server

  depends_on = [
    module.ubuntu_server
  ]

  triggers_replace = [
    each.value.vm_id,
    each.value.vm_name,
    each.value.ip_address,
  ]

  provisioner "local-exec" {
    working_dir = path.module

    command = "wsl.exe --cd /mnt/c/Users/example-user/Documents/DEV/terraform/terraform-proxmox/ansible env ANSIBLE_CONFIG=/mnt/c/Users/example-user/Documents/DEV/terraform/terraform-proxmox/ansible/ansible.cfg ansible-playbook -i inventory/hosts.yml -i inventory/generated_ubuntu.yml playbooks/configure_ubuntu.yml --limit ${each.key} --extra-vars ansible_host=${split("/", each.value.ip_address)[0]}"
  }
}

# ============================================================
# VM CHECK - WINDOWS
# ============================================================

resource "terraform_data" "windows_vm_check" {
  for_each = module.windows_server

  depends_on = [
    module.windows_server
  ]

  triggers_replace = [
    each.value.vm_id,
    each.value.vm_name,
    each.value.ip_address,
  ]

  provisioner "local-exec" {
    working_dir = path.module

    command = "python Scripts/vm_check.py --os windows --ip ${each.value.ip_address} --user ${var.windows_vms[each.key].windows_username}"

    environment = {
      VM_CHECK_PASSWORD = var.vm_check_password
      PYTHONIOENCODING  = "utf-8"
    }
  }
}

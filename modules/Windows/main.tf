resource "proxmox_virtual_environment_vm" "windows_vm" {
  count     = var.create_windows ? 1 : 0
  name      = var.vm_name
  node_name = "proxmox-lab"
  vm_id     = var.vm_id

  timeout_clone = 3600

  agent {
    enabled = true
  }

  clone {
    vm_id   = var.template_id
    full    = false
    retries = 3
  }

  machine = "q35"

  cpu {
    cores = 6
    type  = "host"
  }

  memory {
    dedicated = 20480
  }

  operating_system {
    type = "win11"
  }

  bios = "ovmf"

    vga {
    type = "std"
  }

  network_device {
    bridge = "vmbr0"
  }

  network_device {
    bridge = "vmbr1"
  }

  initialization {
    interface = "sata0"

    ip_config {
      ipv4 {
        address = var.ip_address
      }
    }
    user_account {
      username = var.windows_username
      password = var.windows_password
    }
  }
}

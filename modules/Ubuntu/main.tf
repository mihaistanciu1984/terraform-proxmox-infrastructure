resource "proxmox_virtual_environment_vm" "ubuntu_vm" {
  count = var.create_ubuntu ? 1 : 0

  name      = var.vm_name
  node_name = var.node_name
  vm_id     = var.vm_id

  started = true
  on_boot = true

  timeout_clone = 3600

  clone {
    vm_id   = var.template_id
    full    = true
    retries = 3
  }

  agent {
    enabled = true
  }

  cpu {
    cores = 2
    type  = "host"
  }

  memory {
    dedicated = 16384
  }

  vga {
    type = "std"
  }

  # net0: Management, IP static, fără gateway
  network_device {
    bridge = "vmbr0"
    model  = "virtio"
  }

  # net1: Internet, DHCP
  network_device {
    bridge = "vmbr1"
    model  = "virtio"
  }

  initialization {
    # ipconfig0 → net0 → vmbr0
    ip_config {
      ipv4 {
        address = var.ip_address
      }
    }

    # ipconfig1 → net1 → vmbr1
    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }
  }
}
variable "create_ubuntu" {
  type        = bool
  default     = false
  description = "Set to true to create the Ubuntu VM"
}

variable "ubuntu_vms" {
  description = "Ubuntu virtual machines managed by Terraform"

  type = map(object({
    vm_id      = number
    ip_address = string
  }))

  default = {}
}

variable "create_windows" {
  type        = bool
  default     = true
  description = "Set to true to create the Windows VMs"
}

variable "windows_vms" {
  description = "Windows virtual machines managed by Terraform"

  type = map(object({
    vm_id            = number
    template_id      = number
    ip_address       = string
    windows_username = string
  }))

  default = {}
}
variable "vm_check_password" {
  description = "Password used by VM connectivity checks"
  type        = string
  sensitive   = true
}

variable "windows_username" {
  description = "Windows local user used for VM checks"
  type        = string
}
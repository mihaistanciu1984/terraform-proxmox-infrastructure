variable "create_ubuntu" {
  description = "Create the Ubuntu VM"
  type        = bool
  default     = false
}

variable "node_name" {
  description = "proxmox-lab"
  type        = string
}

variable "template_id" {
  description = "Ubuntu template VM ID"
  type        = number
  default     = 8000
}

variable "vm_name" {
  description = "Ubuntu VM name"
  type        = string
}

variable "vm_id" {
  description = "Ubuntu VM ID"
  type        = number
}

variable "ip_address" {
  description = "Static management IP with CIDR"
  type        = string
}
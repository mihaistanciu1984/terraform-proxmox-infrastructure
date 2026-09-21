variable "vm_name" {
  type    = string
  default = "windows11-25H3"
}

variable "vm_id" {
  type    = number
  default = 312
}

variable "ip_address" {
  type    = string
  default = "192.0.2.143/24"
}

variable "create_windows" {
  type        = bool
  default     = true
  description = "Controleaza crearea VM-ului de Windows"
}

variable "windows_username" {
  description = "Windows local user used for VM checks"
  type        = string
}

variable "template_id" {
  description = "Proxmox template VM ID used for cloning"
  type        = number
}

variable "windows_password" {
  description = "Password supplied to Windows through Cloudbase-Init"
  type        = string
  sensitive   = true
}
#Create only windows
#terraform apply -var="create_windows=true" -var="create_ubuntu=false"
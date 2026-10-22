variable "enabled" {
  type        = bool
  default     = false
  description = <<-EOT
    Deploy Panorama. Defaults to false so the template is usable without
    Panorama; set to true when centralised management is required.
  EOT
}

variable "name" {
  type        = string
  default     = "pano01"
  description = "Panorama VM name."
}

variable "location" {
  type        = string
  description = "Azure region, e.g. \"westeurope\"."
}

variable "resource_group_name" {
  type        = string
  description = "Resource group for Panorama, normally the firewall pair's resource group."
}

variable "subnet_id" {
  type        = string
  description = "Management subnet ID for the Panorama interface."
}

variable "subnet_cidr" {
  type        = string
  description = "CIDR of the management subnet, combined with ip_offset to compute the interface address."

  validation {
    condition     = can(cidrhost(var.subnet_cidr, 0))
    error_message = "subnet_cidr must be a valid IPv4 CIDR, e.g. 10.0.3.0/24."
  }
}

variable "ip_offset" {
  type        = number
  default     = 250
  description = "Host offset of the Panorama management address inside subnet_cidr."

  validation {
    condition     = can(cidrhost(var.subnet_cidr, var.ip_offset))
    error_message = "ip_offset must be a valid host offset inside subnet_cidr."
  }
}

variable "dns_name" {
  type        = string
  description = "DNS label for the Panorama public IP, e.g. \"pano01-dc1\" gives pano01-dc1.<region>.cloudapp.azure.com."
}

variable "vm_size" {
  type        = string
  default     = "Standard_F16s_v2"
  description = "Panorama VM size."
}

variable "image" {
  type = object({
    publisher = optional(string, "paloaltonetworks")
    offer     = optional(string, "panorama")
    sku       = optional(string, "byol")
    version   = optional(string, "latest")
  })
  default     = {}
  description = "Marketplace image."
}

variable "data_disk_size_gb" {
  type        = number
  default     = 2048
  description = "Size of the Panorama logging data disk, which this module creates and attaches."
}

variable "admin_username" {
  type        = string
  description = "Local admin user."
}

variable "admin_password" {
  type        = string
  sensitive   = true
  description = "Local admin password. Supply from a secret store."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to every resource."
}

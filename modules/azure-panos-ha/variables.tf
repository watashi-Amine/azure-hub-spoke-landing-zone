variable "location" {
  type        = string
  description = "Azure region, e.g. \"westeurope\"."
}

variable "resource_group" {
  type = object({
    name   = string
    create = optional(bool, true)
  })
  description = "Resource group for the firewall pair. create = false references an existing one."
}

variable "firewalls" {
  type = map(object({
    name       = string
    is_primary = bool
  }))
  description = <<-EOT
    The firewall pair, keyed by a short logical key (e.g. "fw01").
    Exactly two entries, exactly one with is_primary = true.
  EOT

  validation {
    condition     = length(var.firewalls) == 2
    error_message = "Exactly two firewalls must be supplied (HA pair)."
  }

  validation {
    condition     = length([for fw in values(var.firewalls) : fw if fw.is_primary]) == 1
    error_message = "Exactly one firewall must have is_primary = true."
  }
}

variable "interfaces" {
  type = map(object({
    subnet_id              = string
    subnet_cidr            = string
    primary_ip_offset      = number
    secondary_ip_offset    = number
    public_ip              = optional(bool, false)
    ip_forwarding          = optional(bool, true)
    accelerated_networking = optional(bool, true)
  }))
  description = <<-EOT
    Firewall interfaces keyed by role: normally mgmt, outside, local, ha.

    Each interface states its own IP offsets, so no offset is hardcoded in the
    module and no interface depends on its position in a list.

    Example:
      {
        mgmt    = { subnet_id = "...", subnet_cidr = "10.0.3.0/24", primary_ip_offset = 4, secondary_ip_offset = 5, public_ip = true, ip_forwarding = false, accelerated_networking = false }
        outside = { subnet_id = "...", subnet_cidr = "10.0.2.0/24", primary_ip_offset = 4, secondary_ip_offset = 5 }
        local   = { subnet_id = "...", subnet_cidr = "10.0.1.0/24", primary_ip_offset = 4, secondary_ip_offset = 5 }
        ha      = { subnet_id = "...", subnet_cidr = "10.0.4.0/24", primary_ip_offset = 4, secondary_ip_offset = 5, ip_forwarding = false, accelerated_networking = false }
      }
  EOT

  validation {
    condition     = alltrue([for i in values(var.interfaces) : can(cidrhost(i.subnet_cidr, i.primary_ip_offset))])
    error_message = "primary_ip_offset must be a valid host offset inside its subnet_cidr."
  }

  validation {
    condition     = alltrue([for i in values(var.interfaces) : can(cidrhost(i.subnet_cidr, i.secondary_ip_offset))])
    error_message = "secondary_ip_offset must be a valid host offset inside its subnet_cidr."
  }

  validation {
    condition     = alltrue([for i in values(var.interfaces) : i.primary_ip_offset != i.secondary_ip_offset])
    error_message = "primary_ip_offset and secondary_ip_offset must differ on every interface."
  }
}

variable "interface_order" {
  type        = list(string)
  default     = ["mgmt", "outside", "local", "ha"]
  description = <<-EOT
    NIC attachment order, which PAN-OS uses to map eth0, eth1, eth2, ...

    The previous implementation hardcoded this order twice, inside the VM
    resource, so the mapping was easy to break silently. Here it is one input,
    validated against the interface keys, and it is the single source of truth.
  EOT

  validation {
    condition     = sort(var.interface_order) == sort(keys(var.interfaces))
    error_message = "interface_order must list exactly the keys of var.interfaces, once each."
  }
}

variable "public_ip_dns_prefix" {
  type        = string
  description = "DNS label prefix for internet-facing interface public IPs, e.g. \"fw-dc1\" gives fw-dc1-fw01-mgmt."
}

variable "vm_size" {
  type        = string
  default     = "Standard_DS3_v2"
  description = "Firewall VM size."
}

variable "image" {
  type = object({
    publisher = optional(string, "paloaltonetworks")
    offer     = optional(string, "vmseries1")
    sku       = optional(string, "byol")
    version   = optional(string, "latest")
  })
  default     = {}
  description = "Marketplace image. sku \"byol\" needs a licence configured on the device after deployment."
}

variable "admin_username" {
  type        = string
  description = "Local admin user for the firewalls."
}

variable "admin_password" {
  type        = string
  sensitive   = true
  description = "Local admin password. Supply from a secret store, never in a tfvars file committed to git."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to every resource."
}

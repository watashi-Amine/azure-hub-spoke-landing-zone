variable "name" {
  type        = string
  description = "Full name of the virtual network, e.g. \"vnet-hub-dc1\". The caller owns naming."
}

variable "location" {
  type        = string
  description = "Azure region, e.g. \"westeurope\"."
}

variable "resource_group" {
  type = object({
    name   = string
    create = optional(bool, true)
  })
  description = <<-EOT
    Resource group for the virtual network.
    Set create = true (default) to have this module create it, or false to reference an existing one.
  EOT
}

variable "address_space" {
  type        = list(string)
  description = "One or more IPv4 CIDR blocks for the virtual network, e.g. [\"10.0.0.0/20\"]."

  validation {
    condition     = length(var.address_space) > 0
    error_message = "address_space must contain at least one CIDR block."
  }

  validation {
    condition     = alltrue([for cidr in var.address_space : can(cidrhost(cidr, 0))])
    error_message = "Every address_space entry must be a valid IPv4 CIDR, e.g. 10.0.0.0/20."
  }
}

variable "subnets" {
  type = map(object({
    cidr                                          = string
    private_endpoint_network_policies             = optional(string, "Disabled")
    private_link_service_network_policies_enabled = optional(bool, true)
    service_endpoints                             = optional(list(string), [])
    delegation = optional(map(object({
      name    = string
      actions = optional(list(string), null)
    })), {})
  }))
  default     = {}
  description = <<-EOT
    Subnets keyed by their FULL subnet name (the map key becomes the subnet name).

    private_endpoint_network_policies accepts Azure's native values:
    "Disabled", "Enabled", "NetworkSecurityGroupEnabled", "RouteTableEnabled".
    The default here is "Disabled" so that private endpoints work out of the box;
    Azure's own default for the same property is "Enabled".

    Example:
      {
        "snet-hub-local" = { cidr = "10.0.4.0/24", private_endpoint_network_policies = "Enabled" }
      }
  EOT

  validation {
    condition     = alltrue([for s in values(var.subnets) : can(cidrhost(s.cidr, 0))])
    error_message = "Every subnet cidr must be a valid IPv4 CIDR, e.g. 10.0.4.0/24."
  }

  validation {
    condition = alltrue([
      for s in values(var.subnets) :
      contains(["Disabled", "Enabled", "NetworkSecurityGroupEnabled", "RouteTableEnabled"], s.private_endpoint_network_policies)
    ])
    error_message = "private_endpoint_network_policies must be one of: Disabled, Enabled, NetworkSecurityGroupEnabled, RouteTableEnabled."
  }
}

variable "dns_servers" {
  type        = list(string)
  default     = []
  description = "Custom DNS servers for the virtual network. Leave empty to use Azure-provided DNS."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to every resource created by this module."
}

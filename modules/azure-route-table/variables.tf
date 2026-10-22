variable "location" {
  type        = string
  description = "Azure region, e.g. \"westeurope\"."
}

variable "resource_group_name" {
  type        = string
  description = "Resource group in which the route tables are created."
}

variable "route_tables" {
  type = map(object({
    name                          = string
    subnet_id                     = string
    bgp_route_propagation_enabled = optional(bool, false)
    associate                     = optional(bool, true)
  }))
  default     = {}
  description = <<-EOT
    Route tables keyed by a logical key, each bound to one subnet.

    The caller owns the route table name, so naming conventions live in the
    root module instead of being baked into a shared module.

    bgp_route_propagation_enabled defaults to false: spoke subnets must not
    learn routes around the firewall. Set it to true for hub subnets that need
    BGP/ExpressRoute-learned prefixes propagated.

    Example:
      {
        sb1 = { name = "rt-snet-sb1", subnet_id = module.vnet.subnet_ids["snet-sb1"] }
      }
  EOT
}

variable "routes" {
  type = map(map(object({
    address_prefix         = string
    next_hop_type          = string
    next_hop_in_ip_address = optional(string, null)
  })))
  default     = {}
  description = <<-EOT
    Routes nested as { route table key => { route name => route } }.

    Each route is a typed object. No "Snet-NextHopType-NextHopAddress" string
    keys, which have to be parsed with split("-") and therefore mis-split any
    name containing a hyphen.

    next_hop_type must be one of: VirtualNetworkGateway, VnetLocal, Internet,
    VirtualAppliance, None. next_hop_in_ip_address is required (and only valid)
    when next_hop_type = "VirtualAppliance".

    Example:
      {
        sb1 = {
          default = { address_prefix = "0.0.0.0/0", next_hop_type = "VirtualAppliance", next_hop_in_ip_address = "10.0.4.253" }
        }
      }
  EOT

  validation {
    condition = alltrue([
      for table_key in keys(var.routes) : contains(keys(var.route_tables), table_key)
    ])
    error_message = "Every key in var.routes must also exist in var.route_tables."
  }

  validation {
    condition = alltrue(flatten([
      for table_routes in values(var.routes) : [
        for route in values(table_routes) : contains(
          ["VirtualNetworkGateway", "VnetLocal", "Internet", "VirtualAppliance", "None"],
          route.next_hop_type
        )
      ]
    ]))
    error_message = "next_hop_type must be one of: VirtualNetworkGateway, VnetLocal, Internet, VirtualAppliance, None."
  }

  validation {
    condition = alltrue(flatten([
      for table_routes in values(var.routes) : [
        for route in values(table_routes) :
        route.next_hop_type == "VirtualAppliance" ? route.next_hop_in_ip_address != null : route.next_hop_in_ip_address == null
      ]
    ]))
    error_message = "next_hop_in_ip_address must be set when next_hop_type is VirtualAppliance, and must be null otherwise."
  }

  validation {
    condition = alltrue(flatten([
      for table_routes in values(var.routes) : [
        for route in values(table_routes) : can(cidrhost(route.address_prefix, 0))
      ]
    ]))
    error_message = "Every route address_prefix must be a valid IPv4 CIDR."
  }

  validation {
    condition = alltrue([
      for table_routes in values(var.routes) :
      length(distinct([for route in values(table_routes) : route.address_prefix])) == length(values(table_routes))
    ])
    error_message = "Two routes in the same route table share an address_prefix. Azure rejects duplicate prefixes in one table."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to the route tables."
}

variable "local" {
  type = object({
    name                = string
    resource_group_name = string
    id                  = string
  })
  description = "The virtual network on the side that owns the provider passed as `azurerm`."
}

variable "remote" {
  type = object({
    name                = string
    resource_group_name = string
    id                  = string
    address_space       = list(string)
  })
  description = <<-EOT
    The virtual network on the side that owns the provider passed as `azurerm.peer`.

    address_space is required because callers route towards the peered network;
    returning it from this module removes the need to retype CIDRs elsewhere.
  EOT
}

variable "allow_virtual_network_access" {
  type        = bool
  default     = true
  description = "Allow traffic between the two virtual networks. Must be true for the peering to carry traffic."
}

variable "allow_forwarded_traffic" {
  type        = bool
  default     = true
  description = <<-EOT
    Allow traffic forwarded by a network virtual appliance (the firewall).
    This must be true on BOTH directions or the firewall's forwarded packets
    are silently dropped even when every route table is correct.
  EOT
}

variable "allow_gateway_transit" {
  type        = bool
  default     = false
  description = "Allow the remote network to use this network's virtual network gateway. Requires a gateway on the local side."
}

variable "use_remote_gateways" {
  type        = bool
  default     = false
  description = "Use the remote network's virtual network gateway from this side. Requires allow_gateway_transit = true on the remote peering."
}

variable "create_remote" {
  type        = bool
  default     = true
  description = <<-EOT
    Create the reverse peering as well. Defaults to true so both directions
    exist; set to false when the remote side is managed elsewhere (a partner
    subscription, for example) and only the local direction is ours.
  EOT
}

variable "name_prefix" {
  type        = string
  default     = "peer"
  description = "Prefix for the peering names, which become \"<prefix>-<local>-<remote>\"."
}

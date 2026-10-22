variable "location" {
  type        = string
  description = "Azure region, e.g. \"westeurope\"."
}

variable "resource_group_name" {
  type        = string
  description = "Resource group in which the NSGs are created."
}

variable "subnets" {
  type = map(object({
    id        = string
    associate = optional(bool, true)
  }))
  default     = {}
  description = <<-EOT
    Subnets that receive an NSG, keyed by their FULL subnet name.
    The network security group is named "<nsg_name_prefix><subnet key>", e.g. "nsg-snet-sb1".
    Set associate = false to create the NSG without attaching it to the subnet.
  EOT
}

variable "nsg_name_prefix" {
  type        = string
  default     = "nsg-"
  description = "Prefix prepended to the subnet key to form the NSG name."
}

variable "rules" {
  type = map(map(object({
    priority                     = number
    direction                    = string
    access                       = string
    protocol                     = string
    source_port_range            = optional(string, "*")
    destination_port_range       = optional(string, "*")
    source_address_prefixes      = optional(list(string), ["*"])
    destination_address_prefixes = optional(list(string), ["*"])
    description                  = optional(string, null)
  })))
  default     = {}
  description = <<-EOT
    Security rules nested as { subnet key => { rule name => rule } }.

    Nesting rules under the subnet key removes the need to build composite
    string keys, which have to be split apart again on read and mangle any
    name that already contains a hyphen.

    Rules are created as separate azurerm_network_security_rule resources
    (not inline), so they can be managed and reordered without touching the NSG.

    Example:
      {
        "snet-sb4" = {
          "allow-fw-in"  = { priority = 4000, direction = "Inbound",  access = "Allow", protocol = "*", source_address_prefixes = ["10.0.4.253"] }
        }
      }
  EOT

  validation {
    condition = alltrue([
      for subnet_key, subnet_rules in var.rules : contains(keys(var.subnets), subnet_key)
    ])
    error_message = "Every key in var.rules must also exist in var.subnets."
  }

  validation {
    condition = alltrue(flatten([
      for subnet_rules in values(var.rules) : [
        for rule in values(subnet_rules) : rule.priority >= 100 && rule.priority <= 4096
      ]
    ]))
    error_message = "Rule priorities must be between 100 and 4096 inclusive."
  }

  validation {
    condition = alltrue([
      for subnet_rules in values(var.rules) :
      length(distinct([for rule in values(subnet_rules) : rule.priority])) == length(values(subnet_rules))
    ])
    error_message = "Two rules attached to the same subnet share a priority. Priorities must be unique per NSG."
  }

  validation {
    condition = alltrue(flatten([
      for subnet_rules in values(var.rules) : [
        for rule in values(subnet_rules) : contains(["Inbound", "Outbound"], rule.direction)
      ]
    ]))
    error_message = "Rule direction must be \"Inbound\" or \"Outbound\"."
  }

  validation {
    condition = alltrue(flatten([
      for subnet_rules in values(var.rules) : [
        for rule in values(subnet_rules) : contains(["Allow", "Deny"], rule.access)
      ]
    ]))
    error_message = "Rule access must be \"Allow\" or \"Deny\"."
  }

  validation {
    condition = alltrue(flatten([
      for subnet_rules in values(var.rules) : [
        for rule in values(subnet_rules) : contains(["*", "Tcp", "Udp", "Icmp"], rule.protocol)
      ]
    ]))
    error_message = "Rule protocol must be one of: *, Tcp, Udp, Icmp."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to the NSGs."
}

variable "name" {
  type        = string
  description = "Full name of the load balancer."
}

variable "location" {
  type        = string
  description = "Azure region. No default, so the load balancer cannot land in a region nobody chose."
}

variable "resource_group_name" {
  type        = string
  description = "Resource group in which the load balancer and its public IPs are created."
}

variable "vnet_resource_group_name" {
  type        = string
  description = "Resource group of the virtual network holding the private frontend subnet. Required, with no default, so the value cannot silently fall back to an environment-specific resource group."
}

variable "virtual_network_name" {
  type        = string
  description = "Name of the virtual network holding the private frontend subnet."
}

variable "sku" {
  type        = string
  default     = "Standard"
  description = "Load balancer SKU. This module targets Standard."
}

variable "sku_tier" {
  type        = string
  default     = "Regional"
  description = "Regional or Global."
}

variable "zones" {
  type        = list(string)
  default     = ["1", "2", "3"]
  description = "Availability zones for the frontend public IPs. Override for regions without three zones."
}

variable "frontend_public_ips" {
  type = map(object({
    ip_name       = string
    outbound_rule = optional(bool, false)
    reverse_fqdn  = optional(string, null)
    rules = optional(map(object({
      rule_name         = string
      protocol          = string
      frontend_port     = number
      backend_port      = number
      probe_config_name = string
      enable_float_ip   = optional(bool, false)
      disable_out_snat  = optional(bool, true)
    })), {})
  }))
  default     = {}
  description = "Public frontend IPs keyed by a logical name."
}

variable "frontend_private_ips" {
  type = map(object({
    ip_name                    = string
    subnet_id                  = string
    private_ip_address         = optional(string, null)
    private_ip_address_version = optional(string, "IPv4")
    rules = optional(map(object({
      rule_name         = string
      protocol          = string
      frontend_port     = number
      backend_port      = number
      probe_config_name = string
      enable_float_ip   = optional(bool, false)
      disable_out_snat  = optional(bool, true)
    })), {})
  }))
  default     = {}
  description = "Private frontend IPs keyed by a logical name (used for the egress load balancer)."
}

variable "backend_pool_name" {
  type        = string
  description = "Name of the backend address pool."
}

variable "backend_servers" {
  type = map(object({
    network_interface_id   = string
    ip_configuration_name  = string
  }))
  description = "Backend members keyed by a logical name."
}

variable "probes" {
  type = map(object({
    probe_name          = string
    protocol            = string
    port                = number
    request_path        = optional(string, null)
    interval_in_seconds = optional(number, null)
    number_of_probes    = optional(number, null)
  }))
  default     = {}
  description = "Health probes keyed by the name rules reference in probe_config_name."
}

variable "default_interval_in_seconds" {
  type        = number
  default     = 15
  description = "Probe interval used when a probe does not set its own."
}

variable "default_number_of_probes" {
  type        = number
  default     = 2
  description = "Failure threshold used when a probe does not set its own."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to every resource."
}

locals {
  frontends = merge(var.frontend_public_ips, var.frontend_private_ips)

  # Direct attribute access (frontend.ip_name) rather than the splat form
  # (a.*.ip_name[0]): same values, readable and type-safe.
  rules_list = flatten([
    for frontend_key, frontend in local.frontends : [
      for rule_key, rule in frontend.rules : {
        frontend_key      = frontend_key
        ip_name           = frontend.ip_name
        rule_name         = "${frontend.ip_name}.${rule.rule_name}"
        protocol          = rule.protocol
        frontend_port     = rule.frontend_port
        backend_port      = rule.backend_port
        probe_config_name = rule.probe_config_name
        enable_float_ip   = rule.enable_float_ip
        disable_out_snat  = rule.disable_out_snat
      }
    ]
  ])

  rules_by_name = { for rule in local.rules_list : rule.rule_name => rule }

  outbound_ip_names = [for frontend in values(var.frontend_public_ips) : frontend.ip_name if frontend.outbound_rule]
}

resource "azurerm_public_ip" "this" {
  for_each = var.frontend_public_ips

  name                = each.value.ip_name
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = var.zones
  reverse_fqdn        = each.value.reverse_fqdn
  domain_name_label   = each.value.reverse_fqdn != null ? regex("^[^.]*", each.value.reverse_fqdn) : null
  tags                = var.tags
}

resource "azurerm_lb" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = var.sku
  sku_tier            = var.sku_tier
  tags                = var.tags

  dynamic "frontend_ip_configuration" {
    for_each = azurerm_public_ip.this
    content {
      name                 = frontend_ip_configuration.value.name
      public_ip_address_id = frontend_ip_configuration.value.id
    }
  }

  dynamic "frontend_ip_configuration" {
    for_each = var.frontend_private_ips
    content {
      name                          = frontend_ip_configuration.value.ip_name
      subnet_id                     = frontend_ip_configuration.value.subnet_id
      private_ip_address            = frontend_ip_configuration.value.private_ip_address
      private_ip_address_version    = frontend_ip_configuration.value.private_ip_address_version
      private_ip_address_allocation = frontend_ip_configuration.value.private_ip_address != null ? "Static" : "Dynamic"
    }
  }
}

resource "azurerm_lb_backend_address_pool" "this" {
  name            = var.backend_pool_name
  loadbalancer_id = azurerm_lb.this.id
}

resource "azurerm_network_interface_backend_address_pool_association" "this" {
  for_each = var.backend_servers

  network_interface_id    = each.value.network_interface_id
  ip_configuration_name   = each.value.ip_configuration_name
  backend_address_pool_id = azurerm_lb_backend_address_pool.this.id
}

resource "azurerm_lb_probe" "this" {
  for_each = var.probes

  loadbalancer_id     = azurerm_lb.this.id
  name                = each.value.probe_name
  protocol            = each.value.protocol
  port                = each.value.port
  request_path        = contains(["http", "https"], lower(each.value.protocol)) ? each.value.request_path : null
  interval_in_seconds = coalesce(each.value.interval_in_seconds, var.default_interval_in_seconds)
  number_of_probes    = coalesce(each.value.number_of_probes, var.default_number_of_probes)
}

resource "azurerm_lb_rule" "this" {
  for_each = local.rules_by_name

  loadbalancer_id                = azurerm_lb.this.id
  name                           = each.value.rule_name
  protocol                       = each.value.protocol
  frontend_port                  = each.value.frontend_port
  backend_port                   = each.value.backend_port
  probe_id                       = azurerm_lb_probe.this[each.value.probe_config_name].id
  frontend_ip_configuration_name = each.value.ip_name
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.this.id]
  enable_floating_ip             = each.value.enable_float_ip
  disable_outbound_snat          = each.value.disable_out_snat

  depends_on = [azurerm_lb_probe.this]
}

resource "azurerm_lb_outbound_rule" "this" {
  count = length(local.outbound_ip_names) == 0 ? 0 : 1

  loadbalancer_id         = azurerm_lb.this.id
  name                    = "outbound"
  protocol                = "All"
  backend_address_pool_id = azurerm_lb_backend_address_pool.this.id
  enable_tcp_reset        = true

  allocated_outbound_ports = length(var.backend_servers) > 0 ? floor(63952 * length(local.outbound_ip_names) / length(var.backend_servers)) : null

  dynamic "frontend_ip_configuration" {
    for_each = toset(local.outbound_ip_names)
    content {
      name = frontend_ip_configuration.key
    }
  }

  depends_on = [azurerm_lb_probe.this]
}

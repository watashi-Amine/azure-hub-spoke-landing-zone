locals {
  # One flat map of "<subnet key>/<rule name>" => rule, so for_each can create
  # every rule without composite string parsing at read time.
  all_rules = merge([
    for subnet_key, subnet_rules in var.rules : {
      for rule_name, rule in subnet_rules : "${subnet_key}/${rule_name}" => merge(rule, {
        subnet_key = subnet_key
        rule_name  = rule_name
      })
    }
  ]...)

  associated_subnets = { for key, subnet in var.subnets : key => subnet if subnet.associate }
}

resource "azurerm_network_security_group" "this" {
  for_each = var.subnets

  name                = "${var.nsg_name_prefix}${each.key}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_subnet_network_security_group_association" "this" {
  for_each = local.associated_subnets

  subnet_id                 = each.value.id
  network_security_group_id = azurerm_network_security_group.this[each.key].id
}

resource "azurerm_network_security_rule" "this" {
  for_each = local.all_rules

  name                        = each.value.rule_name
  priority                    = each.value.priority
  direction                   = each.value.direction
  access                      = each.value.access
  protocol                    = each.value.protocol
  source_port_range           = each.value.source_port_range
  destination_port_range      = each.value.destination_port_range
  source_address_prefixes     = each.value.source_address_prefixes
  destination_address_prefixes = each.value.destination_address_prefixes
  description                 = each.value.description

  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.this[each.value.subnet_key].name

  depends_on = [azurerm_network_security_group.this]
}

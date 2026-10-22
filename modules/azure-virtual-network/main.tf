locals {
  # When the caller passes an existing resource group we simply reference it.
  resource_group_name = var.resource_group.create ? azurerm_resource_group.this[0].name : var.resource_group.name
}

resource "azurerm_resource_group" "this" {
  count = var.resource_group.create ? 1 : 0

  name     = var.resource_group.name
  location = var.location
  tags     = var.tags
}

resource "azurerm_virtual_network" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = local.resource_group_name
  address_space       = var.address_space
  dns_servers         = var.dns_servers
  tags                = var.tags
}

resource "azurerm_subnet" "this" {
  for_each = var.subnets

  name                 = each.key
  resource_group_name  = local.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [each.value.cidr]

  private_endpoint_network_policies             = each.value.private_endpoint_network_policies
  private_link_service_network_policies_enabled = each.value.private_link_service_network_policies_enabled
  service_endpoints                             = each.value.service_endpoints

  dynamic "delegation" {
    for_each = each.value.delegation
    content {
      name = delegation.key
      service_delegation {
        name    = delegation.value.name
        actions = delegation.value.actions
      }
    }
  }
}

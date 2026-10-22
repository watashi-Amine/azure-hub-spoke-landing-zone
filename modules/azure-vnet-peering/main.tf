resource "azurerm_virtual_network_peering" "local_to_remote" {
  name                         = "${var.name_prefix}-${var.local.name}-${var.remote.name}"
  resource_group_name          = var.local.resource_group_name
  virtual_network_name         = var.local.name
  remote_virtual_network_id    = var.remote.id
  allow_virtual_network_access = var.allow_virtual_network_access
  allow_forwarded_traffic      = var.allow_forwarded_traffic
  allow_gateway_transit        = var.allow_gateway_transit
  use_remote_gateways          = var.use_remote_gateways
}

resource "azurerm_virtual_network_peering" "remote_to_local" {
  provider = azurerm.peer
  count    = var.create_remote ? 1 : 0

  name                         = "${var.name_prefix}-${var.remote.name}-${var.local.name}"
  resource_group_name          = var.remote.resource_group_name
  virtual_network_name         = var.remote.name
  remote_virtual_network_id    = var.local.id
  allow_virtual_network_access = var.allow_virtual_network_access
  allow_forwarded_traffic      = var.allow_forwarded_traffic
  allow_gateway_transit        = var.use_remote_gateways
  use_remote_gateways          = var.allow_gateway_transit
}

locals {
  # Flat map of "<route table key>/<route name>" => route, for a single for_each.
  all_routes = merge([
    for table_key, table_routes in var.routes : {
      for route_name, route in table_routes : "${table_key}/${route_name}" => merge(route, {
        table_key  = table_key
        route_name = route_name
      })
    }
  ]...)

  associated_tables = { for key, table in var.route_tables : key => table if table.associate }
}

resource "azurerm_route_table" "this" {
  for_each = var.route_tables

  name                          = each.value.name
  location                      = var.location
  resource_group_name           = var.resource_group_name
  bgp_route_propagation_enabled = each.value.bgp_route_propagation_enabled
  tags                          = var.tags
}

resource "azurerm_subnet_route_table_association" "this" {
  for_each = local.associated_tables

  subnet_id      = each.value.subnet_id
  route_table_id = azurerm_route_table.this[each.key].id
}

resource "azurerm_route" "this" {
  for_each = local.all_routes

  name                   = each.value.route_name
  resource_group_name    = var.resource_group_name
  route_table_name       = azurerm_route_table.this[each.value.table_key].name
  address_prefix         = each.value.address_prefix
  next_hop_type          = each.value.next_hop_type
  next_hop_in_ip_address = each.value.next_hop_in_ip_address

  depends_on = [azurerm_route_table.this]
}

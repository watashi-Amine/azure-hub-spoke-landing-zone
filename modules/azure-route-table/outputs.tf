output "route_table_ids" {
  description = "Map of route table key => route table ID."
  value       = { for key, table in azurerm_route_table.this : key => table.id }
}

output "route_table_names" {
  description = "Map of route table key => route table name."
  value       = { for key, table in azurerm_route_table.this : key => table.name }
}

output "route_ids" {
  description = "Map of \"<route table key>/<route name>\" => route ID."
  value       = { for key, route in azurerm_route.this : key => route.id }
}

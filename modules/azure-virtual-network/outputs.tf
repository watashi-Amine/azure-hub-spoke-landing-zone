output "id" {
  description = "Resource ID of the virtual network."
  value       = azurerm_virtual_network.this.id
}

output "name" {
  description = "Name of the virtual network."
  value       = azurerm_virtual_network.this.name
}

output "address_space" {
  description = "Address space of the virtual network."
  value       = azurerm_virtual_network.this.address_space
}

output "resource_group_name" {
  description = "Resource group holding the virtual network."
  value       = local.resource_group_name
}

output "subnet_ids" {
  description = "Map of subnet name => subnet resource ID."
  value       = { for name, subnet in azurerm_subnet.this : name => subnet.id }
}

output "subnet_prefixes" {
  description = "Map of subnet name => CIDR prefix."
  value       = { for name, subnet in azurerm_subnet.this : name => subnet.address_prefixes[0] }
}

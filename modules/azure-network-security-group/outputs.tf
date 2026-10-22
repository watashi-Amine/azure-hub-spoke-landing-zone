output "nsg_ids" {
  description = "Map of subnet name => network security group ID."
  value       = { for key, nsg in azurerm_network_security_group.this : key => nsg.id }
}

output "nsg_names" {
  description = "Map of subnet name => network security group name."
  value       = { for key, nsg in azurerm_network_security_group.this : key => nsg.name }
}

output "association_ids" {
  description = "Map of subnet name => association ID (only for associated subnets)."
  value       = { for key, assoc in azurerm_subnet_network_security_group_association.this : key => assoc.id }
}

output "rule_ids" {
  description = "Map of \"<subnet name>/<rule name>\" => security rule ID."
  value       = { for key, rule in azurerm_network_security_rule.this : key => rule.id }
}

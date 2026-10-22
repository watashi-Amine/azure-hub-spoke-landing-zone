output "resource_group_name" {
  description = "Resource group holding the firewall pair."
  value       = local.resource_group_name
}

output "firewall_ids" {
  description = "Map of firewall key => VM resource ID."
  value       = { for key, vm in azurerm_virtual_machine.this : key => vm.id }
}

output "interface_private_ips" {
  description = "Map of \"<firewall key>/<interface key>\" => private IP address."
  value       = { for key, nic in azurerm_network_interface.this : key => nic.ip_configuration[0].private_ip_address }
}

output "interface_public_ips" {
  description = "Map of \"<firewall key>/<interface key>\" => public IP address (internet-facing interfaces only)."
  value       = { for key, pip in azurerm_public_ip.this : key => pip.ip_address }
}

output "interface_ids" {
  description = "Map of \"<firewall key>/<interface key>\" => network interface ID."
  value       = { for key, nic in azurerm_network_interface.this : key => nic.id }
}

output "ip_configuration_names" {
  description = "Map of \"<firewall key>/<interface key>\" => NIC ip_configuration name, for load balancer backend pools."
  value       = { for key, iface in local.firewall_interfaces : key => "ipconfig-${iface.if_key}" }
}

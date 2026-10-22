output "id" {
  description = "Load balancer ID."
  value       = azurerm_lb.this.id
}

output "public_ips" {
  description = "Map of frontend key => public IP address."
  value       = { for key, pip in azurerm_public_ip.this : key => pip.ip_address }
}

output "backend_pool_id" {
  description = "Backend address pool ID."
  value       = azurerm_lb_backend_address_pool.this.id
}

output "rule_ids" {
  description = "Map of rule name => rule ID."
  value       = { for key, rule in azurerm_lb_rule.this : key => rule.id }
}

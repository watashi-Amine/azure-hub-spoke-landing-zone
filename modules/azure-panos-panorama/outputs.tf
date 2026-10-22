output "public_ip" {
  description = "Panorama public IP address, or null when disabled."
  value       = var.enabled ? azurerm_public_ip.this[0].ip_address : null
}

output "fqdn" {
  description = "Panorama public FQDN, or null when disabled."
  value       = var.enabled ? azurerm_public_ip.this[0].fqdn : null
}

output "private_ip" {
  description = "Panorama management private IP, or null when disabled."
  value       = var.enabled ? azurerm_network_interface.this[0].ip_configuration[0].private_ip_address : null
}

output "vm_id" {
  description = "Panorama VM resource ID, or null when disabled."
  value       = var.enabled ? azurerm_virtual_machine.this[0].id : null
}

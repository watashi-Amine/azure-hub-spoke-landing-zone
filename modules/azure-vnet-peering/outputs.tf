output "peering_ids" {
  description = "Peering IDs, keyed by direction (local_to_remote / remote_to_local)."
  value = merge(
    { local_to_remote = azurerm_virtual_network_peering.local_to_remote.id },
    var.create_remote ? { remote_to_local = azurerm_virtual_network_peering.remote_to_local[0].id } : {}
  )
}

output "remote_address_space" {
  description = "Address space of the remote network, ready to feed the route table module."
  value       = var.remote.address_space
}

output "remote_vnet_id" {
  description = "Resource ID of the remote virtual network."
  value       = var.remote.id
}

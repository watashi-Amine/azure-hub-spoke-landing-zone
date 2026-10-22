output "subnet_ids" {
  description = "Every subnet created by the example, keyed by name."
  value       = module.workload_vnet.subnet_ids
}

output "subnet_prefixes" {
  description = "Every subnet prefix, keyed by name."
  value       = module.workload_vnet.subnet_prefixes
}

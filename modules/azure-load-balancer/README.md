# azure-load-balancer

Standard load balancer with public and/or private frontends, one backend pool,
health probes, rules and an optional outbound rule.

## Usage

```hcl
module "lb_ingress" {
  source = "../../modules/azure-load-balancer"

  name                     = "lb-ingress"
  location                 = var.location
  resource_group_name      = module.panos.resource_group_name
  vnet_resource_group_name = module.vnet.resource_group_name
  virtual_network_name     = module.vnet.name

  frontend_public_ips = {
    web = {
      ip_name       = "pip-lb-ingress"
      outbound_rule = true
      rules = {
        https = {
          rule_name         = "https"
          protocol          = "Tcp"
          frontend_port     = 443
          backend_port      = 443
          probe_config_name = "tcp-22"
          enable_float_ip   = true
          disable_out_snat  = true
        }
      }
    }
  }

  backend_pool_name = "ingress_backend"
  backend_servers = {
    fw01 = { network_interface_id = module.panos.interface_ids["fw01/outside"], ip_configuration_name = "ipconfig-outside" }
    fw02 = { network_interface_id = module.panos.interface_ids["fw02/outside"], ip_configuration_name = "ipconfig-outside" }
  }

  probes = {
    "tcp-22" = { probe_name = "tcp-22", protocol = "Tcp", port = 22 }
  }

  tags = var.tags
}
```

## Inputs

Key inputs; see `variables.tf` for the full typed list.

| Name | Type | Default | Description |
|---|---|---|---|
| `name` | `string` | required | Load balancer name. |
| `location` | `string` | required | Azure region. |
| `resource_group_name` | `string` | required | Resource group for the LB and its public IPs. |
| `vnet_resource_group_name` | `string` | required | Resource group of the frontend subnet. |
| `virtual_network_name` | `string` | required | Virtual network of the frontend subnet. |
| `frontend_public_ips` | `map(object)` | `{}` | Public frontends with their rules. |
| `frontend_private_ips` | `map(object)` | `{}` | Private frontends with their rules. |
| `backend_servers` | `map(object)` | required | Backend NICs and their ip_configuration names. |
| `probes` | `map(object)` | `{}` | Health probes, keyed by the name rules reference. |
| `zones` | `list(string)` | `["1","2","3"]` | Availability zones for public frontends. |

## Outputs

`id`, `public_ips` (map), `backend_pool_id`, `rule_ids`.

## Design notes

- **Legacy splat removed.** The previous implementation read
  `a.*.ip_name[0]` / `c.*.rule_name[0]`. Direct attribute access is used now:
  same values, no list-wrapping, no index-`[0]` assumption.
- **`vnet_resource_group_name` no longer defaults.** It previously defaulted to
  an environment-specific resource group name, which is silently wrong for every
  other consumer.
- **`location` no longer defaults** to a hardcoded region.
- **Zones are an input**, not a literal `[1, 2, 3]`.
- **Tags have no org default.** The previous `{ billingTo = "IT" }` default is gone.
- `allocated_outbound_ports` is derived from the frontend/backend counts, guarded
  against division by zero when no backend members are provided.

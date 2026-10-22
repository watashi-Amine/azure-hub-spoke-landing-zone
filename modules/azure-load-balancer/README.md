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

- **Direct attribute access.** Rules and frontends are read as
  `frontend.ip_name` and `rule.rule_name`, not through the splat form
  `a.*.ip_name[0]`: same values, no list-wrapping, no assumption that an
  attribute sits at index `[0]`.
- **`vnet_resource_group_name` has no default.** A default here would be silently
  wrong for anything outside one particular subscription, and the failure only
  shows up as a 404 on the subnet at apply time.
- **`location` has no default**, so the load balancer cannot land in a region
  nobody chose.
- **Zones are an input** (`["1","2","3"]` by default), not a literal compiled
  into the resource, so a region without three zones can opt out.
- **Tags have no built-in entry.** The map you pass is the map that is applied;
  the module never merges a billing code of its own.
- `allocated_outbound_ports` is derived from the frontend/backend counts, guarded
  against division by zero when no backend members are provided.

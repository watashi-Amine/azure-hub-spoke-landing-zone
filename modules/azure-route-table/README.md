# azure-route-table

Creates route tables, binds them to subnets, and creates routes from data.
Replaces both the hub and spoke route-table modules, which were ~90% identical.

## Usage

```hcl
module "rt" {
  source = "../../modules/azure-route-table"

  location            = var.location
  resource_group_name = module.vnet.resource_group_name

  route_tables = {
    sb1 = { name = "rt-snet-sb1", subnet_id = module.vnet.subnet_ids["snet-sb1"] }
    sb2 = { name = "rt-snet-sb2", subnet_id = module.vnet.subnet_ids["snet-sb2"] }
  }

  routes = {
    for key in ["sb1", "sb2"] : key => {
      default = { address_prefix = "0.0.0.0/0", next_hop_type = "VirtualAppliance", next_hop_in_ip_address = var.firewall_ip }
      hub     = { address_prefix = "10.0.0.0/20", next_hop_type = "VirtualAppliance", next_hop_in_ip_address = var.firewall_ip }
      local   = { address_prefix = "10.1.0.0/20", next_hop_type = "VnetLocal" }
    }
  }

  tags = var.tags
}
```

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `location` | `string` | required | Azure region. |
| `resource_group_name` | `string` | required | Resource group for the route tables. |
| `route_tables` | `map(object({ name, subnet_id, bgp_route_propagation_enabled, associate }))` | `{}` | One route table per subnet. |
| `routes` | `map(map(object({ address_prefix, next_hop_type, next_hop_in_ip_address })))` | `{}` | `{ route table key => { route name => route } }`. |
| `tags` | `map(string)` | `{}` | Applied to the route tables. |

## Outputs

`route_table_ids`, `route_table_names`, `route_ids`.

## Design notes

- **Hub and spoke merged.** The two previous modules differed only by `bgp_route_propagation_enabled` and a name branch; both are now inputs. `bgp_route_propagation_enabled` defaults to `false` because a spoke must not learn routes around the firewall.
- **`split("-")` key parsing is gone.** The old modules encoded `"<subnet>-<NextHopType>-<NextHopAddress>"` in a map key and split it at read time, which broke on hyphenated names — the bug noted in the old `resources-ne.tf`. Routes are typed objects now.
- **`subnets_map_gw` renamed.** It never referred to the gateway subnet; it meant "destinations routed via the firewall". That concept is now just another entry in `routes`.
- **Validations added:** next-hop type enum, `next_hop_in_ip_address` required *only* for `VirtualAppliance`, valid CIDRs, no duplicate prefix within one table, and every route key must match a declared route table.
- `molecule` and `gateway`/`rt_gw` special cases removed: they were project-specific branches inside a shared module.

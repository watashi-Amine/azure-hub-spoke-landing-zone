# azure-route-table

Creates route tables, binds them to subnets, and creates routes from data. One
module covers both the hub and the spoke: they differ only in
`bgp_route_propagation_enabled` and in the prefixes they route, both of which are
inputs.

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

- **One module for hub and spoke.** The only real difference between the two is `bgp_route_propagation_enabled`, which is an input. It defaults to `false` because a spoke must not learn routes around the firewall.
- **Routes are typed objects.** No `"<subnet>-<NextHopType>-<NextHopAddress>"` string keys parsed with `split("-")` at read time, which breaks on any hyphenated name. `address_prefix`, `next_hop_type` and `next_hop_in_ip_address` are separate fields.
- **The gateway subnet is not special-cased.** A route table bound to a gateway subnet is just another entry in `routes`.
- **Validations added:** next-hop type enum, `next_hop_in_ip_address` required *only* for `VirtualAppliance`, valid CIDRs, no duplicate prefix within one table, and every route key must match a declared route table.
- **No caller-specific branches.** Nothing in the module knows about a particular project or environment.

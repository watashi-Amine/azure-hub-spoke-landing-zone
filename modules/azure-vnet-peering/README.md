# azure-vnet-peering

Creates a virtual network peering, in both directions by default, across two
subscriptions.

Rewritten from scratch: the module this replaces declared its own provider
configurations and required an input it never used.

## Usage

```hcl
module "peering" {
  source = "../../modules/azure-vnet-peering"

  providers = {
    azurerm      = azurerm.hub
    azurerm.peer = azurerm.spoke
  }

  local = {
    name                = module.hub_vnet.name
    resource_group_name = module.hub_vnet.resource_group_name
    id                  = module.hub_vnet.id
  }

  remote = {
    name                = module.spoke_vnet.name
    resource_group_name = module.spoke_vnet.resource_group_name
    id                  = module.spoke_vnet.id
    address_space       = module.spoke_vnet.address_space
  }

  allow_forwarded_traffic = true # both sides
}
```

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `local` | `object({ name, resource_group_name, id })` | required | Side owned by the `azurerm` provider. |
| `remote` | `object({ name, resource_group_name, id, address_space })` | required | Side owned by the `azurerm.peer` provider. |
| `allow_virtual_network_access` | `bool` | `true` | Must be true for traffic to flow at all. |
| `allow_forwarded_traffic` | `bool` | `true` | Lets the firewall's forwarded packets traverse the peering. |
| `allow_gateway_transit` | `bool` | `false` | Local gateway usable by the remote side. |
| `use_remote_gateways` | `bool` | `false` | Use the remote side's gateway. |
| `create_remote` | `bool` | `true` | Set false when only the local direction is ours. |
| `name_prefix` | `string` | `"peer"` | Names become `<prefix>-<local>-<remote>`. |

## Outputs

| Name | Description |
|---|---|
| `peering_ids` | `local_to_remote` and, when created, `remote_to_local`. |
| `remote_address_space` | Remote CIDRs, ready to feed `azure-route-table`. |
| `remote_vnet_id` | Remote virtual network ID. |

## Design notes

- **No provider blocks inside the module.** The replaced module declared
  `provider "azurerm" { alias = "sub1" }` and `"sub2"` in its own `connection.tf`.
  Declaring providers inside a child module is a deprecated pattern: it pins the
  module to its own idea of subscriptions and prevents callers from composing it.
  Providers are now passed in, which also means the module can later be driven
  with `for_each` if Terraform ever supports that for provider-bound resources.
- **Typed objects instead of parallel lists.** The old interface took seven
  positional lists that had to stay the same length and order; nothing enforced
  it. Two objects cannot get out of sync.
- **`datacenter_name` removed.** It was required on all nine call sites and never
  referenced in the module body.
- **Gateway flags swap by direction.** `allow_gateway_transit` on one side pairs
  with `use_remote_gateways` on the other; the module applies that mapping so the
  asymmetry cannot be typed wrong.
- **`remote_address_space` is returned on purpose.** Callers need it to build the
  route tables, and returning it removes a class of copy-paste CIDR bugs.

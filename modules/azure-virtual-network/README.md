# azure-virtual-network

Creates a virtual network and its subnets, and optionally its resource group.

## Usage

```hcl
module "vnet" {
  source = "../../modules/azure-virtual-network"

  name     = "vnet-spoke-dc1"
  location = var.location

  resource_group = { name = "rg-spoke-dc1" }

  address_space = ["10.1.0.0/20"]
  dns_servers   = ["10.0.3.4", "10.0.3.5"]

  subnets = {
    "snet-sb1"      = { cidr = "10.1.0.0/24", private_endpoint_network_policies = "Enabled" }
    "snet-sb2"      = { cidr = "10.1.1.0/24" }
    "snet-gateway"  = { cidr = "10.1.15.0/24" }
  }

  tags = var.tags
}
```

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `name` | `string` | required | Full virtual network name. The caller owns naming. |
| `location` | `string` | required | Azure region. |
| `resource_group` | `object({ name, create })` | required | `create = true` creates it, `false` references an existing one. |
| `address_space` | `list(string)` | required | One or more CIDR blocks. Validated. |
| `subnets` | `map(object)` | `{}` | Subnets keyed by **full** subnet name. |
| `dns_servers` | `list(string)` | `[]` | Empty means Azure-provided DNS. |
| `tags` | `map(string)` | `{}` | Applied to all resources. |

## Outputs

| Name | Description |
|---|---|
| `id`, `name` | Virtual network identity. |
| `address_space` | The VNet address space. |
| `resource_group_name` | Resource group in use. |
| `subnet_ids` | `map(name => id)`. |
| `subnet_prefixes` | `map(name => cidr)`. |

## Design notes

- **Map keys are the subnet names.** No `snet-` prefix is built inside the module: naming is a root-module concern, documented in `docs/naming.md`, so the subnet is called exactly what the caller wrote.
- **No `GatewaySubnet` special case.** With no VPN/ExpressRoute gateway in this template there is nothing to reserve a name for; if you add a gateway, name that subnet yourself.
- **`private_endpoint_network_policies` is a string**, matching Azure's native values (`Disabled`, `Enabled`, `NetworkSecurityGroupEnabled`, `RouteTableEnabled`). The boolean `private_endpoint_network_policies_enabled` was **removed from the provider in azurerm 4.0** — do not "fix" this back to a boolean.
- **No default DNS servers.** A resolver address baked in as a default is exactly the kind of value that survives a copy-paste unnoticed and quietly sends traffic somewhere it should not go.
- Outputs return ids and prefixes, not whole resource objects, so consumers stay decoupled from the resource schema.

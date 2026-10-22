# azure-network-security-group

Creates one network security group per subnet, attaches them, and creates the
security rules from data.

## Usage

```hcl
module "nsg" {
  source = "../../modules/azure-network-security-group"

  location            = var.location
  resource_group_name = module.vnet.resource_group_name

  subnets = {
    "snet-sb1" = { id = module.vnet.subnet_ids["snet-sb1"] }
    "snet-sb2" = { id = module.vnet.subnet_ids["snet-sb2"] }
  }

  rules = {
    "snet-sb1" = {
      "allow-internet-in" = {
        priority                = 4000
        direction               = "Inbound"
        access                  = "Allow"
        protocol                = "Tcp"
        destination_port_range  = "443"
        source_address_prefixes = ["Internet"]
      }
    }
    "snet-sb2" = {
      "allow-fw-in" = {
        priority                = 4000
        direction               = "Inbound"
        access                  = "Allow"
        protocol                = "*"
        source_address_prefixes = ["10.0.1.253", "10.0.1.252"]
      }
      "deny-all-in" = {
        priority                = 4096
        direction               = "Inbound"
        access                  = "Deny"
        protocol                = "*"
      }
    }
  }

  tags = var.tags
}
```

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `location` | `string` | required | Azure region. |
| `resource_group_name` | `string` | required | Resource group for the NSGs. |
| `subnets` | `map(object({ id, associate }))` | `{}` | Subnets that receive an NSG, keyed by full subnet name. |
| `nsg_name_prefix` | `string` | `"nsg-"` | Prefix for the NSG name. |
| `rules` | `map(map(object))` | `{}` | `{ subnet key => { rule name => rule } }`. |
| `tags` | `map(string)` | `{}` | Applied to the NSGs. |

## Outputs

`nsg_ids`, `nsg_names`, `association_ids`, `rule_ids`.

## Design notes

- **Rules are nested per subnet**, `{ subnet => { rule name => rule } }`. The previous implementation required a flat map with composite string keys and later split those strings on `-`, which corrupted any hyphenated subnet or route name. Nesting removes string parsing entirely.
- **Rules are separate resources**, not inline `security_rule` blocks, so a single rule can be added or reordered without rewriting the NSG.
- **Validations added:** priority range 100–4096, priority uniqueness per NSG, direction/access/protocol enums, and every rule key must correspond to a declared subnet.
- **Removed:** `subscription_id` and `environment_name`, which were required inputs that the module never used.
- The default `private` behaviour stays with `subnets_map`-free naming: association looks up the real subnet id passed in, rather than reconstructing a name with a `snet-` prefix.

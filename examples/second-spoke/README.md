# Example: a second spoke

The template ships one reference spoke. This is the complete change set for
adding a second one, and nothing here is new code — it is the same three blocks
repeated with different values.

## 1. Add a provider alias

`providers.tf`:

```hcl
provider "azurerm" {
  alias           = "spoke_b"
  subscription_id = var.spoke_b_subscription_id
  features {}
}
```

Two spokes can share one subscription. If they do, point both aliases at the same
`subscription_id` — aliases are still needed because peering takes two providers.

## 2. Create the VNet

Use an address space that does not overlap the hub (`10.10.0.0/20`) or the first
spoke (`10.20.0.0/20`):

```hcl
module "spoke_b_vnet" {
  source    = "../../modules/azure-virtual-network"
  providers = { azurerm = azurerm.spoke_b }

  name           = "vnet-spoke-dc1-b"
  location       = var.location
  resource_group = { name = "rg-spoke-dc1-b" }
  address_space  = ["10.30.0.0/20"]
  dns_servers    = []

  subnets = {
    "snet-sb1" = { cidr = "10.30.0.0/24", private_endpoint_network_policies = "Enabled" }
    "snet-sb2" = { cidr = "10.30.1.0/24" }
    "snet-sb3" = { cidr = "10.30.2.0/24" }
    "snet-sb4" = { cidr = "10.30.3.0/24" }
  }

  tags = var.tags
}
```

## 3. Peer it to the hub

```hcl
module "hub_spoke_b_peering" {
  source = "../../modules/azure-vnet-peering"

  providers = {
    azurerm      = azurerm.hub
    azurerm.peer = azurerm.spoke_b
  }

  local = {
    name                = module.hub_vnet.name
    resource_group_name = module.hub_vnet.resource_group_name
    id                  = module.hub_vnet.id
  }

  remote = {
    name                = module.spoke_b_vnet.name
    resource_group_name = module.spoke_b_vnet.resource_group_name
    id                  = module.spoke_b_vnet.id
    address_space       = module.spoke_b_vnet.address_space
  }

  allow_forwarded_traffic = true
}
```

## 4. Route it to the firewall

```hcl
module "spoke_b_routes" {
  source    = "../../modules/azure-route-table"
  providers = { azurerm = azurerm.spoke_b }

  location            = var.location
  resource_group_name = module.spoke_b_vnet.resource_group_name

  route_tables = {
    for key, subnet_id in {
      sb1 = module.spoke_b_vnet.subnet_ids["snet-sb1"]
      sb2 = module.spoke_b_vnet.subnet_ids["snet-sb2"]
      sb3 = module.spoke_b_vnet.subnet_ids["snet-sb3"]
      sb4 = module.spoke_b_vnet.subnet_ids["snet-sb4"]
    } : key => {
      name                          = "rt-b-${key}"
      subnet_id                     = subnet_id
      bgp_route_propagation_enabled = false
    }
  }

  routes = {
    for key in ["sb1", "sb2", "sb3", "sb4"] : key => merge(
      { local = { address_prefix = "10.30.0.0/20", next_hop_type = "VnetLocal" } },
      {
        for name, cidr in {
          default = "0.0.0.0/0"
          hub     = "10.10.0.0/20"
          spoke_a = "10.20.0.0/20"
        } : name => {
          address_prefix         = cidr
          next_hop_type          = "VirtualAppliance"
          next_hop_in_ip_address = var.firewall_trust_ip
        }
      }
    )
  }

  tags = var.tags
}
```

## 5. Do not forget the return paths

Two edits, both easy to miss, and both fail silently:

**Hub side** — the hub needs a route to the new spoke:

```hcl
module "hub_routes" {
  # ...
  routes = {
    shared = merge(
      local.hub_existing_routes,
      {
        spoke_b = {
          address_prefix         = "10.30.0.0/20"
          next_hop_type          = "VirtualAppliance"
          next_hop_in_ip_address = var.firewall_trust_ip
        }
      }
    )
  }
}
```

Without it: spoke B can reach the hub, the hub cannot reply.

**Spoke A side** — spoke A needs a route to spoke B, or the two spokes cannot talk:

```hcl
spoke_a_new_entry = {
  address_prefix         = "10.30.0.0/20"
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = var.firewall_trust_ip
}
```

Without it: spoke A sends spoke-B traffic to the default route (internet) and it
is dropped at the firewall.

## 6. Firewall side

Terraform stops at the Azure boundary. For spoke B to be reachable, PAN-OS needs:

- an interface or subinterface for `10.30.0.0/20`, or acceptance of the prefix on
  the trust zone
- a virtual router route for `10.30.0.0/20` via the trust next hop
- security policy for spoke-B ↔ spoke-A, spoke-B ↔ hub, spoke-B ↔ internet

Until those exist, the routes are correct and the packets still stop at the
device.

## Checklist

- [ ] address space does not overlap the hub, spoke A, or any remote network
- [ ] provider alias added and passed to every module touching spoke B
- [ ] VNet created with `sb1`–`sb4`
- [ ] peering created in both directions
- [ ] spoke B route tables point at the firewall, BGP propagation disabled
- [ ] hub route table has a route to `10.30.0.0/20`
- [ ] spoke A route table has a route to `10.30.0.0/20`
- [ ] NSG rules applied to spoke B subnets by role
- [ ] PAN-OS has the route and the policy

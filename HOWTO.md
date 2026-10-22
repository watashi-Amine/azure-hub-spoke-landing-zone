# HOWTO — using this project

A step-by-step guide to deploying a hub-and-spoke network with a Palo Alto
VM-Series HA firewall pair on Azure, using the modules in this repository.

---

## Before you start

### What you need

| Requirement | Detail |
|---|---|
| Terraform | `>= 1.5.0` (`terraform version`) |
| AzureRM provider | `~> 4.0`, installed automatically by `terraform init` |
| Azure CLI | for `az login` |
| Permissions | Contributor on the hub subscription, plus Network Contributor on the spoke subscription if it is separate |
| Subscriptions | one for the hub, one for the spoke. The same subscription for both is fine |

### What this project gives you

Seven modules in `modules/`. Each has its own README with inputs, outputs and
design notes. You write a small root configuration that calls them; the modules
do the work.

| Module | Use it for |
|---|---|
| `azure-virtual-network` | VNet, subnets, optional resource group |
| `azure-network-security-group` | NSGs, subnet associations, security rules |
| `azure-route-table` | route tables, associations, routes |
| `azure-vnet-peering` | two-way peering between two subscriptions |
| `azure-panos-ha` | the firewall pair |
| `azure-panos-panorama` | optional Panorama |
| `azure-load-balancer` | ingress and egress load balancers for the firewalls |

> **Status:** the modules are complete and documented. The pre-built root
> configurations under `infra/` are the next phase. Until they land, follow this
> guide to build your own root configuration — it is the same code those stacks
> will contain, so nothing here is throwaway.

---

## Step 1 — Get the code

```bash
git clone <this-repo-url>
cd azure-hub-spoke-landing-zone
```

If you are vendoring this into another project, copy the `modules/` directory and
reference it by relative path. Do not fork the modules per project: they are
designed to be shared.

---

## Step 2 — Design your address plan first

Do this on paper before writing Terraform. Overlapping ranges are the most
expensive mistake to fix later.

Example plan used throughout this guide:

| Scope | Range | Contents |
|---|---|---|
| Hub | `10.10.0.0/20` | `snet-mgmt` `10.10.3.0/24`, `snet-ha` `10.10.4.0/24`, `snet-local` `10.10.1.0/24`, `snet-outside` `10.10.2.0/24`, `snet-shared` `10.10.5.0/24` |
| Spoke | `10.20.0.0/20` | `snet-sb1` `10.20.0.0/24`, `snet-sb2` `10.20.1.0/24`, `snet-sb3` `10.20.2.0/24`, `snet-sb4` `10.20.3.0/24` |
| Remote networks | your other networks | routed through the firewall |

The four hub subnets map to the firewall's four interfaces:
`mgmt` (management), `ha` (HA pair sync), `local` (trust, toward the spoke),
`outside` (untrust, toward the internet).

The four spoke subnets carry a role that decides their security posture:

| Subnet | Role | Typical rules |
|---|---|---|
| `snet-sb1` | public | inbound and outbound internet allowed |
| `snet-sb2` | private | outbound only |
| `snet-sb3` | secure | firewall and remote networks only |
| `snet-sb4` | middle | firewall and remote networks only |

---

## Step 3 — Authenticate

```bash
az login
az account list --output table
```

If the hub and spoke live in different subscriptions, confirm you can see both.
Find the subscription IDs:

```bash
az account show --query id -o tsv
```

Never commit real subscription IDs. Keep them in a `terraform.tfvars` that is
gitignored, or in your pipeline's secret store.

---

## Step 4 — Create a working directory

The guides below build one root configuration. Create it outside `modules/`:

```bash
mkdir -p my-landing-zone
cd my-landing-zone
```

Add `versions.tf`:

```hcl
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}
```

Add `providers.tf` — one provider per subscription:

```hcl
provider "azurerm" {
  alias           = "hub"
  subscription_id = var.hub_subscription_id
  features {}
}

provider "azurerm" {
  alias           = "spoke"
  subscription_id = var.spoke_subscription_id
  features {}
}
```

Add `variables.tf`:

```hcl
variable "hub_subscription_id"  { type = string }
variable "spoke_subscription_id" { type = string }
variable "location" {
  type    = string
  default = "westeurope"
}
variable "admin_username" { type = string }
variable "admin_password" {
  type      = string
  sensitive = true
}
variable "tags" {
  type    = map(string)
  default = { ManagedBy = "terraform" }
}
```

Create `terraform.tfvars` (never commit it):

```hcl
hub_subscription_id   = "00000000-0000-0000-0000-000000000001"
spoke_subscription_id = "00000000-0000-0000-0000-000000000002"
admin_username        = "adminuser"
```

Pass the password through the environment, not a file:

```bash
export TF_VAR_admin_password='...'
```

---

## Step 5 — Build the hub

`hub.tf`:

```hcl
module "hub_vnet" {
  source = "../modules/azure-virtual-network"

  providers = { azurerm = azurerm.hub }

  name           = "vnet-hub-dc1"
  location       = var.location
  resource_group = { name = "rg-hub-dc1" }
  address_space  = ["10.10.0.0/20"]
  dns_servers    = [] # empty = Azure-provided DNS

  subnets = {
    "snet-local" = {
      cidr                                  = "10.10.1.0/24"
      private_endpoint_network_policies     = "Enabled"
    }
    "snet-outside" = {
      cidr                                  = "10.10.2.0/24"
      private_endpoint_network_policies     = "Enabled"
    }
    "snet-mgmt" = {
      cidr                                  = "10.10.3.0/24"
      private_endpoint_network_policies     = "Enabled"
    }
    "snet-ha" = {
      cidr                                  = "10.10.4.0/24"
      private_endpoint_network_policies     = "Enabled"
    }
    "snet-shared" = {
      cidr                                  = "10.10.5.0/24"
      private_endpoint_network_policies     = "Disabled"
    }
  }

  tags = var.tags
}
```

Note that subnet names are yours: the module does not add a `snet-` prefix.

---

## Step 6 — Build the spoke

`spoke.tf`:

```hcl
module "spoke_vnet" {
  source = "../modules/azure-virtual-network"

  providers = { azurerm = azurerm.spoke }

  name           = "vnet-spoke-dc1"
  location       = var.location
  resource_group = { name = "rg-spoke-dc1" }
  address_space  = ["10.20.0.0/20"]
  dns_servers    = []

  subnets = {
    "snet-sb1" = { cidr = "10.20.0.0/24", private_endpoint_network_policies = "Enabled" } # public
    "snet-sb2" = { cidr = "10.20.1.0/24" }                                                # private
    "snet-sb3" = { cidr = "10.20.2.0/24" }                                                # secure
    "snet-sb4" = { cidr = "10.20.3.0/24" }                                                # middle
  }

  tags = var.tags
}
```

---

## Step 7 — Peer the two networks

`peering.tf`:

```hcl
module "hub_spoke_peering" {
  source = "../modules/azure-vnet-peering"

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

  # Both directions, and forwarded traffic on both sides, or the firewall's
  # packets are dropped even when every route is correct.
  create_remote           = true
  allow_forwarded_traffic = true
}
```

Both peering directions are created by this one block.

---

## Step 8 — Deploy the firewall pair

`firewall.tf`:

```hcl
locals {
  firewall_trust_ip = cidrhost("10.10.1.0/24", 4) # primary firewall, local interface
}

module "panos" {
  source = "../modules/azure-panos-ha"

  providers = { azurerm = azurerm.hub }

  location       = var.location
  resource_group = { name = "rg-fw-dc1" }

  firewalls = {
    fw01 = { name = "fw01", is_primary = true }
    fw02 = { name = "fw02", is_primary = false }
  }

  interfaces = {
    mgmt = {
      subnet_id              = module.hub_vnet.subnet_ids["snet-mgmt"]
      subnet_cidr            = "10.10.3.0/24"
      primary_ip_offset      = 4
      secondary_ip_offset    = 5
      public_ip              = true
      ip_forwarding          = false
      accelerated_networking = false
    }
    outside = {
      subnet_id           = module.hub_vnet.subnet_ids["snet-outside"]
      subnet_cidr         = "10.10.2.0/24"
      primary_ip_offset   = 4
      secondary_ip_offset = 5
    }
    local = {
      subnet_id           = module.hub_vnet.subnet_ids["snet-local"]
      subnet_cidr         = "10.10.1.0/24"
      primary_ip_offset   = 4
      secondary_ip_offset = 5
    }
    ha = {
      subnet_id              = module.hub_vnet.subnet_ids["snet-ha"]
      subnet_cidr            = "10.10.4.0/24"
      primary_ip_offset      = 4
      secondary_ip_offset    = 5
      ip_forwarding          = false
      accelerated_networking = false
    }
  }

  public_ip_dns_prefix = "fw-dc1"
  admin_username       = var.admin_username
  admin_password       = var.admin_password
  tags                 = var.tags
}
```

`interface_order` defaults to `["mgmt", "outside", "local", "ha"]`, which is the
NIC order PAN-OS sees as eth0–eth3. Change it only if your device expects a
different mapping.

---

## Step 9 — Point the spoke at the firewall

This is the step that makes routing work. Every spoke subnet gets a route table
whose default route, hub route and remote-network routes all point at the
firewall's trust interface.

`routes.tf`:

```hcl
locals {
  spoke_subnet_keys = ["sb1", "sb2", "sb3", "sb4"]

  spoke_subnets = {
    sb1 = module.spoke_vnet.subnet_ids["snet-sb1"]
    sb2 = module.spoke_vnet.subnet_ids["snet-sb2"]
    sb3 = module.spoke_vnet.subnet_ids["snet-sb3"]
    sb4 = module.spoke_vnet.subnet_ids["snet-sb4"]
  }

  # Everything that must leave the spoke goes through the firewall.
  via_firewall = {
    default = "0.0.0.0/0"
    hub     = "10.10.0.0/20"
    # add one entry per remote network you need to reach
  }
}

module "spoke_routes" {
  source = "../modules/azure-route-table"

  providers = { azurerm = azurerm.spoke }

  location            = var.location
  resource_group_name = module.spoke_vnet.resource_group_name

  route_tables = {
    for key, subnet_id in local.spoke_subnets : key => {
      name      = "rt-snet-${key}"
      subnet_id = subnet_id
      # a spoke must not learn routes around the firewall
      bgp_route_propagation_enabled = false
    }
  }

  routes = {
    for key, subnet_id in local.spoke_subnets : key => merge(
      # traffic for the spoke's own address space stays in the VNet
      { local = { address_prefix = "10.20.0.0/20", next_hop_type = "VnetLocal" } },
      # everything else is handed to the firewall
      {
        for name, cidr in local.via_firewall : name => {
          address_prefix         = cidr
          next_hop_type          = "VirtualAppliance"
          next_hop_in_ip_address = local.firewall_trust_ip
        }
      }
    )
  }

  tags = var.tags
}
```

And the matching return path in the hub — without it, spoke-to-hub works but
hub-to-spoke silently fails:

```hcl
module "hub_routes" {
  source = "../modules/azure-route-table"

  providers = { azurerm = azurerm.hub }

  location            = var.location
  resource_group_name = module.hub_vnet.resource_group_name

  route_tables = {
    shared = { name = "rt-snet-shared", subnet_id = module.hub_vnet.subnet_ids["snet-shared"] }
  }

  routes = {
    shared = {
      spoke = {
        address_prefix         = "10.20.0.0/20"
        next_hop_type          = "VirtualAppliance"
        next_hop_in_ip_address = local.firewall_trust_ip
      }
    }
  }

  tags = var.tags
}
```

---

## Step 10 — Add security rules

Rules are data, nested per subnet. `nsg.tf`:

```hcl
module "spoke_nsg" {
  source = "../modules/azure-network-security-group"

  providers = { azurerm = azurerm.spoke }

  location            = var.location
  resource_group_name = module.spoke_vnet.resource_group_name

  subnets = {
    "snet-sb1" = { id = module.spoke_vnet.subnet_ids["snet-sb1"] }
    "snet-sb2" = { id = module.spoke_vnet.subnet_ids["snet-sb2"] }
    "snet-sb3" = { id = module.spoke_vnet.subnet_ids["snet-sb3"] }
    "snet-sb4" = { id = module.spoke_vnet.subnet_ids["snet-sb4"] }
  }

  rules = {
    # public: internet in and out
    "snet-sb1" = {
      "allow-internet-in" = {
        priority                = 4000
        direction               = "Inbound"
        access                  = "Allow"
        protocol                = "Tcp"
        destination_port_range  = "443"
        source_address_prefixes = ["Internet"]
      }
      "deny-all-in" = {
        priority                = 4096
        direction               = "Inbound"
        access                  = "Deny"
        protocol                = "*"
      }
    }

    # private: outbound only
    "snet-sb2" = {
      "allow-internet-out" = {
        priority                     = 4000
        direction                    = "Outbound"
        access                       = "Allow"
        protocol                     = "*"
        destination_address_prefixes = ["Internet"]
      }
      "deny-all-in" = {
        priority   = 4096
        direction  = "Inbound"
        access     = "Deny"
        protocol   = "*"
      }
    }

    # secure and middle: firewall and remote networks only
    "snet-sb3" = {
      "allow-fw-in" = {
        priority                = 4000
        direction               = "Inbound"
        access                  = "Allow"
        protocol                = "*"
        source_address_prefixes = ["10.10.1.4", "10.10.1.5"]
      }
      "deny-all-in" = {
        priority   = 4096
        direction  = "Inbound"
        access     = "Deny"
        protocol   = "*"
      }
    }
  }

  tags = var.tags
}
```

Priorities must be unique per subnet. The module rejects duplicates at plan time.

---

## Step 11 — Validate before creating anything

```bash
terraform init
terraform fmt -recursive
terraform validate
terraform plan -out=tfplan
```

Read the plan. Check specifically:

- the number of route tables equals the number of spoke subnets
- every `next_hop_in_ip_address` is the firewall's trust IP
- both peering directions appear, with `allow_forwarded_traffic = true`

---

## Step 12 — Apply in order

```bash
terraform apply tfplan
```

Terraform resolves the dependency graph itself, so one apply is usually enough.
If you split the stacks later, the order is: hub VNet → spoke VNet → peering →
firewall → route tables, because routes reference the firewall's address.

---

## Step 13 — Verify

**Azure side:**

```bash
# peering is Connected in both directions
az network vnet peering list -g rg-hub-dc1   --vnet-name vnet-hub-dc1 -o table
az network vnet peering list -g rg-spoke-dc1 --vnet-name vnet-spoke-dc1 -o table

# route tables carry the firewall next hop
az network route-table route list -g rg-spoke-dc1 --route-table-name rt-snet-sb1 -o table
```

A peering in state `Initiated` means only one direction exists. `Connected` on both
sides is what you want.

**Effective routes from a VM** in `snet-sb4` should show `0.0.0.0/0` and the hub
range pointing at the firewall's trust IP.

**Device side:** this project does not configure PAN-OS. Zones, the virtual
router, NAT and security policy live in Panorama or on the device. Traffic will
not flow until those exist, even with perfect Azure routing. Configure them next:

1. `local` interface as the trust zone, `outside` as untrust
2. a virtual router with routes for the hub, the spoke and remote networks
3. SNAT for spoke-originated internet traffic
4. security policy allowing spoke-to-hub, spoke-to-remote and spoke-to-internet

---

## Step 14 — Optional: Panorama

Add to `firewall.tf`:

```hcl
module "panorama" {
  source = "../modules/azure-panos-panorama"

  providers = { azurerm = azurerm.hub }

  enabled             = true
  name                = "pano01"
  location            = var.location
  resource_group_name = module.panos.resource_group_name
  subnet_id           = module.hub_vnet.subnet_ids["snet-mgmt"]
  subnet_cidr         = "10.10.3.0/24"
  ip_offset           = 250
  dns_name            = "pano01-dc1"

  admin_username = var.admin_username
  admin_password = var.admin_password
  tags           = var.tags
}
```

The module creates nothing when `enabled = false`, which is the default.

---

## Adding another spoke

1. Add a second provider alias (`spoke_b`) with its subscription ID.
2. Copy the `spoke_vnet` block, rename it, change the address space to a
   non-overlapping range (for example `10.30.0.0/20`).
3. Copy the `hub_spoke_peering` block, pointing `remote` at the new VNet and
   `azurerm.peer` at `azurerm.spoke_b`.
4. Copy the route table block, changing the destination CIDR in `via_firewall`.
5. Add the new spoke range to the hub route table's `routes`, so the return path
   exists.

---

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| Peering shows `Initiated` | only one direction was created; check `create_remote = true` and that both providers are passed |
| Spoke to hub works, hub to spoke does not | missing return route in the hub route table |
| Routes look right but packets are dropped | `allow_forwarded_traffic` is false on one side of the peering |
| Traffic reaches the firewall and dies | PAN-OS zones, virtual router or policy not configured; the firewall drops unknown sessions |
| `Error: Unsupported argument` on plan | the provider is older than `~> 4.0`; run `terraform init -upgrade` |
| Duplicate priority error on plan | two rules on the same subnet share a priority; the module checks this on purpose |
| `next_hop_in_ip_address` validation error | it is set on a route whose `next_hop_type` is not `VirtualAppliance`, or missing on one that is |

---

## Conventions this project uses

- **You name everything.** Modules never invent prefixes; a subnet called
  `snet-sb1` is called that because you passed that key.
- **One provider per subscription**, aliased, passed explicitly with
  `providers = { ... }`. Modules declare no providers of their own.
- **Maps are keyed by name**, so `for_each` is stable and adding a subnet does
  not renumber anything.
- **Sensitive values are marked `sensitive`** and should arrive from environment
  variables or a secret store, never a committed file.
- **No state is stored in this repository.** Configure a remote backend before
  your first apply; see Step 15.

---

## Step 15 — Use a remote backend

Local state is fine for a first experiment, not for teams. Add to `versions.tf`:

```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-tfstate"
    storage_account_name = "sttfstatedc1"
    container_name       = "tfstate"
    key                  = "landing-zone-01.tfstate"
  }
}
```

Then:

```bash
terraform init -migrate-state
```

Enable versioning on the storage account. State contains secrets in clear text;
treat the container as sensitive.

---

## Where to read next

| Document | Read it for |
|---|---|
| `docs/architecture.md` | components, subscription model, every traffic flow, and why the design is shaped this way |
| `docs/naming.md` | the naming convention and the type prefixes |
| `docs/routing.md` | every route the template creates, peering flags, verification commands, troubleshooting matrix |
| `docs/security-rules.md` | the role-based NSG model and how rules are generated per role |
| `docs/module-standards.md` | the rules every module follows, for when you write your own |
| `examples/workload-subnets/` | delegation, private endpoints, service endpoints, gateway subnet |
| `examples/second-spoke/` | the complete change set for adding another spoke |

## What is not in this project yet

- Pre-built root configurations under `infra/` (next phase)
- ExpressRoute and VPN gateway support (out of scope by design)

Until the root configurations land, the steps above are the complete path: the
modules are finished, and everything else is composition.

# Security rules

NSG rules in this project are data, not code. The `azure-network-security-group`
module takes a nested map — `{ subnet => { rule name => rule } }` — and creates
one `azurerm_network_security_rule` per entry.

## Why rules are data

Writing security rules as one resource block per rule does not scale. A subnet
with a dozen ports and four peers needs roughly that many blocks, and a policy
change means editing every one of them in place. Four similar networks built
that way are four files that look alike and drift apart.

A nested map turns the same policy into a table that can be read in one screen
and generated per role.

## Roles

Subnet names are arbitrary. The **role** is what decides policy.

| Role | Posture | Inbound | Outbound |
|---|---|---|---|
| `public` | reachable from the internet | internet → published ports | all |
| `private` | not reachable, can reach out | deny | internet |
| `secure` | internal only | firewall and remote networks | firewall and remote networks |
| `middle` | internal only | firewall and remote networks | firewall and remote networks |

`secure` and `middle` are identical at the Azure layer. They are separate subnets
because PAN-OS policy usually distinguishes them; if your device does not, use
one role for both.

## Defining rules per role

```hcl
locals {
  firewall_trust_ips = ["10.10.1.4", "10.10.1.5"]
  remote_networks    = ["10.30.0.0/16"]

  role_rules = {
    public = {
      "allow-internet-in" = {
        priority                = 4000
        direction               = "Inbound"
        access                  = "Allow"
        protocol                = "Tcp"
        destination_port_range  = "443"
        source_address_prefixes = ["Internet"]
      }
    }
    private = {}
    secure  = {}
    middle  = {}
  }

  # applied to every role that is not public
  default_internal_rules = {
    "allow-fw-in" = {
      priority                = 4000
      direction               = "Inbound"
      access                  = "Allow"
      protocol                = "*"
      source_address_prefixes = local.firewall_trust_ips
    }
    "allow-fw-out" = {
      priority                      = 4000
      direction                     = "Outbound"
      access                        = "Allow"
      protocol                      = "*"
      destination_address_prefixes  = local.firewall_trust_ips
    }
  }

  deny_all = {
    "deny-all-in" = {
      priority   = 4096
      direction  = "Inbound"
      access     = "Deny"
      protocol   = "*"
    }
    "deny-all-out" = {
      priority   = 4096
      direction  = "Outbound"
      access     = "Deny"
      protocol   = "*"
    }
  }
}

module "spoke_nsg" {
  source = "../../modules/azure-network-security-group"

  location            = var.location
  resource_group_name = module.spoke_vnet.resource_group_name

  subnets = {
    "snet-sb1" = { id = module.spoke_vnet.subnet_ids["snet-sb1"] }
    "snet-sb2" = { id = module.spoke_vnet.subnet_ids["snet-sb2"] }
    "snet-sb3" = { id = module.spoke_vnet.subnet_ids["snet-sb3"] }
    "snet-sb4" = { id = module.spoke_vnet.subnet_ids["snet-sb4"] }
  }

  rules = {
    for subnet, role in {
      "snet-sb1" = "public"
      "snet-sb2" = "private"
      "snet-sb3" = "secure"
      "snet-sb4" = "middle"
    } : subnet => merge(
      local.role_rules[role],
      role == "public" ? local.deny_all : local.default_internal_rules,
      role == "public" ? {} : local.deny_all
    )
  }
}
```

## Rules the module enforces

| Validation | Failure mode it prevents |
|---|---|
| priority within 100–4096 | Azure rejects anything outside the range |
| priorities unique per subnet | Azure rejects duplicates; catching it at plan time is cheaper |
| direction is `Inbound`/`Outbound` | typo producing a silently ignored rule |
| access is `Allow`/`Deny` | same |
| protocol is `*`, `Tcp`, `Udp`, `Icmp` | same |
| every rule key matches a declared subnet | a rule attached to a subnet that does not exist |

## Ordering

Azure evaluates rules by priority, lowest first, and stops at the first match.
The template's convention: `4000+` for allow rules, `4096` for catch-all denies.
This leaves `1000–3999` free for specific exceptions that must precede the
general allows.

## Source and destination prefixes

Rules take `source_address_prefixes` and `destination_address_prefixes`
(**plural**), which map to Azure's list form. This avoids the string-splitting
that a comma-separated `source_address_prefix` invites.

Accepted special values: `*`, `Internet`, `VirtualNetwork`, `AzureLoadBalancer`,
or a CIDR / list of CIDRs.

## Interaction with the firewall

NSGs and PAN-OS policy are two independent gates. A packet must pass both.

- **NSG**: filters at the subnet boundary in Azure
- **firewall**: filters at the hub, and sees all inter-zone traffic

Keep NSGs coarse — allow the firewall's addresses, deny the rest — and let the
firewall carry the granular policy. Duplicating detailed rules in both places
creates two sources of truth that drift.

Practical consequence: when traffic is blocked, check the NSG first (fast, visible
in Azure) and the firewall second (sessions, policy, NAT).

## Anti-patterns

- **`source_address_prefix = "*"` on an internal subnet.** The firewall is the
  filter, not the NSG, so `*` from the firewall's address is usually enough.
- **One NSG shared by every subnet.** It makes per-role policy impossible and
  couples unrelated workloads.
- **Deny rules without a final allow.** Azure applies default rules after yours;
  an explicit deny-all with no exceptions silently kills platform traffic such as
  health probes and updates.

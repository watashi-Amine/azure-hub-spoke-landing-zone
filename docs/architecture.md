# Architecture

## Overview

A hub-and-spoke network on Azure where all traffic between spokes, and all
traffic leaving a spoke, passes through a Palo Alto VM-Series HA firewall pair
in the hub.

```
                     internet
                        │
                        │
  hub subscription ─────┼──────────────────────────────────────
  ┌─────────────────────┴──────────────────────────────────┐
  │ vnet-hub-dc1                    10.10.0.0/20           │
  │                                                        │
  │   snet-outside  10.10.2.0/24   ← untrust, towards WAN   │
  │   snet-local    10.10.1.0/24   ← trust, towards spokes  │
  │   snet-ha       10.10.4.0/24   ← HA pair synchronisation│
  │   snet-mgmt     10.10.3.0/24   ← device management      │
  │   snet-shared   10.10.5.0/24   ← shared services        │
  │                                                        │
  │   fw01 / fw02  (active-passive pair)                   │
  │   lb-ingress   (public IP, 443 → both firewalls)        │
  │   lb-egress    (private IP, spoke default route target) │
  └───────────────────────┬────────────────────────────────┘
                          │ peering, both directions
                          │ allow_forwarded_traffic = true
  spoke subscription ─────┼──────────────────────────────────────
  ┌───────────────────────┴────────────────────────────────┐
  │ vnet-spoke-dc1                  10.20.0.0/20           │
  │   snet-sb1  10.20.0.0/24   role: public                │
  │   snet-sb2  10.20.1.0/24   role: private                │
  │   snet-sb3  10.20.2.0/24   role: secure                 │
  │   snet-sb4  10.20.3.0/24   role: middle                 │
  │                                                        │
  │   every subnet: rt-snet-sbN, bgp propagation disabled,  │
  │   0.0.0.0/0 and all remote prefixes → firewall trust IP │
  └────────────────────────────────────────────────────────┘
```

## Components

### Hub

The hub holds the only route out. It is deliberately small: four subnets for the
firewall's four interfaces, plus shared subnets for services every spoke needs.

| Subnet | Purpose | Firewall interface |
|---|---|---|
| `snet-local` | trust side, spoke traffic arrives here | `local` |
| `snet-outside` | untrust side, towards the internet or WAN | `outside` |
| `snet-ha` | HA1/HA2 state and session sync between the pair | `ha` |
| `snet-mgmt` | device management, public IP attached | `mgmt` |
| `snet-shared` | shared services (DNS, jump hosts, tooling) | — |

### Firewall pair

Two VM-Series firewalls in an active-passive pair, each with four NICs mapped to
the four hub subnets.

- **Ingress load balancer** has a public frontend and both firewalls in its
  backend pool. Inbound sessions land on the active member; floating-IP rules
  keep the flow symmetric.
- **Egress load balancer** has a private frontend in `snet-local` and both
  firewalls in its pool. This is why spoke route tables point at the load
  balancer's private address rather than at a single firewall: if the active
  member fails, the next hop stays valid.

### Spoke

One reference spoke with four subnets. The subnet names carry no meaning on
their own; the **role** attached to each subnet is what decides policy.

| Subnet | Role | Posture |
|---|---|---|
| `snet-sb1` | public | internet in and out |
| `snet-sb2` | private | internet out only |
| `snet-sb3` | secure | firewall and remote networks only |
| `snet-sb4` | middle | firewall and remote networks only |

`secure` and `middle` exist as separate subnets because they usually carry
different firewall policy on the PAN-OS side, even though their Azure NSG rules
are identical.

## Subscription model

One provider alias per subscription, declared in the root configuration and
passed explicitly to each module:

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

Modules declare no providers of their own. A module call that touches the hub
receives `providers = { azurerm = azurerm.hub }`; one that spans both receives
`{ azurerm = azurerm.hub, azurerm.peer = azurerm.spoke }`.

This is why the template scales by adding an alias and a peering block rather
than by duplicating a stack: **the unit of reuse is the module call, not the
directory.** Adding a third spoke means one more alias and one more block. See
`docs/naming.md` for how to name it and `HOWTO.md` for the recipe.

## Traffic flows

| Source | Destination | Path |
|---|---|---|
| spoke subnet | another spoke subnet | spoke route table → firewall trust → hub route → firewall → spoke |
| spoke subnet | internet | spoke route table → firewall → SNAT → egress LB → internet |
| spoke subnet | hub subnet | spoke route table → firewall trust → hub route table |
| spoke subnet | on-prem or remote network | spoke route table → firewall → remote route on the firewall |
| internet | published service | ingress LB → firewall → spoke route |
| hub subnet | spoke subnet | hub route table → firewall trust → spoke |

Azure moves the packet; the firewall decides whether it continues. Both must be
right, which is why `docs/routing.md` and the PAN-OS configuration are separate
concerns.

## Deliberate exclusions

| Not included | Why |
|---|---|
| ExpressRoute | site-to-site connectivity is deployment-specific; the hub can attach a gateway later without changing the spoke design |
| VPN gateway | same reason. Diagram the gateway subnet if you add one |
| DDoS Protection plan | cost decision, not architectural |
| Azure Firewall | the design uses VM-Series; the NSG and route-table modules are independent of that choice |
| PAN-OS configuration | zones, virtual router, NAT and policy live in Panorama or on the device, not in Terraform |

## Why these choices

**Peering, not a gateway, between hub and spoke.** Peering is free of charge for
the traffic path this design needs and does not require a shared gateway.

**Route tables on every spoke subnet, not one per VNet.** Azure associates route
tables per subnet. One table for the whole VNet forces the same policy on
`public` and `secure` subnets, which is exactly what the roles are meant to avoid.

**`bgp_route_propagation_enabled = false` on spokes.** If Azure propagates routes
learned elsewhere, a spoke can reach a remote network without passing the
firewall. Disabling it makes the firewall the only path.

**The firewall module does not create load balancers.** Pool membership and probe
configuration are policy decisions taken in the root stack, where they are
visible next to the rules they support.

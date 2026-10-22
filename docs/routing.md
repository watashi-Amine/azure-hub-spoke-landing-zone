# Routing reference

This document describes the routes the template creates and why. It is the
reference for verifying a deployment without reading the Terraform.

## The principle

**The firewall is the only next hop.** Every prefix a spoke cannot reach locally
is handed to the firewall pair. Nothing routes around it.

Two mechanisms enforce it:

1. Route tables send unknown prefixes to the firewall's trust address.
2. `bgp_route_propagation_enabled = false` stops Azure from learning routes
   another way, so a spoke cannot reach a remote network without transiting the
   firewall.

## Address plan used in examples

| Scope | Range |
|---|---|
| Hub VNet | `10.10.0.0/20` |
| Firewall trust (`snet-local`) | `10.10.1.0/24` |
| Firewall untrust (`snet-outside`) | `10.10.2.0/24` |
| Firewall management (`snet-mgmt`) | `10.10.3.0/24` |
| Firewall HA (`snet-ha`) | `10.10.4.0/24` |
| Shared services (`snet-shared`) | `10.10.5.0/24` |
| Spoke VNet | `10.20.0.0/20` |
| Spoke subnets | `10.20.0.0/24` … `10.20.3.0/24` |
| Remote network (example) | `10.30.0.0/16` |

**Next hop.** All firewall-bound routes use the egress load balancer's private
address in `snet-local`, not a specific firewall's address. If the active member
fails, the next hop stays valid. In the examples this is `cidrhost("10.10.1.0/24", -2)`,
the second-to-last address of the subnet, mirroring how the egress LB frontend is
configured.

## Route tables created

### Spoke: one table per subnet

Each of `snet-sb1` … `snet-sb4` gets its own table. All four carry the same
routes: the roles differ in NSG policy, not in reachability.

| Route name | Prefix | Next hop |
|---|---|---|
| `local` | `10.20.0.0/20` | `VnetLocal` |
| `default` | `0.0.0.0/0` | `VirtualAppliance` → firewall trust |
| `hub` | `10.10.0.0/20` | `VirtualAppliance` → firewall trust |
| `remote-<name>` | one per remote network | `VirtualAppliance` → firewall trust |

`bgp_route_propagation_enabled = false`.

Why `local` exists: without it, traffic between two subnets in the same VNet
would hairpin through the firewall, which doubles latency and load on the device
for no policy benefit. Same-VNet traffic stays local.

Why one table per subnet rather than one per VNet: Azure associates route tables
per subnet, so a VNet-wide table forces identical routing on `public` and
`secure`, defeating the point of the roles.

### Hub: return path

The hub needs a route back to every spoke. Without it, spoke-to-hub works and
hub-to-spoke silently fails — the most common defect in this design.

| Table | Route | Prefix | Next hop |
|---|---|---|---|
| `rt-snet-shared` | `spoke` | `10.20.0.0/20` | `VirtualAppliance` → firewall trust |
| `rt-snet-local` | `spoke` | `10.20.0.0/20` | `VirtualAppliance` → firewall trust |

Add one route per spoke. Two spokes means two routes in each hub table.

## Traffic flows, step by step

### Spoke to spoke

```
VM in snet-sb1 (10.20.0.10) → 10.20.2.10 in snet-sb3
route: 10.20.0.0/20 → VnetLocal
result: stays inside vnet-spoke-dc1, never reaches the firewall
```

Same-VNet traffic does **not** transit the firewall by design. If policy requires
inspection between subnets, remove the `local` route from the tables that need
inspection and let the default route carry them — at the cost of firewall
throughput.

### Spoke to internet

```
VM in snet-sb2 → 93.184.216.34
route: 0.0.0.0/0 → VirtualAppliance 10.10.1.254
Azure forwards to the egress LB → firewall
firewall: SNAT to its outside interface → internet
return: firewall keeps session state, un-NATs, returns via the LB
```

The firewall must SNAT; without it the return packet has no route home.

### Spoke to hub shared services

```
VM in snet-sb4 → 10.10.5.10
route: 10.10.0.0/20 → VirtualAppliance 10.10.1.254
firewall policy decides whether to allow it
return: hub route table 10.20.0.0/20 → VirtualAppliance
```

### Internet to a published service

```
client → ingress LB public IP :443
ingress LB: floating IP rule → active firewall
firewall: DNAT to the backend in the spoke
return: firewall → spoke route table → subnet
```

Ingress rules use `enable_floating_ip = true` so the backend sees the original
destination and the firewall state stays symmetric across a failover.

## Peering flags

| Flag | Hub side | Spoke side | Why |
|---|---|---|---|
| `allow_virtual_network_access` | `true` | `true` | traffic must be permitted at all |
| `allow_forwarded_traffic` | `true` | `true` | the firewall forwards packets that did not originate in the hub; both sides need this or they are dropped |
| `allow_gateway_transit` | `false` | `false` | no gateway in this template |
| `use_remote_gateways` | `false` | `false` | same |

`allow_forwarded_traffic` is the flag most often missed: routes look perfect,
Azure drops the packets, and nothing in the route table explains why.

## NSG interaction

Routes decide where a packet goes; NSGs decide whether it may. For the spoke
design to work, the NSGs must allow:

- spoke subnets: inbound from the firewall trust addresses
- hub `snet-local`: inbound from every spoke address space
- hub `snet-outside`: inbound from the internet if you publish services

See `docs/security-rules.md`.

## Verification

```bash
# route tables exist for every spoke subnet, with the firewall as next hop
az network route-table list -g rg-spoke-dc1 -o table
az network route-table route list -g rg-spoke-dc1 --route-table-name rt-snet-sb1 -o table

# BGP propagation must be disabled on spoke tables
az network route-table show -g rg-spoke-dc1 -n rt-snet-sb1 \
  --query "disableBgpRoutePropagation" -o tsv      # expect: true

# effective routes seen by a VM
az network nic show-effective-route-table -g rg-spoke-dc1 -n <nic> -o table
```

In the effective route table, `0.0.0.0/0` should appear as
`VirtualNetworkGateway`-style `VirtualAppliance` with the LB address as next hop.
If Azure shows `None` or `Internet`, the route table is not associated with the
subnet — check `azurerm_subnet_route_table_association`.

## Troubleshooting matrix

| Symptom | Check |
|---|---|
| spoke→hub works, hub→spoke does not | hub route table missing the spoke prefix |
| nothing reaches the firewall | spoke route table not associated with the subnet |
| peering `Initiated` | only one direction created; see `create_remote` |
| packets reach the firewall, nothing returns | `allow_forwarded_traffic` false on one side, or no SNAT on the firewall |
| traffic takes an unexpected path | BGP propagation enabled on the spoke table |
| same-VNet traffic slow | the `local` route is missing, traffic is hairpinning |
| failover breaks egress | route tables point at a firewall address instead of the egress LB |

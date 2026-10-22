# Naming convention

Modules in this project never invent names. Every resource name is supplied by
the root configuration, which keeps the convention in one place instead of
scattered across seven modules.

## The pattern

```
<type>-<workload>-<location>-<instance>
```

- **type** — the Azure resource abbreviation, lowercase
- **workload** — what the resource serves: `hub`, `spoke`, `sb1`, `fw`, `shared`
- **location** — short region or site code: `dc1`, `weu`, `neu`
- **instance** — optional ordinal or purpose suffix: `01`, `02`

Separators are hyphens. Everything is lowercase.

## Type prefixes

| Resource | Prefix | Example |
|---|---|---|
| Resource group | `rg-` | `rg-hub-dc1` |
| Virtual network | `vnet-` | `vnet-spoke-dc1` |
| Subnet | `snet-` | `snet-sb1` |
| Network security group | `nsg-` | `nsg-snet-sb1` |
| Route table | `rt-` | `rt-snet-sb1` |
| Public IP | `pip-` | `pip-fw01-mgmt` |
| Load balancer | `lb-` | `lb-ingress` |
| Network interface | `nic-` | `nic-fw01-local` |
| Virtual machine | none | `fw01`, `pano01` |
| Managed disk | `disk-` | `disk-pano01-data` |
| Key vault | `kv-` | `kv-dc1-tf` |
| Storage account | `st` (no hyphens) | `sttfstatedc1` |

## Subnets

Subnet names are flat and purpose-based, never positional:

```
snet-local      firewall trust
snet-outside    firewall untrust
snet-ha         firewall HA sync
snet-mgmt       device management
snet-shared     shared services
snet-sb1..sb4   spoke subnets, role assigned in configuration
```

No `GatewaySubnet` in this template: there is no VPN or ExpressRoute gateway by
design. If you add one, Azure requires that exact name — it is the one exception
to this convention.

## Route tables

```
rt-snet-<subnet name without the snet- prefix>
```

So `snet-sb3` gets `rt-snet-sb3`. The one-to-one mapping between subnet and route
table is intentional and worth preserving: it makes `az network route-table list`
readable against the subnet list.

## Firewalls

| Thing | Pattern | Example |
|---|---|---|
| VM | `fw<nn>` | `fw01`, `fw02` |
| Interface | `nic-<vm>-<role>` | `nic-fw01-outside` |
| IP configuration | `ipconfig-<role>` | `ipconfig-outside` |
| Public IP | `pip-<vm>-<role>` | `pip-fw01-mgmt` |
| DNS label | `<prefix>-<vm>-<role>` | `fw-dc1-fw01-mgmt` |

The interface role — `mgmt`, `outside`, `local`, `ha` — is the anchor. It appears
in the interface key, the NIC name, the IP configuration name and the DNS label,
so a packet capture or a load balancer pool entry can be traced back to one role
without cross-referencing three files.

## Tags

Tags are configuration, not constants. A minimum set:

```hcl
tags = {
  Environment = "prod"
  Owner       = "platform-team"
  ManagedBy   = "terraform"
  CostCentre  = "network"
}
```

Nothing in `modules/` merges organisation tags into your own, so the map you pass
is the map that gets applied.

## Naming by phase

| Phase | Name example |
|---|---|
| Single site, single environment | `vnet-hub-dc1`, `vnet-spoke-dc1` |
| Two regions | `vnet-hub-weu`, `vnet-hub-neu` |
| Two environments, same region | `vnet-hub-dc1-prod`, `vnet-hub-dc1-nonprod` |
| Many spokes | `vnet-spoke-dc1-01`, `vnet-spoke-dc1-02` — one per workload |

Pick one scheme and apply it everywhere. The modules do not care; consistency is
what makes the route tables and NSG maps readable.

## What not to do

- **Do not encode the subscription or tenant** in resource names. It leaks
  information and changes when subscriptions are reorganised.
- **Do not number subnets** (`snet-01`, `snet-02`). A number survives a purpose
  change and then lies about what the subnet is for.
- **Do not use a single token for both site and environment** (`dc1prod`). They
  are different axes; collapsing them makes a second region or a non-production
  copy impossible to name.

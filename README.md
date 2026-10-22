# azure-hub-spoke-landing-zone

A reusable Terraform template for an Azure hub-and-spoke network with a Palo
Alto VM-Series HA firewall pair between the hub and one reference spoke.

Everything environment-specific — organisation, datacenter codes, subscription
IDs, address plan, DNS, credentials — has been removed. What remains is the
architecture and the wiring.

## Project layout

Everything for this project lives under `azure-hub-spoke-landing-zone/`.

```
README.md                     this file
HOWTO.md                      step-by-step deployment guide
modules/                      reusable building blocks, each with its own README
  azure-virtual-network/      VNet + subnets (+ optional resource group)
  azure-network-security-group/  NSGs, associations and rules from data
  azure-route-table/          route tables, associations and routes from data
  azure-vnet-peering/         two-way peering across subscriptions
  azure-load-balancer/        standard LB with public/private frontends
  azure-panos-ha/             VM-Series HA pair, named interfaces
  azure-panos-panorama/       optional Panorama + logging disk
infra/
  01-connectivity-hub/        hub: VNet, subnets, NSGs, route tables, peering
  02-spoke/                   one reference spoke, same shape
  03-firewall/                firewall pair, load balancers, optional Panorama
  tfvars/                     the only files an operator edits
docs/
  architecture.md             components, subscription model, traffic flows, why these choices
  naming.md                   the naming convention
  routing.md                  route tables, peering flags, troubleshooting matrix
  security-rules.md           role-based NSG model
  module-standards.md         the rules every module follows
examples/
  workload-subnets/           delegation, private endpoints, service endpoints, gateway subnet
  second-spoke/               the complete change set for adding another spoke
```

Folder prefixes `01-`, `02-`, `03-` reflect apply order: the hub must exist
before the spoke can peer to it, and the firewall needs the hub's subnets.

## Architecture

```
hub subscription                          spoke subscription
┌────────────────────────────────┐        ┌────────────────────────────┐
│ vnet-hub-dc1   10.0.0.0/20     │        │ vnet-spoke-dc1  10.1.0.0/20│
│  snet-local    (FW trust)      │        │  snet-sb1  public          │
│  snet-outside  (FW untrust)    │◄──────►│  snet-sb2  private         │
│  snet-ha       (FW HA)         │ peering│  snet-sb3  secure          │
│  snet-mgmt     (FW management) │        │  snet-sb4  middle          │
│  firewall pair + 2 LBs         │        │  route tables → firewall   │
└────────────────────────────────┘        └────────────────────────────┘
```

Every spoke subnet has a route table that sends its default route, the hub
address space and every remote network to the firewall's trust address. The hub
has the matching return route to each spoke. See `docs/routing.md`.

## Design principles

These are enforced across every module in this repository:

1. **No `provider` blocks inside modules.** Providers are passed from the root.
2. **No environment values in modules** — no regions, resource group names, IPs,
   DNS servers, tags or organisation names.
3. **The caller owns names.** Modules accept full resource names; they do not
   invent prefixes. The naming convention lives in one place.
4. **Typed variables with validation.** No parallel positional lists; CIDRs,
   priorities, enums and offsets are validated at plan time.
5. **Data over repetition.** Subnets, NSGs, rules and routes are maps, not
   hundreds of near-identical resources.
6. **`for_each` over maps**, never `count` (except genuine on/off toggles).
7. **Outputs are data**, not whole resource objects.
8. **Sensitive inputs marked `sensitive`.**

## Status

| Layer | State |
|---|---|
| `modules/` (7) | **done** — refactored, anonymised, documented |
| `infra/` (3 stacks) | planned — see `STATUS.md` |
| `docs/` | planned |
| `examples/` | planned |

## Relationship to the original code

This template was derived from a single-environment project repository. The
architecture, the network logic and the firewall placement are unchanged. What
changed is naming, defaults, structure, and the module interfaces — every module
input was re-typed and every hidden default removed. `STATUS.md` records the
mapping and the outstanding work.

# Module standards

Every module in `modules/` follows these rules. They exist so the modules can be
shared between projects without edits, and so a reader can predict the shape of a
module before opening it.

## File layout

```
modules/<name>/
  README.md       purpose, usage, inputs table, outputs table, design notes
  versions.tf     required_version and required_providers only
  variables.tf    every input: typed, described, validated where possible
  main.tf         resources and locals
  outputs.tf      every output, described
```

One concern per module. If a module needs a `count`/`for_each` toggle to make
half of itself disappear, it is two modules.

## Rules

### 1. No `provider` blocks inside modules

Providers are configured in the root and passed down:

```hcl
module "spoke_vnet" {
  source    = "../../modules/azure-virtual-network"
  providers = { azurerm = azurerm.spoke }
}
```

Declaring a provider inside a module pins it to its own subscriptions, prevents
composition, and in older Terraform versions blocked `for_each` entirely. The
one thing a module may do is declare `required_providers` in `versions.tf` so the
version constraint travels with it.

### 2. No environment values

A module may not contain a region, resource group name, subscription ID, CIDR,
DNS server, address prefix, device name or organisation name — not even as a
default. Defaults that encode an environment survive copy-paste and are the
hardest defect to notice in review.

Acceptable defaults are behavioural, not environmental: `bgp_route_propagation_enabled = false`,
`enabled = false`, `associate = true`.

### 3. The caller owns names

Modules accept full resource names and build nothing:

```hcl
module "vnet" {
  name = "vnet-spoke-dc1"     # not: name_prefix = "spoke" → module produces "vnet-spoke"
}
```

The notable exception is derived child resources, where the parent name is
already caller-owned: `nsg-snet-sb1` from subnet key `snet-sb1`, or
`nic-fw01-local` from firewall and interface keys. These are documented in each
README.

### 4. Typed variables, validated at plan time

```hcl
type = map(object({
  cidr  = string
  role  = optional(string, "private")
}))
```

Never `map(any)` when the shape is known. Every CIDR, offset and enum is checked
with a `validation` block so a mistake fails during `plan`, not halfway through
an apply.

### 5. Data over repetition, `for_each` over maps

Subnets, NSGs, rules, routes and load balancer frontends are maps. `count` is used
only for genuine on/off toggles (`enabled`, `create_remote`).

Map keys are part of the contract: renaming a key destroys and recreates the
resource, so keys are names, not indexes.

### 6. Outputs are data

```hcl
output "subnet_ids" {
  value = { for name, s in azurerm_subnet.this : name => s.id }
}
```

Not whole resource objects: a consumer that needs `.id` should not be able to
depend on the resource's whole schema, because that couples it to a provider
version.

### 7. Secrets are marked sensitive

Any password or key input carries `sensitive = true`. No module reads a secret
from a hardcoded vault name; the caller passes a value and decides where it came
from.

### 8. Every deviation is documented

Each README has a **Design notes** section explaining why the module differs from
an obvious implementation — for example why `private_endpoint_network_policies`
is a string rather than a boolean, or why `azurerm_virtual_machine` is retained
instead of `azurerm_linux_virtual_machine`. Without that, the next reader "fixes"
it back.

## Deprecations

`azurerm_virtual_machine` is feature-frozen in the AzureRM provider but still
supported in 4.x. The firewall and Panorama modules use it deliberately.
Migrating to `azurerm_linux_virtual_machine` changes resource addresses and
therefore needs a state migration; it is a separate change, not part of a
template release.

Similarly, `private_endpoint_network_policies` (string) is the current property.
`private_endpoint_network_policies_enabled` (boolean) was removed in azurerm 4.0
and must not be reintroduced.

## Adding a module

1. Create `modules/<name>/` with the five files above.
2. Write `versions.tf` with `required_version` and `required_providers`, and no
   provider block.
3. Type and validate every variable.
4. Write the README: usage snippet first, then tables, then design notes.
5. Check it: no environment values, no invented prefixes, `for_each` over maps,
   outputs are data.

# azure-panos-ha

Deploys a Palo Alto VM-Series HA pair with named interfaces, public management
IPs, and the NIC ordering PAN-OS expects.

## Usage

```hcl
module "panos" {
  source = "../../modules/azure-panos-ha"

  location       = var.location
  resource_group = { name = "rg-fw-dc1" }

  firewalls = {
    fw01 = { name = "fw01", is_primary = true }
    fw02 = { name = "fw02", is_primary = false }
  }

  interfaces = {
    mgmt    = { subnet_id = module.hub.subnet_ids["snet-mgmt"],    subnet_cidr = "10.0.3.0/24", primary_ip_offset = 4, secondary_ip_offset = 5, public_ip = true, ip_forwarding = false, accelerated_networking = false }
    outside = { subnet_id = module.hub.subnet_ids["snet-outside"], subnet_cidr = "10.0.2.0/24", primary_ip_offset = 4, secondary_ip_offset = 5 }
    local   = { subnet_id = module.hub.subnet_ids["snet-local"],   subnet_cidr = "10.0.1.0/24", primary_ip_offset = 4, secondary_ip_offset = 5 }
    ha      = { subnet_id = module.hub.subnet_ids["snet-ha"],      subnet_cidr = "10.0.4.0/24", primary_ip_offset = 4, secondary_ip_offset = 5, ip_forwarding = false, accelerated_networking = false }
  }

  public_ip_dns_prefix = "fw-dc1"
  admin_username       = var.admin_username
  admin_password       = var.admin_password
  tags                 = var.tags
}
```

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `location` | `string` | required | Azure region. |
| `resource_group` | `object({ name, create })` | required | Where the pair is created. |
| `firewalls` | `map(object({ name, is_primary }))` | required | Exactly two, exactly one primary. |
| `interfaces` | `map(object)` | required | Keyed by role; each carries its own subnet, CIDR and IP offsets. |
| `interface_order` | `list(string)` | `["mgmt","outside","local","ha"]` | NIC attachment order, i.e. eth0…ethN. |
| `public_ip_dns_prefix` | `string` | required | DNS label prefix for internet-facing interfaces. |
| `vm_size` | `string` | `Standard_DS3_v2` | Firewall size. |
| `image` | `object` | `paloaltonetworks/vmseries1/byol` | Marketplace image. |
| `admin_username` / `admin_password` | `string` | required | `admin_password` is `sensitive`. |
| `tags` | `map(string)` | `{}` | Applied to all resources. |

## Outputs

| Name | Description |
|---|---|
| `resource_group_name` | Resource group in use. |
| `firewall_ids` | `map(firewall key => VM id)`. |
| `interface_private_ips` | `map("<fw>/<interface>" => private IP)`. |
| `interface_public_ips` | `map("<fw>/<interface>" => public IP)`. |
| `interface_ids` | `map("<fw>/<interface>" => NIC id)`, for load balancer pools. |
| `ip_configuration_names` | `map("<fw>/<interface>" => ip_configuration name)`. |

## Design notes

- **Interface order is an input, validated once.** The replaced module hardcoded
  `[mgmt, outside, local, ha]` twice inside the VM resource, so the eth0…eth3
  mapping could be broken by an unrelated edit. It is now `interface_order`,
  checked against the interface keys.
- **IP offsets belong to the interface.** No `cidrhost(cidr, 253)` literal
  anywhere; each interface states its own primary and secondary offset and both
  are validated against its CIDR.
- **No org-specific names.** `hub_firewalls_rg`, `hub_pr_nic`, `hub_sc_nic` and
  environment-coded device names are gone; names derive from the firewall and
  interface keys you supply.
- **Public IPs are opt-in per interface** (`public_ip = true`), instead of being
  attached to a hardcoded `mgmt` key.
- **VM resource type.** `azurerm_virtual_machine` is feature-frozen in the
  AzureRM provider but still supported in 4.x. It is kept here deliberately, so
  that migrating to `azurerm_linux_virtual_machine` stays a separate change with
  its own state migration, rather than being bundled into a template release.
- **Load balancers are not in this module.** Ingress/egress LBs are composed in
  the root stack from `azure-load-balancer`, so their rules are visible where
  they are decided.

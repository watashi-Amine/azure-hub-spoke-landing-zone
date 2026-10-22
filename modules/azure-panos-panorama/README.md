# azure-panos-panorama

Deploys a Panorama VM with its public IP and logging data disk. Optional.

## Usage

```hcl
module "panorama" {
  source = "../../modules/azure-panos-panorama"

  enabled             = true
  name                = "pano01"
  location            = var.location
  resource_group_name = module.panos.resource_group_name
  subnet_id           = module.hub.subnet_ids["snet-mgmt"]
  subnet_cidr         = "10.0.3.0/24"
  ip_offset           = 250
  dns_name            = "pano01-dc1"

  admin_username = var.admin_username
  admin_password = var.admin_password
  tags           = var.tags
}
```

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `enabled` | `bool` | `false` | Deploy Panorama or nothing. |
| `name` | `string` | `pano01` | VM name. |
| `location` | `string` | required | Azure region. |
| `resource_group_name` | `string` | required | Normally the firewall pair's resource group. |
| `subnet_id` | `string` | required | Management subnet. |
| `subnet_cidr` | `string` | required | CIDR of that subnet. |
| `ip_offset` | `number` | `250` | Host offset inside the subnet. |
| `dns_name` | `string` | required | Public DNS label. |
| `vm_size` | `string` | `Standard_F16s_v2` | Panorama size. |
| `data_disk_size_gb` | `number` | `2048` | Logging disk size. |
| `admin_username` / `admin_password` | `string` | required | `admin_password` is `sensitive`. |

## Outputs

`public_ip`, `fqdn`, `private_ip`, `vm_id` — all `null` when `enabled = false`.

## Design notes

- **Optional by default.** The replaced module always deployed Panorama, which
  made it unusable for anyone without it.
- **Address computed, not spliced.** The old module took a string prefix such as
  `"10.1.50."` and concatenated `250`. Here the address is
  `cidrhost(subnet_cidr, ip_offset)`, validated.
- **The logging disk moved in.** The disk and its attachment used to live in the
  root stack with org-specific tags; they belong with the VM.
- **No hardcoded tags.** The previous module merged fixed
  `BillingTo/Environment/Governance` values into every resource.
- Same `azurerm_virtual_machine` note as `azure-panos-ha`: retained deliberately,
  migration is a separate change.

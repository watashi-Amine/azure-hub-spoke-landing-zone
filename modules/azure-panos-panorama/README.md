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

- **Optional by default.** `enabled = false` means the module creates nothing, so
  a deployment without centralised management does not pay for Panorama.
- **Address computed, not spliced.** The interface address is
  `cidrhost(subnet_cidr, ip_offset)`, validated, so a prefix is never
  concatenated with a host number by hand.
- **The logging disk lives here.** The disk and its attachment belong with the VM
  that uses them, not with the caller that happens to know the size.
- **No built-in tags.** The module merges nothing into the tag map it is given.
- Same `azurerm_virtual_machine` note as `azure-panos-ha`: the feature-frozen
  resource is used deliberately, and moving to `azurerm_linux_virtual_machine` is
  a separate change with its own state migration.

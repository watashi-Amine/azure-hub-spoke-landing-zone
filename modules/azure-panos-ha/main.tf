locals {
  resource_group_name = var.resource_group.create ? azurerm_resource_group.this[0].name : var.resource_group.name

  # One flat map keyed "<firewall key>/<interface key>".
  firewall_interfaces = merge([
    for fw_key, fw in var.firewalls : {
      for if_key, interface in var.interfaces : "${fw_key}/${if_key}" => merge(interface, {
        fw_key   = fw_key
        fw_name  = fw.name
        if_key   = if_key
        is_primary = fw.is_primary
      })
    }
  ]...)

  public_ips = { for key, interface in local.firewall_interfaces : key => interface if interface.public_ip }
}

resource "azurerm_resource_group" "this" {
  count = var.resource_group.create ? 1 : 0

  name     = var.resource_group.name
  location = var.location
  tags     = var.tags
}

resource "azurerm_public_ip" "this" {
  for_each = local.public_ips

  name                = "pip-${each.value.fw_name}-${each.value.if_key}"
  location            = var.location
  resource_group_name = local.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = lower("${var.public_ip_dns_prefix}-${each.value.fw_key}-${each.value.if_key}")
  tags                = var.tags
}

resource "azurerm_network_interface" "this" {
  for_each = local.firewall_interfaces

  name                          = "nic-${each.value.fw_name}-${each.value.if_key}"
  location                      = var.location
  resource_group_name           = local.resource_group_name
  enable_ip_forwarding          = each.value.ip_forwarding
  enable_accelerated_networking = each.value.accelerated_networking
  tags                          = var.tags

  ip_configuration {
    name                          = "ipconfig-${each.value.if_key}"
    subnet_id                     = each.value.subnet_id
    private_ip_address_allocation = "Static"
    private_ip_address            = cidrhost(
      each.value.subnet_cidr,
      each.value.is_primary ? each.value.primary_ip_offset : each.value.secondary_ip_offset
    )
    public_ip_address_id = each.value.public_ip ? azurerm_public_ip.this[each.key].id : null
  }
}

# Note: azurerm_virtual_machine is feature-frozen in the AzureRM provider but
# still supported in 4.x. Moving to azurerm_linux_virtual_machine changes
# resource addresses and therefore needs its own state migration, so it is
# deliberately a separate change rather than part of this module.
resource "azurerm_virtual_machine" "this" {
  for_each = var.firewalls

  name                = each.value.name
  location            = var.location
  resource_group_name = local.resource_group_name
  vm_size             = var.vm_size
  tags                = var.tags

  plan {
    name      = var.image.sku
    publisher = var.image.publisher
    product   = var.image.offer
  }

  storage_image_reference {
    publisher = var.image.publisher
    offer     = var.image.offer
    sku       = var.image.sku
    version   = var.image.version
  }

  storage_os_disk {
    name              = "osdisk-${each.value.name}"
    managed_disk_type = "Standard_LRS"
    caching           = "ReadWrite"
    create_option     = "FromImage"
  }

  os_profile {
    computer_name  = each.value.name
    admin_username = var.admin_username
    admin_password = var.admin_password
  }

  os_profile_linux_config {
    disable_password_authentication = false
  }

  boot_diagnostics {
    enabled     = false
    storage_uri = ""
  }

  # eth0..ethN follow interface_order, which is validated against the interface keys.
  primary_network_interface_id = azurerm_network_interface.this["${each.key}/${var.interface_order[0]}"].id
  network_interface_ids = [
    for if_key in var.interface_order : azurerm_network_interface.this["${each.key}/${if_key}"].id
  ]
}

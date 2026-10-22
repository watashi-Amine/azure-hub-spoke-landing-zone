resource "azurerm_public_ip" "this" {
  count = var.enabled ? 1 : 0

  name                = "pip-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = lower(var.dns_name)
  tags                = var.tags
}

resource "azurerm_network_interface" "this" {
  count = var.enabled ? 1 : 0

  name                = "nic-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  ip_configuration {
    name                          = "ipconfig-${var.name}"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Static"
    private_ip_address            = cidrhost(var.subnet_cidr, var.ip_offset)
    public_ip_address_id          = azurerm_public_ip.this[0].id
    primary                       = true
  }
}

# Note: see azure-panos-ha for why azurerm_virtual_machine is retained rather
# than migrated to azurerm_linux_virtual_machine in this release.
resource "azurerm_virtual_machine" "this" {
  count = var.enabled ? 1 : 0

  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
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
    name              = "osdisk-${var.name}"
    managed_disk_type = "Standard_LRS"
    caching           = "ReadWrite"
    create_option     = "FromImage"
  }

  os_profile {
    computer_name  = var.name
    admin_username = var.admin_username
    admin_password = var.admin_password
  }

  os_profile_linux_config {
    disable_password_authentication = false
  }

  primary_network_interface_id = azurerm_network_interface.this[0].id
  network_interface_ids        = [azurerm_network_interface.this[0].id]

  lifecycle {
    ignore_changes = [boot_diagnostics]
  }
}

resource "azurerm_managed_disk" "this" {
  count = var.enabled ? 1 : 0

  name                 = "disk-${var.name}-data"
  location             = var.location
  resource_group_name  = var.resource_group_name
  storage_account_type = "StandardSSD_LRS"
  create_option        = "Empty"
  disk_size_gb         = var.data_disk_size_gb
  tags                 = var.tags
}

resource "azurerm_virtual_machine_data_disk_attachment" "this" {
  count = var.enabled ? 1 : 0

  managed_disk_id    = azurerm_managed_disk.this[0].id
  virtual_machine_id = azurerm_virtual_machine.this[0].id
  lun                = 0
  caching            = "ReadWrite"
}

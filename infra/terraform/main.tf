locals {
  fqdn = "${var.dns_label}.${var.location}.cloudapp.azure.com"
  tags = {
    project = "smarterpillow"
    purpose = "snoring-inference"
  }
}

resource "azurerm_resource_group" "snoring" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.tags
}

resource "azurerm_virtual_network" "vnet" {
  name                = "snoring-vnet"
  address_space       = ["10.20.0.0/16"]
  location            = azurerm_resource_group.snoring.location
  resource_group_name = azurerm_resource_group.snoring.name
  tags                = local.tags
}

resource "azurerm_subnet" "sn" {
  name                 = "snoring-subnet"
  resource_group_name  = azurerm_resource_group.snoring.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.20.1.0/24"]
}

resource "azurerm_public_ip" "pip" {
  name                = "snoring-pip"
  location            = azurerm_resource_group.snoring.location
  resource_group_name = azurerm_resource_group.snoring.name
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = var.dns_label
  tags                = local.tags
}

resource "azurerm_network_security_group" "nsg" {
  name                = "snoring-nsg"
  location            = azurerm_resource_group.snoring.location
  resource_group_name = azurerm_resource_group.snoring.name
  tags                = local.tags

  security_rule {
    name                       = "ssh"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.allowed_ssh_cidr
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "http-acme"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "https"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface" "nic" {
  name                = "snoring-nic"
  location            = azurerm_resource_group.snoring.location
  resource_group_name = azurerm_resource_group.snoring.name
  tags                = local.tags

  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.sn.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip.id
  }
}

resource "azurerm_network_interface_security_group_association" "nic_nsg" {
  network_interface_id      = azurerm_network_interface.nic.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

resource "azurerm_linux_virtual_machine" "vm" {
  name                            = "snoring-vm"
  resource_group_name             = azurerm_resource_group.snoring.name
  location                        = azurerm_resource_group.snoring.location
  size                            = var.vm_size
  admin_username                  = var.admin_username
  network_interface_ids           = [azurerm_network_interface.nic.id]
  disable_password_authentication = true
  tags                            = local.tags

  admin_ssh_key {
    username   = var.admin_username
    public_key = file(pathexpand(var.ssh_public_key_path))
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 30
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  custom_data = base64encode(templatefile("${path.module}/cloud-init.yaml.tftpl", {
    hmac_secret        = var.hmac_secret
    fqdn               = local.fqdn
    admin_username     = var.admin_username
    server_tarball_b64 = filebase64("${path.module}/server_bundle.tar.gz")
  }))
}

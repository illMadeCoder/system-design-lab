provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
  subscription_id = "ea1c09cc-6150-4e0d-a054-9ea78916533b"
}

resource "azurerm_resource_group" "this" {
  name     = "1_single_server_startup"
  location = "eastus2"
}

resource "azurerm_virtual_network" "this" {
  name                = "tfvmex-network"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
}

resource "azurerm_subnet" "this" {
  name                 = "this"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = ["10.0.2.0/24"]
}

resource "azurerm_network_interface" "this" {
  name                = "tfvmex-nic"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  ip_configuration {
    name                          = "testconfiguration1"
    subnet_id                     = azurerm_subnet.this.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.this.id
  }
}

resource "azurerm_network_interface_security_group_association" "this" {
  network_interface_id      = azurerm_network_interface.this.id
  network_security_group_id = azurerm_network_security_group.this.id
}

resource "azurerm_public_ip" "this" {
  name                = "tfvmex-pip"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  allocation_method   = "Static"
}

resource "azurerm_network_security_group" "this" {
  name                = "tfvmex-nsg"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  security_rule {
    # Rule to allow HTTP/HTTPS from anywhere
    name                       = "Allow-HTTP"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Allow ICMP (traceroute/ping)
  security_rule {
    name                       = "Allow-ICMP"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Icmp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    # Rule to allow HTTP/HTTPS from anywhere
    name                       = "Allow-HTTPS"
    priority                   = 1003
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Allow SSH traffic only from the VPN address space (172.16.0.0/24)
  security_rule {
    name                       = "Allow-SSH-VPN"
    priority                   = 1004
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "172.16.0.0/24" # VPN client IP range
    destination_address_prefix = "*"
  }

  # Deny SSH traffic from public
  security_rule {
    name                       = "Deny-SSH-Public"
    priority                   = 1005
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Subnet for VPN Gateway
resource "azurerm_subnet" "this" {
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = ["10.0.3.0/24"]
}

# Public IP for the VPN Gateway
resource "azurerm_public_ip" "vpn_pip" {
  name                = "vpn-gateway-pip"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  allocation_method   = "Dynamic"
}

# VPN Gateway
resource "azurerm_virtual_network_gateway" "vpn_gateway" {
  name                = "vpn-gateway"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  type     = "Vpn"
  vpn_type = "RouteBased"
  sku      = "VpnGw1"

  ip_configuration {
    name                          = "vpngatewayconfig"
    public_ip_address_id          = azurerm_public_ip.vpn_pip.id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.this.id
  }

  vpn_client_configuration {
    address_space = ["172.16.0.0/24"]

    root_certificate {
      name = "vpn-cert"
      public_cert_data = filebase64("path_to_your_root_certificate.pem")
    }
  }
}

resource "azurerm_virtual_machine" "this" {
  name                  = "tfvmex-vm"
  location              = azurerm_resource_group.this.location
  resource_group_name   = azurerm_resource_group.this.name
  network_interface_ids = [azurerm_network_interface.this.id]
  vm_size               = "Standard_DS1_v2"

  # Uncomment this line to delete the OS disk automatically when deleting the VM
  #delete_os_disk_on_termination = true

  # Uncomment this line to delete the data disks automatically when deleting the VM
  #delete_data_disks_on_termination = true

  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }
  storage_os_disk {
    name              = "myosdisk1"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }
  os_profile {
    computer_name  = "hostname"
    admin_username = "testadmin"
    admin_password = "Password1234!"
  }
  os_profile_linux_config {
    disable_password_authentication = true
    ssh_keys {
      path     = "/home/testadmin/.ssh/authorized_keys"
      key_data = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDYD68lW91VgYmP6nt5kdPgtKWLDwY4FBVuDInpXXtjR0MyECJsU3wKOk0R3YVgN+0541qFNguUqBkY0Frl9eldZtYX48g0TH3omSwL7dCG0/AW/sDTAhErjwd42HQQc22xfWL0OGbbRcTIfPR6d4Kt5zps4vCaNaO0f1iLxLKEzE0YLCcOA7IIlchrRFSQRN0uap9DhiakTo1i5KMk9bBDAIWnSkhsZooAMg/dr2Lc4TOjXori/CKvB9z8Q4AEWPkdHX6ZSBJT47+NYXiU7oJt2UgIAE8kxdQGsMAErqfSkpjWDGlGad2EhTU+sb9O7+KMh3Nq24hKvj/qi7CKzNxVIyMDq0x6FqFhKYy3/1aIW+YL3Xt8eFPwZ9HAVAcnNqnFXQfB0D53+G7EIf8R6wXTrHSOtRrSmr64wPWwBkdT3mkBZ4Wlcad72x1kX8WWr84d/XwuoiS4fVBhc4E6E00EYlPJp94HKOj7ak3HVFNOQYo3CJ7/z/SMHKnpPkfOjMz0aJbsCxElj1PTA+gvlHttfZxrdc9kBg5uyBeyHAUCa7zeC2ke8YFU9x98rjCzMPwZSf2aFOQFJITFk7gVbKOA6L37DYffb+fvmB7w+EwpH5RMn81WKAAe7bqQXzGjcLff3m/v07Z1ir/UE+aPL+owPjGKYXYCWYxk7pls1vUzTw=="
    }
  }
  tags = {
    environment = "staging"
  }
}

terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

# Define a variable for the Cloudflare API token
variable "cloudflare_api_token" {
  description = "The API token for Cloudflare"
  type        = string
  sensitive   = true
}


# Retrieve Cloudflare zone (your domain)
data "cloudflare_zones" "this" {
  filter {
    name   = "illmadecoder.org" # Replace with your domain name
    status = "active"
  }
}

# Create an A record that points to your Azure VM's static IP
resource "cloudflare_record" "a_record" {
  zone_id = data.cloudflare_zones.this.zones[0].id

  name    = "illmadecoder.org"                # The root domain
  type    = "A"                               # A record to map domain to IP
  value   = azurerm_public_ip.this.ip_address # Static public IP from Azure
  ttl     = 3600                              # Time-to-live, 1 hour
  proxied = false                             # Set to false if you don't want Cloudflare's CDN/proxy features
}
# =============================================================================
# MÓDULO AZURE NETWORKING — VNet, NSGs, Bastion e DDoS Protection
# =============================================================================

# Resource Group principal da plataforma
resource "azurerm_resource_group" "main" {
  name     = "rg-${var.app_name}-${var.environment}"
  location = var.location

  tags = {
    environment = var.environment
    app         = var.app_name
    managed-by  = "terraform"
    team        = "devops"
  }
}

# Resource Group separado para o estado do Terraform (recomendado manter separado)
resource "azurerm_resource_group" "monitoring" {
  name     = "rg-${var.app_name}-${var.environment}-monitoring"
  location = var.location

  tags = {
    environment = var.environment
    app         = var.app_name
    managed-by  = "terraform"
    purpose     = "monitoring"
  }
}

# =============================================================================
# DDoS PROTECTION PLAN
# =============================================================================

resource "azurerm_network_ddos_protection_plan" "main" {
  name                = "ddos-${var.app_name}-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  tags = {
    environment = var.environment
    app         = var.app_name
  }
}

# =============================================================================
# VIRTUAL NETWORK
# =============================================================================

resource "azurerm_virtual_network" "main" {
  name                = "vnet-${var.app_name}-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = ["10.10.0.0/16"]

  # DDoS Protection Standard habilitado
  ddos_protection_plan {
    id     = azurerm_network_ddos_protection_plan.main.id
    enable = true
  }

  tags = {
    environment = var.environment
    app         = var.app_name
    managed-by  = "terraform"
  }
}

# =============================================================================
# SUBNETS
# =============================================================================

# Subnet para os nodes do AKS
resource "azurerm_subnet" "aks" {
  name                 = "snet-aks-${var.environment}"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.10.0.0/20"]    # 4096 IPs para nodes AKS

  # Necessário para AKS com Azure CNI
  service_endpoints = [
    "Microsoft.ContainerRegistry",
    "Microsoft.KeyVault",
    "Microsoft.Storage",
  ]
}

# Subnet para o Application Gateway (ingress do AKS)
resource "azurerm_subnet" "appgw" {
  name                 = "snet-appgw-${var.environment}"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.10.16.0/24"]   # 256 IPs para Application Gateway
}

# Subnet dedicada ao Azure Bastion (requisito: nome fixo AzureBastionSubnet)
resource "azurerm_subnet" "bastion" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.10.17.0/27"]   # Mínimo /27 para Bastion
}

# Subnet para serviços privados (banco de dados, cache, etc.)
resource "azurerm_subnet" "private_endpoints" {
  name                 = "snet-private-endpoints-${var.environment}"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.10.18.0/24"]

  private_endpoint_network_policies_enabled = false
}

# =============================================================================
# NETWORK SECURITY GROUPS
# =============================================================================

# NSG para subnet do AKS
resource "azurerm_network_security_group" "aks" {
  name                = "nsg-aks-${var.app_name}-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  # Nega todo tráfego de entrada por padrão (security-first)
  security_rule {
    name                       = "DenyAllInbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Permite tráfego interno da VNet
  security_rule {
    name                       = "AllowVNetInbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  # Permite health checks do Azure Load Balancer
  security_rule {
    name                       = "AllowAzureLoadBalancerInbound"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["10250", "30000-32767"]
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }

  # Permite HTTPS para o Application Gateway encaminhar para os pods
  security_rule {
    name                       = "AllowHTTPSFromAppGW"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["443", "80", "8080"]
    source_address_prefix      = "10.10.16.0/24"  # Subnet do Application Gateway
    destination_address_prefix = "10.10.0.0/20"
  }

  tags = {
    environment = var.environment
    app         = var.app_name
  }
}

# NSG para Application Gateway
resource "azurerm_network_security_group" "appgw" {
  name                = "nsg-appgw-${var.app_name}-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  # Regra obrigatória para o Application Gateway funcionar
  security_rule {
    name                       = "AllowGatewayManagerInbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "65200-65535"
    source_address_prefix      = "GatewayManager"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowHTTPSInbound"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["80", "443"]
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

  tags = {
    environment = var.environment
    app         = var.app_name
  }
}

# Associações NSG → Subnets
resource "azurerm_subnet_network_security_group_association" "aks" {
  subnet_id                 = azurerm_subnet.aks.id
  network_security_group_id = azurerm_network_security_group.aks.id
}

resource "azurerm_subnet_network_security_group_association" "appgw" {
  subnet_id                 = azurerm_subnet.appgw.id
  network_security_group_id = azurerm_network_security_group.appgw.id
}

# =============================================================================
# AZURE BASTION — Acesso seguro sem IP público nos nodes
# =============================================================================

# IP público do Bastion (SKU Standard obrigatório)
resource "azurerm_public_ip" "bastion" {
  name                = "pip-bastion-${var.app_name}-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = {
    environment = var.environment
    app         = var.app_name
    purpose     = "bastion"
  }
}

resource "azurerm_bastion_host" "main" {
  name                = "bastion-${var.app_name}-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "Standard"

  # Habilita tunneling nativo (SSH/RDP via browser)
  tunneling_enabled = true

  ip_configuration {
    name                 = "configuration"
    subnet_id            = azurerm_subnet.bastion.id
    public_ip_address_id = azurerm_public_ip.bastion.id
  }

  tags = {
    environment = var.environment
    app         = var.app_name
    managed-by  = "terraform"
  }
}

# =============================================================================
# LOG ANALYTICS WORKSPACE — Centraliza logs do AKS e outros recursos
# =============================================================================

resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-${var.app_name}-${var.environment}"
  location            = azurerm_resource_group.monitoring.location
  resource_group_name = azurerm_resource_group.monitoring.name
  sku                 = "PerGB2018"
  retention_in_days   = 90

  tags = {
    environment = var.environment
    app         = var.app_name
    managed-by  = "terraform"
  }
}

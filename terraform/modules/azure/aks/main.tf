# =============================================================================
# MÓDULO AZURE AKS — Cluster Kubernetes com CNI, OIDC e Monitoring
# =============================================================================

# Container Registry para imagens Docker (associado ao AKS)
resource "azurerm_container_registry" "main" {
  name                = "acr${replace(var.app_name, "-", "")}${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "Premium"

  # Georeplica para alta disponibilidade (adicionar outras regiões conforme necessário)
  # georeplications {
  #   location = "westus"
  # }

  # Acesso via rede privada (necessário configurar private endpoint separadamente)
  public_network_access_enabled = false
  network_rule_bypass_option    = "AzureServices"

  tags = {
    environment = var.environment
    app         = var.app_name
    managed-by  = "terraform"
  }
}

# =============================================================================
# CLUSTER AKS
# =============================================================================

resource "azurerm_kubernetes_cluster" "main" {
  name                = "aks-${var.app_name}-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = "${var.app_name}-${var.environment}"

  kubernetes_version        = var.aks_config.kubernetes_version
  automatic_channel_upgrade = "stable"

  # Cluster privado: sem endpoint público do control plane
  private_cluster_enabled             = true
  private_cluster_public_fqdn_enabled = false

  # OIDC Issuer: habilita Workload Identity nos pods
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  # Azure AD integração para RBAC
  azure_active_directory_role_based_access_control {
    managed            = true
    azure_rbac_enabled = true
  }

  # Node pool system: componentes do control plane do Kubernetes
  default_node_pool {
    name                        = "system"
    vm_size                     = var.aks_config.system_node_vm_size
    vnet_subnet_id              = var.aks_subnet_id
    min_count                   = var.aks_config.system_node_min_count
    max_count                   = var.aks_config.system_node_max_count
    enable_auto_scaling         = true
    only_critical_addons_enabled = true  # Apenas componentes system neste pool
    os_disk_size_gb             = 128
    os_disk_type                = "Ephemeral"  # Mais rápido e sem custo extra de disco

    # Upgrade progressivo dos nodes
    upgrade_settings {
      max_surge = "33%"
    }

    node_labels = {
      "nodepool-type" = "system"
      "environment"   = var.environment
      "app"           = var.app_name
    }

    tags = {
      environment   = var.environment
      app           = var.app_name
      "node-pool"   = "system"
    }
  }

  # Configuração de identidade gerenciada
  identity {
    type = "SystemAssigned"
  }

  # Rede: Azure CNI (cada pod recebe IP da VNet)
  network_profile {
    network_plugin     = "azure"
    network_policy     = var.aks_config.network_policy
    load_balancer_sku  = "standard"
    outbound_type      = "loadBalancer"
    service_cidr       = "172.16.0.0/16"
    dns_service_ip     = "172.16.0.10"
  }

  # Monitoring: integração com Log Analytics
  dynamic "oms_agent" {
    for_each = var.aks_config.enable_oms_agent ? [1] : []
    content {
      log_analytics_workspace_id      = var.log_analytics_id
      msi_auth_for_monitoring_enabled = true
    }
  }

  # Azure Policy addon para conformidade de pods
  dynamic "azure_policy" {
    for_each = var.aks_config.enable_azure_policy ? [1] : []
    content {
      enabled = true
    }
  }

  # Manutenção planejada (finais de semana de madrugada)
  maintenance_window {
    allowed {
      day   = "Saturday"
      hours = [2, 3, 4]
    }
    allowed {
      day   = "Sunday"
      hours = [2, 3, 4]
    }
  }

  tags = {
    environment = var.environment
    app         = var.app_name
    managed-by  = "terraform"
    team        = "devops"
  }

  lifecycle {
    ignore_changes = [
      # Ignora mudanças automáticas na versão do Kubernetes via auto-upgrade
      kubernetes_version,
      default_node_pool[0].node_count,
    ]
  }
}

# =============================================================================
# NODE POOL EXTRA — Para workloads de aplicação
# =============================================================================

resource "azurerm_kubernetes_cluster_node_pool" "user" {
  name                  = "user"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  vm_size               = var.aks_config.user_node_vm_size
  vnet_subnet_id        = var.aks_subnet_id
  min_count             = var.aks_config.user_node_min_count
  max_count             = var.aks_config.user_node_max_count
  enable_auto_scaling   = true
  os_disk_size_gb       = 256
  os_disk_type          = "Managed"
  mode                  = "User"   # Pool para workloads de aplicação

  upgrade_settings {
    max_surge = "33%"
  }

  node_labels = {
    "nodepool-type" = "user"
    "environment"   = var.environment
    "workload-type" = "application"
  }

  node_taints = []  # Sem taints: aceita qualquer workload

  tags = {
    environment = var.environment
    app         = var.app_name
    "node-pool" = "user"
  }
}

# =============================================================================
# RBAC — Permissões do AKS
# =============================================================================

# AKS pode fazer pull de imagens do Container Registry
resource "azurerm_role_assignment" "aks_acr_pull" {
  principal_id                     = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
  role_definition_name             = "AcrPull"
  scope                            = azurerm_container_registry.main.id
  skip_service_principal_aad_check = true
}

# AKS pode ler configurações de rede (necessário para Azure CNI)
resource "azurerm_role_assignment" "aks_network_contributor" {
  principal_id         = azurerm_kubernetes_cluster.main.identity[0].principal_id
  role_definition_name = "Network Contributor"
  scope                = var.vnet_id
}

# =============================================================================
# AZURE METRIC ALERTS — AKS e Application Gateway
# =============================================================================

variable "azure_subscription_id" {
  description = "ID da Subscription Azure"
  type        = string
}

variable "resource_group_name" {
  description = "Nome do Resource Group onde os alertas serão criados"
  type        = string
}

variable "location" {
  description = "Região Azure"
  type        = string
  default     = "eastus"
}

variable "aks_cluster_name" {
  description = "Nome do cluster AKS"
  type        = string
}

variable "app_gateway_name" {
  description = "Nome do Application Gateway"
  type        = string
  default     = ""
}

variable "log_analytics_workspace_id" {
  description = "ID do Log Analytics Workspace"
  type        = string
}

variable "alert_email" {
  description = "E-mail para notificações"
  type        = string
  default     = "devops-team@empresa.com"
}

variable "app_name" {
  description = "Nome da aplicação"
  type        = string
  default     = "devops-platform"
}

# =============================================================================
# ACTION GROUP
# =============================================================================

resource "azurerm_monitor_action_group" "alerts" {
  name                = "ag-${var.app_name}-alerts"
  resource_group_name = var.resource_group_name
  short_name          = "alerts"

  email_receiver {
    name                    = "DevOps Team"
    email_address           = var.alert_email
    use_common_alert_schema = true
  }

  tags = {
    environment = "production"
    app         = var.app_name
    managed-by  = "terraform"
  }
}

locals {
  aks_resource_id = "/subscriptions/${var.azure_subscription_id}/resourceGroups/${var.resource_group_name}/providers/Microsoft.ContainerService/managedClusters/${var.aks_cluster_name}"
}

# =============================================================================
# ALERTA: CPU dos Nodes AKS > 80%
# =============================================================================

resource "azurerm_monitor_metric_alert" "aks_cpu_high" {
  name                = "alert-${var.app_name}-aks-cpu-high"
  resource_group_name = var.resource_group_name
  scopes              = [local.aks_resource_id]
  description         = "CPU dos nodes AKS acima de 80% por 5 minutos. Verificar workloads ou escalar node pool."
  severity            = 2  # Warning
  frequency           = "PT1M"
  window_size         = "PT5M"
  enabled             = true
  auto_mitigate       = true

  criteria {
    metric_namespace = "Microsoft.ContainerService/managedClusters"
    metric_name      = "node_cpu_usage_percentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }

  action {
    action_group_id = azurerm_monitor_action_group.alerts.id
  }

  tags = {
    environment = "production"
    app         = var.app_name
    managed-by  = "terraform"
  }
}

# =============================================================================
# ALERTA: Memória dos Nodes AKS > 85%
# =============================================================================

resource "azurerm_monitor_metric_alert" "aks_memory_high" {
  name                = "alert-${var.app_name}-aks-memory-high"
  resource_group_name = var.resource_group_name
  scopes              = [local.aks_resource_id]
  description         = "Memória dos nodes AKS acima de 85%. Risco de OOMKill. Verificar memory limits dos pods."
  severity            = 1  # Error
  frequency           = "PT1M"
  window_size         = "PT5M"
  enabled             = true
  auto_mitigate       = true

  criteria {
    metric_namespace = "Microsoft.ContainerService/managedClusters"
    metric_name      = "node_memory_working_set_percentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 85
  }

  action {
    action_group_id = azurerm_monitor_action_group.alerts.id
  }

  tags = {
    environment = "production"
    app         = var.app_name
    managed-by  = "terraform"
  }
}

# =============================================================================
# ALERTA: Application Gateway — Taxa de erros 5xx > 5%
# =============================================================================

resource "azurerm_monitor_metric_alert" "appgw_5xx_rate" {
  count               = var.app_gateway_name != "" ? 1 : 0
  name                = "alert-${var.app_name}-appgw-5xx"
  resource_group_name = var.resource_group_name
  scopes = [
    "/subscriptions/${var.azure_subscription_id}/resourceGroups/${var.resource_group_name}/providers/Microsoft.Network/applicationGateways/${var.app_gateway_name}"
  ]
  description = "Taxa de erros HTTP 5xx no Application Gateway acima de 5%. Verificar backend pools e logs de acesso."
  severity    = 1
  frequency   = "PT1M"
  window_size = "PT5M"
  enabled     = true

  criteria {
    metric_namespace = "Microsoft.Network/applicationGateways"
    metric_name      = "FailedRequests"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 10  # Ajustar conforme volume de tráfego

    dimension {
      name     = "BackendSettingsPool"
      operator = "Include"
      values   = ["*"]
    }
  }

  action {
    action_group_id = azurerm_monitor_action_group.alerts.id
  }

  tags = {
    environment = "production"
    app         = var.app_name
    managed-by  = "terraform"
  }
}

# =============================================================================
# ALERTA: Pods com restart count alto (CrashLoopBackOff)
# =============================================================================

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "pod_crash_loop" {
  name                = "alert-${var.app_name}-pod-crash-loop"
  resource_group_name = var.resource_group_name
  location            = var.location
  description         = "Pods com mais de 5 restarts em 10 minutos — possível CrashLoopBackOff"
  severity            = 1
  enabled             = true
  scopes              = [var.log_analytics_workspace_id]

  evaluation_frequency = "PT5M"
  window_duration      = "PT10M"

  criteria {
    query = <<-QUERY
      KubePodInventory
      | where ClusterName == "${var.aks_cluster_name}"
      | where ContainerStatusReason == "CrashLoopBackOff"
      | summarize PodCount = count() by Namespace, Name, bin(TimeGenerated, 5m)
      | where PodCount > 0
    QUERY

    time_aggregation_method = "Count"
    threshold               = 0
    operator                = "GreaterThan"

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 2
    }
  }

  action {
    action_groups = [azurerm_monitor_action_group.alerts.id]

    custom_properties = {
      alert_type = "CrashLoopBackOff"
      app        = var.app_name
      cluster    = var.aks_cluster_name
    }
  }

  tags = {
    environment = "production"
    app         = var.app_name
    managed-by  = "terraform"
  }
}

# =============================================================================
# ALERTA: Disk usage dos nodes AKS > 90%
# =============================================================================

resource "azurerm_monitor_metric_alert" "aks_disk_high" {
  name                = "alert-${var.app_name}-aks-disk-high"
  resource_group_name = var.resource_group_name
  scopes              = [local.aks_resource_id]
  description         = "Uso de disco dos nodes AKS acima de 90%. Risco de falha em pods que escrevem no disco."
  severity            = 1
  frequency           = "PT5M"
  window_size         = "PT15M"
  enabled             = true
  auto_mitigate       = true

  criteria {
    metric_namespace = "Microsoft.ContainerService/managedClusters"
    metric_name      = "node_disk_usage_percentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 90
  }

  action {
    action_group_id = azurerm_monitor_action_group.alerts.id
  }

  tags = {
    environment = "production"
    app         = var.app_name
    managed-by  = "terraform"
  }
}

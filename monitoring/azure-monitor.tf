# =============================================================================
# AZURE MONITOR — Log Analytics Queries, Alertas e Action Groups
# =============================================================================

variable "azure_subscription_id" {
  description = "ID da Subscription Azure"
  type        = string
}

variable "log_analytics_workspace_id" {
  description = "ID do Log Analytics Workspace para as queries e alertas"
  type        = string
}

variable "log_analytics_workspace_name" {
  description = "Nome do Log Analytics Workspace"
  type        = string
}

variable "resource_group_name" {
  description = "Nome do Resource Group onde os alertas serão criados"
  type        = string
}

variable "location" {
  description = "Região Azure para os recursos de monitoring"
  type        = string
  default     = "eastus"
}

variable "alert_email" {
  description = "E-mail para receber notificações de alerta"
  type        = string
  default     = "devops-team@empresa.com"
}

variable "aks_cluster_name" {
  description = "Nome do cluster AKS para filtros dos alertas"
  type        = string
}

variable "app_name" {
  description = "Nome da aplicação"
  type        = string
  default     = "devops-platform"
}

# =============================================================================
# ACTION GROUP — Notificações de Alerta
# =============================================================================

resource "azurerm_monitor_action_group" "devops_team" {
  name                = "ag-${var.app_name}-devops-team"
  resource_group_name = var.resource_group_name
  short_name          = "devops"

  email_receiver {
    name                    = "Equipe DevOps"
    email_address           = var.alert_email
    use_common_alert_schema = true
  }

  # Webhook para integração com Slack/PagerDuty (configurar URL)
  # webhook_receiver {
  #   name        = "Slack DevOps Channel"
  #   service_uri = "https://hooks.slack.com/services/T.../B.../xxx"
  # }

  tags = {
    environment = "production"
    app         = var.app_name
    managed-by  = "terraform"
  }
}

# =============================================================================
# SAVED QUERIES — Log Analytics Workbook Queries
# =============================================================================

# Query: Pods com CrashLoopBackOff (últimas 24h)
resource "azurerm_log_analytics_saved_search" "pod_crash_loops" {
  name                       = "PodCrashLoops-${var.app_name}"
  log_analytics_workspace_id = var.log_analytics_workspace_id
  category                   = "Kubernetes"
  display_name               = "[${var.app_name}] Pods em CrashLoopBackOff"
  query                      = <<-QUERY
    KubePodInventory
    | where TimeGenerated > ago(24h)
    | where ClusterName == "${var.aks_cluster_name}"
    | where ContainerStatusReason == "CrashLoopBackOff"
    | project TimeGenerated, Namespace, Name, ContainerName, ContainerStatus, ContainerStatusReason
    | summarize count() by Name, Namespace, ContainerStatusReason
    | order by count_ desc
  QUERY
  function_alias = "PodCrashLoops"
}

# Query: Error Rate por endpoint (últimas 1h)
resource "azurerm_log_analytics_saved_search" "error_rate_by_endpoint" {
  name                       = "ErrorRateByEndpoint-${var.app_name}"
  log_analytics_workspace_id = var.log_analytics_workspace_id
  category                   = "Application"
  display_name               = "[${var.app_name}] Error Rate por Endpoint"
  query                      = <<-QUERY
    ContainerLog
    | where TimeGenerated > ago(1h)
    | where ContainerID contains "${var.app_name}"
    | extend ParsedLog = parse_json(LogEntry)
    | where ParsedLog.status_code >= 500
    | summarize ErrorCount = count(),
                ErrorRate = countif(ParsedLog.status_code >= 500) * 100.0 / count()
        by endpoint = tostring(ParsedLog.endpoint), bin(TimeGenerated, 5m)
    | order by TimeGenerated desc, ErrorRate desc
  QUERY
  function_alias = "ErrorRateByEndpoint"
}

# Query: Blue/Green slot traffic split
resource "azurerm_log_analytics_saved_search" "blue_green_traffic" {
  name                       = "BlueGreenTrafficSplit-${var.app_name}"
  log_analytics_workspace_id = var.log_analytics_workspace_id
  category                   = "Deployment"
  display_name               = "[${var.app_name}] Blue/Green Traffic Split"
  query                      = <<-QUERY
    ContainerLog
    | where TimeGenerated > ago(1h)
    | where ContainerID contains "${var.app_name}"
    | extend slot = extract("slot.*?:(\\w+)", 1, LogEntry)
    | where slot in ("blue", "green", "canary")
    | summarize RequestCount = count() by slot, bin(TimeGenerated, 5m)
    | extend TotalRequests = sum(RequestCount)
    | extend TrafficPercentage = RequestCount * 100.0 / TotalRequests
    | project TimeGenerated, slot, RequestCount, TrafficPercentage
    | order by TimeGenerated desc
  QUERY
  function_alias = "BlueGreenTrafficSplit"
}

# =============================================================================
# METRIC ALERTS — AKS
# =============================================================================

# Alerta: CPU alto nos nodes AKS (>80%)
resource "azurerm_monitor_metric_alert" "aks_high_cpu" {
  name                = "alert-${var.app_name}-aks-high-cpu"
  resource_group_name = var.resource_group_name
  scopes              = ["/subscriptions/${var.azure_subscription_id}/resourceGroups/${var.resource_group_name}/providers/Microsoft.ContainerService/managedClusters/${var.aks_cluster_name}"]
  description         = "Alerta quando a CPU média dos nodes AKS ultrapassa 80%"
  severity            = 2  # Warning
  frequency           = "PT5M"
  window_size         = "PT15M"
  enabled             = true

  criteria {
    metric_namespace = "Microsoft.ContainerService/managedClusters"
    metric_name      = "node_cpu_usage_percentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }

  action {
    action_group_id = azurerm_monitor_action_group.devops_team.id
  }

  tags = {
    environment = "production"
    app         = var.app_name
    managed-by  = "terraform"
  }
}

# Alerta: Memória alta nos nodes AKS (>85%)
resource "azurerm_monitor_metric_alert" "aks_high_memory" {
  name                = "alert-${var.app_name}-aks-high-memory"
  resource_group_name = var.resource_group_name
  scopes              = ["/subscriptions/${var.azure_subscription_id}/resourceGroups/${var.resource_group_name}/providers/Microsoft.ContainerService/managedClusters/${var.aks_cluster_name}"]
  description         = "Alerta quando a memória média dos nodes AKS ultrapassa 85%"
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"
  enabled             = true

  criteria {
    metric_namespace = "Microsoft.ContainerService/managedClusters"
    metric_name      = "node_memory_working_set_percentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 85
  }

  action {
    action_group_id = azurerm_monitor_action_group.devops_team.id
  }

  tags = {
    environment = "production"
    app         = var.app_name
    managed-by  = "terraform"
  }
}

# Alerta: Pods não prontos no AKS
resource "azurerm_monitor_metric_alert" "aks_pods_not_ready" {
  name                = "alert-${var.app_name}-aks-pods-not-ready"
  resource_group_name = var.resource_group_name
  scopes              = ["/subscriptions/${var.azure_subscription_id}/resourceGroups/${var.resource_group_name}/providers/Microsoft.ContainerService/managedClusters/${var.aks_cluster_name}"]
  description         = "Alerta quando há pods não prontos por mais de 5 minutos"
  severity            = 1  # Error
  frequency           = "PT5M"
  window_size         = "PT10M"
  enabled             = true

  criteria {
    metric_namespace = "Microsoft.ContainerService/managedClusters"
    metric_name      = "kube_pod_status_ready"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = 1

    dimension {
      name     = "condition"
      operator = "Include"
      values   = ["false"]
    }
  }

  action {
    action_group_id = azurerm_monitor_action_group.devops_team.id
  }

  tags = {
    environment = "production"
    app         = var.app_name
    managed-by  = "terraform"
  }
}

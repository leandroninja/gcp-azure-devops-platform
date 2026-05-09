# =============================================================================
# VARIÁVEIS — Módulo Azure AKS
# =============================================================================

variable "location" {
  description = "Região Azure para o cluster AKS"
  type        = string
}

variable "environment" {
  description = "Ambiente: development, staging ou production"
  type        = string
}

variable "app_name" {
  description = "Prefixo para os nomes dos recursos AKS"
  type        = string
}

variable "aks_config" {
  description = "Objeto com todas as configurações do cluster AKS"
  type = object({
    kubernetes_version    = string
    system_node_vm_size   = string
    system_node_min_count = number
    system_node_max_count = number
    user_node_vm_size     = string
    user_node_min_count   = number
    user_node_max_count   = number
    enable_azure_policy   = bool
    enable_oms_agent      = bool
    network_policy        = string
  })
}

variable "resource_group_name" {
  description = "Nome do Resource Group onde o AKS será provisionado"
  type        = string
}

variable "vnet_id" {
  description = "ID da VNet para configuração de rede do AKS"
  type        = string
}

variable "aks_subnet_id" {
  description = "ID da subnet para os nodes do AKS (Azure CNI)"
  type        = string
}

variable "log_analytics_id" {
  description = "ID do Log Analytics Workspace para monitoramento do AKS"
  type        = string
}

# =============================================================================
# VARIÁVEIS — Módulo Azure Key Vault
# =============================================================================

variable "location" {
  description = "Região Azure para o Key Vault"
  type        = string
}

variable "environment" {
  description = "Ambiente: development, staging ou production"
  type        = string
}

variable "app_name" {
  description = "Prefixo para o nome do Key Vault"
  type        = string
}

variable "resource_group_name" {
  description = "Nome do Resource Group onde o Key Vault será criado"
  type        = string
}

variable "aks_kubelet_identity_id" {
  description = "Object ID da identidade Kubelet do AKS (para leitura de secrets via Workload Identity)"
  type        = string
}

variable "cicd_principal_id" {
  description = "Object ID do Service Principal ou Managed Identity do pipeline CI/CD (para gerenciar secrets)"
  type        = string
}

variable "aks_subnet_id" {
  description = "ID da subnet do AKS para configuração de network ACLs do Key Vault"
  type        = string
  default     = null
}

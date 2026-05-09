# =============================================================================
# VARIÁVEIS — Módulo GCP Secret Manager
# =============================================================================

variable "project_id" {
  description = "ID do projeto GCP"
  type        = string
}

variable "region" {
  description = "Região GCP para replicação dos secrets"
  type        = string
}

variable "environment" {
  description = "Ambiente: development, staging ou production"
  type        = string
}

variable "app_name" {
  description = "Prefixo para os nomes dos secrets"
  type        = string
}

variable "cicd_sa_email" {
  description = "E-mail da Service Account do CI/CD que terá acesso de leitura aos secrets"
  type        = string
}

variable "gke_sa_email" {
  description = "E-mail da Service Account dos nodes GKE que terá acesso aos secrets da aplicação"
  type        = string
}

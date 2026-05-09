# =============================================================================
# VARIÁVEIS — Módulo GCP IAM
# =============================================================================

variable "project_id" {
  description = "ID do projeto GCP"
  type        = string
}

variable "environment" {
  description = "Ambiente: development, staging ou production"
  type        = string
}

variable "app_name" {
  description = "Prefixo usado no nome dos recursos IAM"
  type        = string
}

variable "github_org" {
  description = "Organização GitHub para o Workload Identity binding (ex: minha-empresa)"
  type        = string
}

variable "github_repo" {
  description = "Nome do repositório GitHub para o Workload Identity binding (ex: gcp-azure-devops-platform)"
  type        = string
}

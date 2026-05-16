# =============================================================================
# VARIÁVEIS — Módulo GCP Networking
# =============================================================================

variable "project_id" {
  description = "ID do projeto GCP"
  type        = string
}

variable "region" {
  description = "Região GCP para os recursos de rede"
  type        = string
  default     = "us-central1"
}

variable "environment" {
  description = "Ambiente: development, staging ou production"
  type        = string
}

variable "app_name" {
  description = "Prefixo usado no nome dos recursos de rede"
  type        = string
}

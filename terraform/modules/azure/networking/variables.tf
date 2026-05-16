# =============================================================================
# VARIÁVEIS — Módulo Azure Networking
# =============================================================================

variable "location" {
  description = "Região Azure onde os recursos de rede serão provisionados (ex: eastus, brazilsouth)"
  type        = string
}

variable "environment" {
  description = "Ambiente: development, staging ou production"
  type        = string
}

variable "app_name" {
  description = "Prefixo usado nos nomes dos recursos de rede Azure"
  type        = string
}

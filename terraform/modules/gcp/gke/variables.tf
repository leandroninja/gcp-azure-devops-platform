# =============================================================================
# VARIÁVEIS — Módulo GCP GKE
# =============================================================================

variable "project_id" {
  description = "ID do projeto GCP"
  type        = string
}

variable "region" {
  description = "Região GCP para o cluster GKE (cluster regional para HA)"
  type        = string
}

variable "environment" {
  description = "Ambiente: development, staging ou production"
  type        = string
}

variable "app_name" {
  description = "Prefixo para os nomes dos recursos GKE"
  type        = string
}

variable "gke_config" {
  description = "Objeto com todas as configurações do cluster GKE"
  type = object({
    cluster_version      = string
    node_machine_type    = string
    node_disk_size_gb    = number
    node_pool_min_count  = number
    node_pool_max_count  = number
    enable_private_nodes = bool
    master_cidr          = string
  })
}

variable "network_id" {
  description = "ID da VPC onde o cluster será provisionado"
  type        = string
}

variable "subnetwork_id" {
  description = "ID da subnet onde os nodes serão provisionados"
  type        = string
}

variable "pods_range_name" {
  description = "Nome do secondary IP range para os Pods"
  type        = string
}

variable "svcs_range_name" {
  description = "Nome do secondary IP range para os Services"
  type        = string
}

variable "gke_sa_email" {
  description = "E-mail da Service Account que será atribuída aos nodes do GKE"
  type        = string
}

# =============================================================================
# VARIÁVEIS GLOBAIS DA PLATAFORMA DEVOPS MULTI-CLOUD
# =============================================================================

# -----------------------------------------------------------------------------
# GCP — Configurações Gerais
# -----------------------------------------------------------------------------

variable "gcp_project_id" {
  description = "ID do projeto GCP onde a infraestrutura será provisionada"
  type        = string

  validation {
    condition     = length(var.gcp_project_id) > 0
    error_message = "O ID do projeto GCP não pode ser vazio."
  }
}

variable "gcp_region" {
  description = "Região GCP para provisionamento dos recursos (ex: us-central1, southamerica-east1)"
  type        = string
  default     = "us-central1"
}

variable "gcp_impersonate_sa" {
  description = "Service Account para impersonação em execução local (opcional, deixe vazio em CI/CD)"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Azure — Configurações Gerais
# -----------------------------------------------------------------------------

variable "azure_subscription_id" {
  description = "ID da Subscription Azure"
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.azure_subscription_id))
    error_message = "O ID da Subscription Azure deve ser um UUID válido."
  }
}

variable "azure_location" {
  description = "Região Azure para provisionamento dos recursos (ex: eastus, brazilsouth)"
  type        = string
  default     = "eastus"
}

variable "azure_cicd_principal_id" {
  description = "Object ID do Service Principal ou Managed Identity usado pelo pipeline CI/CD para acessar o Key Vault"
  type        = string
}

# -----------------------------------------------------------------------------
# Configurações Compartilhadas
# -----------------------------------------------------------------------------

variable "environment" {
  description = "Ambiente de destino: development, staging ou production"
  type        = string
  default     = "production"

  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "O ambiente deve ser 'development', 'staging' ou 'production'."
  }
}

variable "app_name" {
  description = "Nome da aplicação, usado como prefixo nos recursos provisionados"
  type        = string
  default     = "devops-platform"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,28}[a-z0-9]$", var.app_name))
    error_message = "O nome da aplicação deve conter apenas letras minúsculas, números e hífens (3-30 caracteres)."
  }
}

# -----------------------------------------------------------------------------
# GitHub — Workload Identity Federation
# -----------------------------------------------------------------------------

variable "github_org" {
  description = "Organização ou usuário do GitHub (ex: minha-empresa)"
  type        = string
}

variable "github_repo" {
  description = "Nome do repositório GitHub (sem a org, ex: gcp-azure-devops-platform)"
  type        = string
}

# -----------------------------------------------------------------------------
# GKE — Configuração do Cluster
# -----------------------------------------------------------------------------

variable "gke_config" {
  description = "Configurações do cluster GKE"
  type = object({
    cluster_version       = string  # Versão do Kubernetes (ex: "1.28")
    node_machine_type     = string  # Tipo de máquina para os nodes (ex: "e2-standard-4")
    node_disk_size_gb     = number  # Tamanho do disco dos nodes em GB
    node_pool_min_count   = number  # Mínimo de nodes por zona no auto-scaling
    node_pool_max_count   = number  # Máximo de nodes por zona no auto-scaling
    enable_private_nodes  = bool    # Habilita nodes sem IP público
    master_cidr           = string  # CIDR do plano de controle (ex: "172.16.0.0/28")
  })

  default = {
    cluster_version      = "1.28"
    node_machine_type    = "e2-standard-4"
    node_disk_size_gb    = 100
    node_pool_min_count  = 2
    node_pool_max_count  = 8
    enable_private_nodes = true
    master_cidr          = "172.16.0.0/28"
  }
}

# -----------------------------------------------------------------------------
# AKS — Configuração do Cluster
# -----------------------------------------------------------------------------

variable "aks_config" {
  description = "Configurações do cluster AKS"
  type = object({
    kubernetes_version         = string  # Versão do Kubernetes (ex: "1.28")
    system_node_vm_size        = string  # Tamanho das VMs do node pool system
    system_node_min_count      = number  # Mínimo de nodes system
    system_node_max_count      = number  # Máximo de nodes system
    user_node_vm_size          = string  # Tamanho das VMs do node pool user
    user_node_min_count        = number  # Mínimo de nodes user
    user_node_max_count        = number  # Máximo de nodes user
    enable_azure_policy        = bool    # Habilita Azure Policy para Kubernetes
    enable_oms_agent           = bool    # Habilita OMS agent para Log Analytics
    network_policy             = string  # Política de rede: "azure" ou "calico"
  })

  default = {
    kubernetes_version    = "1.28"
    system_node_vm_size   = "Standard_D4s_v3"
    system_node_min_count = 2
    system_node_max_count = 5
    user_node_vm_size     = "Standard_D8s_v3"
    user_node_min_count   = 1
    user_node_max_count   = 10
    enable_azure_policy   = true
    enable_oms_agent      = true
    network_policy        = "azure"
  }
}

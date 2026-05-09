# =============================================================================
# OUTPUTS GLOBAIS DA PLATAFORMA DEVOPS MULTI-CLOUD
# =============================================================================

# -----------------------------------------------------------------------------
# GCP — Outputs do GKE
# -----------------------------------------------------------------------------

output "gke_endpoint" {
  description = "Endpoint privado do cluster GKE (IP do plano de controle)"
  value       = module.gcp_gke.cluster_endpoint
  sensitive   = true
}

output "gke_cluster_name" {
  description = "Nome do cluster GKE provisionado"
  value       = module.gcp_gke.cluster_name
}

output "gke_cluster_ca_certificate" {
  description = "Certificado CA do cluster GKE (base64)"
  value       = module.gcp_gke.cluster_ca_certificate
  sensitive   = true
}

output "gke_get_credentials_command" {
  description = "Comando gcloud para obter as credenciais do cluster GKE"
  value       = "gcloud container clusters get-credentials ${module.gcp_gke.cluster_name} --region ${var.gcp_region} --project ${var.gcp_project_id}"
}

# -----------------------------------------------------------------------------
# GCP — Outputs do Secret Manager
# -----------------------------------------------------------------------------

output "gcp_secret_manager_ids" {
  description = "Mapa com os IDs de todos os secrets criados no GCP Secret Manager"
  value       = module.gcp_secret_manager.secret_ids
}

output "gcp_secret_manager_project" {
  description = "Projeto GCP onde os secrets estão armazenados"
  value       = var.gcp_project_id
}

# -----------------------------------------------------------------------------
# GCP — Outputs de IAM
# -----------------------------------------------------------------------------

output "gcp_cicd_sa_email" {
  description = "E-mail da Service Account usada pelo pipeline CI/CD no GCP"
  value       = module.gcp_iam.cicd_sa_email
}

output "gcp_workload_identity_provider" {
  description = "Resource name do Workload Identity Provider para configurar no GitHub Actions"
  value       = module.gcp_iam.workload_identity_provider
}

# -----------------------------------------------------------------------------
# Azure — Outputs do AKS
# -----------------------------------------------------------------------------

output "aks_fqdn" {
  description = "FQDN privado do cluster AKS"
  value       = module.azure_aks.cluster_fqdn
  sensitive   = true
}

output "aks_cluster_name" {
  description = "Nome do cluster AKS provisionado"
  value       = module.azure_aks.cluster_name
}

output "aks_oidc_issuer_url" {
  description = "URL do OIDC issuer do AKS para Workload Identity"
  value       = module.azure_aks.oidc_issuer_url
}

output "aks_get_credentials_command" {
  description = "Comando az para obter as credenciais do cluster AKS"
  value       = "az aks get-credentials --resource-group ${module.azure_networking.resource_group_name} --name ${module.azure_aks.cluster_name}"
}

# -----------------------------------------------------------------------------
# Azure — Outputs do Key Vault
# -----------------------------------------------------------------------------

output "azure_key_vault_uri" {
  description = "URI do Azure Key Vault para uso nas aplicações"
  value       = module.azure_key_vault.vault_uri
}

output "azure_key_vault_name" {
  description = "Nome do Azure Key Vault provisionado"
  value       = module.azure_key_vault.vault_name
}

# -----------------------------------------------------------------------------
# Azure — Outputs de Rede
# -----------------------------------------------------------------------------

output "azure_resource_group_name" {
  description = "Nome do Resource Group Azure"
  value       = module.azure_networking.resource_group_name
}

output "azure_vnet_id" {
  description = "ID da VNet Azure"
  value       = module.azure_networking.vnet_id
}

# -----------------------------------------------------------------------------
# Resumo da Plataforma
# -----------------------------------------------------------------------------

output "platform_summary" {
  description = "Resumo dos recursos principais da plataforma"
  value = {
    gcp = {
      project    = var.gcp_project_id
      region     = var.gcp_region
      cluster    = module.gcp_gke.cluster_name
    }
    azure = {
      subscription = var.azure_subscription_id
      location     = var.azure_location
      cluster      = module.azure_aks.cluster_name
      key_vault    = module.azure_key_vault.vault_name
    }
    environment = var.environment
    app_name    = var.app_name
  }
}

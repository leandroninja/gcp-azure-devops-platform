# =============================================================================
# MAIN — PLATAFORMA DEVOPS MULTI-CLOUD GCP + AZURE
# =============================================================================
# Arquivo raiz que orquestra todos os módulos da plataforma.
# A infra GCP e Azure é provisionada em paralelo pelo Terraform.
# =============================================================================

# -----------------------------------------------------------------------------
# Provider Google Cloud Platform
# -----------------------------------------------------------------------------
provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region

  # Impersonação de service account para execução local (opcional)
  # impersonate_service_account = var.gcp_impersonate_sa
}

# Provider secundário para recursos multi-region no GCP
provider "google-beta" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

# -----------------------------------------------------------------------------
# Provider Microsoft Azure
# -----------------------------------------------------------------------------
provider "azurerm" {
  subscription_id = var.azure_subscription_id

  features {
    key_vault {
      purge_soft_delete_on_destroy    = false
      recover_soft_deleted_key_vaults = true
    }
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
  }
}

# =============================================================================
# MÓDULOS GCP
# =============================================================================

# Rede privada GCP: VPC, subnets, Cloud NAT, firewall
module "gcp_networking" {
  source = "./modules/gcp/networking"

  project_id   = var.gcp_project_id
  region       = var.gcp_region
  environment  = var.environment
  app_name     = var.app_name
}

# IAM: Service Accounts, Workload Identity Federation para GitHub Actions
module "gcp_iam" {
  source = "./modules/gcp/iam"

  project_id   = var.gcp_project_id
  environment  = var.environment
  app_name     = var.app_name

  # GitHub repo para o Workload Identity binding
  github_org  = var.github_org
  github_repo = var.github_repo

  depends_on = [module.gcp_networking]
}

# GKE: cluster privado com Workload Identity, auto-scaling, CMEK e CALICO
module "gcp_gke" {
  source = "./modules/gcp/gke"

  project_id      = var.gcp_project_id
  region          = var.gcp_region
  environment     = var.environment
  app_name        = var.app_name
  gke_config      = var.gke_config
  network_id      = module.gcp_networking.network_id
  subnetwork_id   = module.gcp_networking.subnetwork_id
  pods_range_name = module.gcp_networking.pods_range_name
  svcs_range_name = module.gcp_networking.svcs_range_name
  gke_sa_email    = module.gcp_iam.gke_node_sa_email

  depends_on = [module.gcp_iam]
}

# Secret Manager: secrets com CMEK e IAM bindings
module "gcp_secret_manager" {
  source = "./modules/gcp/secret-manager"

  project_id      = var.gcp_project_id
  region          = var.gcp_region
  environment     = var.environment
  app_name        = var.app_name
  cicd_sa_email   = module.gcp_iam.cicd_sa_email
  gke_sa_email    = module.gcp_iam.gke_node_sa_email

  depends_on = [module.gcp_iam]
}

# =============================================================================
# MÓDULOS AZURE
# =============================================================================

# Rede Azure: VNet, subnets, NSGs, Bastion, DDoS Protection
module "azure_networking" {
  source = "./modules/azure/networking"

  location     = var.azure_location
  environment  = var.environment
  app_name     = var.app_name
}

# AKS: cluster privado com Azure CNI, OIDC, monitoring e Azure Policy
module "azure_aks" {
  source = "./modules/azure/aks"

  location            = var.azure_location
  environment         = var.environment
  app_name            = var.app_name
  aks_config          = var.aks_config
  resource_group_name = module.azure_networking.resource_group_name
  vnet_id             = module.azure_networking.vnet_id
  aks_subnet_id       = module.azure_networking.aks_subnet_id
  log_analytics_id    = module.azure_networking.log_analytics_id

  depends_on = [module.azure_networking]
}

# Key Vault: secrets com RBAC, soft-delete e purge protection
module "azure_key_vault" {
  source = "./modules/azure/key-vault"

  location                = var.azure_location
  environment             = var.environment
  app_name                = var.app_name
  resource_group_name     = module.azure_networking.resource_group_name
  aks_kubelet_identity_id = module.azure_aks.kubelet_identity_object_id
  cicd_principal_id       = var.azure_cicd_principal_id

  depends_on = [module.azure_aks]
}

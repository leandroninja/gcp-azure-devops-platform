# =============================================================================
# BACKEND REMOTO — ESTADO DO TERRAFORM
# =============================================================================
# Backend primário: Azure Blob Storage
# Oferece criptografia em repouso, controle de acesso via RBAC e versionamento
# automático dos arquivos de estado.
#
# ALTERNATIVA com GCS (Google Cloud Storage):
# Para usar o GCS como backend, comente o bloco abaixo e descomente o bloco
# "gcs" logo em seguida. Lembre-se de criar o bucket antes de rodar `terraform init`.
#
#  terraform {
#    backend "gcs" {
#      bucket  = "meu-projeto-terraform-state"
#      prefix  = "gcp-azure-platform/state"
#    }
#  }
#
# Para inicializar com o backend Azure:
#   terraform init \
#     -backend-config="storage_account_name=STORAGE_ACCOUNT" \
#     -backend-config="container_name=CONTAINER_NAME" \
#     -backend-config="key=gcp-azure-platform.tfstate" \
#     -backend-config="resource_group_name=rg-terraform-state" \
#     -backend-config="subscription_id=SUBSCRIPTION_ID"
#
# Em pipelines CI/CD, as variáveis ARM_* são injetadas automaticamente
# pelo workflow GitHub Actions via OIDC.
# =============================================================================

terraform {
  backend "azurerm" {
    # Configurado via variáveis de ambiente ou -backend-config no CI/CD:
    # ARM_STORAGE_ACCOUNT_NAME, ARM_CONTAINER_NAME, ARM_KEY, ARM_RESOURCE_GROUP_NAME
    # Os valores abaixo são defaults que podem ser sobrescritos.
    resource_group_name  = "rg-terraform-state"
    storage_account_name = "stterraformstate"   # Substitua pelo nome real
    container_name       = "tfstate"
    key                  = "gcp-azure-platform/terraform.tfstate"

    # Autenticação via OIDC (recomendado para CI/CD)
    # use_oidc = true
    # client_id       → variável de ambiente ARM_CLIENT_ID
    # tenant_id       → variável de ambiente ARM_TENANT_ID
    # subscription_id → variável de ambiente ARM_SUBSCRIPTION_ID
  }
}

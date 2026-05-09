# =============================================================================
# MÓDULO AZURE KEY VAULT — Secrets com RBAC, Soft-Delete e Purge Protection
# =============================================================================

# Dados da subscription para construir resource IDs
data "azurerm_client_config" "current" {}

# =============================================================================
# KEY VAULT
# =============================================================================

resource "azurerm_key_vault" "main" {
  name                = "kv-${var.app_name}-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "premium"  # Premium: suporte a HSM keys

  # Soft-delete: 90 dias para recuperar secrets deletados
  soft_delete_retention_days = 90

  # Purge protection: impede exclusão permanente mesmo por admins
  purge_protection_enabled = true

  # Modelo de autorização via RBAC (recomendado sobre Access Policies)
  enable_rbac_authorization = true

  # Network ACLs: restringe acesso por rede
  network_acls {
    default_action             = "Deny"
    bypass                     = "AzureServices"
    virtual_network_subnet_ids = [var.aks_subnet_id]
    # ip_rules = [] # Adicione CIDRs específicos se necessário
  }

  tags = {
    environment = var.environment
    app         = var.app_name
    managed-by  = "terraform"
    team        = "devops"
  }
}

# =============================================================================
# SECRETS DA APLICAÇÃO
# =============================================================================

resource "azurerm_key_vault_secret" "app_db_password" {
  name         = "app-db-password"
  value        = "PLACEHOLDER-SUBSTITUIR-EM-PRODUCAO"
  key_vault_id = azurerm_key_vault.main.id

  content_type = "application/password"

  tags = {
    environment = var.environment
    app         = var.app_name
    type        = "database"
  }

  lifecycle {
    ignore_changes = [value]  # Não sobrescreve após criação inicial
  }

  depends_on = [
    azurerm_role_assignment.terraform_kv_officer,
  ]
}

resource "azurerm_key_vault_secret" "app_api_key" {
  name         = "app-api-key"
  value        = "PLACEHOLDER-SUBSTITUIR-EM-PRODUCAO"
  key_vault_id = azurerm_key_vault.main.id

  content_type = "application/api-key"

  tags = {
    environment = var.environment
    app         = var.app_name
    type        = "api-key"
  }

  lifecycle {
    ignore_changes = [value]
  }

  depends_on = [
    azurerm_role_assignment.terraform_kv_officer,
  ]
}

resource "azurerm_key_vault_secret" "jwt_secret" {
  name         = "jwt-secret"
  value        = "PLACEHOLDER-SUBSTITUIR-EM-PRODUCAO"
  key_vault_id = azurerm_key_vault.main.id

  content_type = "application/jwt-secret"

  tags = {
    environment = var.environment
    app         = var.app_name
    type        = "auth"
  }

  lifecycle {
    ignore_changes = [value]
  }

  depends_on = [
    azurerm_role_assignment.terraform_kv_officer,
  ]
}

# =============================================================================
# RBAC — Controle de Acesso ao Key Vault
# =============================================================================

# Terraform (pipeline CI/CD): Key Vault Officer para criar/gerenciar secrets
resource "azurerm_role_assignment" "terraform_kv_officer" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = var.cicd_principal_id
}

# AKS Workload Identity (kubelet): leitura de secrets para os pods
resource "azurerm_role_assignment" "aks_kv_reader" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = var.aks_kubelet_identity_id
}

# Diagnóstico: log de acessos ao Key Vault para auditoria
resource "azurerm_monitor_diagnostic_setting" "key_vault" {
  name               = "kv-diagnostics"
  target_resource_id = azurerm_key_vault.main.id

  # Cria um Log Analytics workspace local para os logs do Key Vault
  # Em produção, redirecionar para o Log Analytics central
  storage_account_id = null  # Opcional: usar storage account para retenção longa

  enabled_log {
    category = "AuditEvent"
  }

  enabled_log {
    category = "AzurePolicyEvaluationDetails"
  }

  metric {
    category = "AllMetrics"
  }
}

# =============================================================================
# OUTPUTS — Módulo Azure Key Vault
# =============================================================================

output "vault_id" {
  description = "ID do Azure Key Vault"
  value       = azurerm_key_vault.main.id
}

output "vault_uri" {
  description = "URI do Key Vault para uso nas aplicações (ex: https://kv-app-prod.vault.azure.net/)"
  value       = azurerm_key_vault.main.vault_uri
}

output "vault_name" {
  description = "Nome do Key Vault provisionado"
  value       = azurerm_key_vault.main.name
}

output "secret_ids" {
  description = "Mapa com os IDs de todos os secrets criados no Key Vault"
  value = {
    app_db_password = azurerm_key_vault_secret.app_db_password.id
    app_api_key     = azurerm_key_vault_secret.app_api_key.id
    jwt_secret      = azurerm_key_vault_secret.jwt_secret.id
  }
}

output "secret_resource_ids" {
  description = "Mapa com os versionless resource IDs dos secrets (sem versão específica)"
  value = {
    app_db_password = azurerm_key_vault_secret.app_db_password.resource_id
    app_api_key     = azurerm_key_vault_secret.app_api_key.resource_id
    jwt_secret      = azurerm_key_vault_secret.jwt_secret.resource_id
  }
}

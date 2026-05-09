# =============================================================================
# OUTPUTS — Módulo GCP Secret Manager
# =============================================================================

output "secret_ids" {
  description = "Mapa com os IDs de todos os secrets criados no GCP Secret Manager"
  value = {
    app_db_password = google_secret_manager_secret.app_db_password.id
    app_api_key     = google_secret_manager_secret.app_api_key.id
    jwt_secret      = google_secret_manager_secret.jwt_secret.id
    tls_cert        = google_secret_manager_secret.tls_cert.id
  }
}

output "secret_names" {
  description = "Mapa com os nomes (resource IDs) dos secrets para uso em aplicações"
  value = {
    app_db_password = google_secret_manager_secret.app_db_password.name
    app_api_key     = google_secret_manager_secret.app_api_key.name
    jwt_secret      = google_secret_manager_secret.jwt_secret.name
    tls_cert        = google_secret_manager_secret.tls_cert.name
  }
}

output "kms_key_id" {
  description = "ID da chave KMS usada para criptografar os secrets"
  value       = google_kms_crypto_key.secrets_key.id
}

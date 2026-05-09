# =============================================================================
# MÓDULO GCP SECRET MANAGER — Secrets com CMEK e IAM Bindings
# =============================================================================

# Chave KMS para criptografia dos secrets
resource "google_kms_key_ring" "secrets" {
  name     = "${var.app_name}-${var.environment}-secrets-keyring"
  location = var.region
  project  = var.project_id
}

resource "google_kms_crypto_key" "secrets_key" {
  name            = "${var.app_name}-${var.environment}-secrets-cmek"
  key_ring        = google_kms_key_ring.secrets.id
  rotation_period = "7776000s"  # 90 dias

  lifecycle {
    prevent_destroy = true
  }
}

# Concede permissão ao Secret Manager para usar a chave KMS
resource "google_kms_crypto_key_iam_member" "secret_manager_encrypt" {
  crypto_key_id = google_kms_crypto_key.secrets_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-secretmanager.iam.gserviceaccount.com"
}

data "google_project" "current" {
  project_id = var.project_id
}

# =============================================================================
# SECRETS DA APLICAÇÃO
# =============================================================================

# Secret: senha do banco de dados
resource "google_secret_manager_secret" "app_db_password" {
  secret_id = "${var.app_name}-${var.environment}-app-db-password"
  project   = var.project_id

  labels = {
    environment = var.environment
    app         = var.app_name
    type        = "database"
  }

  replication {
    user_managed {
      replicas {
        location = var.region
        customer_managed_encryption {
          kms_key_name = google_kms_crypto_key.secrets_key.id
        }
      }
    }
  }

  depends_on = [google_kms_crypto_key_iam_member.secret_manager_encrypt]
}

# Versão inicial do secret (valor placeholder — atualizar em produção)
resource "google_secret_manager_secret_version" "app_db_password_v1" {
  secret      = google_secret_manager_secret.app_db_password.id
  secret_data = "PLACEHOLDER_SUBSTITUIR_EM_PRODUCAO"

  lifecycle {
    ignore_changes = [secret_data]  # Não sobrescreve valor após criação inicial
  }
}

# Secret: API Key da aplicação
resource "google_secret_manager_secret" "app_api_key" {
  secret_id = "${var.app_name}-${var.environment}-app-api-key"
  project   = var.project_id

  labels = {
    environment = var.environment
    app         = var.app_name
    type        = "api-key"
  }

  replication {
    user_managed {
      replicas {
        location = var.region
        customer_managed_encryption {
          kms_key_name = google_kms_crypto_key.secrets_key.id
        }
      }
    }
  }

  depends_on = [google_kms_crypto_key_iam_member.secret_manager_encrypt]
}

resource "google_secret_manager_secret_version" "app_api_key_v1" {
  secret      = google_secret_manager_secret.app_api_key.id
  secret_data = "PLACEHOLDER_SUBSTITUIR_EM_PRODUCAO"

  lifecycle {
    ignore_changes = [secret_data]
  }
}

# Secret: JWT secret para autenticação
resource "google_secret_manager_secret" "jwt_secret" {
  secret_id = "${var.app_name}-${var.environment}-jwt-secret"
  project   = var.project_id

  labels = {
    environment = var.environment
    app         = var.app_name
    type        = "auth"
  }

  replication {
    user_managed {
      replicas {
        location = var.region
        customer_managed_encryption {
          kms_key_name = google_kms_crypto_key.secrets_key.id
        }
      }
    }
  }

  depends_on = [google_kms_crypto_key_iam_member.secret_manager_encrypt]
}

resource "google_secret_manager_secret_version" "jwt_secret_v1" {
  secret      = google_secret_manager_secret.jwt_secret.id
  secret_data = "PLACEHOLDER_SUBSTITUIR_EM_PRODUCAO"

  lifecycle {
    ignore_changes = [secret_data]
  }
}

# Secret: Certificado TLS (PEM)
resource "google_secret_manager_secret" "tls_cert" {
  secret_id = "${var.app_name}-${var.environment}-tls-cert"
  project   = var.project_id

  labels = {
    environment = var.environment
    app         = var.app_name
    type        = "tls"
  }

  replication {
    user_managed {
      replicas {
        location = var.region
        customer_managed_encryption {
          kms_key_name = google_kms_crypto_key.secrets_key.id
        }
      }
    }
  }

  depends_on = [google_kms_crypto_key_iam_member.secret_manager_encrypt]
}

resource "google_secret_manager_secret_version" "tls_cert_v1" {
  secret      = google_secret_manager_secret.tls_cert.id
  secret_data = "PLACEHOLDER_CERTIFICADO_TLS"

  lifecycle {
    ignore_changes = [secret_data]
  }
}

# =============================================================================
# IAM BINDINGS — Controle de acesso aos secrets
# =============================================================================

# CI/CD SA: acesso de leitura a todos os secrets (para injeção em pipelines)
resource "google_secret_manager_secret_iam_member" "cicd_db_password" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.app_db_password.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.cicd_sa_email}"
}

resource "google_secret_manager_secret_iam_member" "cicd_api_key" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.app_api_key.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.cicd_sa_email}"
}

resource "google_secret_manager_secret_iam_member" "cicd_jwt_secret" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.jwt_secret.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.cicd_sa_email}"
}

resource "google_secret_manager_secret_iam_member" "cicd_tls_cert" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.tls_cert.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.cicd_sa_email}"
}

# GKE Nodes SA: acesso de leitura (para Workload Identity nos pods)
resource "google_secret_manager_secret_iam_member" "gke_db_password" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.app_db_password.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.gke_sa_email}"
}

resource "google_secret_manager_secret_iam_member" "gke_api_key" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.app_api_key.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.gke_sa_email}"
}

resource "google_secret_manager_secret_iam_member" "gke_jwt_secret" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.jwt_secret.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.gke_sa_email}"
}

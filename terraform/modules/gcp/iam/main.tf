# =============================================================================
# MÓDULO GCP IAM — Service Accounts e Workload Identity Federation
# =============================================================================

# =============================================================================
# SERVICE ACCOUNT — Nodes do GKE
# =============================================================================
# SA com permissões mínimas necessárias para os nodes operarem.
# Segue o princípio de least privilege.

resource "google_service_account" "gke_nodes" {
  account_id   = "${var.app_name}-${var.environment}-gke-nodes"
  display_name = "GKE Nodes SA — ${var.app_name} (${var.environment})"
  description  = "Service Account para os nodes do GKE. Permissões mínimas para logging, monitoring e Artifact Registry."
  project      = var.project_id
}

# Logging: escreve logs dos containers e do sistema
resource "google_project_iam_member" "gke_nodes_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

# Monitoring: envia métricas para o Cloud Monitoring
resource "google_project_iam_member" "gke_nodes_monitoring_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

# Monitoring: acesso para leitura do estado do cluster
resource "google_project_iam_member" "gke_nodes_monitoring_viewer" {
  project = var.project_id
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

# Artifact Registry: pull de imagens Docker
resource "google_project_iam_member" "gke_nodes_artifact_registry" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

# Stack Driver: trace para observabilidade
resource "google_project_iam_member" "gke_nodes_trace" {
  project = var.project_id
  role    = "roles/cloudtrace.agent"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

# =============================================================================
# SERVICE ACCOUNT — Pipeline CI/CD
# =============================================================================
# SA com permissões para deployar no GKE, Cloud Run, e gerenciar secrets.

resource "google_service_account" "cicd" {
  account_id   = "${var.app_name}-${var.environment}-cicd"
  display_name = "CI/CD Service Account — ${var.app_name} (${var.environment})"
  description  = "Service Account para pipelines GitHub Actions. Acessa GKE, Cloud Run e Secret Manager."
  project      = var.project_id
}

# Kubernetes Developer: deploy no GKE via kubectl
resource "google_project_iam_member" "cicd_container_developer" {
  project = var.project_id
  role    = "roles/container.developer"
  member  = "serviceAccount:${google_service_account.cicd.email}"
}

# Cloud Run Admin: deploy e gerenciamento de Cloud Run services
resource "google_project_iam_member" "cicd_run_admin" {
  project = var.project_id
  role    = "roles/run.admin"
  member  = "serviceAccount:${google_service_account.cicd.email}"
}

# Service Account Token Creator: criar tokens para outros service accounts
resource "google_project_iam_member" "cicd_token_creator" {
  project = var.project_id
  role    = "roles/iam.serviceAccountTokenCreator"
  member  = "serviceAccount:${google_service_account.cicd.email}"
}

# Artifact Registry Writer: push de imagens Docker
resource "google_project_iam_member" "cicd_artifact_registry_writer" {
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.cicd.email}"
}

# Secret Manager Accessor: leitura de secrets no pipeline
resource "google_project_iam_member" "cicd_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.cicd.email}"
}

# =============================================================================
# WORKLOAD IDENTITY FEDERATION — GitHub Actions
# =============================================================================
# Permite que os workflows GitHub Actions obtenham tokens GCP temporários
# sem armazenar chaves de service account como secrets.
# Autenticação via OIDC tokens emitidos pelo GitHub.

resource "google_iam_workload_identity_pool" "github_actions" {
  workload_identity_pool_id = "${var.app_name}-github-pool"
  display_name              = "GitHub Actions Pool — ${var.app_name}"
  description               = "Pool de identidades para GitHub Actions autenticar sem chaves de SA"
  project                   = var.project_id
  disabled                  = false
}

resource "google_iam_workload_identity_pool_provider" "github_actions" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github_actions.workload_identity_pool_id
  workload_identity_pool_provider_id = "${var.app_name}-github-provider"
  display_name                       = "GitHub OIDC Provider"
  description                        = "Provider OIDC para autenticação do GitHub Actions no GCP"
  project                            = var.project_id

  # Mapeamento de atributos do token OIDC do GitHub
  attribute_mapping = {
    "google.subject"             = "assertion.sub"
    "attribute.actor"            = "assertion.actor"
    "attribute.repository"       = "assertion.repository"
    "attribute.repository_owner" = "assertion.repository_owner"
    "attribute.ref"              = "assertion.ref"
    "attribute.workflow"         = "assertion.workflow"
  }

  # Condição: apenas o repositório específico pode usar este provider
  attribute_condition = "assertion.repository == '${var.github_org}/${var.github_repo}'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# Binding: o CI/CD SA pode ser acessado pelo Workload Identity do GitHub Actions
# Escopo: apenas o repositório configurado
resource "google_service_account_iam_member" "cicd_workload_identity" {
  service_account_id = google_service_account.cicd.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github_actions.name}/attribute.repository/${var.github_org}/${var.github_repo}"
}

# Binding adicional: restringe apenas à branch main para operações de deploy
resource "google_service_account_iam_member" "cicd_workload_identity_main" {
  service_account_id = google_service_account.cicd.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github_actions.name}/attribute.ref/refs/heads/main"
}

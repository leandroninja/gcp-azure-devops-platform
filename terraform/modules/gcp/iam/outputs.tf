# =============================================================================
# OUTPUTS — Módulo GCP IAM
# =============================================================================

output "gke_node_sa_email" {
  description = "E-mail da Service Account para os nodes do GKE"
  value       = google_service_account.gke_nodes.email
}

output "gke_node_sa_name" {
  description = "Resource name completo da SA dos nodes GKE"
  value       = google_service_account.gke_nodes.name
}

output "cicd_sa_email" {
  description = "E-mail da Service Account do pipeline CI/CD"
  value       = google_service_account.cicd.email
}

output "cicd_sa_name" {
  description = "Resource name completo da SA de CI/CD"
  value       = google_service_account.cicd.name
}

output "workload_identity_pool_name" {
  description = "Resource name do Workload Identity Pool"
  value       = google_iam_workload_identity_pool.github_actions.name
}

output "workload_identity_provider" {
  description = "Resource name completo do Workload Identity Provider (usar no GitHub Actions como GCP_WORKLOAD_IDENTITY_PROVIDER)"
  value       = google_iam_workload_identity_pool_provider.github_actions.name
}

output "workload_identity_provider_display" {
  description = "Formato de exibição do provider (para documentação e configuração manual)"
  value       = "projects/${var.project_id}/locations/global/workloadIdentityPools/${google_iam_workload_identity_pool.github_actions.workload_identity_pool_id}/providers/${google_iam_workload_identity_pool_provider.github_actions.workload_identity_pool_provider_id}"
}

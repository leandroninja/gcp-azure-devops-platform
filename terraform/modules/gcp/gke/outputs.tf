# =============================================================================
# OUTPUTS — Módulo GCP GKE
# =============================================================================

output "cluster_name" {
  description = "Nome do cluster GKE"
  value       = google_container_cluster.main.name
}

output "cluster_id" {
  description = "ID completo do cluster GKE"
  value       = google_container_cluster.main.id
}

output "cluster_endpoint" {
  description = "IP do endpoint do control plane do GKE (sensível)"
  value       = google_container_cluster.main.endpoint
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "Certificado CA do cluster (base64, sensível)"
  value       = google_container_cluster.main.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "cluster_location" {
  description = "Região ou zona onde o cluster foi provisionado"
  value       = google_container_cluster.main.location
}

output "workload_identity_pool" {
  description = "Workload Identity Pool associado ao cluster"
  value       = "${var.project_id}.svc.id.goog"
}

output "kms_key_id" {
  description = "ID da chave KMS usada para criptografar secrets do etcd"
  value       = google_kms_crypto_key.gke_secrets.id
}

output "namespace_production" {
  description = "Nome do namespace de produção"
  value       = kubernetes_namespace.production.metadata[0].name
}

output "namespace_staging" {
  description = "Nome do namespace de staging"
  value       = kubernetes_namespace.staging.metadata[0].name
}

output "namespace_monitoring" {
  description = "Nome do namespace de monitoring"
  value       = kubernetes_namespace.monitoring.metadata[0].name
}

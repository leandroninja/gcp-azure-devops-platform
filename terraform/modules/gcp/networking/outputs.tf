# =============================================================================
# OUTPUTS — Módulo GCP Networking
# =============================================================================

output "network_id" {
  description = "ID da VPC principal"
  value       = google_compute_network.main.id
}

output "network_name" {
  description = "Nome da VPC principal"
  value       = google_compute_network.main.name
}

output "network_self_link" {
  description = "Self-link da VPC principal (usado em referências de outros recursos)"
  value       = google_compute_network.main.self_link
}

output "subnetwork_id" {
  description = "ID da subnet principal"
  value       = google_compute_subnetwork.main.id
}

output "subnetwork_name" {
  description = "Nome da subnet principal"
  value       = google_compute_subnetwork.main.name
}

output "subnetwork_self_link" {
  description = "Self-link da subnet principal"
  value       = google_compute_subnetwork.main.self_link
}

output "pods_range_name" {
  description = "Nome do secondary range para os Pods do GKE"
  value       = "${var.app_name}-${var.environment}-pods"
}

output "svcs_range_name" {
  description = "Nome do secondary range para os Services do GKE"
  value       = "${var.app_name}-${var.environment}-services"
}

output "router_name" {
  description = "Nome do Cloud Router"
  value       = google_compute_router.main.name
}

output "nat_name" {
  description = "Nome do Cloud NAT"
  value       = google_compute_router_nat.main.name
}

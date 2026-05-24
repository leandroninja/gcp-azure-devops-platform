# =============================================================================
# OUTPUTS — Módulo Azure AKS
# =============================================================================

output "cluster_name" {
  description = "Nome do cluster AKS"
  value       = azurerm_kubernetes_cluster.main.name
}

output "cluster_id" {
  description = "ID do cluster AKS"
  value       = azurerm_kubernetes_cluster.main.id
}

output "cluster_fqdn" {
  description = "FQDN privado do cluster AKS"
  value       = azurerm_kubernetes_cluster.main.private_fqdn
  sensitive   = true
}

output "kube_config" {
  description = "Kubeconfig do cluster AKS (sensível)"
  value       = azurerm_kubernetes_cluster.main.kube_config_raw
  sensitive   = true
}

output "oidc_issuer_url" {
  description = "URL do OIDC Issuer para configuração de Workload Identity"
  value       = azurerm_kubernetes_cluster.main.oidc_issuer_url
}

output "kubelet_identity_object_id" {
  description = "Object ID da identidade Kubelet (usada para Key Vault access)"
  value       = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
}

output "cluster_identity_principal_id" {
  description = "Principal ID da identidade do cluster AKS (SystemAssigned)"
  value       = azurerm_kubernetes_cluster.main.identity[0].principal_id
}

output "container_registry_login_server" {
  description = "Login server do Azure Container Registry associado ao AKS"
  value       = azurerm_container_registry.main.login_server
}

output "container_registry_id" {
  description = "ID do Azure Container Registry"
  value       = azurerm_container_registry.main.id
}

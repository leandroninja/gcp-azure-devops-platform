# =============================================================================
# OUTPUTS — Módulo Azure Networking
# =============================================================================

output "resource_group_name" {
  description = "Nome do Resource Group principal"
  value       = azurerm_resource_group.main.name
}

output "resource_group_id" {
  description = "ID do Resource Group principal"
  value       = azurerm_resource_group.main.id
}

output "monitoring_resource_group_name" {
  description = "Nome do Resource Group de monitoring"
  value       = azurerm_resource_group.monitoring.name
}

output "vnet_id" {
  description = "ID da Virtual Network principal"
  value       = azurerm_virtual_network.main.id
}

output "vnet_name" {
  description = "Nome da Virtual Network"
  value       = azurerm_virtual_network.main.name
}

output "aks_subnet_id" {
  description = "ID da subnet para os nodes do AKS"
  value       = azurerm_subnet.aks.id
}

output "appgw_subnet_id" {
  description = "ID da subnet para o Application Gateway"
  value       = azurerm_subnet.appgw.id
}

output "bastion_subnet_id" {
  description = "ID da subnet do Azure Bastion"
  value       = azurerm_subnet.bastion.id
}

output "private_endpoints_subnet_id" {
  description = "ID da subnet para Private Endpoints"
  value       = azurerm_subnet.private_endpoints.id
}

output "log_analytics_id" {
  description = "ID do Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_id" {
  description = "Workspace ID do Log Analytics (para configuração de agentes)"
  value       = azurerm_log_analytics_workspace.main.workspace_id
}

output "bastion_public_ip" {
  description = "IP público do Azure Bastion"
  value       = azurerm_public_ip.bastion.ip_address
}

output "ddos_plan_id" {
  description = "ID do plano DDoS Protection"
  value       = azurerm_network_ddos_protection_plan.main.id
}

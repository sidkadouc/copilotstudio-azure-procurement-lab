output "resource_group_name" {
  value = local.rg_name
}

output "search_service_name" {
  value = azurerm_search_service.this.name
}

output "search_service_endpoint" {
  value = "https://${azurerm_search_service.this.name}.search.windows.net"
}

output "search_admin_key" {
  value     = azurerm_search_service.this.primary_key
  sensitive = true
}

output "openai_endpoint" {
  value = azurerm_cognitive_account.foundry.endpoint
}

output "openai_key" {
  value     = azurerm_cognitive_account.foundry.primary_access_key
  sensitive = true
}

output "openai_embedding_deployment" {
  value = azurerm_cognitive_deployment.embedding.name
}

output "gpt51_deployment_name" {
  value = azurerm_cognitive_deployment.gpt51.name
}

output "app_registration_client_id" {
  value = azuread_application.search_sp.client_id
}

output "app_registration_client_secret" {
  value     = azuread_application_password.search_sp.value
  sensitive = true
}

output "tenant_id" {
  value = data.azuread_client_config.current.tenant_id
}

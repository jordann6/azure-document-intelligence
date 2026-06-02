output "function_app_name" {
  description = "Azure Function App name."
  value       = azurerm_linux_function_app.processor.name
}

output "documents_storage_account" {
  description = "Storage account name for raw/processed containers."
  value       = azurerm_storage_account.documents.name
}

output "doc_intel_endpoint" {
  description = "Document Intelligence endpoint URL."
  value       = azurerm_cognitive_account.doc_intel.endpoint
}

output "resource_group_name" {
  description = "Resource group containing all project resources."
  value       = azurerm_resource_group.this.name
}

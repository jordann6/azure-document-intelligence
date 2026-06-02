locals {
  project     = "docintel"
  environment = var.environment
  location    = var.location

  common_tags = {
    project     = local.project
    environment = local.environment
    owner       = "jordann6"
    managed_by  = "terraform"
  }
}

# --- Resource Group -----------------------------------------------------------

resource "azurerm_resource_group" "this" {
  name     = "rg-${local.project}-${local.environment}"
  location = local.location
  tags     = local.common_tags
}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# --- Storage Account: documents (raw + processed containers, extractions table) ---

resource "azurerm_storage_account" "documents" {
  name                            = "stdocs${local.environment}${random_string.suffix.result}"
  resource_group_name             = azurerm_resource_group.this.name
  location                        = azurerm_resource_group.this.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false
  tags                            = local.common_tags
}

resource "azurerm_storage_container" "raw" {
  name                  = "raw"
  storage_account_name  = azurerm_storage_account.documents.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "processed" {
  name                  = "processed"
  storage_account_name  = azurerm_storage_account.documents.name
  container_access_type = "private"
}

resource "azurerm_storage_table" "extractions" {
  name                 = "extractions"
  storage_account_name = azurerm_storage_account.documents.name
}

# --- Storage Account: Function App runtime (AzureWebJobsStorage) --------------

resource "azurerm_storage_account" "functions" {
  name                            = "stfunc${local.environment}${random_string.suffix.result}"
  resource_group_name             = azurerm_resource_group.this.name
  location                        = azurerm_resource_group.this.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false
  tags                            = local.common_tags
}

# --- Document Intelligence ---------------------------------------------------

resource "azurerm_cognitive_account" "doc_intel" {
  name                = "cog-${local.project}-${local.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  kind                = "FormRecognizer"
  sku_name            = "S0"
  tags                = local.common_tags
}

# --- App Service Plan (Consumption) ------------------------------------------

resource "azurerm_service_plan" "this" {
  name                = "plan-${local.project}-${local.environment}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  os_type             = "Linux"
  sku_name            = "Y1"
  tags                = local.common_tags
}

# --- Function App (Python 3.11) -----------------------------------------------

resource "azurerm_linux_function_app" "processor" {
  name                = "func-${local.project}-${local.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  service_plan_id     = azurerm_service_plan.this.id

  # Identity-based connection — no storage key stored in config
  storage_account_name          = azurerm_storage_account.functions.name
  storage_uses_managed_identity = true

  identity {
    type = "SystemAssigned"
  }

  site_config {
    application_stack {
      python_version = "3.11"
    }
  }

  app_settings = {
    # AzureWebJobsStorage via managed identity — no connection string
    "AzureWebJobsStorage__blobServiceUri"  = "https://${azurerm_storage_account.functions.name}.blob.core.windows.net"
    "AzureWebJobsStorage__queueServiceUri" = "https://${azurerm_storage_account.functions.name}.queue.core.windows.net"
    "AzureWebJobsStorage__tableServiceUri" = "https://${azurerm_storage_account.functions.name}.table.core.windows.net"

    # Document storage connection (managed identity)
    "DOC_STORAGE__blobServiceUri" = "https://${azurerm_storage_account.documents.name}.blob.core.windows.net"

    "DOC_INTEL_ENDPOINT"                 = azurerm_cognitive_account.doc_intel.endpoint
    "STORAGE_ACCOUNT_NAME"               = azurerm_storage_account.documents.name
    "FUNCTIONS_WORKER_RUNTIME"           = "python"
    "PYTHON_ISOLATE_WORKER_DEPENDENCIES" = "1"
  }

  tags = local.common_tags
}

# --- Managed Identity role assignments ----------------------------------------

# Functions runtime storage
resource "azurerm_role_assignment" "func_runtime_blob_owner" {
  scope                = azurerm_storage_account.functions.id
  role_definition_name = "Storage Blob Data Owner"
  principal_id         = azurerm_linux_function_app.processor.identity[0].principal_id
}

resource "azurerm_role_assignment" "func_runtime_queue_contributor" {
  scope                = azurerm_storage_account.functions.id
  role_definition_name = "Storage Queue Data Contributor"
  principal_id         = azurerm_linux_function_app.processor.identity[0].principal_id
}

resource "azurerm_role_assignment" "func_runtime_table_contributor" {
  scope                = azurerm_storage_account.functions.id
  role_definition_name = "Storage Table Data Contributor"
  principal_id         = azurerm_linux_function_app.processor.identity[0].principal_id
}

# Documents storage — read raw blobs via trigger, write processed blobs + table rows
resource "azurerm_role_assignment" "func_docs_blob_contributor" {
  scope                = azurerm_storage_account.documents.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_function_app.processor.identity[0].principal_id
}

resource "azurerm_role_assignment" "func_docs_table_contributor" {
  scope                = azurerm_storage_account.documents.id
  role_definition_name = "Storage Table Data Contributor"
  principal_id         = azurerm_linux_function_app.processor.identity[0].principal_id
}

# Document Intelligence
resource "azurerm_role_assignment" "func_cognitive_user" {
  scope                = azurerm_cognitive_account.doc_intel.id
  role_definition_name = "Cognitive Services User"
  principal_id         = azurerm_linux_function_app.processor.identity[0].principal_id
}

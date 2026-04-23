locals {
  name_suffix  = "${var.environment_name}-${var.unique_suffix}"
  default_tags = merge(var.tags, {
    purpose    = "procurement-rag-poc"
    managed-by = "terraform"
  })

  # Resolved RG name & location — works for both create and existing modes
  rg_name     = var.create_resource_group ? azurerm_resource_group.this[0].name : data.azurerm_resource_group.existing[0].name
  rg_location = var.create_resource_group ? azurerm_resource_group.this[0].location : data.azurerm_resource_group.existing[0].location
}

##############################################################################
# Resource Group
# Set create_resource_group = false to use an existing RG (Contributor is enough)
##############################################################################

resource "azurerm_resource_group" "this" {
  count    = var.create_resource_group ? 1 : 0
  name     = var.resource_group_name
  location = var.location
  tags     = local.default_tags
}

data "azurerm_resource_group" "existing" {
  count = var.create_resource_group ? 0 : 1
  name  = var.resource_group_name
}

##############################################################################
# Azure AI Search
##############################################################################

resource "azurerm_search_service" "this" {
  name                          = "search-procurement-${local.name_suffix}"
  resource_group_name           = local.rg_name
  location                      = var.search_location != "" ? var.search_location : local.rg_location
  sku                           = var.search_sku
  semantic_search_sku           = "standard"
  tags                          = local.default_tags

  identity {
    type = "SystemAssigned"
  }
}

##############################################################################
# Microsoft Foundry (AIServices - single resource in Sweden Central)
# Hosts both embeddings and GPT-5.1 in the same region
##############################################################################

resource "azurerm_cognitive_account" "foundry" {
  name                  = "ai-procurement-${local.name_suffix}"
  resource_group_name   = local.rg_name
  location              = local.rg_location
  kind                  = "AIServices"
  sku_name              = "S0"
  tags                  = local.default_tags
  custom_subdomain_name = "ai-procurement-${local.name_suffix}"

  identity {
    type = "SystemAssigned"
  }
}

# Embedding model (used by AI Search skillset)
resource "azurerm_cognitive_deployment" "embedding" {
  name                 = var.embedding_model
  cognitive_account_id = azurerm_cognitive_account.foundry.id

  model {
    format  = "OpenAI"
    name    = "text-embedding-ada-002"
    version = "2"
  }

  sku {
    name     = "Standard"
    capacity = 30
  }
}

# GPT-5.1 (Data Zone deployment)
resource "azurerm_cognitive_deployment" "gpt51" {
  name                 = "gpt-51"
  cognitive_account_id = azurerm_cognitive_account.foundry.id

  model {
    format  = "OpenAI"
    name    = "gpt-5.1"
    version = "2025-11-13"
  }

  sku {
    name     = "DataZoneStandard"
    capacity = 10
  }
}

##############################################################################
# App Registration (for SharePoint indexer auth)
##############################################################################

data "azuread_client_config" "current" {}

resource "azuread_application" "search_sp" {
  display_name = "AI Search - SharePoint Indexer - ${local.name_suffix}"
  owners       = [data.azuread_client_config.current.object_id]

  required_resource_access {
    resource_app_id = "00000003-0000-0000-c000-000000000000" # Microsoft Graph

    resource_access {
      id   = "332a536c-c7ef-4017-ab91-336970924f0d" # Sites.Read.All (application)
      type = "Role"
    }
  }
}

resource "azuread_application_password" "search_sp" {
  application_id = azuread_application.search_sp.id
  display_name   = "ai-search-indexer"
  end_date       = "2027-12-31T00:00:00Z"
}

resource "azuread_service_principal" "search_sp" {
  client_id = azuread_application.search_sp.client_id
  owners    = [data.azuread_client_config.current.object_id]
}

# Grant admin consent for Sites.Read.All (application permission)
data "azuread_service_principal" "msgraph" {
  client_id = "00000003-0000-0000-c000-000000000000"
}

resource "azuread_app_role_assignment" "sites_read_all" {
  app_role_id         = "332a536c-c7ef-4017-ab91-336970924f0d" # Sites.Read.All
  principal_object_id = azuread_service_principal.search_sp.object_id
  resource_object_id  = data.azuread_service_principal.msgraph.object_id
}

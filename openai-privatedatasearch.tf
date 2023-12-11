provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "rsg" {
  name     = "byod-resources"
  location = "australiaeast"
}


resource "azurerm_cognitive_account" "openai" {
  name                          = "byodopenai"
  kind                          = "OpenAI"
  sku_name                      = "S0"
  location            = azurerm_resource_group.rsg.location
  resource_group_name = azurerm_resource_group.rsg.name
  public_network_access_enabled = true
  custom_subdomain_name         = "byod-openai"
}

resource "azurerm_cognitive_deployment" "gpt_35_turbo" {
  name                 = "gpt-35-turbo-16k"
  cognitive_account_id = azurerm_cognitive_account.openai.id
  rai_policy_name      = "Microsoft.Default"
  model {
    format  = "OpenAI"
    name    = "gpt-35-turbo-16k"
    version = "0613"
  }

  scale {
    type     = "Standard"
    capacity = 120
  }
}

resource "azurerm_cognitive_deployment" "embedding" {
  name                 = "text-embedding-ada-002"
  cognitive_account_id = azurerm_cognitive_account.openai.id
  rai_policy_name      = "Microsoft.Default"
  model {
    format  = "OpenAI"
    name    = "text-embedding-ada-002"
    version = "2"
  }

  scale {
    type     = "Standard"
    capacity = 120
  }
}

resource "azurerm_virtual_network" "openai-vnet" {
  name                = "openai-vnet01"
  address_space       = ["10.0.0.0/24"]
  location            = azurerm_resource_group.rsg.location
  resource_group_name = azurerm_resource_group.rsg.name
}

resource "azurerm_subnet" "openai-subnet" {
  name                 = "openai-snet"
  resource_group_name  = azurerm_resource_group.rsg.name
  virtual_network_name = azurerm_virtual_network.openai-vnet.name
  address_prefixes     = ["10.0.0.0/25"]
}

resource "azurerm_private_endpoint" "openai-pe01" {
  name                = "pe-openai-byod"
  location            = azurerm_resource_group.rsg.location
  resource_group_name = azurerm_resource_group.rsg.name
  subnet_id           = azurerm_subnet.openai-subnet.id


  private_service_connection {
    name                           = "pe-openai-byod"
    private_connection_resource_id = azurerm_cognitive_account.openai.id
    subresource_names              = ["account"]
    is_manual_connection           = false
  }

      private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.openaidns.id]
  }
}

resource "azurerm_private_dns_zone" "openaidns" {
  name                = "privatelink.openai.azure.com"
  resource_group_name = azurerm_resource_group.rsg.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "openailink" {
  name                  = "openai-byod-vnet-link"
  resource_group_name   = azurerm_resource_group.rsg.name
  private_dns_zone_name = azurerm_private_dns_zone.openaidns.name
  virtual_network_id    = azurerm_virtual_network.openai-vnet.id
}


resource "azurerm_search_service" "search" {
  name                = "byod-enterprise-search"
  resource_group_name = azurerm_resource_group.rsg.name
  location            = azurerm_resource_group.rsg.location
  sku                 = "standard"
  replica_count       = 1
  partition_count     = 1
}


resource "azurerm_private_endpoint" "openaisearch-pe01" {
  name                = "pe-openaisearch-byod"
  location            = azurerm_resource_group.rsg.location
  resource_group_name = azurerm_resource_group.rsg.name
  subnet_id           = azurerm_subnet.openai-subnet.id


  private_service_connection {
    name                           = "pe-openaisearch-byod"
    private_connection_resource_id = azurerm_search_service.search.id
    subresource_names              = ["searchService"]
    is_manual_connection           = false
  }

      private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.openaisearchdns.id]
  }
}

resource "azurerm_private_dns_zone" "openaisearchdns" {
  name                = "privatelink.serach.windows.net"
  resource_group_name = azurerm_resource_group.rsg.name
}


resource "azurerm_storage_account" "byodkedbst" {
  name                     = "byodkedbdoc"
  resource_group_name      = azurerm_resource_group.rsg.name
  location                 = azurerm_resource_group.rsg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version = "TLS1_2"
  network_rules {
    default_action             = "Deny"
    ip_rules                   = []
  }

}

resource "azurerm_private_dns_zone" "pdns_byodkedbdoc_st" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.rsg.name
}


resource "azurerm_private_endpoint" "pep_st" {
  name                = "pep-byodkedb-st"
  location            = azurerm_resource_group.rsg.location
  resource_group_name = azurerm_resource_group.rsg.name
  subnet_id           = azurerm_subnet.openai-subnet.id

  private_service_connection {
    name                           = "sc-sta-byod-kedb"
    private_connection_resource_id = azurerm_storage_account.byodkedbst.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "dns-group-sta"
    private_dns_zone_ids = [azurerm_private_dns_zone.pdns_byodkedbdoc_st.id]
  }
}

resource "azurerm_private_dns_zone_virtual_network_link" "dns_vnet_lnk_sta" {
  name                  = "lnk-dns-vnet-sta"
  resource_group_name   = azurerm_resource_group.rsg.name
  private_dns_zone_name = azurerm_private_dns_zone.pdns_byodkedbdoc_st.name
  virtual_network_id    = azurerm_virtual_network.openai-vnet.id
}

resource "azurerm_private_dns_a_record" "dns_a_sta" {
  name                = "sta_a_record"
  zone_name           = azurerm_private_dns_zone.pdns_byodkedbdoc_st.name 
  resource_group_name = azurerm_resource_group.rsg.name
  ttl                 = 300
  records             = [azurerm_private_endpoint.pep_st.private_service_connection.0.private_ip_address]
}

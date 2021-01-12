terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "2.36.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.0.0"
    }
  }
}

provider "azurerm" {
  features {}
}

locals {
  deployment_name = "autoscalebatchsvc"
  location        = "eastus2"
}

resource "azurerm_resource_group" "this" {
  name     = "rg-${local.deployment_name}-${local.location}"
  location = local.location
}

resource "random_string" "this" {
  length  = 22
  special = false
  upper   = false
}

resource "azurerm_storage_account" "this" {
  name                     = "st${random_string.this.result}"
  resource_group_name      = azurerm_resource_group.this.name
  location                 = azurerm_resource_group.this.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_batch_account" "this" {
  name                 = "batch${local.deployment_name}"
  resource_group_name  = azurerm_resource_group.this.name
  location             = azurerm_resource_group.this.location
  pool_allocation_mode = "BatchService"
  storage_account_id   = azurerm_storage_account.this.id
}

resource "azurerm_batch_pool" "this" {
  name                = "pool-${local.deployment_name}"
  resource_group_name = azurerm_resource_group.this.name
  account_name        = azurerm_batch_account.this.name
  display_name        = "Auto-Scale Pool"
  vm_size             = "Standard_A1"
  node_agent_sku_id   = "batch.node.windows amd64"

  auto_scale {
    evaluation_interval = "PT5M"

    formula = <<EOF
      maxPoolSize = 4;
      tasks = $ActiveTasks.Count() > 0 ? $ActiveTasks.GetSample(1) : 0;
      $TargetDedicatedNodes = min(tasks, maxPoolSize);
      $NodeDeallocationOption = taskcompletion;
EOF
  }

  storage_image_reference {
    publisher = "microsoftwindowsserver"
    offer     = "windowsserver"
    sku       = "2019-datacenter"
    version   = "latest"
  }

  start_task {
    command_line         = "echo 'Node started..'"
    max_task_retry_count = 1
    wait_for_success     = true

    user_identity {
      auto_user {
        elevation_level = "NonAdmin"
        scope           = "Task"
      }
    }
  }
}


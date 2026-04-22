terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Local state for v1. To move to remote state later:
  #
  # backend "azurerm" {
  #   resource_group_name  = "tfstate-rg"
  #   storage_account_name = "tfstatesmarterpillow"
  #   container_name       = "tfstate"
  #   key                  = "snoring.tfstate"
  # }
}

provider "azurerm" {
  features {}
  # Set ARM_SUBSCRIPTION_ID=0693b330-9523-4bf2-977a-7f30db2dd36e (Azure for Students)
  # Or: subscription_id = var.subscription_id
}

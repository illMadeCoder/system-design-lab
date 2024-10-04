terraform {
  backend "azurerm" {
    resource_group_name  = "terraform"
    storage_account_name = "terraformbackendjesseb"
    container_name       = "tfstate"
    key                  = "1_single_server_setup.tfstate"
  }
}

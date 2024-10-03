terraform {
  backend "azurerm" {
    resource_group_name   = "terraform"
    storage_account_name  = "terraformbackendjesseb"
    container_name        = "tfstate"
    key                   = "terraform.tfstate"  # State file path in the container
  }
}

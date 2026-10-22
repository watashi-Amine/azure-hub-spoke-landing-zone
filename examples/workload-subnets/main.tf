# Workload subnet patterns.
#
# The reference spoke keeps four plain subnets on purpose. Real spoke VNets grow
# subnets that exist to satisfy a specific Azure service, and the shape of those
# subnets is not obvious: delegations must match the service exactly, private
# endpoint subnets need network policies off, and gateway subnets must be named
# GatewaySubnet.
#
# Each subnet below is a documented pattern you can copy into your own spoke.
# Delete the ones you do not need: nothing here is required by the template.

provider "azurerm" {
  features {}
}

variable "location" {
  type    = string
  default = "westeurope"
}

module "workload_vnet" {
  source = "../../modules/azure-virtual-network"

  name           = "vnet-workload-dc1"
  location       = var.location
  resource_group = { name = "rg-workload-dc1" }
  address_space  = ["10.40.0.0/20"]
  dns_servers    = []

  subnets = {
    # ---------------------------------------------------------------------
    # 1. App Service / Functions with VNet integration
    #    Delegation name and actions must match Microsoft.Web/serverFarms.
    # ---------------------------------------------------------------------
    "snet-appsvc" = {
      cidr = "10.40.0.0/24"
      delegation = {
        "app-service" = {
          name    = "Microsoft.Web/serverFarms"
          actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
        }
      }
    }

    # ---------------------------------------------------------------------
    # 2. Container Apps environment
    # ---------------------------------------------------------------------
    "snet-containerapps" = {
      cidr = "10.40.1.0/23"
      delegation = {
        "container-apps" = {
          name    = "Microsoft.App/environments"
          actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
        }
      }
    }

    # ---------------------------------------------------------------------
    # 3. Managed DevOps pool
    # ---------------------------------------------------------------------
    "snet-devops" = {
      cidr = "10.40.3.0/26"
      delegation = {
        "devops-pools" = {
          name    = "Microsoft.DevOpsInfrastructure/pools"
          actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
        }
      }
    }

    # ---------------------------------------------------------------------
    # 4. Private endpoints
    #    Network policies must be disabled for private endpoints to work.
    #    "Disabled" here refers to privateEndpoints only; NSGs still apply to
    #    every other resource in the subnet.
    # ---------------------------------------------------------------------
    "snet-privateendpoints" = {
      cidr                              = "10.40.4.0/24"
      private_endpoint_network_policies = "Disabled"
    }

    # ---------------------------------------------------------------------
    # 5. Private Link Service
    #    Requires private endpoint policies enabled and Private Link service
    #    policies disabled, otherwise the service cannot be created.
    # ---------------------------------------------------------------------
    "snet-privatelinkservice" = {
      cidr                                          = "10.40.5.0/24"
      private_endpoint_network_policies             = "Disabled"
      private_link_service_network_policies_enabled = false
    }

    # ---------------------------------------------------------------------
    # 6. Application Gateway
    #    Application Gateway requires a dedicated subnet with no other
    #    resources in it.
    # ---------------------------------------------------------------------
    "snet-appgateway" = {
      cidr = "10.40.6.0/24"
    }

    # ---------------------------------------------------------------------
    # 7. Service endpoints
    #    Keep storage and key vault traffic on the Azure backbone instead of
    #    the public internet. The service still needs a matching firewall or
    #    network ACL rule on the resource itself.
    # ---------------------------------------------------------------------
    "snet-storage" = {
      cidr              = "10.40.7.0/24"
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault", "Microsoft.Sql"]
    }

    # ---------------------------------------------------------------------
    # 8. Plain subnet for anything else
    # ---------------------------------------------------------------------
    "snet-general" = {
      cidr = "10.40.8.0/24"
    }

    # ---------------------------------------------------------------------
    # 9. Gateway subnet (ONLY if you add a VPN or ExpressRoute gateway)
    #    Azure requires this exact name and it must not be delegated.
    #    This template has no gateway by design, so it is commented out.
    #    Size it /27 or larger.
    # ---------------------------------------------------------------------
    # "GatewaySubnet" = { cidr = "10.40.15.0/27" }
  }

  tags = {
    Environment = "example"
    ManagedBy   = "terraform"
  }
}

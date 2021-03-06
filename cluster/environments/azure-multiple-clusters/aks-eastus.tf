resource "azurerm_resource_group" "eastrg" {
  name     = "${var.east_resource_group_name}"
  location = "${var.east_resource_group_location}"
}

# local variable with cluster and location specific
locals {
  east_rg_name                 = "${azurerm_resource_group.eastrg.name}"
  east_rg_location             = "${azurerm_resource_group.eastrg.location}"
  east_prefix                  = "${local.east_rg_location}-${var.cluster_name}"
  east_flux_clone_dir          = "${local.east_prefix}-flux"
  east_kubeconfig_filename     = "${local.east_prefix}_kube_config"
  east_ip_address_out_filename = "${local.east_prefix}_ip_address"
}

# Creates vnet
module "east_vnet" {
  source = "../../azure/vnet"

  resource_group_name     = "${local.east_rg_name }"
  resource_group_location = "${local.east_rg_location}"
  subnet_names            = ["${var.cluster_name}-aks-subnet"]

  tags = {
    environment = "azure-multiple-clusters"
  }
}

# Creates aks cluster
module "east_aks" {
  source = "../../azure/aks"

  resource_group_name      = "${local.east_rg_name }"
  resource_group_location  = "${local.east_rg_location}"
  cluster_name             = "${var.cluster_name}"
  agent_vm_count           = "${var.agent_vm_count}"
  dns_prefix               = "${var.dns_prefix}"
  vnet_subnet_id           = "${module.east_vnet.vnet_subnet_ids[0]}"
  ssh_public_key           = "${var.ssh_public_key}"
  service_principal_id     = "${var.service_principal_id}"
  service_principal_secret = "${var.service_principal_secret}"
  kubeconfig_recreate      = ""
  kubeconfig_filename      = "${local.east_kubeconfig_filename}"
}

# Deploys flux in aks cluster
module "east_flux" {
  source = "../../common/flux"

  gitops_ssh_url      = "${var.gitops_ssh_url}"
  gitops_ssh_key      = "${var.gitops_ssh_key}"
  flux_recreate       = ""
  kubeconfig_complete = "${module.east_aks.kubeconfig_done}"
  kubeconfig_filename = "${local.east_kubeconfig_filename}"
  flux_clone_dir      = "${local.east_flux_clone_dir}"
}

# create a static public ip and associate with traffic manger endpoint 
module "east_tm_endpoint" {
  source = "../../azure/tm-endpoint-ip"

  resource_group_name                 = "${local.east_rg_name }"
  resource_location                   = "${local.east_rg_location}"
  traffic_manager_resource_group_name = "${var.traffic_manager_resource_group_name}"
  traffic_manager_profile_name        = "${var.traffic_manager_profile_name}"
  endpoint_name                       = "${local.east_rg_location}-${var.cluster_name}"
  public_ip_name                      = "${var.cluster_name}"
  ip_address_out_filename             = "${local.east_ip_address_out_filename}"

  tags = {
    environment = "azure-multiple-clusters - ${var.cluster_name} - public ip"
  }
}

# Create a role assignment with Contributor role for AKS client service principal object 
#   to join vnet/subnet/ip for load balancer/ingress controller
resource "azurerm_role_assignment" "east_spra" {
  principal_id         = "${data.azuread_service_principal.sp.id}"
  role_definition_name = "${var.aks_client_role_assignment_role}"
  scope                = "${azurerm_resource_group.eastrg.id}"
}

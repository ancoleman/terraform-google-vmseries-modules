module "iam_service_account" {
  source = "../../modules/iam_service_account"

  for_each = var.service_accounts

  service_account_id = "${var.name_prefix}${each.value.service_account_id}"
  display_name       = "${var.name_prefix}${each.value.display_name}"
  roles              = each.value.roles
}

resource "local_file" "bootstrap_xml_region_1" {

  for_each = { for k, v in var.vmseries_region_1 : k => v
    if can(v.bootstrap_template_map)
  }

  filename = "files/${each.key}/config/bootstrap.xml"
  content = templatefile("templates/bootstrap_common.tmpl",
    {
      trust_gcp_router_ip   = each.value.bootstrap_template_map.trust_gcp_router_ip
      private_network_cidr  = each.value.bootstrap_template_map.private_network_cidr
      untrust_gcp_router_ip = each.value.bootstrap_template_map.untrust_gcp_router_ip
      trust_loopback_ip     = each.value.bootstrap_template_map.trust_loopback_ip
      untrust_loopback_ip   = each.value.bootstrap_template_map.untrust_loopback_ip
    }
  )
}

resource "local_file" "bootstrap_xml_region_2" {

  for_each = { for k, v in var.vmseries_region_2 : k => v
    if can(v.bootstrap_template_map)
  }

  filename = "files/${each.key}/config/bootstrap.xml"
  content = templatefile("templates/bootstrap_common.tmpl",
    {
      trust_gcp_router_ip   = each.value.bootstrap_template_map.trust_gcp_router_ip
      private_network_cidr  = each.value.bootstrap_template_map.private_network_cidr
      untrust_gcp_router_ip = each.value.bootstrap_template_map.untrust_gcp_router_ip
      trust_loopback_ip     = each.value.bootstrap_template_map.trust_loopback_ip
      untrust_loopback_ip   = each.value.bootstrap_template_map.untrust_loopback_ip
    }
  )
}

resource "local_file" "init_cfg_region_1" {

  for_each = { for k, v in var.vmseries_region_1 : k => v
    if can(v.bootstrap_template_map)
  }

  filename = "files/${each.key}/config/init-cfg.txt"
  content = templatefile("templates/init-cfg.tmpl",
    {
      panorama-server = try(each.value.bootstrap_options.panorama-server, var.vmseries_common.bootstrap_options.panorama-server, "")
      type            = try(each.value.bootstrap_options.type, var.vmseries_common.bootstrap_options.type, "")
      dns-primary     = try(each.value.bootstrap_options.dns-primary, var.vmseries_common.bootstrap_options.dns-primary, "")
      dns-secondary   = try(each.value.bootstrap_options.dns-secondary, var.vmseries_common.bootstrap_options.dns-secondary, "")
  })
}

resource "local_file" "init_cfg_region_2" {

  for_each = { for k, v in var.vmseries_region_2 : k => v
    if can(v.bootstrap_template_map)
  }

  filename = "files/${each.key}/config/init-cfg.txt"
  content = templatefile("templates/init-cfg.tmpl",
    {
      panorama-server = try(each.value.bootstrap_options.panorama-server, var.vmseries_common.bootstrap_options.panorama-server, "")
      type            = try(each.value.bootstrap_options.type, var.vmseries_common.bootstrap_options.type, "")
      dns-primary     = try(each.value.bootstrap_options.dns-primary, var.vmseries_common.bootstrap_options.dns-primary, "")
      dns-secondary   = try(each.value.bootstrap_options.dns-secondary, var.vmseries_common.bootstrap_options.dns-secondary, "")
  })
}

module "bootstrap" {
  source = "../../modules/bootstrap"

  for_each = var.bootstrap_buckets

  folders = keys(merge(var.vmseries_region_1, var.vmseries_region_2))

  name_prefix     = "${var.name_prefix}${each.value.bucket_name_prefix}"
  service_account = module.iam_service_account[each.value.service_account_key].email
  location        = each.value.location
  files = merge(
    { for k, v in var.vmseries_region_1 : "files/${k}/config/bootstrap.xml" => "${k}/config/bootstrap.xml" },
    { for k, v in var.vmseries_region_1 : "files/${k}/config/init-cfg.txt" => "${k}/config/init-cfg.txt" },
    { for k, v in var.vmseries_region_2 : "files/${k}/config/bootstrap.xml" => "${k}/config/bootstrap.xml" },
    { for k, v in var.vmseries_region_2 : "files/${k}/config/init-cfg.txt" => "${k}/config/init-cfg.txt" },
  )
}

module "vpc_region_1" {
  source = "../../modules/vpc"

  networks = { for k, v in var.networks_region_1 : k => merge(v, {
    name            = "${var.name_prefix}${v.name}"
    subnetwork_name = "${var.name_prefix}${v.subnetwork_name}-${var.region_1}"
    region          = var.region_1
    })
  }

}

module "vpc_region_2" {
  source = "../../modules/vpc"

  networks = { for k, v in var.networks_region_2 : k => merge(v, {
    name            = "${var.name_prefix}${v.name}"
    subnetwork_name = "${var.name_prefix}${v.subnetwork_name}-${var.region_2}"
    region          = var.region_2
    })
  }
  depends_on = [module.vpc_region_1]
}

resource "google_compute_route" "route_region_1" {

  for_each = var.routes_region_1

  name         = "${var.name_prefix}${each.value.name}-${var.region_1}"
  dest_range   = each.value.destination_range
  network      = module.vpc_region_1.networks["${var.name_prefix}${each.value.network}"].self_link
  next_hop_ilb = module.lb_internal_region_1[each.value.lb_internal_key].address
  priority     = 100
  tags         = [var.region_1]
}

resource "google_compute_route" "route_region_2" {

  for_each = var.routes_region_2

  name         = "${var.name_prefix}${each.value.name}-${var.region_2}"
  dest_range   = each.value.destination_range
  network      = module.vpc_region_2.networks["${var.name_prefix}${each.value.network}"].self_link
  next_hop_ilb = module.lb_internal_region_2[each.value.lb_internal_key].address
  priority     = 100
  tags         = [var.region_2]
}

module "vpc_peering" {
  source = "../../modules/vpc-peering"

  for_each = var.vpc_peerings

  local_network = module.vpc_region_1.networks["${var.name_prefix}${each.value.local_network}"].id
  peer_network  = module.vpc_region_1.networks["${var.name_prefix}${each.value.peer_network}"].id

  local_export_custom_routes                = each.value.local_export_custom_routes
  local_import_custom_routes                = each.value.local_import_custom_routes
  local_export_subnet_routes_with_public_ip = each.value.local_export_subnet_routes_with_public_ip
  local_import_subnet_routes_with_public_ip = each.value.local_import_subnet_routes_with_public_ip

  peer_export_custom_routes                = each.value.peer_export_custom_routes
  peer_import_custom_routes                = each.value.peer_import_custom_routes
  peer_export_subnet_routes_with_public_ip = each.value.peer_export_subnet_routes_with_public_ip
  peer_import_subnet_routes_with_public_ip = each.value.peer_import_subnet_routes_with_public_ip
}

module "vmseries_region_1" {
  source = "../../modules/vmseries"

  for_each = var.vmseries_region_1

  name                  = "${var.name_prefix}${each.value.name}-${var.region_1}"
  zone                  = each.value.zone
  ssh_keys              = try(each.value.ssh_keys, var.vmseries_common.ssh_keys)
  vmseries_image        = try(each.value.vmseries_image, var.vmseries_common.vmseries_image)
  machine_type          = try(each.value.machine_type, var.vmseries_common.machine_type)
  min_cpu_platform      = try(each.value.min_cpu_platform, var.vmseries_common.min_cpu_platform, "Intel Cascade Lake")
  tags                  = try(each.value.tags, var.vmseries_common.tags, [])
  service_account       = try(module.iam_service_account[each.value.service_account_key].email, module.iam_service_account[var.vmseries_common.service_account_key].email)
  scopes                = try(each.value.scopes, var.vmseries_common.scopes, [])
  create_instance_group = true

  bootstrap_options = try(
    merge(
      { vmseries-bootstrap-gce-storagebucket = "${module.bootstrap[each.value.bootstrap_bucket_key].bucket_name}/${each.key}/" },
    var.vmseries_common.bootstrap_options),
    merge(
      try(each.value.bootstrap_options, {}),
      try(var.vmseries_common.bootstrap_options, {})
  ))

  named_ports = try(each.value.named_ports, [])

  network_interfaces = [for v in each.value.network_interfaces :
    {
      subnetwork       = module.vpc_region_1.subnetworks["${var.name_prefix}${v.subnetwork}-${var.region_1}"].self_link
      private_ip       = v.private_ip
      create_public_ip = try(v.create_public_ip, false)
  }]
}

module "vmseries_region_2" {
  source = "../../modules/vmseries"

  for_each = var.vmseries_region_2

  name                  = "${var.name_prefix}${each.value.name}-${var.region_2}"
  zone                  = each.value.zone
  ssh_keys              = try(each.value.ssh_keys, var.vmseries_common.ssh_keys)
  vmseries_image        = try(each.value.vmseries_image, var.vmseries_common.vmseries_image)
  machine_type          = try(each.value.machine_type, var.vmseries_common.machine_type)
  min_cpu_platform      = try(each.value.min_cpu_platform, var.vmseries_common.min_cpu_platform, "Intel Cascade Lake")
  tags                  = try(each.value.tags, var.vmseries_common.tags, [])
  service_account       = try(module.iam_service_account[each.value.service_account_key].email, module.iam_service_account[var.vmseries_common.service_account_key].email)
  scopes                = try(each.value.scopes, var.vmseries_common.scopes, [])
  create_instance_group = true

  bootstrap_options = try(
    merge(
      { vmseries-bootstrap-gce-storagebucket = "${module.bootstrap[each.value.bootstrap_bucket_key].bucket_name}/${each.key}/" },
    var.vmseries_common.bootstrap_options),
    merge(
      try(each.value.bootstrap_options, {}),
      try(var.vmseries_common.bootstrap_options, {})
  ))

  named_ports = try(each.value.named_ports, [])

  network_interfaces = [for v in each.value.network_interfaces :
    {
      subnetwork       = module.vpc_region_2.subnetworks["${var.name_prefix}${v.subnetwork}-${var.region_2}"].self_link
      private_ip       = v.private_ip
      create_public_ip = try(v.create_public_ip, false)
  }]
}

data "google_compute_image" "my_image" {
  family  = "ubuntu-pro-2204-lts"
  project = "ubuntu-os-pro-cloud"
}

resource "google_compute_instance" "linux_vm_region_1" {
  for_each = var.linux_vms_region_1

  name         = "${var.name_prefix}${each.key}-${var.region_1}"
  machine_type = each.value.linux_machine_type
  zone         = each.value.zone

  boot_disk {
    initialize_params {
      image = data.google_compute_image.my_image.id
      size  = each.value.linux_disk_size
    }
  }

  network_interface {
    subnetwork = module.vpc_region_1.subnetworks["${var.name_prefix}${each.value.subnetwork}-${var.region_1}"].self_link
    network_ip = each.value.private_ip
  }

  tags = [var.region_1]

  metadata = {
    enable-oslogin = true
  }


  service_account {
    email  = module.iam_service_account[each.value.service_account_key].email
    scopes = each.value.scopes
  }
}

resource "google_compute_instance" "linux_vm_region_2" {
  for_each = var.linux_vms_region_2

  name         = "${var.name_prefix}${each.key}-${var.region_2}"
  machine_type = each.value.linux_machine_type
  zone         = each.value.zone

  boot_disk {
    initialize_params {
      image = data.google_compute_image.my_image.id
      size  = each.value.linux_disk_size
    }
  }

  network_interface {
    subnetwork = module.vpc_region_2.subnetworks["${var.name_prefix}${each.value.subnetwork}-${var.region_2}"].self_link
    network_ip = each.value.private_ip
  }

  tags = [var.region_2]

  metadata = {
    enable-oslogin = true
  }


  service_account {
    email  = module.iam_service_account[each.value.service_account_key].email
    scopes = each.value.scopes
  }
}

module "lb_internal_region_1" {
  source = "../../modules/lb_internal"

  for_each = var.lbs_internal_region_1

  region = var.region_1

  name              = "${var.name_prefix}${each.value.name}-${var.region_1}"
  health_check_port = try(each.value.health_check_port, "80")
  backends          = { for v in each.value.backends : v => module.vmseries_region_1[v].instance_group_self_link }
  ip_address        = each.value.ip_address
  subnetwork        = module.vpc_region_1.subnetworks["${var.name_prefix}${each.value.subnetwork}-${var.region_1}"].self_link
  network           = module.vpc_region_1.networks["${var.name_prefix}${each.value.network}"].self_link
  all_ports         = true
}

module "lb_internal_region_2" {
  source = "../../modules/lb_internal"

  for_each = var.lbs_internal_region_2

  region = var.region_2

  name              = "${var.name_prefix}${each.value.name}-${var.region_2}"
  health_check_port = try(each.value.health_check_port, "80")
  backends          = { for v in each.value.backends : v => module.vmseries_region_2[v].instance_group_self_link }
  ip_address        = each.value.ip_address
  subnetwork        = module.vpc_region_2.subnetworks["${var.name_prefix}${each.value.subnetwork}-${var.region_2}"].self_link
  network           = module.vpc_region_2.networks["${var.name_prefix}${each.value.network}"].self_link
  all_ports         = true
}

module "lb_external_region_1" {
  source = "../../modules/lb_external"

  for_each = var.lbs_external_region_1

  project = var.project

  region = var.region_1

  name                    = "${var.name_prefix}${each.value.name}-${var.region_1}"
  backend_instance_groups = { for v in each.value.backends : v => module.vmseries_region_1[v].instance_group_self_link }
  rules                   = each.value.rules

  health_check_http_port         = each.value.http_health_check_port
  health_check_http_request_path = try(each.value.http_health_check_request_path, "/php/login.php")
}

module "lb_external_region_2" {
  source = "../../modules/lb_external"

  for_each = var.lbs_external_region_2

  project = var.project

  region = var.region_2

  name                    = "${var.name_prefix}${each.value.name}-${var.region_2}"
  backend_instance_groups = { for v in each.value.backends : v => module.vmseries_region_2[v].instance_group_self_link }
  rules                   = each.value.rules

  health_check_http_port         = each.value.http_health_check_port
  health_check_http_request_path = try(each.value.http_health_check_request_path, "/php/login.php")
}
# tofu/simplified/image.tf
data "http" "schematic_id" {
  url          = "${var.talos_factory_url}/schematics"
  method       = "POST"
  request_body = local.schematic
}

data "http" "schematic_id_intel_a310" {
  count = length(var.intel_a310_worker_id) == 0 ? 0 : 1

  url          = "${var.talos_factory_url}/schematics"
  method       = "POST"
  request_body = local.schematic_intel_a310
}

data "http" "schematic_id_amd_r9700" {
  count = length(var.amd_r9700_worker_id) == 0 ? 0 : 1

  url          = "${var.talos_factory_url}/schematics"
  method       = "POST"
  request_body = local.schematic_amd_r9700
}

data "http" "schematic_id_intel_b70" {
  count = length(var.intel_b70_worker_id) == 0 ? 0 : 1

  url          = "${var.talos_factory_url}/schematics"
  method       = "POST"
  request_body = local.schematic_intel_b70
}

data "http" "schematic_id_amd_framework" {
  count = length(var.metal_amd_framework_workers) == 0 ? 0 : 1

  url          = "${var.talos_factory_url}/schematics"
  method       = "POST"
  request_body = local.schematic_amd_framework
}

resource "proxmox_virtual_environment_download_file" "intel_a310" {
  count = length(var.intel_a310_worker_id) == 0 ? 0 : 1

  node_name               = var.proxmox_file_node
  content_type            = "iso"
  datastore_id            = var.file_datastore_id
  decompression_algorithm = "gz"
  overwrite               = false

  url       = "${var.talos_factory_url}/image/${local.schematic_id_intel_a310}/${var.talos_version}/${var.talos_platform}-${var.talos_arch}.raw.gz"
  file_name = "${var.environment}-talos-${local.schematic_id_intel_a310}-${var.talos_version}-${var.talos_platform}-${var.talos_arch}.img"
}

resource "proxmox_virtual_environment_download_file" "intel_b70" {
  count = length(var.intel_b70_worker_id) == 0 ? 0 : 1

  node_name               = var.proxmox_file_node
  content_type            = "iso"
  datastore_id            = var.file_datastore_id
  decompression_algorithm = "gz"
  overwrite               = false

  url       = "${var.talos_factory_url}/image/${local.schematic_id_intel_b70}/${var.talos_version}/${var.talos_platform}-${var.talos_arch}.raw.gz"
  file_name = "${var.environment}-talos-${local.schematic_id_intel_b70}-${var.talos_version}-${var.talos_platform}-${var.talos_arch}.img"
}

resource "proxmox_virtual_environment_download_file" "amd_r9700" {
  count = length(var.amd_r9700_worker_id) == 0 ? 0 : 1

  node_name               = var.proxmox_file_node
  content_type            = "iso"
  datastore_id            = var.file_datastore_id
  decompression_algorithm = "gz"
  overwrite               = false

  url       = "${var.talos_factory_url}/image/${local.schematic_id_amd_r9700}/${var.talos_version}/${var.talos_platform}-${var.talos_arch}.raw.gz"
  file_name = "${var.environment}-talos-${local.schematic_id_amd_r9700}-${var.talos_version}-${var.talos_platform}-${var.talos_arch}.img"
}

resource "proxmox_virtual_environment_download_file" "this" {
  node_name               = var.proxmox_file_node
  content_type            = "iso"
  datastore_id            = var.file_datastore_id
  decompression_algorithm = "gz"
  overwrite               = false

  url       = "${var.talos_factory_url}/image/${local.schematic_id}/${var.talos_version}/${var.talos_platform}-${var.talos_arch}.raw.gz"
  file_name = "${var.environment}-talos-${local.schematic_id}-${var.talos_version}-${var.talos_platform}-${var.talos_arch}.img"
}

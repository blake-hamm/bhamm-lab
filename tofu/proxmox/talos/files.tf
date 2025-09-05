# tofu/simplified/image.tf
data "http" "schematic_id" {
  url          = "${var.talos_factory_url}/schematics"
  method       = "POST"
  request_body = local.schematic
}

data "http" "schematic_id_intel_gpu" {
  count = var.enable_intel_gpu_worker ? 1 : 0

  url          = "${var.talos_factory_url}/schematics"
  method       = "POST"
  request_body = local.schematic_intel_gpu
}

resource "proxmox_virtual_environment_download_file" "intel_gpu" {
  count = var.enable_intel_gpu_worker ? 1 : 0

  node_name               = var.proxmox_file_node
  content_type            = "iso"
  datastore_id            = var.file_datastore_id
  decompression_algorithm = "gz"
  overwrite               = false

  url       = "${var.talos_factory_url}/image/${local.schematic_id_intel_gpu}/${var.talos_version}/${var.talos_platform}-${var.talos_arch}.raw.gz"
  file_name = "${var.environment}-talos-${local.schematic_id_intel_gpu}-${var.talos_version}-${var.talos_platform}-${var.talos_arch}.img"
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

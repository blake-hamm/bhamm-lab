# tofu/simplified/image.tf
data "http" "schematic_id" {
  url          = "${var.talos_factory_url}/schematics"
  method       = "POST"
  request_body = local.schematic
}

resource "proxmox_virtual_environment_download_file" "this" {
  node_name               = var.proxmox_file_node
  content_type            = "iso"
  datastore_id            = var.file_datastore_id
  decompression_algorithm = "gz"
  overwrite               = false

  url       = "${var.talos_factory_url}/image/${local.schematic_id}/${var.talos_version}/${var.talos_platform}-${var.talos_arch}.raw.gz"
  file_name = "talos-${local.schematic_id}-${var.talos_version}-${var.talos_platform}-${var.talos_arch}.img"
}

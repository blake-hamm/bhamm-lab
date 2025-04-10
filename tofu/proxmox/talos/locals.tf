locals {
  # Gather metadata to download talos image
  schematic    = file("${path.module}/image/schematic.yaml")
  schematic_id = jsondecode(data.http.schematic_id.response_body)["id"]
  image_id     = "${local.schematic_id}_${var.talos_version}"

  # Talos vm config
  master_nodes = [
    for idx in range(var.count_master) : {
      ip = format(var.master_ip_format, idx)
    }
  ]

  worker_nodes = [
    for idx in range(var.count_worker) : {
      ip = format(var.worker_ip_format, idx)
    }
  ]

  all_nodes = concat(local.worker_nodes, local.master_nodes)
}
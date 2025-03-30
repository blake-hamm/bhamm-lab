module "k3s_cluster" {
  source = "../../modules/k3s"

  # Required variables
  environment           = var.environment
  count_k3s_master      = var.count_k3s_master
  count_k3s_worker      = var.count_k3s_worker
  master_vm_id_start    = var.master_vm_id_start
  worker_vm_id_start    = var.worker_vm_id_start
  master_ip_format      = var.master_ip_format
  worker_ip_format      = var.worker_ip_format
  cpu_cores_master      = var.cpu_cores_master
  cpu_cores_worker      = var.cpu_cores_worker
  memory_dedicated_base = var.memory_dedicated_base
  enable_gpu_worker     = var.enable_gpu_worker
}
environment        = "blue"
count_master       = 3
count_worker       = 3
master_vm_id_start = 210
worker_vm_id_start = 220
master_ip_format   = "10.0.30.16%d"
worker_ip_format   = "10.0.30.17%d"
vip                = "10.0.30.130"
# enable_intel_gpu_worker = true
bare_metal_workers = {
  nose = {
    ip = "10.0.30.78"
    taint = {
      key    = "amd.com/gpu"
      effect = "NoSchedule"
    }
  }
}
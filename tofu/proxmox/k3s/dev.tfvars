environment        = "dev"
count_k3s_master   = 3
count_k3s_worker   = 1
master_vm_id_start = 210
worker_vm_id_start = 220
master_ip_format   = "10.0.30.16%d/24"
worker_ip_format   = "10.0.30.17%d/24"
enable_gpu_worker  = false
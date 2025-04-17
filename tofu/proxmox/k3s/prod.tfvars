environment        = "prod"
count_k3s_master   = 3
count_k3s_worker   = 2
master_vm_id_start = 110
worker_vm_id_start = 120
master_ip_format   = "10.0.30.6%d/24"
worker_ip_format   = "10.0.30.7%d/24"
enable_gpu_worker  = false
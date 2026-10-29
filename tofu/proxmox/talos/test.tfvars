environment        = "test"
count_master       = 3
count_worker       = 3
master_vm_id_start = 210
worker_vm_id_start = 220
master_ip_format   = "10.0.30.16%d"
worker_ip_format   = "10.0.30.17%d"
vip                = "10.0.30.130"
memory_base_master = 4096
memory_base_worker = 12288
# Cap test workers at 4 vCPU so test + prod running side by side on
# indy/japan (16 threads each) stay at or below the host thread count (#360).
cpu_cores_worker = 4
# enable_intel_a310_worker = true
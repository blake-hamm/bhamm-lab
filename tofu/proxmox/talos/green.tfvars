environment        = "green"
count_master       = 3
count_worker       = 3
master_vm_id_start = 110
worker_vm_id_start = 120
master_ip_format   = "10.0.30.6%d"
worker_ip_format   = "10.0.30.7%d"
vip                = "10.0.30.30"
intel_gpu_worker_id = [
  "0000:86:00.0",
  "0000:87:00.0"
]
# metal_amd_framework_workers = {
#   nose = {
#     ip = "10.0.30.78"
#     taint = {
#       key    = "amd.com/gpu"
#       effect = "NoSchedule"
#     }
#   }
#   tail = {
#     ip = "10.0.30.79"
#     taint = {
#       key    = "amd.com/gpu"
#       effect = "NoSchedule"
#     }
#   }
# }
amd_gpu_worker_id = [
  "0000:83:00"
]
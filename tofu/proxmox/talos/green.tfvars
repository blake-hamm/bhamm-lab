environment        = "green"
count_master       = 3
count_worker       = 3
master_vm_id_start = 110
worker_vm_id_start = 120
master_ip_format   = "10.0.30.6%d"
worker_ip_format   = "10.0.30.7%d"
vip                = "10.0.30.30"
intel_a310_worker_id = [
  "0000:86:00.0",
  "0000:87:00.0"
]
metal_amd_framework_workers = {
  nose = {
    ip = "10.0.30.78"
    taint = {
      key    = "amd.com/gpu"
      effect = "NoSchedule"
    }
    usb4_bus_path = "0-2.0"
    usb4_mesh_ip  = "10.30.0.78"
    usb4_peer_ip  = "10.30.0.79"
  }
  tail = {
    ip = "10.0.30.79"
    taint = {
      key    = "amd.com/gpu"
      effect = "NoSchedule"
    }
    usb4_bus_path = "1-2.0"
    usb4_mesh_ip  = "10.30.0.79"
    usb4_peer_ip  = "10.30.0.78"
  }
}
amd_r9700_worker_id = [
  "0000:83:00"
]
# Intel Arc Pro B70 (Battlemage, PCI 8086:e223, audio 8086:e2f7).
# TODO(blake): fill in the full PCI address(es) discovered on method via:
#   sudo lspci -d 8086: | grep -i "3d\|display\|e223"   (GPU + audio function)
# e.g. "0000:88:00.0" (GPU) + "0000:88:00.1" (audio). Until set, the B70
# VM is not created (length == 0 -> no VM / image / schematic).
intel_b70_worker_id = []
disk_size_amd_r9700_worker = 100

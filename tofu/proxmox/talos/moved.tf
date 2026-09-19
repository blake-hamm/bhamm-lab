# moved blocks for GPU node hostname rename (Phase 0 naming refactor)
# Ensures tofu apply renames VMs in-place rather than destroy + recreate.
# Safe to delete after the rename is applied and state is stable.

moved {
  from = proxmox_virtual_environment_vm.this["green-talos-worker-intel-gpu"]
  to   = proxmox_virtual_environment_vm.this["green-talos-worker-intel-a310"]
}

moved {
  from = proxmox_virtual_environment_vm.this["green-talos-worker-amd-gpu"]
  to   = proxmox_virtual_environment_vm.this["green-talos-worker-amd-r9700"]
}

moved {
  from = talos_machine_configuration_apply.vms["green-talos-worker-intel-gpu"]
  to   = talos_machine_configuration_apply.vms["green-talos-worker-intel-a310"]
}

moved {
  from = talos_machine_configuration_apply.vms["green-talos-worker-amd-gpu"]
  to   = talos_machine_configuration_apply.vms["green-talos-worker-amd-r9700"]
}

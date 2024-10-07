data "vault_kv_secret_v2" "example" {
  mount = "secret"
  name  = "example/foo"
}
output "example_secret_output" {
  value     = data.vault_kv_secret_v2.example
  sensitive = true
}
resource "proxmox_vm_qemu" "pxe-minimal-example" {
  name        = "pxe-minimal-example"
  agent       = 0
  boot        = "order=scsi0;net0"
  pxe         = true
  target_node = "aorus"
  network {
    bridge    = "vmbr0"
    firewall  = false
    link_down = false
    model     = "virtio"
  }
}
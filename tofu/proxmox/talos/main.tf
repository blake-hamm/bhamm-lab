provider "proxmox" {
  endpoint = var.proxmox_url
  insecure = true
  ssh {
    agent    = true
    username = "root"
    node {
      name    = "method"
      address = "10.0.20.11"
      port    = "4185"
    }
    node {
      name    = "indy"
      address = "10.0.20.12"
      port    = "4185"
    }
    node {
      name    = "stale"
      address = "10.0.20.13"
      port    = "4185"
    }
  }
}

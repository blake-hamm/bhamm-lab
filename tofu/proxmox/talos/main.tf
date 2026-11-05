provider "proxmox" {
  endpoint = var.proxmox_url
  insecure = true
}

# CI apply-path probe: comment-only edit to exercise plan+apply wiring
# for this stack now that it is apply-eligible. Safe to remove later.

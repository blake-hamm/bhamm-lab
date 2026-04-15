# NUT Client Integration Plan

## Goal
Integrate NUT (Network UPS Tools) client into:
1. Proxmox nodes (`method`, `indy`, `japan`) via Ansible
2. Talos bare metal nodes (`nose`, `tail`) via OpenTofu/Talos extensions

Both sets of nodes will monitor the existing NUT servers running on Orange Pi Zero3 devices.

---

## Existing Infrastructure

### NUT Servers (Orange Pi Zero3 - NixOS)
- **Server A:** `10.0.9.3` (CyberPower UPS, `usbhid-ups` driver)
- **Server B:** `10.0.9.4` (CyberPower UPS, `usbhid-ups` driver)
- Username: `nut-admin`
- Password: Managed via SOPS in `nix/secrets.yaml`
- NixOS module: `nix/modules/services/nut.nix`
- UPS name in config: `cyberpower`

### Proxmox Nodes (Ansible-managed)
- `method` (`10.0.20.11`)
- `indy` (`10.0.20.12`)
- `japan` (`10.0.20.15`)
- All three nodes are in the `proxmox` inventory group
- Custom `proxmox` role wraps `lae.proxmox` with pre/post tasks

### Talos Bare Metal Nodes (OpenTofu-managed)
- `nose` (`10.0.30.78`)
- `tail` (`10.0.30.79`)
- AMD Framework laptops running Talos Linux
- Schematic: `config/schematic-amd-framework.yaml`
- Machine config applied via `talos_machine_configuration_apply.bare_metal`

---

## Part 1: Proxmox NUT Client (Ansible)

### Target
All 3 Proxmox nodes will monitor `cyberpower@10.0.9.3` as NUT secondary clients.

### Implementation Location
Add tasks to the existing custom `proxmox` role:
- `ansible/roles/proxmox/tasks/nut-client.yml`
- Include it from `ansible/roles/proxmox/tasks/main.yml`

### Steps

1. **Install NUT client packages**
   - `nut-client` (Debian package)

2. **Create `upsmon.conf`**
   ```
   MONITOR cyberpower@10.0.9.3 1 nut-admin <password> secondary
   SHUTDOWNCMD "/sbin/shutdown -h +5"
   MINSUPPLIES 1
   POLLFREQ 5
   POLLFREQALERT 5
   HOSTSYNC 15
   DEADTIME 15
   RBWARNTIME 43200
   NOCOMMWARNTIME 300
   FINALDELAY 5
   ```

3. **Manage credentials securely**
   - Store the NUT `nut-admin` password in an Ansible Vault-encrypted file or SOPS-encrypted file within the Ansible directory.
   - Reference it via an Ansible variable (e.g., `nut_admin_password`).

4. **Configure service**
   - Ensure `nut-client` systemd service is enabled and started
   - Restart the service when `upsmon.conf` changes

5. **Variables to add**
   - In `ansible/inventory/group_vars/proxmox.yml`:
     ```yaml
     nut_client_enabled: true
     nut_server_host: "10.0.9.3"
     nut_ups_name: "cyberpower"
     nut_user: "nut-admin"
     nut_shutdown_delay_minutes: 5
     ```

6. **Proxmox role task flow update**
   - Add `nut-client.yml` as a post-task (after `lae.proxmox` but before or after `pbs.yml`)
   - Wrap with `when: nut_client_enabled | default(false)`

---

## Part 2: Talos Bare Metal NUT Client (OpenTofu/Talos)

### Target
`nose` and `tail` will monitor `cyberpower@10.0.9.4` using the official Talos `nut-client` system extension.

### Implementation Location
- `tofu/proxmox/talos/config/schematic-amd-framework.yaml` — add extension
- `tofu/proxmox/talos/cluster.tf` — add `ExtensionServiceConfig` patch for bare metal nodes
- `tofu/proxmox/talos/files.tf` — schematic ID will auto-regenerate on change

### Steps

1. **Add `nut-client` to the AMD Framework schematic**
   Update `tofu/proxmox/talos/config/schematic-amd-framework.yaml`:
   ```yaml
   customization:
     extraKernelArgs:
       - amd_iommu=off
       - amdgpu.gttsize=126976
       - amdgpu.vm_fragment_size=8
       - ttm.pages_limit=32505856
       - ttm.page_pool_size=25165824
     systemExtensions:
       officialExtensions:
         - siderolabs/fuse3
         - siderolabs/amd-ucode
         - siderolabs/amdgpu
         - siderolabs/thunderbolt
         - siderolabs/nut-client
   ```

2. **Add `ExtensionServiceConfig` for bare metal nodes**
   In `cluster.tf`, within the `talos_machine_configuration_apply.bare_metal` resource, add an additional `config_patches` entry (before the install disk patch):
   ```yaml
   apiVersion: v1alpha1
   kind: ExtensionServiceConfig
   name: nut-client
   configFiles:
     - content: |-
         MONITOR cyberpower@10.0.9.4 1 nut-admin <password> secondary
         SHUTDOWNCMD "/sbin/poweroff"
         MINSUPPLIES 1
         POLLFREQ 5
         POLLFREQALERT 5
         HOSTSYNC 15
         DEADTIME 15
       mountPath: /usr/local/etc/nut/upsmon.conf
   ```

3. **Password management**
   - The password can be hardcoded in the Terraform configuration or sourced from a Terraform variable.
   - Since the existing Talos configs don't use SOPS from OpenTofu directly, we can either:
     a) Pass it as a new Terraform variable (`var.nut_admin_password`)
     b) Hardcode it in the machine config patch (less ideal)
   - **Recommendation:** Add `nut_admin_password` to `variables.tf` and pass it via `*.tfvars` or environment variable.

4. **Variables to add**
   - `tofu/proxmox/talos/variables.tf`:
     ```hcl
     variable "nut_admin_password" {
       description = "Password for NUT admin user"
       type        = string
       sensitive   = true
     }
     ```
   - Update `green.tfvars` (and optionally `blue.tfvars`/`dev.tfvars`) to include the password or leave as manual input.

5. **Re-provision bare metal nodes**
   - Running `tofu apply` will regenerate the schematic ID (due to changed schematic file) and update the machine configuration.
   - The `nut-client` extension will be installed and `upsmon` will connect to `10.0.9.4`.

---

## Part 3: Testing & Validation

### Proxmox
1. Run Ansible against one Proxmox node:
   ```bash
   ansible-playbook ansible/main.yml --limit method --tags proxmox --check --diff
   ```
2. After apply, SSH to the node and verify:
   ```bash
   upsc cyberpower@10.0.9.3
   systemctl status nut-client
   ```
3. Simulate power failure (if safe) or disconnect NUT server to verify shutdown behavior after 5 minutes.

### Talos
1. Plan OpenTofu changes:
   ```bash
   cd tofu/proxmox/talos
   tofu workspace select green
   tofu plan -var-file=green.tfvars
   ```
2. Apply and reboot bare metal nodes if needed (schematic changes typically require an upgrade/reboot cycle on Talos).
3. Verify extension is running:
   ```bash
   talosctl -n 10.0.30.78 services | grep nut
   talosctl -n 10.0.30.78 logs nut-client
   ```
4. Test connectivity from within the extension:
   ```bash
   talosctl -n 10.0.30.78 exec --service nut-client -- /usr/local/bin/upsc cyberpower@10.0.9.4
   ```

---

## Part 4: Files to Modify

| File | Action |
|------|--------|
| `ansible/roles/proxmox/tasks/main.yml` | Include new `nut-client.yml` task file |
| `ansible/roles/proxmox/tasks/nut-client.yml` | Create new tasks for NUT client install/config |
| `ansible/inventory/group_vars/proxmox.yml` | Add NUT client variables |
| `ansible/inventory/group_vars/proxmox.yml` (or vault) | Add encrypted `nut_admin_password` |
| `tofu/proxmox/talos/config/schematic-amd-framework.yaml` | Add `siderolabs/nut-client` extension |
| `tofu/proxmox/talos/cluster.tf` | Add `ExtensionServiceConfig` patch to bare metal machine config apply |
| `tofu/proxmox/talos/variables.tf` | Add `nut_admin_password` variable |
| `tofu/proxmox/talos/green.tfvars` | Supply `nut_admin_password` value |

---

## Notes & Caveats

- **Talos `nut-client` extension** is community-tier (`contrib`). It has known issues on some hardware (e.g., Raspberry Pi 4 boot issues). For AMD Framework laptops, it should work but monitor logs after deployment.
- **Talos shutdown behavior:** The extension only supports `SHUTDOWNCMD "/sbin/poweroff"`. There is no built-in hook to drain Kubernetes workloads before shutdown. Proxmox handles VM shutdown gracefully via its own init system.
- **Proxmox shutdown delay:** `SHUTDOWNCMD "/sbin/shutdown -h +5"` schedules shutdown 5 minutes after the low-battery/on-battery signal triggers. Adjust as needed.
- **Password synchronization:** If the NUT server password changes in NixOS SOPS, both Ansible and OpenTofu configurations must be updated.

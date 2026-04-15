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
- Password: Managed via SOPS in `secrets.enc.json`
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

## Part 0: Pre-Requisites — Unify Secrets in `secrets.enc.json`

All secrets (Ansible, OpenTofu, and NixOS) will source the NUT password from the root-level `secrets.enc.json` file.

### Steps

1. **Add NUT secrets to `secrets.enc.json`**
   Add the following structure under the `core` namespace:
   ```json
   {
     "core": {
       "nut_server": {
         "password": "<nut-admin-password>"
       }
     }
   }
   ```
   > **Note:** Migrate the existing `nut_password` value from `nix/secrets.yaml` into this new key, then re-encrypt `secrets.enc.json`.

2. **Update NixOS SOPS configuration**
   Modify `nix/modules/core/sops.nix` to point to `secrets.enc.json`:
   ```nix
   sops.defaultSopsFile = ../../secrets.enc.json;
   sops.defaultSopsFormat = "json";
   ```
   Update any NixOS profiles that previously referenced `../secrets.yaml` (e.g., `nix/profiles/orangepi-pihole.nix`) to remove explicit `sopsFile` overrides if they are now covered by the default.

3. **(Optional) Retire `nix/secrets.yaml`**
   Once all NixOS secrets are migrated to `secrets.enc.json`, delete `nix/secrets.yaml` to eliminate duplication.

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

2. **Load root-level SOPS secrets**
   Use `community.sops.load_vars` to decrypt `secrets.enc.json` from the repo root:
   ```yaml
   - name: Load SOPS secrets
     community.sops.load_vars:
       file: "{{ playbook_dir }}/../secrets.enc.json"
     delegate_to: localhost
     no_log: true
   ```

3. **Create `upsmon.conf`**
   Template content:
   ```
   MONITOR cyberpower@10.0.9.3 1 nut-admin {{ ansible_secrets.core.nut_server.password }} secondary
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
- `tofu/proxmox/talos/sops.tf` — read the NUT password from `secrets.enc.json`

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

2. **Read the NUT password from SOPS in OpenTofu**
   Ensure `tofu/proxmox/talos/sops.tf` loads `secrets.enc.json` (or add a new `data.sops_file` resource scoped to this module):
   ```hcl
   data "sops_file" "this" {
     source_file = "../../secrets.enc.json"
   }
   ```
   Extract the password locally:
   ```hcl
   locals {
     nut_password = jsondecode(nonsensitive(data.sops_file.this.raw)).core.nut_server.password
   }
   ```

3. **Add `ExtensionServiceConfig` for bare metal nodes**
   In `cluster.tf`, within the `talos_machine_configuration_apply.bare_metal` resource, add an additional `config_patches` entry (before the install disk patch):
   ```yaml
   apiVersion: v1alpha1
   kind: ExtensionServiceConfig
   name: nut-client
   configFiles:
     - content: |-
         MONITOR cyberpower@10.0.9.4 1 nut-admin ${local.nut_password} secondary
         SHUTDOWNCMD "/sbin/poweroff"
         MINSUPPLIES 1
         POLLFREQ 5
         POLLFREQALERT 5
         HOSTSYNC 15
         DEADTIME 15
       mountPath: /usr/local/etc/nut/upsmon.conf
   ```

4. **Variables to add (optional)**
   If you prefer a Terraform variable wrapper instead of direct `local.nut_password`, add to `tofu/proxmox/talos/variables.tf`:
   ```hcl
   variable "nut_admin_password" {
     description = "Password for NUT admin user"
     type        = string
     sensitive   = true
     default     = ""
   }
   ```
   Then use `coalesce(var.nut_admin_password, local.nut_password)` in the patch. However, sourcing directly from SOPS is preferred.

5. **Re-provision bare metal nodes**
   - Running `tofu apply` will regenerate the schematic ID (due to changed schematic file) and update the machine configuration.
   - The `nut-client` extension will be installed and `upsmon` will connect to `10.0.9.4`.

---

## Part 3: Testing & Validation

### Proxmox
1. Run Ansible against one Proxmox node in check mode:
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

## Part 4: Update `AGENTS.md`

Update `AGENTS.md` to reflect the current server inventory. Specifically:
- Confirm `japan` is listed as an active Proxmox node under the Hardware section.
- Ensure the server list is accurate:
  - `method` (SuperMicro H12SSL-i)
  - `indy` (SuperMicro D-2146NT)
  - `japan` (X10SDV-4C-TLN4F or current hardware)
  - `stale` (X10SDV-4C-TLN4F)
  - `nose` & `tail` (Framework)

---

## Part 5: Files to Modify

| File | Action |
|------|--------|
| `secrets.enc.json` | Add `core.nut_server.password` (manual migration from `nix/secrets.yaml`) |
| `nix/modules/core/sops.nix` | Change `defaultSopsFile` to `../../secrets.enc.json` and `defaultSopsFormat` to `"json"` |
| `nix/profiles/orangepi-pihole.nix` | Remove explicit `sopsFile` overrides if now covered by default |
| `nix/secrets.yaml` | Delete after migration is complete |
| `ansible/roles/proxmox/tasks/main.yml` | Include new `nut-client.yml` task file |
| `ansible/roles/proxmox/tasks/nut-client.yml` | Create new tasks for NUT client install/config |
| `ansible/inventory/group_vars/proxmox.yml` | Add NUT client variables |
| `tofu/proxmox/talos/config/schematic-amd-framework.yaml` | Add `siderolabs/nut-client` extension |
| `tofu/proxmox/talos/sops.tf` | Add or confirm SOPS data source for `secrets.enc.json` |
| `tofu/proxmox/talos/cluster.tf` | Add `ExtensionServiceConfig` patch to bare metal machine config apply |
| `tofu/proxmox/talos/variables.tf` | Optionally add `nut_admin_password` variable |
| `AGENTS.md` | Update server inventory to include `japan` |

---

## Notes & Caveats

- **Unified secrets:** All tools now source the NUT password from a single `secrets.enc.json` file. Any password rotation requires updating only this file.
- **Talos `nut-client` extension** is community-tier (`contrib`). It has known issues on some hardware (e.g., Raspberry Pi 4 boot issues). For AMD Framework laptops, it should work but monitor logs after deployment.
- **Talos shutdown behavior:** The extension only supports `SHUTDOWNCMD "/sbin/poweroff"`. There is no built-in hook to drain Kubernetes workloads before shutdown. Proxmox handles VM shutdown gracefully via its own init system.
- **Proxmox shutdown delay:** `SHUTDOWNCMD "/sbin/shutdown -h +5"` schedules shutdown 5 minutes after the low-battery/on-battery signal triggers. Adjust as needed.

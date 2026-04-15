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

All NixOS, Ansible, and OpenTofu secrets will source from the root-level `secrets.enc.json` file.

> **Scope:** Only two NixOS hosts define SOPS secrets: `orangepi-zero3` and `orangepi-zero3-backup` (both import `nix/profiles/orangepi-pihole.nix`). The blast radius is minimal.

### Steps

1. **Migrate all NixOS secrets into `secrets.enc.json`**
   Add the following keys:
    ```json
    {
      "vault_secrets": {
        "core": {
          "orangepi": {
            "password": "<nut-admin-password>",
            "keepalived_auth_pass": "<keepalived-password>"
          }
        }
      }
    }
    ```
    > **Note:** Migrate both `nut_password` and `keepalived_auth_pass` from `nix/secrets.yaml` into `vault_secrets.core.orangepi`, then re-encrypt `secrets.enc.json`.

2. **Update NixOS SOPS configuration**
   Modify `nix/modules/core/sops.nix`:
   ```nix
   sops.defaultSopsFile = ../../secrets.enc.json;
   sops.defaultSopsFormat = "json";
   ```

3. **Update `nix/profiles/orangepi-pihole.nix`**
   - Remove both explicit `sopsFile = ../secrets.yaml;` overrides
   - Update `nut_password` to reference the shared key:
     ```nix
     sops.secrets.nut_password = {
       key = "vault_secrets.core.orangepi.password";
       restartUnits = [ "upsdrv.service" "upsd.service" "upsmon.service" ];
     };
     ```
   - Update `keepalived_auth_pass` to reference the new key under `orangepi`:
      ```nix
      sops.secrets.keepalived_auth_pass = {
        key = "vault_secrets.core.orangepi.keepalived_auth_pass";
        restartUnits = [ "keepalived.service" ];
      };
      ```

4. **Validate NixOS builds**
   Before applying, confirm both Orange Pi hosts still build:
   ```bash
   nix build .#nixosConfigurations.orangepi-zero3.config.system.build.toplevel
   nix build .#nixosConfigurations.orangepi-zero3-backup.config.system.build.toplevel
   ```

5. **Retire `nix/secrets.yaml`**
   Once builds pass and hosts activate successfully, delete `nix/secrets.yaml`.

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
   Use the `community.sops.sops` lookup plugin with `extract` to read only the required password:
   ```yaml
   - name: Get NUT password from SOPS
     ansible.builtin.set_fact:
       nut_password: "{{ lookup('community.sops.sops', playbook_dir + '/../secrets.enc.json', extract=['vault_secrets','core','orangepi','password']) }}"
     delegate_to: localhost
     no_log: true
   ```

3. **Create `upsmon.conf`**
   Template content:
   ```
   MONITOR cyberpower@10.0.9.3 1 nut-admin {{ nut_password }} secondary
   SHUTDOWNCMD "/sbin/shutdown -h now"
   MINSUPPLIES 1
   POLLFREQ 5
   POLLFREQALERT 5
   HOSTSYNC 15
   DEADTIME 15
   RBWARNTIME 43200
   NOCOMMWARNTIME 300
   FINALDELAY 5
   ```
   > **Why `now`?** FSD is sent when the server estimates ~3 minutes of battery remain. A client-side delay risks hard power loss. If you want to tolerate transient outages, handle delays server-side with `upssched` or `NOTIFYCMD`.

4. **Configure service**
   - Ensure `nut-monitor` systemd service is enabled and started
   - Restart the service when `upsmon.conf` changes
   > **Note:** On Debian 12 / Proxmox VE, the correct unit name is `nut-monitor.service`, not `nut-client.service`.

5. **Variables to add**
   - In `ansible/inventory/group_vars/proxmox.yml`:
     ```yaml
     nut_client_enabled: true
     nut_server_host: "10.0.9.3"
     nut_ups_name: "cyberpower"
     nut_user: "nut-admin"
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
   Ensure `tofu/proxmox/talos/sops.tf` loads `secrets.enc.json`:
   ```hcl
   data "sops_file" "this" {
     source_file = "../../secrets.enc.json"
   }
   ```
   Extract the password locally:
   ```hcl
   locals {
     nut_password = jsondecode(nonsensitive(data.sops_file.this.raw)).vault_secrets.core.orangepi.password
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
   > **Warning:** `ExtensionServiceConfig` embeds the password as plaintext in the Talos machine configuration. It will be visible in Terraform state and node config (`talosctl get machineconfigs`). This is a fundamental limitation of the extension.

4. **Re-provision bare metal nodes**
   - Running `tofu apply` will regenerate the schematic ID and update the machine configuration.
   - **Crucially, for bare metal nodes the extension must be baked into the installed OS image.** Existing nodes (`nose`, `tail`) will **not** automatically receive the extension until you explicitly upgrade them:
     ```bash
     talosctl upgrade --nodes <ip> --image factory.talos.dev/installer/<new-schematic-id>:<version>
     ```
   - After upgrading, `upsmon` will connect to `10.0.9.4`.

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
   systemctl status nut-monitor
   ```
3. Simulate power failure (if safe) or disconnect NUT server to verify shutdown behavior.

### Talos
1. Plan OpenTofu changes:
   ```bash
   cd tofu/proxmox/talos
   tofu workspace select green
   tofu plan -var-file=green.tfvars
   ```
2. Apply the configuration changes:
   ```bash
   tofu apply -var-file=green.tfvars
   ```
3. Upgrade the bare metal nodes with the new schematic installer image (get the schematic ID from `files.tf` or Terraform output):
   ```bash
   talosctl upgrade --nodes 10.0.30.78 --image factory.talos.dev/installer/<schematic-id>:<talos-version>
   talosctl upgrade --nodes 10.0.30.79 --image factory.talos.dev/installer/<schematic-id>:<talos-version>
   ```
4. Verify the extension is running:
   ```bash
   talosctl -n 10.0.30.78 services | grep nut
   talosctl -n 10.0.30.78 logs nut-client
   ```
5. Test connectivity from within the extension:
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
| `secrets.enc.json` | Add `vault_secrets.core.orangepi.password` and `vault_secrets.core.orangepi.keepalived_auth_pass` (migrate from `nix/secrets.yaml`) |
| `nix/modules/core/sops.nix` | Change `defaultSopsFile` to `../../secrets.enc.json` and `defaultSopsFormat` to `"json"` |
| `nix/profiles/orangepi-pihole.nix` | Remove explicit `sopsFile` overrides; update `nut_password` and `keepalived_auth_pass` keys to point under `vault_secrets.core.orangepi` |
| `nix/secrets.yaml` | Delete after migration and validation |
| `ansible/roles/proxmox/tasks/main.yml` | Include new `nut-client.yml` task file |
| `ansible/roles/proxmox/tasks/nut-client.yml` | Create new tasks for NUT client install/config |
| `ansible/inventory/group_vars/proxmox.yml` | Add NUT client variables |
| `tofu/proxmox/talos/config/schematic-amd-framework.yaml` | Add `siderolabs/nut-client` extension |
| `tofu/proxmox/talos/sops.tf` | Add or confirm SOPS data source for `secrets.enc.json` |
| `tofu/proxmox/talos/cluster.tf` | Add `ExtensionServiceConfig` patch to bare metal machine config apply |
| `AGENTS.md` | Update server inventory to include `japan` |

---

## Notes & Caveats

- **Unified secrets:** All tools now source secrets from a single `secrets.enc.json` file. Any password rotation requires updating only this file.
- **Talos `nut-client` extension** is community-tier (`contrib`). It has known issues on some hardware (e.g., Raspberry Pi 4 boot issues). For AMD Framework laptops, it should work but monitor logs after deployment.
- **Talos shutdown behavior:** The extension only supports `SHUTDOWNCMD "/sbin/poweroff"`. There is no built-in hook to drain Kubernetes workloads before shutdown. Proxmox handles VM shutdown gracefully via its own init system.
- **Proxmox shutdown delay:** `SHUTDOWNCMD "/sbin/shutdown -h now"` shuts down immediately upon receiving the FSD signal. FSD is sent when the server estimates ~3 minutes of battery remain; delaying client shutdown risks hard power loss. If you want to tolerate transient outages, implement a cancellable timer server-side using NUT `upssched` or `NOTIFYCMD`.
- **Talos password exposure:** The NUT password is embedded as plaintext in the Talos machine config via `ExtensionServiceConfig`. This is unavoidable with the current extension design.
- **No redundancy:** The plan assigns Proxmox to `10.0.9.3` and Talos to `10.0.9.4`. Consider adding both NUT servers as `MONITOR` targets (with `MINSUPPLIES 1`) in a future iteration for failover resilience.

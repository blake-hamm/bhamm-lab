# storage

Configures LVM storage for Proxmox hosts.

## Role behavior

The role operates in one of two modes depending on host hardware.

### Single-drive mode

Used on hosts with one drive shared by the OS and VMs (e.g. `indy`, `japan`).

- Root LV is resized to `storage_root_size` (default: `100g`).
- Root VG is renamed from `<hostname>-vg` to `local-vg`.
- Swap LV is created/resized to `storage_swap_size` (default: `4g`).
- Remaining space in `local-vg` is available for Proxmox VMs.

### Separate VM drive mode

Used on hosts with a small boot drive and a separate larger VM drive (e.g. `method`).

- `storage_vm_device` must be set to the VM drive path (e.g. `/dev/disk/by-id/...`).
- Root LV on the boot drive is resized to `storage_root_size`.
- Root VG keeps its original name (`<hostname>-vg`).
- A separate `local-vg` is created on `storage_vm_device`.
- Swap LV is created on the root VG.

## Variables

### `defaults/main.yml`

| Variable            | Default | Description                                          |
|---------------------|---------|------------------------------------------------------|
| `storage_vm_device` | `""`    | Path to dedicated VM storage device. Empty string enables single-drive mode. |
| `storage_root_size` | `100g`  | Size of the root logical volume.                     |
| `storage_swap_size` | `4g`    | Size of the swap logical volume.                     |
| `storage_resize_swap`| `true` | Whether to create/resize swap.                       |

### `vars/main.yml`

| Variable         | Value                        | Description                              |
|------------------|------------------------------|------------------------------------------|
| `storage_root_vg`| `local-vg` or `<hostname>-vg`| Dynamically set based on mode.           |
| `storage_root_lv`| `/dev/<vg>/root`             | Full path to the root logical volume.    |
| `storage_swap_lv`| `/dev/<vg>/swap1`            | Full path to the swap logical volume.    |

## Why `local-vg`?

The [`lae.proxmox`](https://galaxy.ansible.com/lae/proxmox) role provisions Proxmox storage using `vgname: local-vg`. Using a consistent VG name across all hosts lets Terraform provision VMs without per-host logic.

## Idempotency

The role is fully idempotent. Re-runs report no changes when the system is already correctly configured.

## Known behaviors

- Uses `/dev/<vg>/<lv>` paths instead of `/dev/mapper/` to avoid LVM rename escaping issues.
- Swap LV resize uses remove-and-recreate because `lvreduce` cannot shrink swap filesystems.
- Filesystem resize uses separate `xfs_growfs`/`resize2fs` calls because `lvol resizefs` fails after a VG rename.

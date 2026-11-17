# pi-display

Raspberry Pi 5 (4 GB) driving the official Raspberry Pi Touch Display 2
(7 inch, 720x1280 native portrait, DSI, Goodix GT911 touch) as a Wall-Display
style kiosk: `greetd` -> `labwc` -> `brave --kiosk`, with `wvkbd` available on
demand and a local test page served on port 8080.

- Node name: `pi-display` (colmena hive node, tags `pi-display sbc kiosk display`)
- Address: `10.0.9.101` **temporarily** (bench iteration), static `10.0.20.22`
  once the board is on its real VLAN
- Image: `nixosConfigurations.pi-display-image`
- Boot: firmware-direct kernel boot from SD (bootloader = kernel, no U-Boot)

## Layout

| file | role |
|------|------|
| `default.nix` | colmena node: `system`, `deploy` attrs, module list |
| `config.nix` | kiosk stack (greetd/labwc/brave/wvkbd), test page, zram, thermals - shared by image and deploy |
| `hardware.nix` | board support module, vendor kernel/firmware overlays, DSI overlay, bootloader |
| `sd-image.nix` | SD image bits (`compressImage`) on top of the vendor sd-image module |
| `index.html`, `policies.json` | served test page and Brave managed policy |

## Hardware facts proven on this board

- Official Touch Display 2 on the **CAM/DISP 1** connector (DSI1). The
  `vc4-kms-dsi-ili9881-7inch` overlay defaults to DSI1 + `i2c_csi_dsi`; the
  `dsi0` parameter is deliberately omitted because it selects DISP0/DSI0.
- **The overlay is mandatory, not a fallback.** Firmware autodetect does not
  bring this panel up: generated `config.txt` has `display_auto_detect=1` and no
  ili9881 overlay, and the live system showed no DSI connector and no
  `ili9881`/`goodix` modules.
- `services.greetd` needs **both** `initial_session` and `default_session`; with
  only `initial_session` it exits 1 with `default_session contains no command`
  and systemd restarts it every 5s.
- `raspberry-pi-5.display-rp1` must **not** be imported: it only sets an X11
  `OutputClass`, inert under Wayland/labwc.
- 16k page size is *not* enabled: `raspberry-pi-5.page-size-16k` is not
  imported. Only `raspberry-pi-5.base` (vendor `linux-rpi` kernel) plus the
  vendor overlays are, and the board will not boot a stock nixpkgs aarch64
  image.

## Known open defects

1. **No scanout to the DSI panel** even though `drm-rp1-dsi` binds. The
   connector exists, the panel does not light up.
2. **Goodix GT911 touch fails to probe with `-121`** (`-EREMOTEIO`, i2c
   transfer error), so no touch input at all.

Both are kernel/overlay-side and out of scope for the change that created this
host; record progress on Codeberg issue #415.

## Building the image

Native `aarch64-linux` only - there is no cross-build path in this repo. An
aarch64 builder (on-device, QEMU binfmt, or a remote builder) is required.

The vendor kernel (`linux-rpi`) is not on `cache.nixos.org`. Trust the upstream
cache once, otherwise the kernel is compiled under emulation (hours):

```bash
nix build .#nixosConfigurations.pi-display-image.config.system.build.sdImage --accept-flake-config
```

Or permanently, in the build machine's `nix.conf`:

```
extra-substituters = https://nixos-raspberrypi.cachix.org
extra-trusted-public-keys = nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI=
```

`copying path` means the cache is in use; `building '/nix/store/...-linux-rpi-*.drv'`
means you are compiling the kernel. The root `flake.nix` declares the same cache
in `nixConfig`, which Nix only honours with `--accept-flake-config` or a trusted
`nix.conf` entry.

```bash
zstdcat result/sd-image/nixos-image-rpi5-kernel-*.img.zst | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
```

`/dev/sdX` is whatever `lsblk` says it is. Connect the display ribbon to
CAM/DISP 1 and the touch ribbon per the Touch Display 2 instructions, then power
on. The panel shows the test page including the host's IPv4 address, which is how
you find the box without a serial console.

## Deploying

Over SSH from the hub/workstation, with the node's temporary `targetPort = 22`:

```bash
colmena build --on pi-display
colmena apply --on pi-display
```

Colmena's `deployment.targetPort` is **per node** (colmena v0.5.0,
`src/nix/hive/options.nix`, `deploymentOptions.deployment.targetPort`), so this
node uses 22 while every other node keeps the shared 4185 from
`nix/lib/generators.nix`. If a colmena version without that option is in use,
drive it with `NIX_SSHOPTS="-p 22"` instead.

The node deploys as `root` for now: this image has no `bhamm` user until
`core/ssh.nix` / `core/user.nix` are imported.

`config.txt` changes are the exception to `apply`: the firmware partition is not
rebuilt by a switch, so overlay edits need an image rebuild or a hand edit of
`/boot/firmware/config.txt` plus a reboot:

```bash
sudo mount /boot/firmware
printf 'dtoverlay=vc4-kms-dsi-ili9881-7inch,sizex=720,sizey=1280,rotation=0\n' | sudo tee -a /boot/firmware/config.txt
sync
sudo reboot
```

## Deliberately deferred to the next change

- Static address `10.0.20.22` on the production VLAN (now `10.0.9.101`, DHCP-era
  bench address in `deploy.targetHost`).
- `nix/modules/core/ssh.nix`: port 4185, key-only auth, `AllowUsers`. Until then
  sshd stays on 22 with root reachable - this host is one bad change away from
  needing a physical recovery, and the structural refactor does not get to risk
  that.
- The shared profiles (`nix/profiles/sbc.nix`, `base.nix`) and therefore every
  `cfg.*` option: they import `nix/modules` wholesale, which includes
  `core/ssh.nix`.
- sops-nix secrets (root password and the known `bench` hash are temporary).
- Prometheus exporters / `monitoring.enable` from the shared profile.
- WiFi - wired Ethernet only.

## Verifying by hand

```bash
ls /sys/class/drm/
for f in /sys/class/drm/card*/modes; do echo "== $f"; cat "$f"; done
sudo dmesg | grep -i -E 'ili9881|dsi|drm|goodix|rp1'
lsmod | grep -i -E 'ili9881|goodix'
sudo libinput list-devices | grep -i -A4 goodix
vcgencmd measure_temp
```

Panel mode target: 720x1280 portrait (or 1280x720 if the compositor rotated it).
Touch is only proven when a finger trail on the panel follows the four corner
targets of the test page.

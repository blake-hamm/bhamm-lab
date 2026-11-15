# Pi 5 + Touch Display 2 bench harness

Throwaway bench for bringing up the official Raspberry Pi Touch Display 2
(7 inch, 720x1280 native portrait, DSI0, Goodix GT911 touch) on a Raspberry Pi 5
(4 GB) with a Brave kiosk on top.

This directory is a set of plain NixOS modules, not a flake. It is deliberately
not under `nix/hosts/` (the colmena auto-discovery would register it as a node)
and nothing here is deployed. It is wired into the root `flake.nix` as the
`pi5-bench-image` configuration so the image builds from the repo root exactly
like the Orange Pi SD images do. Delete the directory and that one attribute
once the question below is answered.

Question: what does the panel actually look like when `nixos-raspberrypi`'s
vendor kernel and firmware bring it up?

There is one configuration: `nixos-raspberrypi` (`raspberry-pi-5.base` +
`raspberry-pi-5.display-rp1`) with its own pinned nixpkgs and vendor kernel,
firmware-direct boot (`boot.loader.raspberry-pi.bootloader = "kernel"`).

The earlier "path A" (nixos-hardware `raspberry-pi/5` with the Foundation
`linux-rpi` kernel, booted the nixpkgs SD-image way through U-Boot) was
withdrawn and deleted: comparing the two paths no longer decided anything, since
nixos-hardware's pinned revision has no `deviceTreeOverlays` option and
`display-rp1` only sets an X11 OutputClass, which is inert under the kiosk's
Wayland session. Do not resurrect it.

## Status of this harness (read before trusting it)

- Nothing here has been built or booted yet. That is the point of the bench; the
  first run is the test.
- The `nixos-raspberrypi` input was added to the root `flake.nix` on a machine
  with no Nix, so `flake.lock` does not contain it yet. The first
  `nix build` resolves and writes it, which leaves `flake.lock` modified in the
  tree. Commit that updated `flake.lock` back on this branch once the image
  builds, and do not commit it before then.
- `nixos-raspberrypi` is pinned to its `main` branch. The module names used here
  (`raspberry-pi-5.base`, `raspberry-pi-5.display-rp1`, `sd-image`) were read
  from that flake's `nixosModules` output.
- Footnote, not a reason for the choice: `display-rp1` only sets an X11
  `OutputClass` for the RP1 drivers. It is harmless under the kiosk's Wayland
  session, but do not expect it to do anything for what the panel shows.

## Prerequisites

- Raspberry Pi 5, 4 GB.
- Official 27 W USB-C power supply.
- Active cooler or heatsink. This bench runs a kiosk for an hour and then
  measures temperature.
- Two SD cards (16 GB is plenty) and a USB SD reader.
- Ethernet cable on the same LAN as your workstation. The bench takes a DHCP
  lease; it does not use the production `10.0.20.22` address.

## Step 1 - get any aarch64 NixOS onto the Pi

Flash an aarch64 nixos-unstable SD image. The 26.05 release images do not carry
the Pi 5 boot files, and the unstable channel no longer publishes SD images
under a `latest-*` alias, so resolve the current build from Hydra first:

```
curl -sL https://hydra.nixos.org/job/nixos/trunk-combined/nixos.sd_image.aarch64-linux/latest -o /tmp/sd.html
url=$(grep -o 'https://hydra.nixos.org/build/[0-9]*/download/1/[^"]*\.img\.zst' /tmp/sd.html | head -1)
echo "$url"
curl -L -o nixos-sd.img.zst "$url"
nix-shell -p zstd --run "zstd -d nixos-sd.img.zst"
lsblk
sudo dd if=nixos-sd.img of=/dev/sdX bs=4M status=progress conv=fsync
```

Any other aarch64 nixos-unstable SD image works just as well, as long as it
carries the Pi 5 firmware and device trees; where it came from does not matter
to the bench.

Boot it with the display NOT connected yet, plug in Ethernet, and find it:

```
ping nixos
ssh nixos@nixos.local
```

A `nixos-raspberrypi` installer image is equally acceptable here, and it is the
better starting point because its binary cache already holds the vendor kernel.

## Step 2 - build the bench image from the repo root

Builds are native `aarch64-linux` only; there is no cross-build path in this
repo. An `aarch64-linux` builder (native on-device, QEMU binfmt, or a remote
builder) is required.

These commands run from the repo root against the root flake, exactly like the
Orange Pi SD-image commands in the operations docs.

```
nix-shell -p git
git clone https://codeberg.org/blake-hamm/bhamm-lab.git
git -C bhamm-lab checkout feature/pi-display-bench
```

Open a shell in that directory ("the repo root" below), then continue.

Then, still at the repo root:

```bash
nix build .#nixosConfigurations.pi5-bench-image.config.system.build.sdImage
```

Result: `./result/sd-image/nixos-image-sd-card-*.img.zst`

**Flash to SD card** (verify `/dev/sdX` with `lsblk`):

```bash
zstdcat result/sd-image/nixos-image-sd-card-*.img.zst | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
```

The vendor kernel comes from the `nixos-raspberrypi` cache, so the build should
not compile a kernel. If it starts to, the cache was not trusted: pass
`--accept-flake-config`, or check that the flake's `nixConfig` substituters are
reachable.

If `nix build` refuses to work at all with an "experimental Nix feature
'nix-command' is disabled" error, enable flakes on that machine once (for
example `experimental-features = nix-command flakes` in
`/etc/nix/nix.conf`); the commands in this runbook then run unmodified.

## Step 3 - boot the bench card

Power off, swap cards, connect the display ribbon to DSI0 and the touch ribbon
to the CSI/display connector as per the Touch Display 2 instructions, power on.

The panel should show the test page: window size, devicePixelRatio, orientation,
the host IPv4 address, a clock, a touch trail, and four corner targets.

Read the address off the panel and log in (the root password is `bench`; this is
a desk bench, change it if it ever leaves the desk):

```
ssh root@192.168.1.50   # substitute the DHCP address shown on the panel
```

If the panel stays dark, read the address from the router's DHCP leases or plug
in a monitor on HDMI, then continue to steps 4 and 5.

## Step 4 - checks to run and record

Panel mode. You are looking for a connector whose modelist is 720x1280 and a
current mode of 720x1280 (portrait), or 1280x720 if the compositor rotated it:

```
ls /sys/class/drm/
for f in /sys/class/drm/card*/modes; do echo "== $f"; cat "$f"; done
modetest -c 2>/dev/null | grep -i -A6 dsi
```

Touch. The Goodix GT911 must be bound and must produce ABS_MT events whose
coordinates match what the page shows when you drag a finger:

```
sudo libinput list-devices | grep -i -A4 goodix
sudo libinput debug-events
sudo evtest
```

Touch mapping is the check with teeth: draw a line from the top-left target to
the bottom-right target and confirm the trail follows the finger, including
while the panel is in its native portrait orientation.

Kernel side:

```
sudo dmesg | grep -i -E 'ili9881|dsi|drm|goodix|rp1'
lsmod | grep -i -E 'ili9881|goodix'
```

Thermals over an hour with the kiosk running:

```
for i in $(seq 60); do printf '%s ' "$(date +%H:%M)"; vcgencmd measure_temp; sleep 60; done
```

Brave policy, verified in the browser rather than assumed:

```
sudo -u kiosk env XDG_RUNTIME_DIR=/run/user/$(id -u kiosk) WAYLAND_DISPLAY=wayland-0 \
  brave --ozone-platform=wayland brave://policy
```

Record which of the keys in `policies.json` show up as managed values. The
`Brave*` keys are documented by Brave; `HideFirstRunExperience`,
`DefaultBrowserSettingEnabled`, `PromotionalTabsEnabled` and
`MetricsReportingEnabled` are Chromium-inherited and are NOT documented by Brave,
so `brave://policy` is the only proof they were accepted.

Four-corner test: tap all four targets, expect `PASS`, tap the centre circle to
reset, then repeat once after rotating the panel if you changed rotation
parameters.

## Step 5 - if the panel stays dark

The firmware is meant to detect the display and apply the overlay by itself
(`display_auto_detect=1` is nixos-raspberrypi's default and is left untouched).
If it does not, add the overlay explicitly and reboot:

```
sudo mount /boot/firmware
printf 'dtoverlay=vc4-kms-dsi-ili9881-7inch\n' | sudo tee -a /boot/firmware/config.txt
sync
sudo reboot
```

If the panel comes up but the image is mirrored or rotated, replace that line
(it must not appear twice) with the parameterised form:

```
sudo sed -i '/vc4-kms-dsi-ili9881-7inch/d' /boot/firmware/config.txt
printf 'dtoverlay=vc4-kms-dsi-ili9881-7inch,sizex=720,sizey=1280,swapxy=0,invx=0,invy=0\n' \
  | sudo tee -a /boot/firmware/config.txt
sync
sudo reboot
```

The same change lives in `pi5-bench.nix` as the commented
`hardware.raspberry-pi.config.all.dt-overlays.vc4-kms-dsi-ili9881-7inch` block.
Editing `/boot/firmware/config.txt` and rebooting is faster than rebuilding an
image, which is why it is the documented flip.

After the first successful boot, iterate without reflashing (from the repo root,
on the bench itself):

```bash
sudo nixos-rebuild switch --flake .#pi5-bench-image
```

`config.txt` changes are the exception: the firmware partition is not rebuilt by
`nixos-rebuild`, so those still need an image rebuild or a hand edit plus reboot.

## Results

Fill this in as you go. Leave a cell as `?` rather than guessing.

| panel came up | mode reported | touch works | rotation params needed | dmesg errors | peak temp | notes |
|---------------|---------------|-------------|------------------------|--------------|-----------|-------|
| y / n         |               | y / n       |                        |              |           |       |

## How to report back

Paste the filled table, plus the raw output of the step 4 commands, as a comment
on Codeberg issue #415.

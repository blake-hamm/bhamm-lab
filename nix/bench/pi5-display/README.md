# Pi 5 + Touch Display 2 bench harness

Throwaway bench for bringing up the official Raspberry Pi Touch Display 2
(7 inch, 720x1280 native portrait, DSI0, Goodix GT911 touch) on a Raspberry Pi 5
(4 GB) with a Brave kiosk on top.

This directory is a self-contained sub-flake. It is deliberately not under
`nix/hosts/` (the colmena auto-discovery would register it as a node), it is not
imported from the root `flake.nix`, and nothing here is deployed. Delete it once
the question below is answered.

Question: which stack actually lights the panel, and what does it look like when
it does?

- Path A (`bench-a`): nixos-hardware `raspberry-pi/5` with the Foundation
  `linux-rpi` kernel, booted the nixpkgs SD-image way (firmware -> U-Boot ->
  extlinux), relying on the firmware's `display_auto_detect=1`.
- Path B (`bench-b`): `nixos-raspberrypi` (`raspberry-pi-5.base` +
  `raspberry-pi-5.display-rp1`) with its own pinned nixpkgs and vendor kernel,
  firmware-direct boot (`boot.loader.raspberry-pi.bootloader = "kernel"`).

Both share `kiosk.nix` byte for byte, so the kernel and display stack are the
only variable.

## Status of this harness (read before trusting it)

- Neither configuration has been built or booted yet. That is the point of the
  bench; the first run is the test.
- No `flake.lock` is committed: the agent box that wrote this had no Nix, so the
  lock is created by the first `nix build` on the Pi. Commit it back if you want
  the pins recorded.
- The nixos-hardware revision pinned by the root flake exposes
  `hardware.raspberry-pi.configtxt.{settings,file}` only. There is no
  `deviceTreeOverlays` option at that revision, so overlay lines are written as
  `settings.<filter>.dtoverlay = [ ... ]` instead (lists replace, they do not
  merge).
- `nixos-raspberrypi` is pinned to its `main` branch. The module names used here
  (`raspberry-pi-5.base`, `raspberry-pi-5.display-rp1`, `sd-image`) were read
  from that flake's `nixosModules` output, and `display-rp1` only sets an X11
  `OutputClass` for the RP1 drivers. It is harmless under Wayland, but do not
  expect it to do anything for the kiosk.

## Prerequisites

- Raspberry Pi 5, 4 GB.
- Official 27 W USB-C power supply.
- Active cooler or heatsink. This bench runs a kiosk for an hour and then
  measures temperature.
- Two SD cards (16 GB is plenty) and a USB SD reader.
- Ethernet cable on the same LAN as your workstation (DHCP).

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
better starting point for path B because its binary cache already holds the
vendor kernel.

## Step 2 - build the bench image on the Pi, dd it to the second card

Builds are native aarch64 only; there is no cross-build path in this repo. Run
these on the Pi, not on the workstation.

```
nix-shell -p git
git clone https://codeberg.org/blake-hamm/bhamm-lab.git
cd bhamm-lab
git checkout feature/pi-display-bench
cd nix/bench/pi5-display
```

Path A:

```
nix --extra-experimental-features 'nix-command flakes' build \
  .#nixosConfigurations.bench-a.config.system.build.sdImage
```

Path B:

```
nix --extra-experimental-features 'nix-command flakes' build \
  .#nixosConfigurations.bench-b.config.system.build.sdImage
```

Path A compiles the Foundation `linux-rpi` 6.12 kernel, which is not in any
binary cache. On a 4 GB Pi that is a multi-hour build and it will happily OOM.
Before starting it, put a 4 GB swapfile on a USB stick and cap parallelism:

```
sudo fallocate -l 4G /swapfile && sudo chmod 600 /swapfile
sudo mkswap /swapfile && sudo swapon /swapfile
export NIX_CONFIG='max-jobs = 3'
```

Path B pulls the kernel from the `nixos-raspberrypi` cache and should be quick.

Write the image to the second card:

```
ls -l result/sd-image/
lsblk
sudo dd if="$(ls result/sd-image/*.img | head -1)" of=/dev/sdX bs=4M status=progress conv=fsync
sync
```

## Step 3 - boot the bench card

Power off, swap cards, connect the display ribbon to DSI0 and the touch ribbon
to the CSI/display connector as per the Touch Display 2 instructions, power on.

The panel should show the test page: window size, devicePixelRatio, orientation,
the host IPv4 address, a clock, a touch trail, and four corner targets.

Read the address off the panel and log in (the root password is `bench`; this is
a desk bench, change it if it ever leaves the desk):

```
ssh root@192.168.1.50   # substitute the address shown on the panel
```

If the panel stays dark, read the address from the router's DHCP leases or plug
in a monitor on HDMI, then continue to step 4 and 5.

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

## Step 5 - if the panel stays dark on path A

The firmware is meant to detect the display and apply the overlay by itself. If
it does not, add the overlay explicitly and reboot:

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

The same change lives in `bench-a.nix` as the commented
`hardware.raspberry-pi.configtxt.settings.all.dtoverlay` block; on path B it is
`hardware.raspberry-pi.config.all.dt-overlays.vc4-kms-dsi-ili9881-7inch` in
`bench-b.nix`. Editing `/boot/firmware/config.txt` and rebooting is faster than
rebuilding an image, which is why it is the documented flip.

One known confounder on path A: the nixpkgs SD image boots through U-Boot, and
U-Boot loads the device tree itself. A firmware-applied DSI overlay may not
survive that hand-off. If the overlay line changes nothing on path A but does
work on path B, that is the difference, not the kernel choice. Confirm with
`ls /proc/device-tree/ | grep -i dsi` on both paths.

After the first successful boot, iterate without reflashing:

```
sudo nixos-rebuild switch --flake /path/to/bhamm-lab/nix/bench/pi5-display#bench-a
```

`config.txt` changes are the exception: the firmware partition is not rebuilt by
`nixos-rebuild`, so those still need an image rebuild or a hand edit plus reboot.

## Results

Fill this in as you go. Leave a cell as `?` rather than guessing.

| path | panel came up | mode reported | touch works | rotation params needed | dmesg errors | peak temp | notes |
|------|---------------|---------------|-------------|------------------------|--------------|-----------|-------|
| A    | y / n         |               | y / n       |                        |              |           |       |
| B    | y / n         |               | y / n       |                        |              |           |       |

## How to report back

Paste the filled table, plus the raw output of the step 4 commands, as a comment
on Codeberg issue #415.

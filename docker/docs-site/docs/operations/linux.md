# Linux
## ISO
*Some helpful commands when dealing with iso's*
```bash
# ⚠️ WARNING: These commands will irreversibly erase the target USB drive.
# Double-check the device path (e.g., /dev/sdX) before running them.
# You can list disks with:
lsblk

# To check for mounts and unmount
mount | grep /dev/sdx
sudo umount /dev/sdX*

# To clear device
sudo wipefs --all /dev/sdX
sudo dd if=/dev/zero of=/dev/sdX bs=1M count=10

# To flash device
sudo dd if=~/Downloads/debian-12.11.0-amd64-netinst.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

## Flashing sd card with nixos
```bash
# Build image (with special uboot)
nix build .#nixosConfigurations.orange-pi.config.system.build.sdImage

# Flash result to sd card /dev/sdX
zstdcat result/sd-image/nixos-image-sd*-aarch64-linux.img.zst | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync

# Confirm uboot file bin exists:
sudo dd if=/dev/sdX bs=1024 skip=8 count=1 | hexdump -C
## 00000000  XX XX XX XX 65 47 4f 4e  2e 42 54 30 XX XX XX XX  |....eGON.BT0....|
```

## PCI
```bash
# List all pci devices
lspci

# Check kernel logs for iommu support
dmesg | grep -e DMAR -e IOMMU
```

## Memory
```bash
# To view memory
free -h
```
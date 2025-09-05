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
sudo dd if=~/Downloads/debian-live-13.0.0-amd64-standard.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

# PCI
```bash
# List all pci devices
lspci

# Check kernel logs for iommu support
dmesg | grep -e DMAR -e IOMMU
```

# Memory
```bash
# To view memory
free -h
```
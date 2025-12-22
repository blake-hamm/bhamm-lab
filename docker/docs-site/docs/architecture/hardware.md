# Hardware

## Overview
This page provides a view of the lab's physical infrastructure. It covers the hardware inventory and future expansion plans.

## Hardware Inventory

### Servers

| Name     | Model                          | CPU                          | RAM       | Storage                                      | Features                               | Role                           |
|----------|--------------------------------|------------------------------|-----------|----------------------------------------------|----------------------------------------|--------------------------------|
| Method   | Supermicro H12SSL-i            | AMD EPYC 7502    | 128 GB ECC     | 1TB NVME (boot and vm storage), 1 TB NVME (ceph db/wal), 1TB SSD (ceph osd), 3.84 TB SSD (ceph osd), 2x2TB and 1TB SSD (TrueNas pcie passthrough) | Dual 10 GB NIC SFP+, ipmi, AMD Radeon AI Pro R9700 (Talos llama.cpp VM), Intel Arc A310e (Talos immich/jellyfin VM), SATA pcie | Proxmox and ceph |
| Indy     | Supermicro D-2146NT            | Intel Xeon D-2146NT 8-Core   | 128 GB ECC| 1TB NVME (boot and vm storage), 1 TB NVME (ceph db/wal), 1TB SSD (ceph osd), 3.84 TB SSD (ceph osd) | 2x10GB NIC SFP+, 2x10GB NIC, 2x1GB NIC, ipmi | Proxmox and ceph |
| Stale    | X10SDV-4C-TLN4F                | Intel Xeon CPU D-1518 8-Core | 64 GB ECC     | 1TB NVME (boot and vm storage), 1 TB NVME (ceph db/wal), 1TB SSD (ceph osd), 3.84 TB SSD (ceph osd) | 2x10GB NIC, 2x1GB NIC, ipmi           | Proxmox and ceph               |
| Nose     | Framework Mainboard            | AMD Ryzen AI MAX+ 395        | 128 GB (120 dedicated vram)     | 500GB NVME (boot drive), 1 TB NVME (model local path storage)           | 5GB NIC, Thunderbolt | Talos bare metal |
| Tail     | Framework Mainboard            | AMD Ryzen AI MAX+ 395        | 128 GB (120 dedicated vram)     | 500GB NVME (boot drive), 1 TB NVME (model local path storage)           | 5GB NIC, Thunderbolt | Talos bare metal |

### Networking Equipment

| Name         | Model           | Specifications                                      | Role                        |
|--------------|-----------------|-----------------------------------------------------|-----------------------------|
| PoE Switch   | SG3218XP-M2     | Omada 16-Port 2.5GBASE-T and 2-Port 10GE SFP+ L2+ Managed Switch with 8-Port PoE+ | PoE and core network switch |
| Server Switch  | TL-SX3008F      | JetStream 8-Port 10G SFP+ L2+ Managed Switch        | Ceph and core server switch |
| Access Point       | EAP650          | WiFi 6 support                                      | WiFi network                |

### Peripheral Devices
- **UPS:** CyberPower OR500LCDRM1U Smart App LCD UPS
- **PiKVM:** KVM for managing physical devices

## Future Plans
- **Replace Antsle:** The antsle server is the weakest link in my setup. At some point, I'd like to replace it with something that has more PCIe expandability. Then, I would move my Antsle server to my parents for an offsite backup and site-to-site VPN.

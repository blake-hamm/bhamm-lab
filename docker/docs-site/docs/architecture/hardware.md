# Hardware

## Overview
This page provides a view of the lab's physical infrastructure. It covers the hardware inventory and future expansion plans.

## Hardware Inventory

### Servers

| Name     | Model                          | CPU                          | RAM       | Storage                                      | Features                               | Role                           |
|----------|--------------------------------|------------------------------|-----------|----------------------------------------------|----------------------------------------|--------------------------------|
| Method   | Supermicro H12SSL-i            | AMD EPYC 7502    | 128 GB     | 250 GB SSD (boot), 2x4 TB NVME, 2x2 TB NVME, 1 TB NVME (ceph) | Dual 10 GB NIC SFP+, AMD Radeon AI Pro R9700 | Proxmox, ceph, AMD GPU VM |
| Indy     | Supermicro D-2146NT            | Intel Xeon D-2146NT 8-Core   | 128 GB ECC| 250 GB SSD (boot), 1 TB NVME (ceph), 2x1TB SSD (zfs) | 2x10GB NIC SFP+, 2x10GB NIC, 2x1GB NIC, ipmi, Intel Arc A310 | Proxmox, ceph and Arc GPU VM |
| Stale    | X10SDV-4C-TLN4F                | Intel Xeon CPU D-1518 8-Core | 64 GB     | 120 GB SSD (boot), 1 TB NVME (ceph), 2x1TB SSD (zfs) | 2x10GB NIC, 2x1GB NIC, ipmi           | Proxmox and ceph               |
| Nose     | Framework Laptop 13            | AMD Ryzen AI MAX+ 395        | 32 GB     | 1 TB NVME (boot), 1 TB NVME (ceph)           | 2x10GB NIC, 2x1GB NIC, ipmi, AMD Strix Halo GPU | Proxmox, ceph and Strix Halo GPU VM |
| Tail     | Framework Laptop 13            | AMD Ryzen AI MAX+ 395        | 32 GB     | 1 TB NVME (boot), 1 TB NVME (ceph)           | 2x10GB NIC, 2x1GB NIC, ipmi, AMD Strix Halo GPU | Proxmox, ceph and Strix Halo GPU VM |

### Networking Equipment

| Name         | Model           | Specifications                                      | Role                        |
|--------------|-----------------|-----------------------------------------------------|-----------------------------|
| PoE Switch   | SG3218XP-M2     | Omada 16-Port 2.5GBASE-T and 2-Port 10GE SFP+ L2+ Managed Switch with 8-Port PoE+ | PoE and core network switch |
| Server Switch  | TL-SX3008F      | JetStream 8-Port 10G SFP+ L2+ Managed Switch        | Ceph and core server switch |
| Access Point       | EAP650          | WiFi 6 support                                      | WiFi network                |

### Peripheral Devices
- **UPS:** CyberPower OR500LCDRM1U Smart App LCD UPS
- **PiKVM:** KVM for managing physical devices

## Future plans
- **Replace Antsle:** The antsle server is the weakest link in my setup. At some point, I'd like to replace it with something that has more pcie expandability. Then, I would move my Antsle server to my parents for an offsite backup and site-to-site vpn.

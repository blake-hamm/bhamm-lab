# Hardware Infrastructure

## Overview
This page provides an architectural view of the lab’s physical infrastructure. It covers the hardware inventory, physical organization, connectivity, and future expansion plans.

## Hardware Inventory

### Servers

- **Aorus:**
  - **Name:** aorus
  - **Model:** B550 AORUS ELITE AX V2
  - **CPU:** AMD Ryzen 7 3700X 16-Core
  - **RAM:** 32 GB
  - **Storage:** 250 GB SSD (boot), 2x2 TB SSD, 1 TB SSD, 1 TB NVME (ceph)
  - **Features:** Dual 10 GB NIC SFP+
  - **Role:** Proxmox, ceph and Snapraid/mergerfs nfs host
- **Antsle:**
  - **Name:** antsle
  - **Model:** Supermicro X10SDV-4C-TLN4F
  - **CPU:** Intel Xeon CPU D-1518 8-Core
  - **RAM:** 64 GB
  - **Storage:** 120 GB SSD (boot), 1 TB NVME (ceph)
  - **Features:** 2x10GB NIC, 2x1GB NIC, ipmi
  - **Role:** Proxmox and ceph
- **Supermicro:**
  - **Name:** supermicro
  - **Model:** Supermicro SYS-5019D-FN8TP
  - **CPU:** Intel Xeon processor D-2146NT 8-Core
  - **RAM:** 128 GB ECC
  - **Storage:** 250 GB SSD (boot), 1 TB NVME (ceph)
  - **Features:** 2x10GB NIC SFP+, 2x10GB NIC, 2x1GB NIC, ipmi
  - **Role:** Proxmox and ceph

### Networking Equipment

- **Opnsense:**
  - **Device:** opnsense
  - **Model:** Protectli V1410
  - **Features:** Intel N5105 Quad Core CPU, 4 Intel I226-V 2.5GB NIC, 8 GB Ram
  - **Role:** Bare metal opnsense firewall
- **TP Link PoE Switch:**
  - **Device:** poe_switch
  - **Model:** SG3218XP-M2
  - **Specs:** Omada 16-Port 2.5GBASE-T and 2-Port 10GE SFP+ L2+ Managed Switch with 8-Port PoE+
  - **Role:** PoE and core network switch
- **TP Link 10gb Switch:**
  - **Device:** 10gb_switch
  - **Model:** TL-SX3008F
  - **Specs:** JetStream 8-Port 10G SFP+ L2+ Managed Switch
  - **Role:** Ceph and core server switch
- **TP Link AP:**
  - **Device:** eap650
  - **Model:** EAP650
  - **Specs:** WiFi 6 support
  - **Role:** WiFi network

### Storage Systems

- **Ceph:**
  - **System:** Ceph Cluster
  - **Configuration:** 3 OSD nodes (aorus, antsle, supermicro) with 3TB capacity
  - **Role:** Distributed, fast storage for virtualization and container workloads
- **NFS:**
  - **System:** NFS host on Aorus node
  - **Configuration:** Snapraid + mergerfs with 3 TB (redundant 2 TB)
  - **Role:** Slower, file storage

### Peripheral Devices
- **UPS:** CyberPower OR500LCDRM1U Smart App LCD UPS
- **PiKVM:** KVM for managing physical devices

## Physical Layout & Diagrams

- **Rack Diagrams:**
  Illustrate the arrangement of servers and networking equipment within racks.
- **Floor Plans:**
  Data center or lab room layouts showing rack locations and spatial relationships.
- **Connectivity Schematics:**
  Diagrams that detail cabling routes, patch panel setups, and physical network topology.

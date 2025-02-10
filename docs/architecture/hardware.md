# Hardware Infrastructure

## Overview
This page provides an architectural view of the lab’s physical infrastructure. It covers the hardware inventory, physical organization, connectivity, and future expansion plans.

## Hardware Inventory
A catalog of the physical assets that form the foundation of this lab.

### Servers
Catalog of servers including bare-metal hosts, rack-mounted units, and blade systems.
- **Aorus:**
  - **Name:** aorus
  - **Model:** Aorus B650
  - **Specs:**
  - **Role:** Proxmox, ceph and Snapraid/mergerfs nfs host
- **Antsle:**
  - **Name:** antsle
  - **Model:**
  - **Specs:**
  - **Role:** Proxmox and ceph
- **Sys:**
  - **Name:** sys
  - **Model:** Supermicro
  - **Specs:**
  - **Role:** Proxmox and ceph

### Networking Equipment
Devices that manage and direct network traffic, including switches, routers, and firewalls.
- **Opnsense:**
  - **Device:** opnsense
  - **Model:** Cisco Catalyst 9300
  - **Specs:** 48 ports, 10GbE uplinks
  - **Role:** Bare metal opnsense firewall
- **TP Link PoE Switch:**
  - **Device:** poe_switch
  - **Model:**
  - **Specs:**
  - **Role:** PoE and core network switch
- **TP Link 10gb Switch:**
  - **Device:** 10gb_switch
  - **Model:**
  - **Specs:**
  - **Role:** Ceph and core server switch
- **TP Link AP:**
  - **Device:** ap
  - **Model:**
  - **Specs:**
  - **Role:** WiFi network

### Storage Systems
- **Ceph:**
  - **System:** Ceph Cluster
  - **Configuration:** 3 OSD nodes, 100TB capacity
  - **Role:** Distributed, fast storage for virtualization and container workloads
- **NFS:**
  - **System:** NFS host on aorus node
  - **Configuration:** Snapraid + mergerfs with 10 usable gb
  - **Role:** Slower, file storage

### Peripheral Devices
- **UPS:** Uninterruptible Power Supplies (UPS)
- **PiKVM:** KVM for managing physical devices

## Physical Layout & Diagrams
Visual representations that provide context on the placement and interconnection of hardware.

- **Rack Diagrams:**
  Illustrate the arrangement of servers and networking equipment within racks.
- **Floor Plans:**
  Data center or lab room layouts showing rack locations and spatial relationships.
- **Connectivity Schematics:**
  Diagrams that detail cabling routes, patch panel setups, and physical network topology.

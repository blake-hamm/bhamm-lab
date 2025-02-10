# Hardware Infrastructure

## Overview
This page provides an architectural view of the lab’s physical infrastructure. It covers the hardware inventory, physical organization, connectivity, and future expansion plans.

## Hardware Inventory
A catalog of the physical assets that form the foundation of the lab. This inventory is divided into several categories:

### Servers
- **Description:**
  Catalog of servers including bare-metal hosts, rack-mounted units, and blade systems.
- **Details:**
  - **Model & Make:** Specific model information, e.g., Dell PowerEdge, HP ProLiant
  - **Specifications:** CPU type, number of cores, RAM capacity, storage type (SSD/HDD)
  - **Role:** Function within the lab (e.g., virtualization host for Proxmox, CI/CD runner)
- **Example:**
  - **Name:** Lab-Server-01
    **Model:** Dell PowerEdge R740
    **Specs:** Dual Intel Xeon Silver, 256GB RAM, 4 x 1TB SSD
    **Role:** Primary virtualization host

### Networking Equipment
- **Description:**
  Devices that manage and direct network traffic, including switches, routers, and firewalls.
- **Details:**
  - **Device Type:** Core switches, access points, etc.
  - **Specifications:** Port counts, supported speeds (10GbE, 1GbE), connectivity details
  - **Placement:** Role within the network topology (e.g., aggregation, edge routing)
- **Example:**
  - **Device:** Core Switch
    **Model:** Cisco Catalyst 9300
    **Specs:** 48 ports, 10GbE uplinks
    **Role:** Aggregation point for lab network traffic

### Storage Systems
- **Description:**
  The systems responsible for data storage and management.
- **Details:**
  - **Type:** NAS, SAN, or distributed storage (e.g., Ceph)
  - **Capacity & Configuration:** Total storage capacity, RAID/replication setups
  - **Purpose:** Serving as primary storage for VMs, containers, or backups
- **Example:**
  - **System:** Ceph Cluster
    **Configuration:** 10 OSD nodes, 100TB capacity
    **Role:** Distributed storage for virtualization and container workloads

### Peripheral Devices
- **Description:**
  Additional hardware components supporting the core infrastructure.
- **Examples:**
  - Uninterruptible Power Supplies (UPS)
  - Environmental monitoring sensors
  - Patch panels and cable management systems

## Physical Layout & Diagrams
Visual representations that provide context on the placement and interconnection of hardware.

- **Rack Diagrams:**
  Illustrate the arrangement of servers and networking equipment within racks.
- **Floor Plans:**
  Data center or lab room layouts showing rack locations and spatial relationships.
- **Connectivity Schematics:**
  Diagrams that detail cabling routes, patch panel setups, and physical network topology.

*Note: Insert images or links to external diagram files as applicable.*

## Connectivity & Cabling
Details regarding the physical interconnections among hardware components:

- **Cabling Standards:**
  Outline the use of Ethernet (e.g., Cat6a) or fiber optics for device interconnectivity.
- **Patch Panels & Cable Management:**
  Describe the routing of cables and organizational strategies to maintain clarity and reduce clutter.
- **Redundancy:**
  Summarize any redundant cabling paths or failover connections to enhance reliability.

# Network Architecture

## Overview
This document outlines the network architecture of the lab, detailing both the physical and logical components that ensure robust, secure, and scalable connectivity. It covers the topology, key network devices, VLAN segmentation, IP addressing, cabling infrastructure, and security policies.

## Topology & Diagrams
- **Physical Topology:**
  Describes how network devices are physically connected, including the layout of core, distribution, and access layers.

- **Logical Topology:**
  Explains how network traffic is segmented via VLANs and subnets, including routing and segmentation strategies.

- **Diagrams & Visuals:**
  Include high-level network diagrams, connectivity schematics, and detailed layout images.

## Network Components

### Firewall and Security Appliances
- **Firewalls & IDS/IPS:**
  Dedicated security devices that monitor, filter, and protect network traffic.
  - **Example:**
    - **Device:** Next-Generation Firewall
      **Role:** Enforce security policies and detect potential intrusions

## VLANs & IP Addressing
- **VLAN Segmentation:**
  - Different VLANs are used to isolate traffic by function, tenant, or security level.
  - Document the VLAN IDs, associated subnets, and their intended purposes.

- **IP Addressing Scheme:**
  - Outline the IP ranges allocated to each subnet.
  - Define the roles of key IP addresses such as gateways, DNS, and DHCP servers.
  - *Example:*
    - **VLAN 10 (Management):** 192.168.10.0/24
    - **VLAN 20 (Production):** 192.168.20.0/24

## Network Security & Policies
- **Security Measures:**
  - Network segmentation through VLANs and dedicated subnets.
  - Firewall rules and access control lists (ACLs) to protect sensitive areas.

- **Access Controls:**
  - Policies for managing administrative access to network devices.

- **Monitoring & Logging:**
  - Overview of tools and practices used for monitoring network traffic and logging events to detect anomalies or potential security breaches.

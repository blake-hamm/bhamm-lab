# Storage Architecture

## Overview
This document details the storage architecture employed in the lab. It covers the two primary storage solutions in use—Ceph and MergerFS combined with SnapRAID—as well as a retrospective look at ZFS, which was previously evaluated but ultimately found less suitable for a heterogeneous hardware environment. Additionally, the document outlines the use of Google Cloud Platform (GCP) storage for offsite backups to ensure data resilience and disaster recovery.

## Ceph: Distributed Storage Solution
- **Purpose & Role:**
  Ceph is implemented as a scalable, distributed storage system that provides high availability and fault tolerance for both virtual machines and containerized workloads.

- **Key Features:**
  - **Scalability:** Easily expands by adding more OSD (Object Storage Device) nodes.
  - **Redundancy:** Replicates data across multiple nodes to ensure data integrity and high availability.
  - **Flexibility:** Supports block, object, and file storage interfaces, making it versatile for various application needs.

- **Usage in the Lab:**
  - Primary storage for hosting VM images, container data, and application-level datasets.
  - Integrated into the virtualization and orchestration layers for dynamic resource allocation.

## MergerFS + SnapRAID: Flexible and Resilient Storage for Archival and Backup
- **Purpose & Role:**
  This solution is used for scenarios where flexible storage pooling and data redundancy are required, particularly for archival data and less performance-critical workloads.

- **Key Components:**
  - **MergerFS:**
    - **Function:** Pools multiple drives into a single virtual filesystem, allowing for efficient use of disk space.
    - **Advantage:** Simplifies management by abstracting the underlying physical drives.
  - **SnapRAID:**
    - **Function:** Provides RAID-like data protection by using parity information for error detection and recovery.
    - **Advantage:** Offers flexibility in drive sizes and types, making it ideal for a diverse hardware environment.

- **Usage in the Lab:**
  - Ideal for offloading less frequently accessed data or archival backups.
  - Serves as a complementary solution to Ceph, particularly where performance is less critical than storage capacity and cost efficiency.

## ZFS: Lessons Learned
- **Background:**
  ZFS was evaluated and deployed in earlier phases of the lab’s evolution as a unified file system and volume manager.

- **Challenges & Limitations:**
  - **Hardware Diversity:** ZFS exhibited challenges when used with heterogeneous storage hardware, leading to compatibility and performance issues.
  - **Complexity:** Managing ZFS on a mix of hardware types increased administrative overhead.

- **Outcome:**
  While ZFS provides robust features such as data integrity verification and snapshot capabilities, it was ultimately set aside in favor of more flexible solutions (Ceph and MergerFS+SnapRAID) that better accommodate a varied hardware landscape.

## Offsite Backups with GCP Storage
- **Purpose & Role:**
  To complement the on-premises storage solutions, GCP storage is used for offsite backups. This integration ensures that critical data is securely backed up and accessible in the event of a local disaster.

- **Key Features:**
  - **Data Durability:** High redundancy and geographic distribution provided by GCP.
  - **Scalability:** On-demand storage capacity to handle varying backup loads.
  - **Integration:** Automated backup routines and synchronization with local storage solutions to ensure minimal data loss.

- **Usage in the Lab:**
  - Critical datasets and snapshots from Ceph and MergerFS+SnapRAID systems are periodically backed up to GCP.
  - Provides a robust disaster recovery solution by enabling rapid restoration of data from the cloud in case of local failures.

## Summary
The storage architecture in the lab leverages multiple solutions to meet varying requirements:
- **Ceph** delivers a high-performance, scalable, and fault-tolerant system for mission-critical workloads.
- **MergerFS + SnapRAID** provides an adaptable and cost-effective solution for archival and backup needs.
- **ZFS** offered valuable lessons, reinforcing the need for flexibility when managing diverse hardware.
- **GCP Storage** enhances overall data protection by offering offsite backup capabilities, ensuring resilience in the face of disasters.

This multi-tiered approach ensures that the lab’s storage infrastructure is robust, scalable, and resilient, catering to both high-performance needs and long-term data protection.

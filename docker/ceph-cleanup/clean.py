#!/usr/bin/env python3
"""
Ceph Kubernetes Resource Manager - Identifies and cleans orphaned Ceph resources
that were previously used by Kubernetes but are no longer referenced.
"""

import json
import logging
import os
import re
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timedelta
from typing import List, Dict, Set, Optional

import kubernetes.client
from kubernetes.client.rest import ApiException
from kubernetes.config import load_kube_config

# Set up logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(f"ceph_cleanup_{datetime.now().strftime('%Y%m%d')}.log"),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

# Configuration
CEPH_POOL = "osd"
CEPH_CONF = "./result/ceph.conf"
CEPH_KEYRING="./result/ceph.client.k8s-cleaner.keyring"
CEPH_USER="k8s-cleaner"
GRACE_PERIOD_DAYS = 7
DRY_RUN = True



def run_ceph_command(command: List[str], json_output: bool = True, rbd: bool = False) -> Optional[dict]:
    """Run a Ceph command with proper credentials and return its output."""
    try:
        # Add common arguments for authentication
        if rbd:
            cmd = ["rbd", "--conf", CEPH_CONF, "--keyring", CEPH_KEYRING, "--name", f"client.{CEPH_USER}"]
        else:
            cmd = ["ceph", "--conf", CEPH_CONF, "--keyring", CEPH_KEYRING, "--name", f"client.{CEPH_USER}"]

        # Add the specific command arguments
        cmd.extend(command)

        # Add JSON output format if requested
        if json_output:
            cmd.append("--format=json")

        logger.debug(f"Running command: {' '.join(cmd)}")
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)

        if json_output:
            return json.loads(result.stdout)
        return result.stdout
    except subprocess.CalledProcessError as e:
        logger.error(f"Command failed: {' '.join(cmd)}")
        logger.error(f"Error: {e.stderr}")
        return None
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse JSON output: {e}")
        logger.error(f"Output was: {result.stdout}")
        return None


def get_k8s_volumes(rbd_pool: str, cephfs_pool: str) -> Dict[str, Set[str]]:
    """Get all volume IDs currently used by Kubernetes PVs for both RBD and CephFS."""
    try:
        load_kube_config()
        api = kubernetes.client.CoreV1Api()
        pvs = api.list_persistent_volume()

        rbd_volumes = set()
        cephfs_volumes = set()

        for pv in pvs.items:
            if pv.spec.csi:
                if 'rbd.csi.ceph.com' in pv.spec.csi.driver:
                    volume_attributes = pv.spec.csi.volume_attributes
                    if volume_attributes.get("pool") == rbd_pool:
                        rbd_volumes.add(volume_attributes['imageName'])
                elif 'cephfs.csi.ceph.com' in pv.spec.csi.driver and cephfs_pool:
                    volume_attributes = pv.spec.csi.volume_attributes
                    volume_id = volume_attributes.get('subvolumeName')
                    cephfs_volumes.add(volume_id)

        logger.info(f"Found {len(rbd_volumes)} active RBD PVs and {len(cephfs_volumes)} active CephFS PVs in Kubernetes")
        return {"rbd": rbd_volumes, "cephfs": cephfs_volumes}
    except ApiException as e:
        logger.error(f"Error fetching Kubernetes volumes: {e}")
        return {"rbd": set(), "cephfs": set()}


def get_pool_usage() -> Dict:
    """Get usage statistics for the pool."""
    result = run_ceph_command(["df", "detail"])
    if result is None:
        logger.error("Failed to get cluster usage information")
        return {}

    # Find our pool in the pools list
    pool_stats = {}
    for pool in result.get('pools', []):
        if pool.get('name') == CEPH_POOL:
            pool_stats = pool.get('stats', {})
            break

    if pool_stats:
        bytes_used = pool_stats.get('bytes_used', 0)
        max_avail = pool_stats.get('max_avail', 0)
        logger.info(f"Pool {CEPH_POOL} usage: {bytes_used/(1024**3):.2f} GB used, {max_avail/(1024**3):.2f} GB available")

    return pool_stats


def get_ceph_images(pool: str, rbd: bool = True) -> List[str]:
    """Get all RBD images or CephFS volumes in the specified Ceph pool."""
    if rbd:
        result = run_ceph_command(["ls", "-p", pool], rbd=True)
        if result is None:
            logger.error(f"Failed to get RBD images from pool {pool}")
            return []
        logger.info(f"Found {len(result)} total RBD images in Ceph pool {pool}")
        return result
    else:
        # For CephFS, get the subvolumes
        result = run_ceph_command(["fs", "subvolume", "ls", pool, "--group_name", "csi"], rbd=False)
        if result is None:
            logger.error(f"Failed to get CephFS volumes from pool {pool}")
            return []
        logger.info(f"Found {len(result)} total CephFS volumes in filesystem {pool}")
        return [vol['name'] for vol in result]


def move_to_trash(image: str, pool: str, rbd: bool = True) -> bool:
    """Move a Ceph RBD image to trash or remove a CephFS volume."""
    if DRY_RUN:
        if rbd:
            logger.info(f"[DRY RUN] Would move RBD image {image} to trash in pool {pool}")
        else:
            logger.info(f"[DRY RUN] Would remove CephFS volume {image} from pool {pool}")
        return True

    if rbd:
        result = run_ceph_command(["trash", "mv", "-p", pool, image], json_output=False, rbd=True)
        if result is not None:
            logger.info(f"Successfully moved RBD image {image} to trash")
            return True
        else:
            logger.error(f"Failed to move RBD image {image} to trash")
            return False
    else:
        # For CephFS, remove the subvolume
        result = run_ceph_command(["fs", "subvolume", "rm", pool, image, "--group_name", "csi"], json_output=False, rbd=False)
        if result is not None:
            logger.info(f"Successfully removed CephFS volume {image}")
            return True
        else:
            logger.error(f"Failed to remove CephFS volume {image}")
            return False


def get_trash_images() -> List[Dict]:
    """Get details of all images in the Ceph RBD trash."""
    result = run_ceph_command(["trash", "ls", "-p", CEPH_POOL], rbd=True)
    if result is None:
        logger.error(f"Failed to get trash images from pool {CEPH_POOL}")
        return []

    logger.info(f"Found {len(result)} images in Ceph trash")
    return result


def purge_from_trash(trash_id: str) -> bool:
    """Remove a Ceph RBD image from trash."""
    if DRY_RUN:
        logger.info(f"[DRY RUN] Would remove trash image {trash_id}")
        return True

    try:
        logger.info(f"Removing trash image {trash_id}")
        trash_rm_cmd = ["trash", "rm", "-p", CEPH_POOL, trash_id]

        trash_result = run_ceph_command(trash_rm_cmd, json_output=False, rbd=True)
        if trash_result is not None:
            logger.info(f"Successfully removed trash image {trash_id}")
            return True
        else:
            logger.error(f"Failed to remove trash image {trash_id}")
            return False

    except Exception as e:
        logger.error(f"Error in trash cleanup for {trash_id}: {e}")
        return False



def main(rbd_pool: str, cephfs_pool: str):
    """Main function to manage Ceph resources for both RBD and CephFS."""
    logger.info("=== Ceph Maintenance Script Started ===")

    # Get initial pool usage
    usage_before = get_pool_usage()

    # Get active resources
    k8s_volumes = get_k8s_volumes(rbd_pool, cephfs_pool)

    # Get all Ceph images and volumes
    ceph_images = get_ceph_images(rbd_pool, rbd=True)
    cephfs_volumes = get_ceph_images(cephfs_pool, rbd=False) if cephfs_pool else []

    # Find orphaned RBD images
    orphaned_rbd_images = []
    for image in ceph_images:
        if image not in k8s_volumes["rbd"]:
            logger.info(f"Found orphaned RBD image: {image}")
            orphaned_rbd_images.append(image)
        else:
            logger.debug(f"Found active RBD image: {image}")

    # Move orphaned RBD images to trash
    for image in orphaned_rbd_images:
        move_to_trash(image, rbd_pool, rbd=True)

    # Find orphaned CephFS volumes
    orphaned_cephfs_volumes = []
    for volume in cephfs_volumes:
        if volume not in k8s_volumes["cephfs"]:
            logger.info(f"Found orphaned CephFS volume: {volume}")
            orphaned_cephfs_volumes.append(volume)
        else:
            logger.debug(f"Found active CephFS volume: {volume}")

    # Remove orphaned CephFS volumes
    for volume in orphaned_cephfs_volumes:
        move_to_trash(volume, cephfs_pool, rbd=False)

    # Process trash (RBD only)
    trash_images = get_trash_images()
    cutoff_time = int(time.time()) - (GRACE_PERIOD_DAYS * 86400)

    for trash_item in trash_images:
        # Extract the deferment end time
        # Note: Format may vary based on Ceph version
        deferment_end = trash_item.get('deferment_end_time', 0)
        if isinstance(deferment_end, str) and deferment_end.isdigit():
            deferment_end = int(deferment_end)

        if deferment_end < cutoff_time:
            logger.info(f"Trash image {trash_item['id']} is older than grace period ({GRACE_PERIOD_DAYS} days)")
            purge_from_trash(trash_item['id'])
        else:
            days_left = int((deferment_end - cutoff_time) / 86400)
            logger.info(f"Keeping {trash_item['id']} in trash ({days_left} days left in grace period)")

    # Get final pool usage
    usage_after = get_pool_usage()

    # Report on space saved
    if usage_before and usage_after:
        bytes_before = usage_before.get('bytes_used', 0)
        bytes_after = usage_after.get('bytes_used', 0)
        space_saved = bytes_before - bytes_after
        if space_saved > 0:
            logger.info(f"Cleanup freed approximately {space_saved/(1024**3):.2f} GB of storage")

    logger.info("=== Ceph Maintenance Script Completed ===")


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description='Ceph Kubernetes Resource Manager')
    parser.add_argument('--rbd-pool', required=True, help='Ceph RBD pool name')
    parser.add_argument('--cephfs-pool', help='CephFS pool/filesystem name (optional)')
    parser.add_argument('--dry-run', action='store_true', help='Dry run mode - no actual changes')

    args = parser.parse_args()

    # Update configuration
    DRY_RUN = args.dry_run

    # Run main function
    main(args.rbd_pool, args.cephfs_pool)

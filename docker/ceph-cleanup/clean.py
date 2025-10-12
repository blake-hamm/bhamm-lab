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
DRY_RUN = False



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


def get_k8s_volumes() -> Set[str]:
    """Get all volume IDs currently used by Kubernetes PVs."""
    try:
        load_kube_config()
        api = kubernetes.client.CoreV1Api()
        pvs = api.list_persistent_volume()

        volume_ids = set()
        for pv in pvs.items:
            if pv.spec.csi and 'rbd.csi.ceph.com' in pv.spec.csi.driver:
                # Extract just the image name from the volume handle
                volume_attributes = pv.spec.csi.volume_attributes
                if volume_attributes["pool"] == CEPH_POOL:
                    volume_ids.add(volume_attributes['imageName'])
        logger.info(f"Found {len(volume_ids)} active PVs in Kubernetes")
        return volume_ids
    except ApiException as e:
        logger.error(f"Error fetching Kubernetes volumes: {e}")
        return set()


def get_k8s_snapshots() -> Set[str]:
    """Get all snapshot IDs currently used by Kubernetes VolumeSnapshots."""
    try:
        load_kube_config()
        api = kubernetes.client.CustomObjectsApi()

        # Get VolumeSnapshotContents
        snapshot_contents = api.list_cluster_custom_object(
            group="snapshot.storage.k8s.io",
            version="v1",
            plural="volumesnapshotcontents"
        )

        snapshot_ids = set()
        for content in snapshot_contents['items']:
            if 'snapshotHandle' in (snapshot_status := content['status']):
                snapshot_handle = snapshot_status['snapshotHandle']
                m = re.search(r'([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$', snapshot_handle)
                if not m:
                    raise ValueError("No trailing UUID found in snapshot_handle")
                uuid = m.group(1)
                snap_id = f'csi-snap-{uuid}'
                snapshot_ids.add(snap_id)

        logger.info(f"Found {len(snapshot_ids)} active snapshots in Kubernetes")
        return snapshot_ids
    except ApiException as e:
        logger.error(f"Error fetching Kubernetes snapshots: {e}")
        return set()


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


def get_ceph_images() -> List[str]:
    """Get all RBD images in the specified Ceph pool."""
    result = run_ceph_command(["ls", "-p", CEPH_POOL], rbd=True)
    if result is None:
        logger.error(f"Failed to get RBD images from pool {CEPH_POOL}")
        return []

    logger.info(f"Found {len(result)} total RBD images in Ceph pool {CEPH_POOL}")
    return result


def check_and_cleanup_snapshots(image: str, k8s_snapshots: Set[str]):
    """Check for orphaned snapshots within an image and clean them up."""
    # Get all snapshots for this image
    result = run_ceph_command(["snap", "ls", f"{CEPH_POOL}/{image}"], rbd=True)
    if result is None:
        logger.error(f"Failed to get snapshots for image {image}")
        return

    for snap in result:
        snap_name = snap['name']
        # Check if this snapshot is referenced by k8s
        is_referenced = any(snap_name in k_snap for k_snap in k8s_snapshots)

        if not is_referenced:
            logger.info(f"Found orphaned snapshot: {image}@{snap_name}")

            if not DRY_RUN:
                # Unprotect snapshot if protected
                if 'snap' in image:
                  snap_cmd = ["snap", "unprotect", f"{CEPH_POOL}/{image}@{snap_name}"]
                  run_ceph_command(snap_cmd, json_output=False, rbd=True)

                # Remove the snapshot
                snap_cmd = ["snap", "rm", f"{CEPH_POOL}/{image}@{snap_name}"]
                if run_ceph_command(snap_cmd, json_output=False, rbd=True) is not None:
                    logger.info(f"Removed orphaned snapshot: {image}@{snap_name}")
                else:
                    logger.error(f"Failed to remove snapshot: {image}@{snap_name}")


def move_to_trash(image: str) -> bool:
    """Move a Ceph RBD image to trash."""
    if DRY_RUN:
        logger.info(f"[DRY RUN] Would move image {image} to trash")
        return True

    result = run_ceph_command(["trash", "mv", "-p", CEPH_POOL, image], json_output=False, rbd=True)
    if result is not None:
        logger.info(f"Successfully moved {image} to trash")
        return True
    else:
        logger.error(f"Failed to move {image} to trash")
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
    """Enhanced version that handles protected snapshots properly."""
    if DRY_RUN:
        logger.info(f"[DRY RUN] Would purge all snapshots and trash image {trash_id}")
        return True

    try:
        # Step 1: Get all snapshots for this trash image
        snap_list_cmd = ["snap", "ls", "-p", CEPH_POOL, "--image-id", trash_id, "--all"]
        snapshots = run_ceph_command(snap_list_cmd, rbd=True)

        if snapshots is None:
            logger.error(f"Failed to list snapshots for trash image {trash_id}")
            return False

        if not snapshots:
            logger.info(f"No snapshots found for trash image {trash_id}")
        else:
            logger.info(f"Found {len(snapshots)} snapshots for trash image {trash_id}")

            # Step 2: Unprotect all snapshots first
            for snap in snapshots:
                snap_name = snap['name']
                protected = snap.get('protected', False)

                if protected == 'yes' or protected is True:
                    logger.info(f"Unprotecting snapshot {snap_name}")
                    unprotect_cmd = ["snap", "unprotect", "-p", CEPH_POOL, "--image-id", trash_id, "--snap", snap_name]
                    run_ceph_command(unprotect_cmd, json_output=False, rbd=True)  # Don't fail if already unprotected

            # Step 3: Now purge all snapshots
            logger.info(f"Purging all snapshots for trash image {trash_id}")
            purge_cmd = ["snap", "purge", "-p", CEPH_POOL, "--image-id", trash_id]

            purge_result = run_ceph_command(purge_cmd, json_output=False, rbd=True)
            if purge_result is None:
                logger.error(f"Failed to purge snapshots for trash image {trash_id}")
                return False

            # Step 4: Verify snapshots are gone
            verification_cmd = ["snap", "ls", "-p", CEPH_POOL, "--image-id", trash_id]
            remaining_snaps = run_ceph_command(verification_cmd, rbd=True)

            if remaining_snaps and len(remaining_snaps) > 0:
                logger.error(f"Still found {len(remaining_snaps)} snapshots after purge - manual cleanup required")
                return False
            else:
                logger.info(f"Verified: All snapshots successfully removed")

        # Step 5: Remove the image from trash
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



def main():
    """Main function to manage Ceph resources."""
    logger.info("=== Ceph Maintenance Script Started ===")

    # Get initial pool usage
    usage_before = get_pool_usage()

    # Get active resources
    k8s_volumes = get_k8s_volumes()
    k8s_snapshots = get_k8s_snapshots()

    # Protect current snapshots
    for snap_id in k8s_snapshots:
      results = run_ceph_command(
        ["snap", "protect", f"{CEPH_POOL}/{snap_id}@{snap_id}"],
        json_output=False,
        rbd=True
      )

    # Get all Ceph images
    ceph_images = get_ceph_images()

    # Find orphaned images
    orphaned_images = []
    for image in ceph_images:
        if image not in k8s_volumes and image not in k8s_snapshots:
            logger.info(f"Found orphaned image: {image}")
            orphaned_images.append(image)
        else:
            # For active images, check for orphaned snapshots
            logger.debug(f"Found active image: {image}")
            check_and_cleanup_snapshots(image, k8s_snapshots)

    # Move orphaned images to trash
    for image in orphaned_images:
        move_to_trash(image)

    # Process trash
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
    main()

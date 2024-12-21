#!/bin/bash
# Prerequisites: scale down minio statefulsets replicas to 0

# Inputs
BASE_DIR="/mnt/storage/kubernetes"
RESTORE_DATE="2024-12-19"

# Get the source and destination directories
SOURCE_DIRS=$(find $BASE_DIR -maxdepth 1 -type d ! -newermt $RESTORE_DATE -name "*backups*" -printf '%f\n')
DEST_DIRS=$(find $BASE_DIR -maxdepth 1 -type d -newermt $RESTORE_DATE -name "*backups*" -printf '%f\n')

for source_dir in $SOURCE_DIRS; do
	# Parse out base filename
	base_name=$(echo "$source_dir" | sed -E 's/-[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$//')

	# Find match in destination
	for dest_dir_candidates in $DEST_DIRS; do
		if [[ $dest_dir_candidates == "$base_name"* ]]; then
			dest_dir=$dest_dir_candidates
		fi
	done
	source_dir_full="$BASE_DIR/$source_dir/data/backups"
	dest_dir_full="$BASE_DIR/$dest_dir/data/"
	printf "Going to copy contents of: \n$source_dir_full: \n$(ls $source_dir_full) \n to \n$dest_dir_full: \n$(ls $dest_dir_full) \n \n"

	# Copy content
	cp -r $source_dir_full $dest_dir_full
	printf "Copy complete. Content of $dest_dir_full: \n$(ls $dest_dir_full) \n \n"

	# Post actions: scale up minio statefulsets replicas to 4
done

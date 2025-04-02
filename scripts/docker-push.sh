#!/bin/bash
set -e # Exit immediately on error

# Simple Docker build/push script
# Required env vars:
# - DOCKER_URI (registry URL)
# - IMAGE_NAME
# - IMAGE_TAG
# - DOCKER_DIR (directory with Dockerfile)
# - DOCKER_USER
# - DOCKER_TOKEN

# Check required variables
[ -z "$DOCKER_URI" ] && {
	echo "ERROR: DOCKER_URI not set"
	exit 1
}
[ -z "$IMAGE_NAME" ] && {
	echo "ERROR: IMAGE_NAME not set"
	exit 1
}
[ -z "$IMAGE_TAG" ] && {
	echo "ERROR: IMAGE_TAG not set"
	exit 1
}
[ -z "$DOCKER_DIR" ] && {
	echo "ERROR: DOCKER_DIR not set"
	exit 1
}
[ -z "$DOCKER_USER" ] && {
	echo "ERROR: DOCKER_USER not set"
	exit 1
}
[ -z "$DOCKER_TOKEN" ] && {
	echo "ERROR: DOCKER_TOKEN not set"
	exit 1
}

FULL_IMAGE="${DOCKER_URI}/library/${IMAGE_NAME}:${IMAGE_TAG}"

echo "🔑 Logging into Docker registry..."
echo "$DOCKER_TOKEN" | docker login -u "$DOCKER_USER" --password-stdin "$DOCKER_URI"

echo "🛠  Building Docker image..."
docker build -t "$FULL_IMAGE" \
	-f "${DOCKER_DIR}/Dockerfile" \
	"$DOCKER_DIR"

echo "🚀 Pushing image to registry..."
docker push "$FULL_IMAGE"

echo "✅ Successfully pushed: $FULL_IMAGE"

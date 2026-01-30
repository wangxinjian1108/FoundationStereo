#!/bin/bash

# FoundationStereo Inference Script for Custom Image Pairs
# This script runs Docker container for FoundationStereo inference with custom image pairs
#
# Usage: bash run_inference_custom.sh <left_image> <right_image> [intrinsic_file] [output_dir]
#
# Example:
#   bash run_inference_custom.sh /path/to/left.png /path/to/right.png
#   bash run_inference_custom.sh /path/to/left.png /path/to/right.png /path/to/K.txt
#   bash run_inference_custom.sh /path/to/left.png /path/to/right.png /path/to/K.txt /path/to/output

set -e  # Exit on error

# ============================================================
# Configuration
# ============================================================

# Docker image name
IMAGE_NAME="xinjianwang/foundation_stereo:latest"

# Model checkpoint path
HOST_PRETRAINED_DIR="${PWD}/pretrained_models"

# Default intrinsic file (optional)
DEFAULT_INTRINSIC="${PWD}/assets/K.txt"

# Default output directory
DEFAULT_OUTPUT_DIR="${PWD}/output"

# GPU Configuration
GPU_ID=0

# ============================================================
# Parse command line arguments
# ============================================================

if [ $# -lt 2 ]; then
    echo "Usage: $0 <left_image> <right_image> [intrinsic_file] [output_dir]"
    echo ""
    echo "Arguments:"
    echo "  left_image    Path to the left image (required)"
    echo "  right_image   Path to the right image (required)"
    echo "  intrinsic_file Path to the intrinsic matrix file (optional, default: ${DEFAULT_INTRINSIC})"
    echo "  output_dir    Path to the output directory (optional, default: ${DEFAULT_OUTPUT_DIR})"
    echo ""
    echo "Example:"
    echo "  $0 /path/to/left.png /path/to/right.png"
    echo "  $0 /path/to/left.png /path/to/right.png /custom/K.txt"
    echo "  $0 /path/to/left.png /path/to/right.png /custom/K.txt /custom/output"
    exit 1
fi

LEFT_IMG="$1"
RIGHT_IMG="$2"
INTRINSIC_FILE="${3:-${DEFAULT_INTRINSIC}}"
HOST_OUTPUT_DIR="${4:-${DEFAULT_OUTPUT_DIR}}"

# ============================================================
# Validate inputs
# ============================================================

echo "=========================================="
echo "FoundationStereo Custom Inference"
echo "=========================================="
echo ""

# Check if Docker image exists
if ! docker image inspect "${IMAGE_NAME}" &> /dev/null; then
    echo "Error: Docker image '${IMAGE_NAME}' not found!"
    echo "Please build it first using: bash docker_test/build_image.sh"
    exit 1
fi
echo "Docker image found: ${IMAGE_NAME}"

# Check if left image exists
if [ ! -f "${LEFT_IMG}" ]; then
    echo "Error: Left image not found: ${LEFT_IMG}"
    exit 1
fi
echo "Left image: ${LEFT_IMG}"

# Check if right image exists
if [ ! -f "${RIGHT_IMG}" ]; then
    echo "Error: Right image not found: ${RIGHT_IMG}"
    exit 1
fi
echo "Right image: ${RIGHT_IMG}"

# Check if intrinsic file exists
if [ ! -f "${INTRINSIC_FILE}" ]; then
    echo "Warning: Intrinsic file not found: ${INTRINSIC_FILE}"
    echo "Will use default intrinsic inside container if available"
    INTRINSIC_FILE=""
else
    echo "Intrinsic file: ${INTRINSIC_FILE}"
fi

echo "Output directory: ${HOST_OUTPUT_DIR}"
echo ""

# ============================================================
# Prepare paths for Docker mounting
# ============================================================

# Get directory paths for mounting
LEFT_IMG_DIR=$(dirname "$(realpath "${LEFT_IMG}")")
LEFT_IMG_NAME=$(basename "${LEFT_IMG}")

RIGHT_IMG_DIR=$(dirname "$(realpath "${RIGHT_IMG}")")
RIGHT_IMG_NAME=$(basename "${RIGHT_IMG}")

# Create output directory
mkdir -p "${HOST_OUTPUT_DIR}"

# Determine mount points and paths
if [ "${LEFT_IMG_DIR}" = "${RIGHT_IMG_DIR}" ]; then
    # Both images in the same directory - mount once
    MOUNT_INPUT_DIR="${LEFT_IMG_DIR}"
    CONTAINER_LEFT_IMG="/app/input/${LEFT_IMG_NAME}"
    CONTAINER_RIGHT_IMG="/app/input/${RIGHT_IMG_NAME}"
else
    # Images in different directories - mount both
    MOUNT_INPUT_DIR="${LEFT_IMG_DIR}"
    MOUNT_INPUT_DIR_2="${RIGHT_IMG_DIR}"
    CONTAINER_LEFT_IMG="/app/input/${LEFT_IMG_NAME}"
    CONTAINER_RIGHT_IMG="/app/input2/${RIGHT_IMG_NAME}"
fi

# Handle intrinsic file mount
if [ -n "${INTRINSIC_FILE}" ]; then
    INTRINSIC_DIR=$(dirname "$(realpath "${INTRINSIC_FILE}")")
    INTRINSIC_NAME=$(basename "${INTRINSIC_FILE}")

    # Check if intrinsic file is in the same directory as input images
    if [ "${INTRINSIC_DIR}" = "${LEFT_IMG_DIR}" ]; then
        CONTAINER_INTRINSIC="/app/input/${INTRINSIC_NAME}"
    elif [ -n "${MOUNT_INPUT_DIR_2}" ] && [ "${INTRINSIC_DIR}" = "${RIGHT_IMG_DIR}" ]; then
        CONTAINER_INTRINSIC="/app/input2/${INTRINSIC_NAME}"
    else
        # Mount intrinsic file separately
        MOUNT_INTRINSIC_DIR="${INTRINSIC_DIR}"
        CONTAINER_INTRINSIC="/app/intrinsic/${INTRINSIC_NAME}"
    fi
else
    # Use default intrinsic from assets
    CONTAINER_INTRINSIC="/app/input_assets/K.txt"
fi

# ============================================================
# Detect model directory
# ============================================================

USE_HOST_MODEL=0
if [ -d "${HOST_PRETRAINED_DIR}" ]; then
    MODEL_DIR=$(find "${HOST_PRETRAINED_DIR}" -name "model_best_bp2.pth" -type f 2>/dev/null | head -1)
    if [ -n "$MODEL_DIR" ]; then
        MODEL_SUBDIR=$(dirname "$MODEL_DIR" | xargs basename)
        CKPT_DIR="/app/pretrained_models/${MODEL_SUBDIR}/model_best_bp2.pth"
        USE_HOST_MODEL=1
        echo "Found host model: ${MODEL_DIR}"
    fi
fi

if [ -z "${USE_HOST_MODEL}" ]; then
    CKPT_DIR="/app/pretrained_models/23-51-11/model_best_bp2.pth"
    echo "Using baked-in model: ${CKPT_DIR}"
fi

# ============================================================
# Build volume mounts
# ============================================================

VOLUME_MOUNTS="-v \"${MOUNT_INPUT_DIR}:/app/input:ro\""

if [ -n "${MOUNT_INPUT_DIR_2}" ]; then
    VOLUME_MOUNTS="${VOLUME_MOUNTS} -v \"${MOUNT_INPUT_DIR_2}:/app/input2:ro\""
fi

if [ -n "${MOUNT_INTRINSIC_DIR}" ]; then
    VOLUME_MOUNTS="${VOLUME_MOUNTS} -v \"${MOUNT_INTRINSIC_DIR}:/app/intrinsic:ro\""
fi

if [ "${USE_HOST_MODEL}" = "1" ]; then
    VOLUME_MOUNTS="${VOLUME_MOUNTS} -v \"${HOST_PRETRAINED_DIR}:/app/pretrained_models:ro\""
fi

VOLUME_MOUNTS="${VOLUME_MOUNTS} -v \"${HOST_OUTPUT_DIR}:/app/output\""

# ============================================================
# Run inference
# ============================================================

echo ""
echo "=========================================="
echo "Running FoundationStereo Inference"
echo "=========================================="
echo ""

eval "docker run --gpus \"device=${GPU_ID}\" \
    --network=host \
    --shm-size=8g \
    --rm \
    ${VOLUME_MOUNTS} \
    -e CUDA_VISIBLE_DEVICES=${GPU_ID} \
    ${IMAGE_NAME} \
    python scripts/run_demo.py \
        --left_file \"${CONTAINER_LEFT_IMG}\" \
        --right_file \"${CONTAINER_RIGHT_IMG}\" \
        --intrinsic_file \"${CONTAINER_INTRINSIC}\" \
        --ckpt_dir \"${CKPT_DIR}\" \
        --out_dir /app/output \
        --scale 1.0 \
        --hiera 0 \
        --valid_iters 32 \
        --get_pc 1 \
        --z_far 10.0"

# ============================================================
# Check results
# ============================================================

echo ""
echo "=========================================="
echo "Inference Complete!"
echo "=========================================="
echo "Output saved to: ${HOST_OUTPUT_DIR}"
echo ""

# List output files
if [ -d "${HOST_OUTPUT_DIR}" ]; then
    echo "Generated files:"
    ls -lh "${HOST_OUTPUT_DIR}"
fi

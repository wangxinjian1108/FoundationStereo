#!/bin/bash

# FoundationStereo Inference Test Script
# This script runs Docker container for FoundationStereo inference testing

# ============================================================
# Configuration - Modify these paths according to your setup
# ============================================================

# Docker image name (should match what you built with build_image.sh)
IMAGE_NAME="xinjianwang/foundation_stereo:latest"

# Model checkpoint path (update with your actual model path)
# Note: Models are now baked into the Docker image at /app/pretrained_models/
# You can override by setting CKPT_DIR below, or leave as default to use baked-in models
HOST_PRETRAINED_DIR="${PWD}/pretrained_models"

# Input images directory
HOST_INPUT_DIR="${PWD}/assets"

# Output directory
HOST_OUTPUT_DIR="${PWD}/output"

# ============================================================
# Optional: Test with custom images
# ============================================================
# Uncomment and set these if you want to test with your own images
# LEFT_IMG="/path/to/your/left.png"
# RIGHT_IMG="/path/to/your/right.png"
# INTRINSIC_FILE="/path/to/your/K.txt"

# ============================================================
# GPU Configuration
# ============================================================
GPU_ID=0  # GPU device ID to use

# ============================================================
# Docker run options
# ============================================================
# Use host network for better performance
NETWORK_MODE="--network=host"

# Shared memory size (increase if you encounter OOM errors)
SHM_SIZE="--shm-size=8g"

# Remove container after exit
REMOVE_CONTAINER="--rm"

# ============================================================
# Check prerequisites
# ============================================================
echo "Checking prerequisites..."

# Check if Docker image exists
if ! docker image inspect "${IMAGE_NAME}" &> /dev/null; then
    echo "Error: Docker image '${IMAGE_NAME}' not found!"
    echo "Please build it first using: bash docker_test/build_image.sh"
    exit 1
fi
echo "Docker image found: ${IMAGE_NAME}"

# Check if input images exist
if [ ! -f "${HOST_INPUT_DIR}/left.png" ] || [ ! -f "${HOST_INPUT_DIR}/right.png" ]; then
    echo "Warning: Test images not found in ${HOST_INPUT_DIR}"
    echo "Expected: left.png and right.png"
fi

# Create output directory
mkdir -p "${HOST_OUTPUT_DIR}"
echo "Output directory: ${HOST_OUTPUT_DIR}"

# ============================================================
# Run inference
# ============================================================
echo ""
echo "=========================================="
echo "Running FoundationStereo Inference"
echo "=========================================="
echo ""

# Detect model directory (models are now baked into the image)
# Check if host has pretrained_models directory for override
if [ -d "${HOST_PRETRAINED_DIR}" ]; then
    MODEL_DIR=$(find "${HOST_PRETRAINED_DIR}" -name "model_best_bp2.pth" -type f 2>/dev/null | head -1)
    if [ -n "$MODEL_DIR" ]; then
        MODEL_SUBDIR=$(dirname "$MODEL_DIR" | xargs basename)
        CKPT_DIR="/app/pretrained_models/${MODEL_SUBDIR}/model_best_bp2.pth"
        USE_HOST_MODEL=1
        echo "Found host model: ${MODEL_DIR}"
    fi
fi

# Default to baked-in model
if [ -z "${USE_HOST_MODEL}" ]; then
    CKPT_DIR="/app/pretrained_models/23-51-11/model_best_bp2.pth"
    echo "Using baked-in model: ${CKPT_DIR}"
fi

# Prepare volume mounts (only mount host model if it exists)
VOLUME_MOUNTS=""
if [ "${USE_HOST_MODEL}" = "1" ]; then
    VOLUME_MOUNTS="-v \"${HOST_PRETRAINED_DIR}:/app/pretrained_models:ro\""
fi

# Run Docker container with inference
eval "docker run --gpus \"device=${GPU_ID}\" \
    ${NETWORK_MODE} \
    ${SHM_SIZE} \
    ${REMOVE_CONTAINER} \
    ${VOLUME_MOUNTS} \
    -v \"${HOST_INPUT_DIR}:/app/input_assets:ro\" \
    -v \"${HOST_OUTPUT_DIR}:/app/output\" \
    -e CUDA_VISIBLE_DEVICES=${GPU_ID} \
    ${IMAGE_NAME} \
    python scripts/run_demo.py \
        --left_file /app/input_assets/left.png \
        --right_file /app/input_assets/right.png \
        --intrinsic_file /app/input_assets/K.txt \
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
else
    echo "Warning: Output directory not found!"
fi

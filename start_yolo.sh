#!/bin/bash
#
# YOLO11 Detection Startup Script
#
# Usage:
#   ./start_yolo.sh [OPTIONS]
#
# Options:
#   --robot-id ID         Robot ID for namespacing (default: YOLO_001)
#   --model MODEL         YOLO model file (default: yolo11n.pt)
#   --device DEVICE       Device for inference: "cuda:0" for GPU, "cpu" for CPU (default: cuda:0)
#   --video-device DEV    Video device path (default: /dev/video0)
#   --no-camera           Disable USB camera node (use external image topic)
#   --confidence CONF     Detection confidence threshold (default: 0.5)
#   --help                Show this help message
#

set -e

# Default values
ROBOT_ID="YOLO_001"
MODEL="/workspace/models/yolo11n.pt"
DEVICE="cuda:0"
VIDEO_DEVICE="/dev/video0"
ENABLE_CAMERA="true"
CONFIDENCE="0.5"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --robot-id)
            ROBOT_ID="$2"
            shift 2
            ;;
        --model)
            MODEL="$2"
            shift 2
            ;;
        --device)
            DEVICE="$2"
            shift 2
            ;;
        --video-device)
            VIDEO_DEVICE="$2"
            shift 2
            ;;
        --no-camera)
            ENABLE_CAMERA="false"
            shift
            ;;
        --confidence)
            CONFIDENCE="$2"
            shift 2
            ;;
        --help)
            head -20 "$0" | tail -17
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Source ROS 2 setup (auto-detect inside container)
if [ -n "${ROS_DISTRO:-}" ] && [ -f "/opt/ros/${ROS_DISTRO}/setup.bash" ]; then
    source "/opt/ros/${ROS_DISTRO}/setup.bash"
elif [ -f "/opt/ros/humble/setup.bash" ]; then
    source /opt/ros/humble/setup.bash
elif [ -f "/opt/ros/jazzy/setup.bash" ]; then
    source /opt/ros/jazzy/setup.bash
else
    echo "ERROR: ROS 2 setup.bash not found under /opt/ros (expected humble or jazzy)."
    echo "Are you running the correct container image?"
    exit 1
fi

# Source workspace setup if available
if [ -f /workspace/install/setup.bash ]; then
    source /workspace/install/setup.bash
fi

echo "=========================================="
echo "YOLO11 Detection System"
echo "=========================================="
echo "Robot ID:      ${ROBOT_ID}"
echo "Model:         ${MODEL}"
echo "Device:        ${DEVICE}"
echo "Video Device:  ${VIDEO_DEVICE}"
echo "Camera:        ${ENABLE_CAMERA}"
echo "Confidence:    ${CONFIDENCE}"
echo "=========================================="

# Sanity check: if user requested CUDA, verify torch actually has CUDA
if [[ "${DEVICE}" == cuda* ]]; then
    if ! python3 - <<'PY'
import torch
print(f"torch: {torch.__version__}")
print(f"cuda_available: {torch.cuda.is_available()}")
raise SystemExit(0 if torch.cuda.is_available() else 1)
PY
    then
        echo ""
        echo "ERROR: You requested DEVICE='${DEVICE}', but torch.cuda.is_available() is False."
        echo "This usually means either:"
        echo "  - You are running a CPU-only image (e.g. yolo-ros:jazzy), or"
        echo "  - You did not start the container with GPU runtime (--runtime=nvidia)."
        echo ""
        echo "Fix:"
        echo "  1) Exit this container"
        echo "  2) Run: docker run -it --rm --net=host --ipc=host --privileged --runtime=nvidia -v /dev:/dev -v /home/kidou/yolo_ws:/workspace yolo-ros:humble"
        echo ""
        exit 1
    fi
fi

# Launch the detection system
ros2 launch yolo_ros yolo_detection.launch.py \
    robot_id:="${ROBOT_ID}" \
    model:="${MODEL}" \
    device:="${DEVICE}" \
    video_device:="${VIDEO_DEVICE}" \
    enable_camera:="${ENABLE_CAMERA}" \
    confidence_threshold:="${CONFIDENCE}"


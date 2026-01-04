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
#   --rviz                Start rviz2 (requires GUI/X11-enabled container)
#   --rqt                 Start rqt_image_view on annotated image topic (requires GUI/X11-enabled container)
#   --help                Show this help message
#

set -euo pipefail

usage() {
cat <<'EOF'
YOLO11 Detection Startup Script

Usage:
  ./start_yolo.sh [OPTIONS]

Options:
  --robot-id ID         Robot ID for namespacing (default: YOLO_001)
  --model MODEL         YOLO model file (default: /workspace/models/yolo11n.pt)
  --device DEVICE       Device for inference: "cuda:0" for GPU, "cpu" for CPU (default: cuda:0)
  --video-device DEV    Video device path (default: /dev/video0)
  --no-camera           Disable USB camera node (use external image topic)
  --confidence CONF     Detection confidence threshold (default: 0.5)
  --rviz                Start rviz2 (requires GUI/X11-enabled container)
  --rqt                 Start rqt_image_view (requires GUI/X11-enabled container)
  --help                Show this help message

Notes:
  - Topics will be namespaced under /<robot_id>/...
    - annotated image: /<robot_id>/image_annotated
    - detections:      /<robot_id>/detections
EOF
}

# Default values
ROBOT_ID="YOLO_001"
MODEL="/workspace/models/yolo11n.pt"
DEVICE="cuda:0"
VIDEO_DEVICE="/dev/video0"
ENABLE_CAMERA="true"
CONFIDENCE="0.5"
START_RVIZ="false"
START_RQT="false"

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
        --rviz)
            START_RVIZ="true"
            shift
            ;;
        --rqt)
            START_RQT="true"
            shift
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo ""
            usage
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
echo "RViz2:         ${START_RVIZ}"
echo "rqt_image_view:${START_RQT}"
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

# Launch the detection system in the background so we can optionally start viewers.
ANNOTATED_TOPIC="/${ROBOT_ID}/image_annotated"

cleanup() {
    # Best-effort cleanup of background processes
    if [[ -n "${LAUNCH_PID:-}" ]] && kill -0 "${LAUNCH_PID}" 2>/dev/null; then
        kill "${LAUNCH_PID}" 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM

ros2 launch yolo_ros yolo_detection.launch.py \
    robot_id:="${ROBOT_ID}" \
    model:="${MODEL}" \
    device:="${DEVICE}" \
    video_device:="${VIDEO_DEVICE}" \
    enable_camera:="${ENABLE_CAMERA}" \
    confidence_threshold:="${CONFIDENCE}" &
LAUNCH_PID=$!

# Give nodes a moment to start publishing topics
sleep 2

if [[ "${START_RQT}" == "true" ]] || [[ "${START_RVIZ}" == "true" ]]; then
    if [[ -z "${DISPLAY:-}" ]] || [[ ! -S /tmp/.X11-unix/X0 && ! -S /tmp/.X11-unix/X1 && ! -S /tmp/.X11-unix/X2 ]]; then
        echo ""
        echo "GUI requested but DISPLAY/X11 socket is not available inside this container."
        echo "Start the container with X11 enabled, e.g. on the Jetson host:"
        echo "  xhost +local:root"
        echo "  docker run -it --rm --net=host --ipc=host --privileged --runtime=nvidia \\"
        echo "    -e DISPLAY=\\$DISPLAY -e QT_X11_NO_MITSHM=1 -v /tmp/.X11-unix:/tmp/.X11-unix \\"
        echo "    -v /dev:/dev -v /home/kidou/yolo_ws:/workspace yolo-ros:humble"
        echo ""
    else
        if [[ "${START_RQT}" == "true" ]]; then
            if command -v rqt_image_view >/dev/null 2>&1; then
                rqt_image_view "${ANNOTATED_TOPIC}" >/dev/null 2>&1 &
                echo "Started rqt_image_view on ${ANNOTATED_TOPIC}"
            else
                echo "rqt_image_view not found in PATH."
            fi
        fi

        if [[ "${START_RVIZ}" == "true" ]]; then
            if command -v rviz2 >/dev/null 2>&1; then
                rviz2 >/dev/null 2>&1 &
                echo "Started rviz2"
            else
                echo "rviz2 not found in PATH."
            fi
        fi
    fi
fi

wait "${LAUNCH_PID}"


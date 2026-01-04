# YOLO11 ROS 2 Workspace

ROS 2 Humble workspace for YOLO11 object detection using Ultralytics, with Docker and CUDA support (Jetson).

## Features

- YOLO11 real-time object detection via Ultralytics
- ROS 2 Humble integration with standard vision messages
- USB camera support via `usb_cam`
- GPU acceleration with CUDA
- Configurable detection parameters
- Robot ID namespacing for multi-robot setups

## Quick Start

### 1. Build Docker Image

```bash
cd ~/yolo_ws/docker
docker build --network=host -t yolo-ros:humble .
```

### 2. Run Docker Container

```bash
# Create shell alias for convenience
echo "alias yolo-docker='docker run -it --rm --net=host --ipc=host --privileged --runtime=nvidia -v /dev:/dev -v ~/yolo_ws:/workspace yolo-ros:humble'" >> ~/.bashrc
source ~/.bashrc

# Start container
yolo-docker
```

### 2.1 Verify GPU inside the container

```bash
# Inside container
/test_gpu.sh
```

### 3. Build Workspace

```bash
# Inside container
cd /workspace
colcon build --symlink-install
source install/setup.bash
```

If you previously built this workspace against ROS 2 Jazzy on the host, delete the old artifacts (they won’t be compatible with Humble/Python 3.10):

```bash
cd ~/yolo_ws
rm -rf build install log
```

### 4. Launch Detection

```bash
# Basic launch with USB camera
ros2 launch yolo_ros yolo_detection.launch.py

# Or use the startup script
./start_yolo.sh
```

## Configuration

### YOLO Parameters

Edit `src/yolo_ros/config/yolo_params.yaml`:

```yaml
yolo_detector:
  ros__parameters:
    model: "/workspace/models/yolo11n.pt"  # Model size: n, s, m, l, x
    confidence_threshold: 0.5     # Detection confidence (0.0-1.0)
    device: "cuda:0"              # GPU: "cuda:0", CPU: "cpu"
```

### Camera Parameters

Edit `src/yolo_ros/config/camera_params.yaml`:

```yaml
usb_cam:
  ros__parameters:
    video_device: "/dev/video0"
    image_width: 640
    image_height: 480
    framerate: 30.0
```

## Launch Options

```bash
# Custom robot ID
ros2 launch yolo_ros yolo_detection.launch.py robot_id:=MY_ROBOT

# Use different model
ros2 launch yolo_ros yolo_detection.launch.py model:=yolo11s.pt

# CPU-only inference
ros2 launch yolo_ros yolo_detection.launch.py device:=cpu

# Different camera
ros2 launch yolo_ros yolo_detection.launch.py video_device:=/dev/video1

# Subscribe to external image topic (no local camera)
ros2 launch yolo_ros yolo_detection.launch.py enable_camera:=false
```

## Topics

### Published

| Topic | Type | Description |
|-------|------|-------------|
| `/<robot_id>/detections` | `vision_msgs/Detection2DArray` | Detection results with bounding boxes and classes |
| `/<robot_id>/image_annotated` | `sensor_msgs/Image` | Image with detection overlays |

### Subscribed

| Topic | Type | Description |
|-------|------|-------------|
| `/<robot_id>/camera/image_raw` | `sensor_msgs/Image` | Input camera image |

## YOLO Models

| Model | Size | Speed | Accuracy | Use Case |
|-------|------|-------|----------|----------|
| `yolo11n.pt` | 6 MB | Fastest | Good | Real-time on edge devices |
| `yolo11s.pt` | 22 MB | Fast | Better | Balanced performance |
| `yolo11m.pt` | 39 MB | Medium | High | General use |
| `yolo11l.pt` | 49 MB | Slow | Higher | High accuracy needed |
| `yolo11x.pt` | 98 MB | Slowest | Highest | Maximum accuracy |

Models are automatically downloaded on first use. To pre-download:

```bash
./scripts/download_models.sh n    # Download nano model
./scripts/download_models.sh all  # Download all models
```

## Integration with LTR_KS_ws

Both workspaces can run simultaneously and share the ROS 2 network:

```bash
# Terminal 1: Start robot controller
cd ~/LTR_KS_ws
docker run -it --rm --net=host --privileged \
  -v ~/LTR_KS_ws:/workspace my-ros-jazzy:pi \
  /workspace/start_robot_serial_ackermann.sh

# Terminal 2: Start YOLO detection
cd ~/yolo_ws
docker run -it --rm --net=host --privileged --runtime=nvidia \
  -v /dev:/dev -v ~/yolo_ws:/workspace yolo-ros:jazzy \
  /workspace/start_yolo.sh --robot-id YOLO_001
```

The robot can subscribe to `/YOLO_001/detections` for object-aware navigation.

## Troubleshooting

### Camera Not Found

```bash
# List available cameras
ls -la /dev/video*

# Test camera outside Docker
v4l2-ctl --list-devices

# Check camera inside Docker
ros2 run usb_cam usb_cam_node_exe --ros-args -p video_device:=/dev/video0
```

### GPU Not Detected

```bash
# Verify CUDA is available
nvidia-smi

# Check PyTorch sees GPU
python3 -c "import torch; print(torch.cuda.is_available())"

# Use CPU fallback
ros2 launch yolo_ros yolo_detection.launch.py device:=cpu
```

### Model Download Issues

```bash
# Manual download
pip3 install ultralytics
python3 -c "from ultralytics import YOLO; YOLO('yolo11n.pt')"

# Check model location
ls -la ~/.cache/ultralytics/
```

### No Detections

1. Check confidence threshold (try lowering to 0.25)
2. Verify input image topic is publishing
3. Check model is loaded correctly in logs

## Directory Structure

```
yolo_ws/
├── docker/
│   └── Dockerfile           # CUDA + ROS 2 + YOLO11
├── src/
│   └── yolo_ros/            # ROS 2 detection package
│       ├── yolo_ros/
│       │   └── detector_node.py
│       ├── config/
│       │   ├── yolo_params.yaml
│       │   └── camera_params.yaml
│       ├── launch/
│       │   └── yolo_detection.launch.py
│       ├── CMakeLists.txt
│       └── package.xml
├── models/                  # YOLO model weights
├── scripts/
│   └── download_models.sh
├── start_yolo.sh
└── README.md
```

## License

MIT


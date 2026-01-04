#!/usr/bin/env python3
"""
YOLO11 Detection Launch File

Launches USB camera and YOLO detector nodes for real-time object detection.
"""

from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument
from launch.substitutions import LaunchConfiguration, PathJoinSubstitution
from launch.conditions import IfCondition
from launch_ros.actions import Node
from launch_ros.substitutions import FindPackageShare


def generate_launch_description():
    # Declare launch arguments
    robot_id_arg = DeclareLaunchArgument(
        'robot_id',
        default_value='YOLO_001',
        description='Robot ID for namespacing'
    )

    enable_camera_arg = DeclareLaunchArgument(
        'enable_camera',
        default_value='true',
        description='Enable USB camera node'
    )

    video_device_arg = DeclareLaunchArgument(
        'video_device',
        default_value='/dev/video0',
        description='Video device path'
    )

    model_arg = DeclareLaunchArgument(
        'model',
        default_value='/workspace/models/yolo11n.pt',
        description='YOLO model file path (download to /workspace/models/)'
    )

    confidence_arg = DeclareLaunchArgument(
        'confidence_threshold',
        default_value='0.5',
        description='Detection confidence threshold (0.0-1.0)'
    )

    device_arg = DeclareLaunchArgument(
        'device',
        default_value='cuda:0',
        description='Device for inference (GPU: "cuda:0", CPU: "cpu")'
    )

    publish_annotated_arg = DeclareLaunchArgument(
        'publish_annotated',
        default_value='true',
        description='Publish annotated images with bounding boxes'
    )

    # Get launch configurations
    robot_id = LaunchConfiguration('robot_id')
    enable_camera = LaunchConfiguration('enable_camera')
    video_device = LaunchConfiguration('video_device')
    model = LaunchConfiguration('model')
    confidence_threshold = LaunchConfiguration('confidence_threshold')
    device = LaunchConfiguration('device')
    publish_annotated = LaunchConfiguration('publish_annotated')

    # Package share directory for config files
    pkg_share = FindPackageShare('yolo_ros')

    # USB Camera node
    usb_cam_node = Node(
        package='usb_cam',
        executable='usb_cam_node_exe',
        name='usb_cam',
        namespace=robot_id,
        parameters=[
            PathJoinSubstitution([pkg_share, 'config', 'camera_params.yaml']),
            {'video_device': video_device}
        ],
        remappings=[
            ('image_raw', 'camera/image_raw'),
        ],
        condition=IfCondition(enable_camera)
    )

    # YOLO Detector node
    yolo_detector_node = Node(
        package='yolo_ros',
        executable='detector_node.py',
        name='yolo_detector',
        namespace=robot_id,
        parameters=[
            PathJoinSubstitution([pkg_share, 'config', 'yolo_params.yaml']),
            {
                'model': model,
                'confidence_threshold': confidence_threshold,
                'device': device,
                'publish_annotated': publish_annotated,
                'input_topic': 'camera/image_raw',
                'output_topic': 'detections',
                'image_topic': 'image_annotated',
            }
        ],
        output='screen'
    )

    return LaunchDescription([
        # Launch arguments
        robot_id_arg,
        enable_camera_arg,
        video_device_arg,
        model_arg,
        confidence_arg,
        device_arg,
        publish_annotated_arg,
        # Nodes
        usb_cam_node,
        yolo_detector_node,
    ])


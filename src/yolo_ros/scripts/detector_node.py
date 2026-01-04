#!/usr/bin/env python3
"""
YOLO11 Object Detection ROS 2 Node

This node subscribes to an image topic, runs YOLO11 inference,
and publishes detection results and annotated images.
"""

import rclpy
from rclpy.node import Node
from rclpy.qos import QoSProfile, ReliabilityPolicy, HistoryPolicy
from sensor_msgs.msg import Image
from vision_msgs.msg import Detection2D, Detection2DArray, ObjectHypothesisWithPose
from std_msgs.msg import Header
from cv_bridge import CvBridge
import cv2
import numpy as np

from ultralytics import YOLO
import torch


class YoloDetectorNode(Node):
    """ROS 2 node for YOLO11 object detection."""

    def __init__(self):
        super().__init__('yolo_detector')

        # Declare parameters
        self.declare_parameter('model', 'yolo11n.pt')
        self.declare_parameter('confidence_threshold', 0.5)
        self.declare_parameter('device', 'cuda:0')  # 'cpu' or 'cuda:0' (GPU requires Jetson PyTorch)
        # Memory/perf tuning (important on Jetson)
        self.declare_parameter('imgsz', 320)  # smaller = less GPU memory (typical: 320 or 640)
        self.declare_parameter('half', True)  # use FP16 on CUDA to reduce memory (ignored on CPU)
        self.declare_parameter('input_topic', '/camera/image_raw')
        self.declare_parameter('output_topic', '/detections')
        self.declare_parameter('image_topic', '/image_annotated')
        self.declare_parameter('publish_annotated', True)

        # Get parameters
        model_path = self.get_parameter('model').value
        self.confidence_threshold = self.get_parameter('confidence_threshold').value
        self.device = self.get_parameter('device').value
        self.imgsz = int(self.get_parameter('imgsz').value)
        self.half = bool(self.get_parameter('half').value)
        input_topic = self.get_parameter('input_topic').value
        output_topic = self.get_parameter('output_topic').value
        image_topic = self.get_parameter('image_topic').value
        self.publish_annotated = self.get_parameter('publish_annotated').value

        self.get_logger().info(f'Loading YOLO model: {model_path}')
        self.get_logger().info(f'Using device: {self.device}')
        self.get_logger().info(f'imgsz: {self.imgsz}, half: {self.half}')

        # Initialize YOLO model
        try:
            # Reduce fragmentation / stale allocations (helps with intermittent OOM)
            if self.device.startswith('cuda') and torch.cuda.is_available():
                torch.cuda.empty_cache()

            self.model = YOLO(model_path)

            # Move model to device
            self.model.to(self.device)
            self.get_logger().info('YOLO model loaded successfully')
        except Exception as e:
            self.get_logger().error(f'Failed to load YOLO model: {e}')
            if self.device.startswith('cuda'):
                self.get_logger().error(
                    "CUDA OOM on model load. Try one or more of: "
                    "set half:=true, set imgsz:=320, close other GPU apps/containers, "
                    "or run device:=cpu."
                )
            raise

        # Initialize CV bridge
        self.bridge = CvBridge()

        # QoS profile for camera images (best effort for real-time)
        image_qos = QoSProfile(
            reliability=ReliabilityPolicy.BEST_EFFORT,
            history=HistoryPolicy.KEEP_LAST,
            depth=1
        )

        # Create subscriber for input images
        self.image_sub = self.create_subscription(
            Image,
            input_topic,
            self.image_callback,
            image_qos
        )

        # Create publisher for detections
        self.detection_pub = self.create_publisher(
            Detection2DArray,
            output_topic,
            10
        )

        # Create publisher for annotated images
        if self.publish_annotated:
            self.image_pub = self.create_publisher(
                Image,
                image_topic,
                10
            )

        self.get_logger().info(f'Subscribed to: {input_topic}')
        self.get_logger().info(f'Publishing detections to: {output_topic}')
        if self.publish_annotated:
            self.get_logger().info(f'Publishing annotated images to: {image_topic}')

    def image_callback(self, msg: Image):
        """Process incoming image and run YOLO detection."""
        try:
            # Convert ROS Image to OpenCV format
            cv_image = self.bridge.imgmsg_to_cv2(msg, desired_encoding='bgr8')
        except Exception as e:
            self.get_logger().error(f'Failed to convert image: {e}')
            return

        # Run YOLO inference (imgsz/half reduce memory footprint)
        try:
            results = self.model(
                cv_image,
                conf=self.confidence_threshold,
                imgsz=self.imgsz,
                half=(self.half and self.device.startswith('cuda')),
                verbose=False
            )
        except RuntimeError as e:
            # Common Jetson failure mode under memory pressure
            if self.device.startswith('cuda') and "out of memory" in str(e).lower():
                self.get_logger().error(
                    "CUDA out of memory during inference. "
                    "Lower imgsz (e.g. 320), set publish_annotated:=false, "
                    "or switch device:=cpu."
                )
            raise

        # Create Detection2DArray message
        detection_array = Detection2DArray()
        detection_array.header = msg.header

        # Process results
        for result in results:
            if result.boxes is not None:
                for box in result.boxes:
                    detection = Detection2D()
                    detection.header = msg.header

                    # Get bounding box (xyxy format)
                    x1, y1, x2, y2 = box.xyxy[0].cpu().numpy()
                    
                    # Set bounding box center and size
                    detection.bbox.center.position.x = float((x1 + x2) / 2)
                    detection.bbox.center.position.y = float((y1 + y2) / 2)
                    detection.bbox.size_x = float(x2 - x1)
                    detection.bbox.size_y = float(y2 - y1)

                    # Set class and confidence
                    hypothesis = ObjectHypothesisWithPose()
                    class_id = int(box.cls[0].cpu().numpy())
                    hypothesis.hypothesis.class_id = self.model.names[class_id]
                    hypothesis.hypothesis.score = float(box.conf[0].cpu().numpy())
                    detection.results.append(hypothesis)

                    detection_array.detections.append(detection)

        # Publish detections
        self.detection_pub.publish(detection_array)

        # Publish annotated image if enabled
        if self.publish_annotated:
            # Get annotated frame from YOLO
            annotated_frame = results[0].plot()
            
            # Add detection count overlay
            num_detections = len(detection_array.detections)
            cv2.putText(
                annotated_frame,
                f'Detections: {num_detections}',
                (10, 30),
                cv2.FONT_HERSHEY_SIMPLEX,
                1,
                (0, 255, 0),
                2
            )

            try:
                annotated_msg = self.bridge.cv2_to_imgmsg(annotated_frame, encoding='bgr8')
                annotated_msg.header = msg.header
                self.image_pub.publish(annotated_msg)
            except Exception as e:
                self.get_logger().error(f'Failed to publish annotated image: {e}')

        # Log detection summary periodically
        if len(detection_array.detections) > 0:
            classes = [d.results[0].hypothesis.class_id for d in detection_array.detections]
            self.get_logger().debug(f'Detected {len(classes)} objects: {classes}')


def main(args=None):
    rclpy.init(args=args)
    
    node = YoloDetectorNode()
    
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()


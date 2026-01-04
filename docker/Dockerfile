# Jetson L4T PyTorch base (CUDA-enabled PyTorch for Jetson)
# Ubuntu 22.04 (jammy) base: pair with ROS 2 Humble (jammy binaries).
FROM dustynv/l4t-pytorch:r36.4.0

# Avoid tz prompts
ENV DEBIAN_FRONTEND=noninteractive
ENV ROS_DISTRO=humble
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# Common OS deps + locale
RUN apt-get update && apt-get install -y --no-install-recommends \
    locales \
    ca-certificates \
    curl \
    gnupg2 \
    lsb-release \
    software-properties-common \
    build-essential \
    cmake \
    git \
    nano \
    vim \
    python3-pip \
    && locale-gen en_US.UTF-8 \
    && update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 \
    && add-apt-repository universe \
    && rm -rf /var/lib/apt/lists/*

# ROS 2 apt repository
# Note: Some networks/proxies break TLS verification for packages.ros.org.
# Fetch the key from Ubuntu's keyserver over HTTP (no GPG keyserver protocol needed).
RUN curl -fsSL --retry 5 --retry-delay 1 "http://keyserver.ubuntu.com/pks/lookup?op=get&search=0xF42ED6FBAB17C654" \
      | gpg --dearmor -o /usr/share/keyrings/ros-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu $(. /etc/os-release && echo $UBUNTU_CODENAME) main" \
      > /etc/apt/sources.list.d/ros2.list

# ROS 2 + vision stack
RUN apt-get update && apt-get install -y --no-install-recommends \
    ros-humble-ros-base \
    ros-humble-ament-cmake \
    python3-colcon-common-extensions \
    ros-humble-usb-cam \
    ros-humble-cv-bridge \
    ros-humble-image-transport \
    ros-humble-vision-msgs \
    ros-humble-image-transport-plugins \
    ros-humble-rviz2 \
    ros-humble-rqt-image-view \
    python3-opencv \
    python3-yaml \
    python3-tqdm \
    python3-psutil \
    python3-cpuinfo \
    libgl1 \
    libgl1-mesa-dri \
    libegl1 \
    libqt5x11extras5 \
    libxkbcommon-x11-0 \
    libxcb-xinerama0 \
    mesa-utils \
    && rm -rf /var/lib/apt/lists/*

# Ultralytics YOLO (preserve CUDA torch from the base image)
# Use --isolated to ignore any baked-in pip.conf extra indexes (e.g., NVIDIA/NVC).
RUN pip3 install --isolated --no-cache-dir --index-url https://pypi.org/simple \
    --no-deps ultralytics

# Auto-source ROS for interactive shells
SHELL ["/bin/bash", "-lc"]
RUN echo "source /opt/ros/${ROS_DISTRO}/setup.bash" >> /root/.bashrc && \
    echo "if [ -f /workspace/install/setup.bash ]; then source /workspace/install/setup.bash; fi" >> /root/.bashrc && \
    echo "alias cb='colcon build --symlink-install'" >> /root/.bashrc && \
    echo "alias cbp='colcon build --packages-select'" >> /root/.bashrc && \
    echo "alias ct='colcon test'" >> /root/.bashrc && \
    echo "alias ctr='colcon test-result --verbose'" >> /root/.bashrc && \
    echo "alias ws='cd /workspace'" >> /root/.bashrc && \
    echo "alias sb='source ~/.bashrc'" >> /root/.bashrc

# Ensure ROS env is available in login shells (bash -l), even when non-interactive.
# (Ubuntu's default ~/.bashrc returns early for non-interactive shells.)
RUN cat >/etc/profile.d/ros2.sh <<'EOF'
if [ -n "${ROS_DISTRO:-}" ] && [ -f "/opt/ros/${ROS_DISTRO}/setup.bash" ]; then
  source "/opt/ros/${ROS_DISTRO}/setup.bash"
  # ROS 2 Humble setup.bash doesn't set CMAKE_PREFIX_PATH by default, but CMake/ament needs it.
  export CMAKE_PREFIX_PATH="/opt/ros/${ROS_DISTRO}${CMAKE_PREFIX_PATH:+:${CMAKE_PREFIX_PATH}}"
fi
if [ -f /workspace/install/setup.bash ]; then
  source /workspace/install/setup.bash
  export CMAKE_PREFIX_PATH="/workspace/install${CMAKE_PREFIX_PATH:+:${CMAKE_PREFIX_PATH}}"
fi
EOF
RUN chmod +x /etc/profile.d/ros2.sh

# Make login shells (bash -l) load ~/.bashrc (aliases etc.)
RUN echo 'if [ -f ~/.bashrc ]; then . ~/.bashrc; fi' > /root/.bash_profile

# Make non-interactive "bash -c" load ROS env too
ENV BASH_ENV=/etc/profile.d/ros2.sh

# Test script to verify GPU (quoting-safe)
RUN cat >/test_gpu.sh <<'EOF'
#!/bin/bash
set -e
python3 - <<'PY'
import torch
print(f"torch: {torch.__version__}")
print(f"CUDA available: {torch.cuda.is_available()}")
if torch.cuda.is_available():
    print(f"Device: {torch.cuda.get_device_name(0)}")
else:
    print("Device: CPU")
PY
EOF
RUN chmod +x /test_gpu.sh

# Workspace
WORKDIR /workspace
ENV RCUTILS_COLORIZED_OUTPUT=1

CMD ["/bin/bash", "-l"]

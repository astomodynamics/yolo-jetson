#!/bin/bash
#
# Download YOLO11 Models
#
# Downloads YOLO11 model weights from Ultralytics.
# Models are automatically downloaded on first use, but this script
# allows pre-downloading for offline use.
#
# Usage:
#   ./download_models.sh [model_size]
#
# Model sizes:
#   n - nano (fastest, smallest, least accurate)
#   s - small
#   m - medium
#   l - large
#   x - xlarge (slowest, largest, most accurate)
#   all - download all models
#

set -e

MODELS_DIR="/workspace/models"
mkdir -p "${MODELS_DIR}"

download_model() {
    local size=$1
    local model_name="yolo11${size}.pt"
    
    echo "Downloading ${model_name}..."
    
    python3 -c "
from ultralytics import YOLO
import shutil
import os

model = YOLO('${model_name}')
# Model is downloaded to ~/.cache/ultralytics or current directory
# Copy to models directory
src = '${model_name}'
dst = '${MODELS_DIR}/${model_name}'
if os.path.exists(src):
    shutil.copy(src, dst)
    os.remove(src)
    print(f'Model saved to {dst}')
else:
    print(f'Model cached at default location')
"
}

MODEL_SIZE="${1:-n}"

case "${MODEL_SIZE}" in
    n|s|m|l|x)
        download_model "${MODEL_SIZE}"
        ;;
    all)
        for size in n s m l x; do
            download_model "${size}"
        done
        ;;
    *)
        echo "Unknown model size: ${MODEL_SIZE}"
        echo "Valid options: n, s, m, l, x, all"
        exit 1
        ;;
esac

echo ""
echo "Models downloaded to: ${MODELS_DIR}"
ls -lh "${MODELS_DIR}"/*.pt 2>/dev/null || echo "No models found in ${MODELS_DIR}"


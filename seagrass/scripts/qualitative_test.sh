#!/bin/bash

# TODO: Weight version for qualitative test
WEIGHTS_VER='200620'

# Get the path to this script
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

# Download the weights
aws s3 sync "s3://hakai-deep-learning-datasets/seagrass/weights/deeplabv3_seagrass_$WEIGHTS_VER.ckpt" \
  "$DIR/../train_output/weights/"

# Build the docker image
DOCKER_BUILDKIT=1 docker build --file ../Dockerfile --compress --tag tayden/deeplabv3-seagrass ../..

# TODO: Process test image
#docker run -it --rm \
#  -v "$DIR/../train_input":/opt/ml/input \
#  -v "$DIR/../train_output":/opt/ml/output \
#  --user "$(id -u):$(id -g)" \
#  --ipc host \
#  --gpus all \
#  --name seagrass-pred \
#  tayden/deeplabv3-seagrass:latest pred \
#  "/opt/ml/input/data/segmentation/triquet_small.tif" \
#  "/opt/ml/output/segmentation/triquet_small_seagrass_$WEIGHTS_VER.tif" \
#  "/opt/ml/output/weights/deeplabv3_seagrass_$WEIGHTS_VER.ckpt"

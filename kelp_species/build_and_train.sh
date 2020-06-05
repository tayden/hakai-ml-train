#!/bin/bash

# Get the path to this script
NAME=AMPO1
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
PORT=6006

# Build the docker image
DOCKER_BUILDKIT=1 docker build --file ./Dockerfile --compress --tag tayden/deeplabv3-kelp-species ..

# Sync datasets
aws s3 sync s3://hakai-deep-learning-datasets/kelp/train ./train_input/data/train
aws s3 sync s3://hakai-deep-learning-datasets/kelp/eval ./train_input/data/eval

# Make output dirs
mkdir -p "./train_output/checkpoints"

# Run the docker image
docker run -dit --rm \
  -p 0.0.0.0:$PORT:$PORT \
  -v "$DIR/train_input":/opt/ml/input \
  -v "$DIR/train_output":/opt/ml/output \
  --user "$(id -u):$(id -g)" \
  --ipc host \
  --gpus all \
  --name kelp-species-train \
  tayden/deeplabv3-kelp-species train "/opt/ml/input/data/train" "/opt/ml/input/data/eval" "/opt/ml/output/checkpoints" \
  --accumulate_grad_batches=4 --gradient_clip_val=0.5 --weight_decay=0.001 --unfreeze_backbone_epoch=30 --epochs=150 \
  --name=$NAME --precision=16 --amp_level="O1" --lr=0.0003019951720402019

# Can start tensorboard in running container as follows:
docker exec -dit kelp-train tensorboard --logdir=/opt/ml/output/checkpoints --host=0.0.0.0 --port=$PORT
# Navigate to localhost:6006 to see train stats

# Wait for process so AWS exits when it's done
docker wait kelp-train

# Sync results to S3
ARCHIVE="$(date +'%Y-%m-%d-%H%M')_$NAME.tar.gz"
cd ./train_output/checkpoints/$NAME || exit 1
tar -czvf "$ARCHIVE" ./*
aws s3 cp "$ARCHIVE" s3://hakai-deep-learning-datasets/kelp/output/
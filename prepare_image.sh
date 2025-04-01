#!/usr/bin/env bash
set -Eeuox pipefail

source env.sh

echo "start to build and install windows"
docker compose up windows-build -d --wait --build

echo "windows installed, now stop container"
docker stop windows-build

echo "commit all the changes"
docker commit windows-build "$IMAGE_NAME:$IMAGE_VERSION"
docker images

docker push "$IMAGE_NAME:$IMAGE_VERSION"

echo "start container with windows installed"
docker compose up windows-installed -d --wait

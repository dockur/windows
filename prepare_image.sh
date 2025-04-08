#!/usr/bin/env bash
set -Eeuo pipefail

source env.sh

echo "start to build and install windows"
docker compose up windows-build -d --build --force-recreate

echo "streaming logs..."
docker logs -f windows-build | tee windows-build.log &

echo "waiting for windows-build container to be healthy..."
while [[ "$(docker inspect --format='{{.State.Health.Status}}' windows-build 2>/dev/null)" != "healthy" ]]; do
    sleep 2
done

echo "windows installed, now stop container"
docker stop windows-build

echo "commit all the changes"
docker commit windows-build "$IMAGE_NAME:$IMAGE_VERSION"
docker images

echo "start container with windows installed"
docker compose up windows-installed -d

echo "streaming logs..."
docker logs -f windows-installed | tee windows-installed.log &

echo "waiting for windows-installed container to be healthy..."
while [[ "$(docker inspect --format='{{.State.Health.Status}}' windows-installed 2>/dev/null)" != "healthy" ]]; do
    sleep 2
done

docker push "$IMAGE_NAME:$IMAGE_VERSION"

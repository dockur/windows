#!/usr/bin/env bash
set -Eeuo pipefail

# Check if running with interactive TTY or redirected to docker log
if [ -t 1 ]; then
  PROGRESS="--progress=bar:noscroll"
else
  PROGRESS="--progress=dot:giga"
fi

info "Downloading installer..."

URL="https://raw.githubusercontent.com/ElliotKillick/Mido/main/Mido.sh"
{ wget "$URL" -O /run/Mido.sh -q --no-check-certificate; rc=$?; } || :

(( rc != 0 )) && error "Failed to download $URL, reason: $rc" && exit 65

chmod +x /run/Mido.sh
bash /run/Mido.sh

exit 99

BASE="boot.img"
[ -f "$STORAGE/$BASE" ] && return 0

if [ -z "$BOOT" ]; then
  error "No boot disk specified, set BOOT= to the URL of an ISO file." && exit 64
fi

BASE=$(basename "$BOOT")
[ -f "$STORAGE/$BASE" ] && return 0

TMP="$STORAGE/${BASE%.*}.tmp"
rm -f "$TMP"

info "Downloading $BASE as boot image..."

{ wget "$BOOT" -O "$TMP" -q --no-check-certificate --show-progress "$PROGRESS"; rc=$?; } || :

(( rc != 0 )) && error "Failed to download $BOOT, reason: $rc" && exit 60
[ ! -f "$TMP" ] && error "Failed to download $BOOT" && exit 61

SIZE=$(stat -c%s "$TMP")

if ((SIZE<100000)); then
  error "Invalid ISO file: Size is smaller than 100 KB" && exit 62
fi

DEST="$STORAGE/drivers.img"

if [ ! -f "$DEST" ]; then

  info "Downloading VirtIO drivers for Windows..."
  DRIVERS="https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso"

  { wget "$DRIVERS" -O "$DEST" -q --no-check-certificate --show-progress "$PROGRESS"; rc=$?; } || :

  (( rc != 0 )) && info "Failed to download $DRIVERS, reason: $rc" && rm -f "$DEST"

fi

mv -f "$TMP" "$STORAGE/$BASE"

return 0

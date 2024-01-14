#!/usr/bin/env bash
set -Eeuo pipefail

: "${VERSION:="win10x64"}"

BASE="$VERSION.iso"
[ -f "$STORAGE/$BASE" ] && return 0

# Check if running with interactive TTY or redirected to docker log
if [ -t 1 ]; then
  PROGRESS="--progress=bar:noscroll"
else
  PROGRESS="--progress=dot:giga"
fi

SCRIPT="$STORAGE/mido.sh"

rm -f "$SCRIPT"
cp /run/mido.sh "$SCRIPT"
chmod +x "$SCRIPT"

bash "$SCRIPT" "$VERSION"
rm -f "$SCRIPT"

[ ! -f "$STORAGE/$BASE" ] && error "Failed to download $VERSION.iso!" && exit 66

DEST="$STORAGE/drivers.img"

if [ ! -f "$DEST" ]; then

  info "Downloading VirtIO drivers for Windows..."
  DRIVERS="https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso"

  { wget "$DRIVERS" -O "$DEST" -q --no-check-certificate --show-progress "$PROGRESS"; rc=$?; } || :

  (( rc != 0 )) && info "Failed to download $DRIVERS, reason: $rc" && rm -f "$DEST"

fi

return 0

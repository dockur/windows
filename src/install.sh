!/usr/bin/env bash
set -Eeuo pipefail

: "${VERSION:="win11x64"}"

BASE="$VERSION.iso"
[ -f "$STORAGE/$BASE" ] && return 0

URL="https://raw.githubusercontent.com/ElliotKillick/Mido/main/Mido.sh"
{ wget "$URL" -O "$STORAGE/Mido.sh" -q --no-check-certificate; rc=$?; } || :

(( rc != 0 )) && error "Failed to download $URL, reason: $rc" && exit 65

chmod +x "$STORAGE/Mido.sh"
rm -f "$STORAGE/$BASE"

bash "$STORAGE/Mido.sh" "$VERSION"

[ ! -f "$STORAGE/$BASE" ] && error "Failed to download $VERSION.iso!" && exit 66

DEST="$STORAGE/drivers.img"

if [ ! -f "$DEST" ]; then

  info "Downloading VirtIO drivers for Windows..."
  DRIVERS="https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso"

  { wget "$DRIVERS" -O "$DEST" -q --no-check-certificate --show-progress "$PROGRESS"; rc=$?; } || :

  (( rc != 0 )) && info "Failed to download $DRIVERS, reason: $rc" && rm -f "$DEST"

fi

return 0

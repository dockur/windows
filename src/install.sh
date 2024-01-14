#!/usr/bin/env bash
set -Eeuo pipefail

: "${VERSION:="win11x64"}"

BASE="$VERSION.iso"
[ -f "$STORAGE/$BASE" ] && return 0

# Check if running with interactive TTY or redirected to docker log
if [ -t 1 ]; then
  PROGRESS="--progress=bar:noscroll"
else
  PROGRESS="--progress=dot:giga"
fi

DEST="$STORAGE/drivers.img"
[ ! -f "$DEST" ] && cp /run/drivers.iso $DEST

rm -rf "$STORAGE/tmp"
mkdir -p "$STORAGE/tmp"
SCRIPT="$STORAGE/tmp/mido.sh"

cp /run/mido.sh "$SCRIPT"
chmod +x "$SCRIPT"

cd "$STORAGE/tmp"
bash "$SCRIPT" "$VERSION"
rm -f "$SCRIPT"

[ ! -f "$STORAGE/tmp/$BASE" ] && error "Failed to download $VERSION.iso!" && exit 66

info "Modifying ISO to remove keypress requirement..."

7z x "$BASE" -ounpack
genisoimage -b boot/etfsboot.com -no-emul-boot -c BOOT.CAT -iso-level 4 -J -l -D -N -joliet-long -relaxed-filenames -v -V "Custom" -udf -boot-info-table -eltorito-alt-boot -eltorito-boot efi/microsoft/boot/efisys_noprompt.bin -no-emul-boot -o "$STORAGE/tmp/$BASE.tmp" -allow-limited-size unpack

mv "$STORAGE/tmp/$BASE.tmp" "$STORAGE/$BASE"
rm -rf "$STORAGE/tmp"

cd /run

return 0

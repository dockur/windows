#!/usr/bin/env bash
set -Eeuo pipefail

: "${ATTENDED:="N"}"
: "${VERSION:="win11x64"}"

ARGUMENTS="-chardev socket,id=chrtpm,path=/tmp/emulated_tpm/swtpm-sock $ARGUMENTS"
ARGUMENTS="-tpmdev emulator,id=tpm0,chardev=chrtpm -device tpm-tis,tpmdev=tpm0 $ARGUMENTS"

BASE="$VERSION.iso"
[ -f "$STORAGE/$BASE" ] && return 0

TMP="$STORAGE/tmp"
rm -rf "$TMP"
mkdir -p "$TMP"

if [ -f "$STORAGE/custom.iso" ]; then
  cp "$STORAGE/custom.iso" "$TMP/$BASE"
fi

if [ ! -f "$TMP/$BASE" ]; then

  SCRIPT="$TMP/mido.sh"

  cp /run/mido.sh "$SCRIPT"
  chmod +x "$SCRIPT"
  cd "$TMP"
  bash "$SCRIPT" "$VERSION"
  cd /run
  rm -f "$SCRIPT"

  [ ! -f "$TMP/$BASE" ] && error "Failed to download $VERSION.iso from the Microsoft servers!" && exit 66

fi

info "Preparing ISO image for installation..."

DIR="$TMP/unpack"
7z x "$TMP/$BASE" -o"$DIR"

if [[ "$ATTENDED" != [Yy1]* ]]; then
  if [ -f "/run/assets/$VERSION.xml" ]; then

    wimlib-imagex update $DIR/sources/boot.wim 2 \
      --command "add /run/assets/$VERSION.xml /autounattend.xml"

  fi
fi

genisoimage -b boot/etfsboot.com -no-emul-boot -c BOOT.CAT -iso-level 4 -J -l -D -N -joliet-long -relaxed-filenames \
            -v -V "$VERSION" -udf -boot-info-table -eltorito-alt-boot -eltorito-boot efi/microsoft/boot/efisys_noprompt.bin \
            -no-emul-boot -o "$TMP/$BASE.tmp" -allow-limited-size "$DIR"

mv "$TMP/$BASE.tmp" "$STORAGE/$BASE"
rm -rf "$TMP"

return 0

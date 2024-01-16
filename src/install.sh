#!/usr/bin/env bash
set -Eeuo pipefail

: "${ATTENDED:="N"}"
: "${VERSION:="win11x64"}"

# Display wait message
MSG="Please wait while Windows is being downloaded..."
/run/server.sh "Windows" "$MSG" &

ARGUMENTS="-chardev socket,id=chrtpm,path=/dev/shm/emulated_tpm/swtpm-sock $ARGUMENTS"
ARGUMENTS="-tpmdev emulator,id=tpm0,chardev=chrtpm -device tpm-tis,tpmdev=tpm0 $ARGUMENTS"

BASE="$VERSION.iso"
[ -f "$STORAGE/$BASE" ] && return 0

#if [ -f "$STORAGE/data.qcow2" ]; then
#  error "Cannot download ISO '$VERSION' while there is an existing hard disk file present (data.qcow2)."
#  error "If you are sure that the disk contains nothing important, delete it manually and restart the container."
#  exit 68
#fi

TMP="$STORAGE/tmp"
rm -rf "$TMP" && mkdir -p "$TMP"

if [ -f "$STORAGE/custom.iso" ]; then

  ATTENDED="Y"
  LABEL="Custom"
  cp "$STORAGE/custom.iso" "$TMP/$BASE"

else

  LABEL="$VERSION"

fi

if [ ! -f "$TMP/$BASE" ]; then

  SCRIPT="$TMP/mido.sh"

  rm -f "$SCRIPT"
  cp /run/mido.sh "$SCRIPT"
  chmod +x "$SCRIPT"
  cd "$TMP"
  bash "$SCRIPT" "$VERSION"
  rm -f "$SCRIPT"
  cd /run

  [ ! -f "$TMP/$BASE" ] && error "Failed to download '$VERSION' from the Microsoft servers!" && exit 66

fi

info "Preparing ISO image for installation..."

DIR="$TMP/unpack"
rm -rf "$DIR"

7z x "$TMP/$BASE" -o"$DIR"

if [[ "$ATTENDED" != [Yy1]* ]]; then
  if [ -f "/run/assets/$VERSION.xml" ]; then

    wimlib-imagex update "$DIR/sources/boot.wim" 2 \
      --command "add /run/assets/$VERSION.xml /autounattend.xml"

  fi
fi

OUT="$TMP/$VERSION.tmp"
rm -f "$OUT"

genisoimage -b boot/etfsboot.com -no-emul-boot -c BOOT.CAT -iso-level 4 -J -l -D -N -joliet-long -relaxed-filenames \
            -v -V "$LABEL" -udf -boot-info-table -eltorito-alt-boot -eltorito-boot efi/microsoft/boot/efisys_noprompt.bin \
            -no-emul-boot -o "$OUT" -allow-limited-size "$DIR"

mv "$OUT" "$STORAGE/$BASE"
rm -rf "$TMP"

return 0

#!/usr/bin/env bash
set -Eeuo pipefail

: "${EXTERNAL:="N"}"
: "${ATTENDED:="N"}"
: "${VERSION:="win11x64"}"

ARGUMENTS="-chardev socket,id=chrtpm,path=/dev/shm/emulated_tpm/swtpm-sock $ARGUMENTS"
ARGUMENTS="-tpmdev emulator,id=tpm0,chardev=chrtpm -device tpm-tis,tpmdev=tpm0 $ARGUMENTS"

[[ "${VERSION,,}" == "http"* ]] && EXTERNAL="Y"
MSG="Please wait while Windows is being started..."

if [ ! -f "$STORAGE/custom.iso" ]; then
  if [[ "$EXTERNAL" != [Yy1]* ]]; then

    if [ ! -f "$STORAGE/$VERSION.iso" ]; then
      MSG="Please wait while Windows is being downloaded..."
    fi

  else

    BASE=$(basename "$VERSION")
    if [ ! -f "$STORAGE/$BASE" ]; then
      MSG="Please wait while '$BASE' is being downloaded..."
    fi

  fi
fi

# Display wait message
/run/server.sh "Windows" "$MSG" &

BASE="custom.iso"
[ -f "$STORAGE/$BASE" ] && return 0

BASE="Custom.iso"
[ -f "$STORAGE/$BASE" ] && return 0

BASE="custom.ISO"
[ -f "$STORAGE/$BASE" ] && return 0

BASE="CUSTOM.iso"
[ -f "$STORAGE/$BASE" ] && return 0

BASE="CUSTOM.ISO"
[ -f "$STORAGE/$BASE" ] && return 0

if [[ "$EXTERNAL" != [Yy1]* ]]; then

  BASE="$VERSION.iso"

else

  BASE=$(basename "$VERSION")

fi

[ -f "$STORAGE/$BASE" ] && return 0

TMP="$STORAGE/tmp"
rm -rf "$TMP" && mkdir -p "$TMP"

ISO="$TMP/$BASE"
rm -f "$ISO"

if [[ "$EXTERNAL" != [Yy1]* ]]; then

  SCRIPT="$TMP/mido.sh"

  rm -f "$SCRIPT"
  cp /run/mido.sh "$SCRIPT"
  chmod +x "$SCRIPT"
  cd "$TMP"
  bash "$SCRIPT" "$VERSION"
  rm -f "$SCRIPT"
  cd /run

else

  info "Downloading $BASE as boot image..."

  # Check if running with interactive TTY or redirected to docker log
  if [ -t 1 ]; then
    PROGRESS="--progress=bar:noscroll"
  else
    PROGRESS="--progress=dot:giga"
  fi

  { wget "$VERSION" -O "$ISO" -q --no-check-certificate --show-progress "$PROGRESS"; rc=$?; } || :

  (( rc != 0 )) && error "Failed to download $VERSION, reason: $rc" && exit 60

fi

[ ! -f "$ISO" ] && error "Failed to download $VERSION" && exit 61

SIZE=$(stat -c%s "$ISO")

if ((SIZE<10000000)); then
  error "Invalid ISO file: Size is smaller than 10 MB" && exit 62
fi

info "Preparing ISO image for installation..."

DIR="$TMP/unpack"
rm -rf "$DIR"

7z x "$ISO" -o"$DIR"

if [[ "$ATTENDED" != [Yy1]* ]]; then
  if [[ "$EXTERNAL" != [Yy1]* ]]; then
    if [ -f "/run/assets/$VERSION.xml" ]; then

      wimlib-imagex update "$DIR/sources/boot.wim" 2 \
        --command "add /run/assets/$VERSION.xml /autounattend.xml"

    fi
  fi
fi

LABEL="${BASE%.*}"
ISO="$TMP/$LABEL.tmp"
rm -f "$ISO"

genisoimage -b boot/etfsboot.com -no-emul-boot -c BOOT.CAT -iso-level 4 -J -l -D -N -joliet-long -relaxed-filenames \
            -v -V "$LABEL" -udf -boot-info-table -eltorito-alt-boot -eltorito-boot efi/microsoft/boot/efisys_noprompt.bin \
            -no-emul-boot -o "$ISO" -allow-limited-size "$DIR"

mv "$ISO" "$STORAGE/$BASE"

rm -rf "$TMP"

return 0

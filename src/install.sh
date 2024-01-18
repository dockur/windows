#!/usr/bin/env bash
set -Eeuo pipefail

: "${MANUAL:="N"}"
: "${EXTERNAL:="N"}"
: "${VERSION:="win11x64"}"

ARGUMENTS="-audiodev none,id=snd0 $ARGUMENTS"
ARGUMENTS="-device hda-output,audiodev=snd0 $ARGUMENTS"
ARGUMENTS="-device ich9-intel-hda,bus=pcie.0,addr=0x2 $ARGUMENTS"
ARGUMENTS="-chardev socket,id=chrtpm,path=/dev/shm/emulated_tpm/swtpm-sock $ARGUMENTS"
ARGUMENTS="-tpmdev emulator,id=tpm0,chardev=chrtpm -device tpm-tis,tpmdev=tpm0 $ARGUMENTS"

[[ "${VERSION,,}" == "http"* ]] && EXTERNAL="Y"

[[ "${VERSION,,}" == "11" ]] && VERSION="win11x64"
[[ "${VERSION,,}" == "win11" ]] && VERSION="win11x64"

[[ "${VERSION,,}" == "10" ]] && VERSION="win10x64"
[[ "${VERSION,,}" == "win10" ]] && VERSION="win10x64"

[[ "${VERSION,,}" == "8" ]] && VERSION="win81x64"
[[ "${VERSION,,}" == "81" ]] && VERSION="win81x64"
[[ "${VERSION,,}" == "8.1" ]] && VERSION="win81x64"
[[ "${VERSION,,}" == "win81" ]] && VERSION="win81x64"
[[ "${VERSION,,}" == "win8" ]] && VERSION="win81x64"

[[ "${VERSION,,}" == "22" ]] && VERSION="win2022-eval"
[[ "${VERSION,,}" == "2022" ]] && VERSION="win2022-eval"
[[ "${VERSION,,}" == "win22" ]] && VERSION="win2022-eval"
[[ "${VERSION,,}" == "win2022" ]] && VERSION="win2022-eval"

[[ "${VERSION,,}" == "19" ]] && VERSION="win2019-eval"
[[ "${VERSION,,}" == "2019" ]] && VERSION="win2019-eval"
[[ "${VERSION,,}" == "win19" ]] && VERSION="win2019-eval"
[[ "${VERSION,,}" == "win2019" ]] && VERSION="win2019-eval"

[[ "${VERSION,,}" == "16" ]] && VERSION="win2016-eval"
[[ "${VERSION,,}" == "2016" ]] && VERSION="win2016-eval"
[[ "${VERSION,,}" == "win16" ]] && VERSION="win2016-eval"
[[ "${VERSION,,}" == "win2016" ]] && VERSION="win2016-eval"

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

if [[ "$MANUAL" != [Yy1]* ]]; then
  if [[ "$EXTERNAL" != [Yy1]* ]]; then
    if [ -f "/run/assets/$VERSION.xml" ]; then

      wimlib-imagex update "$DIR/sources/boot.wim" 2 \
        --command "add /run/assets/$VERSION.xml /autounattend.xml"

    fi
  fi
fi

LABEL="${BASE%.*}"
LABEL="${LABEL::32}"

ISO="$TMP/$LABEL.tmp"
rm -f "$ISO"

genisoimage -b boot/etfsboot.com -no-emul-boot -c BOOT.CAT -iso-level 4 -J -l -D -N -joliet-long -relaxed-filenames \
            -v -V "$LABEL" -udf -boot-info-table -eltorito-alt-boot -eltorito-boot efi/microsoft/boot/efisys_noprompt.bin \
            -no-emul-boot -o "$ISO" -allow-limited-size "$DIR"

mv "$ISO" "$STORAGE/$BASE"

rm -rf "$TMP"

return 0

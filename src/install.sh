#!/usr/bin/env bash
set -Eeuo pipefail

: "${MANUAL:=""}"
: "${EXTERNAL:=""}"
: "${VERSION:="win11x64"}"

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

if [[ "${VERSION,,}" == "tiny10" ]]; then
  VERSION="https://archive.org/download/tiny-10-23-h2/tiny10%20x64%2023h2.iso"
fi

if [[ "${VERSION,,}" == "tiny11" ]]; then
  VERSION="https://archive.org/download/tiny-11-core-x-64-beta-1/tiny11%20core%20x64%20beta%201.iso"
fi

if [[ "${VERSION,,}" == "http"* ]]; then
  EXTERNAL="Y"
else
  EXTERNAL="N"
fi

MSG="Please wait while Windows is being started..."

BASE="custom.iso"
if [ ! -f "$STORAGE/$BASE" ]; then

  if [[ "$EXTERNAL" != [Yy1]* ]]; then

    BASE="$VERSION.iso"
    if [ ! -f "$STORAGE/$BASE" ]; then
      MSG="Please wait while Windows is being downloaded..."
    fi

  else

    BASE=$(basename "${VERSION%%\?*}")
    : "${BASE//+/ }"; printf -v BASE '%b' "${_//%/\\x}"
    BASE=$(echo "$BASE" | sed -e 's/[^A-Za-z0-9._-]/_/g')

    if [ ! -f "$STORAGE/$BASE" ]; then
      MSG="Please wait while '$BASE' is being downloaded..."
    fi

  fi
fi

# Display wait message
/run/server.sh "Windows" "$MSG" &

[ -f "$STORAGE/$BASE" ] && return 0

TMP="$STORAGE/tmp"
rm -rf "$TMP"
mkdir -p "$TMP"

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

  (( rc != 0 )) && echo && error "Failed to download $VERSION, reason: $rc" && exit 60

fi

[ ! -f "$ISO" ] && echo && error "Failed to download $VERSION" && exit 61

SIZE=$(stat -c%s "$ISO")

if ((SIZE<10000000)); then
  echo && error "Invalid ISO file: Size is smaller than 10 MB" && exit 62
fi

echo && info "Extracting downloaded ISO image..."

DIR="$TMP/unpack"
rm -rf "$DIR"

7z x "$ISO" -o"$DIR" > /dev/null
echo

XML=""
FB="falling back to manual installation!"

if [ -z "$MANUAL" ]; then

  MANUAL="N"

  if [[ "$EXTERNAL" == [Yy1]* ]]; then
    [[ "${BASE,,}" == "tiny10"* ]] && MANUAL="Y"
  fi

fi

if [[ "$MANUAL" != [Yy1]* ]]; then
  if [[ "$EXTERNAL" != [Yy1]* ]]; then

    XML="$VERSION.xml"

  else

    info "Detecting Windows version from ISO image..."

    LOC="$DIR/sources/install.wim"
    [ ! -f "$LOC" ] && LOC="$DIR/sources/install.esd"

    if [ -f "$LOC" ]; then

      DETECTED=""
      TAG="DISPLAYNAME"
      RESULT=$(wimlib-imagex info -xml "$LOC" | tr -d '\000')
      NAME=$(sed -n "/$TAG/{s/.*<$TAG>\(.*\)<\/$TAG>.*/\1/;p}" <<< "$RESULT")

      if [ -z "$NAME" ]; then
        TAG="PRODUCTNAME"
        NAME=$(sed -n "/$TAG/{s/.*<$TAG>\(.*\)<\/$TAG>.*/\1/;p}" <<< "$RESULT")
      fi

      [[ "${NAME,,}" == "windows 11"* ]] && DETECTED="win11x64"
      [[ "${NAME,,}" == "windows 10"* ]] && DETECTED="win10x64"
      [[ "${NAME,,}" == "windows 8"* ]] && DETECTED="win81x64"
      [[ "${NAME,,}" == *"server 2022"* ]] && DETECTED="win2022-eval"
      [[ "${NAME,,}" == *"server 2019"* ]] && DETECTED="win2019-eval"
      [[ "${NAME,,}" == *"server 2016"* ]] && DETECTED="win2016-eval"

      if [ -n "$DETECTED" ]; then

        XML="$DETECTED.xml"
        echo "Detected image of type '$DETECTED', will apply autounattend.xml file."

      else
        if [ -z "$NAME" ]; then
          error "Warning: failed to detect Windows version from image, $FB"
        else
          if [[ "${NAME,,}" == "windows 7" ]]; then
            error "Warning: detected Windows 7 image, $FB"
          else
            error "Warning: failed to detect Windows version from string '$NAME', $FB"
          fi
        fi
      fi
    else
      error "Warning: failed to locate 'install.wim' or 'install.esd' in ISO image, $FB"
    fi
    echo
  fi
fi

ASSET="/run/assets/$XML"

if [ -f "$ASSET" ]; then

  LOC="$DIR/sources/boot.wim"
  [ ! -f "$LOC" ] && LOC="$DIR/sources/boot.esd"

  if [ -f "$LOC" ]; then

    info "Adding XML file for automatic installation..."

    RESULT=$(wimlib-imagex info -xml "$LOC" | tr -d '\000')

    if [[ "${RESULT^^}" == *"<IMAGE INDEX=\"2\">"* ]]; then
      INDEX="2"
    else
      INDEX="1"
    fi

    wimlib-imagex update "$LOC" "$INDEX" --command "add $ASSET /autounattend.xml" > /dev/null

  else
    error "Warning: failed to locate 'boot.wim' or 'boot.esd' in ISO image, $FB"
  fi

  LOC="$DIR/autounattend.xml"
  [ -f "$LOC" ] && mv -f "$ASSET" "$LOC"
  LOC="$DIR/Autounattend.xml"
  [ -f "$LOC" ] && mv -f "$ASSET" "$LOC"
  LOC="$DIR/AutoUnattend.xml"
  [ -f "$LOC" ] && mv -f "$ASSET" "$LOC"
  LOC="$DIR/autounattend.XML"
  [ -f "$LOC" ] && mv -f "$ASSET" "$LOC"
  LOC="$DIR/Autounattend.XML"
  [ -f "$LOC" ] && mv -f "$ASSET" "$LOC"
  LOC="$DIR/AutoUnattend.XML"
  [ -f "$LOC" ] && mv -f "$ASSET" "$LOC"
  LOC="$DIR/AUTOUNATTEND.xml"
  [ -f "$LOC" ] && mv -f "$ASSET" "$LOC"
  LOC="$DIR/AUTOUNATTEND.XML"
  [ -f "$LOC" ] && mv -f "$ASSET" "$LOC"

  echo

else
  [ -n "$XML" ] && error "Warning: XML file '$XML' does not exist, $FB" && echo
fi

ETFS="boot/etfsboot.com"
EFISYS="efi/microsoft/boot/efisys_noprompt.bin"

if [ -f "$DIR/$ETFS" ]; then
  if [ -f "$DIR/$EFISYS" ]; then

    CAT="BOOT.CAT"
    LABEL="${BASE%.*}"
    LABEL="${LABEL::30}"
    ISO="$TMP/$LABEL.tmp"
    rm -f "$ISO"

    info "Generating new ISO image for installation..."

    genisoimage -b "$ETFS" -no-emul-boot -c "$CAT" -iso-level 4 -J -l -D -N -joliet-long -relaxed-filenames -quiet -V "$LABEL" -udf \
                           -boot-info-table -eltorito-alt-boot -eltorito-boot "$EFISYS" -no-emul-boot -o "$ISO" -allow-limited-size "$DIR"

  else
    error "Failed to locate file 'efisys_noprompt.bin' in ISO image, $FB"
  fi
else
  error "Failed to locate file 'etfsboot.com' in ISO image, $FB"
fi

mv "$ISO" "$STORAGE/$BASE"
rm -rf "$TMP"

echo
return 0

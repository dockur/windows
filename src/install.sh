#!/usr/bin/env bash
set -Eeuo pipefail

: "${MANUAL:=""}"
: "${DETECTED:=""}"
: "${VERSION:="win11x64"}"

if [[ "${VERSION}" == \"*\" || "${VERSION}" == \'*\' ]]; then
  VERSION="${VERSION:1:-1}"
fi

[[ "${VERSION,,}" == "11" ]] && VERSION="win11x64"
[[ "${VERSION,,}" == "win11" ]] && VERSION="win11x64"

[[ "${VERSION,,}" == "10" ]] && VERSION="win10x64"
[[ "${VERSION,,}" == "win10" ]] && VERSION="win10x64"

[[ "${VERSION,,}" == "8" ]] && VERSION="win81x64"
[[ "${VERSION,,}" == "81" ]] && VERSION="win81x64"
[[ "${VERSION,,}" == "8.1" ]] && VERSION="win81x64"
[[ "${VERSION,,}" == "win81" ]] && VERSION="win81x64"
[[ "${VERSION,,}" == "win8" ]] && VERSION="win81x64"

[[ "${VERSION,,}" == "7" ]] && VERSION="win7x64"
[[ "${VERSION,,}" == "win7" ]] && VERSION="win7x64"

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

[[ "${VERSION,,}" == "ltsc10" ]] && VERSION="win10x64-enterprise-ltsc-eval"
[[ "${VERSION,,}" == "10ltsc" ]] && VERSION="win10x64-enterprise-ltsc-eval"
[[ "${VERSION,,}" == "win10-ltsc" ]] && VERSION="win10x64-enterprise-ltsc-eval"
[[ "${VERSION,,}" == "win10x64-ltsc" ]] && VERSION="win10x64-enterprise-ltsc-eval"

if [[ "${VERSION,,}" == "win10x64-enterprise-ltsc-eval" ]]; then
  DETECTED="win10x64-ltsc"
fi

if [[ "${VERSION,,}" == "tiny10" ]]; then
  DETECTED="win10x64-ltsc"
  VERSION="https://archive.org/download/tiny-10-23-h2/tiny10%20x64%2023h2.iso"
fi

if [[ "${VERSION,,}" == "win7x64" ]]; then
  DETECTED="win7x64"
  VERSION="https://dl.bobpony.com/windows/7/en_windows_7_with_sp1_x64.iso"
fi

if [[ "${VERSION,,}" == "tiny11" ]]; then
  DETECTED="win11x64"
  VERSION="https://archive.org/download/tiny-11-core-x-64-beta-1/tiny11%20core%20x64%20beta%201.iso"
fi

CUSTOM="custom.iso"

[ ! -f "$STORAGE/$CUSTOM" ] && CUSTOM="Custom.iso"
[ ! -f "$STORAGE/$CUSTOM" ] && CUSTOM="custom.ISO"
[ ! -f "$STORAGE/$CUSTOM" ] && CUSTOM="CUSTOM.ISO"
[ ! -f "$STORAGE/$CUSTOM" ] && CUSTOM="custom.img"
[ ! -f "$STORAGE/$CUSTOM" ] && CUSTOM="Custom.img"
[ ! -f "$STORAGE/$CUSTOM" ] && CUSTOM="custom.IMG"
[ ! -f "$STORAGE/$CUSTOM" ] && CUSTOM="CUSTOM.IMG"

TMP="$STORAGE/tmp"
DIR="$TMP/unpack"
FB="falling back to manual installation!"
ETFS="boot/etfsboot.com"
EFISYS="efi/microsoft/boot/efisys_noprompt.bin"

replaceXML() {

  local dir="$1"
  local asset="$2"

  local path="$dir/autounattend.xml"
  [ -f "$path" ] && cp "$asset" "$path"
  path="$dir/Autounattend.xml"
  [ -f "$path" ] && cp "$asset" "$path"
  path="$dir/AutoUnattend.xml"
  [ -f "$path" ] && cp "$asset" "$path"
  path="$dir/autounattend.XML"
  [ -f "$path" ] && cp "$asset" "$path"
  path="$dir/Autounattend.XML"
  [ -f "$path" ] && cp "$asset" "$path"
  path="$dir/AutoUnattend.XML"
  [ -f "$path" ] && cp "$asset" "$path"
  path="$dir/AUTOUNATTEND.xml"
  [ -f "$path" ] && cp "$asset" "$path"
  path="$dir/AUTOUNATTEND.XML"
  [ -f "$path" ] && cp "$asset" "$path"

  return 0
}

hasDisk() {

  [ -b "${DEVICE:-}" ] && return 0

  if [ -f "$STORAGE/data.img" ] || [ -f "$STORAGE/data.qcow2" ]; then
    return 0
  fi

  return 1
}

skipInstall() {

  if hasDisk && [ -f "$STORAGE/windows.boot" ]; then
    return 0
  fi

  return 1
}

finishInstall() {

  local iso="$1"

  # Mark ISO as prepared via magic byte
  printf '\x16' | dd of="$iso" bs=1 seek=0 count=1 conv=notrunc status=none

  rm -f "$STORAGE/windows.boot"
  cp /run/version "$STORAGE/windows.ver"

  if [[ "${BOOT_MODE,,}" == "windows_legacy" ]]; then
    touch "$STORAGE/windows.old"
  else
    rm -f "$STORAGE/windows.old"
  fi

  rm -rf "$TMP"
  return 0
}

abortInstall() {

  local iso="$1"

  if [[ "$iso" != "$STORAGE/$BASE" ]]; then
    mv -f "$iso" "$STORAGE/$BASE"
  fi

  finishInstall "$STORAGE/$BASE"
  return 0
}

startInstall() {

  local magic
  local msg="Windows is being started, please wait..."

  if [ -f "$STORAGE/$CUSTOM" ]; then

    EXTERNAL="Y"
    BASE="$CUSTOM"

  else

    CUSTOM=""

    if [[ "${VERSION,,}" == "http"* ]]; then
      EXTERNAL="Y"
    else
      EXTERNAL="N"
    fi

    if [[ "$EXTERNAL" != [Yy1]* ]]; then

      BASE="$VERSION.iso"

      if ! skipInstall && [ ! -f "$STORAGE/$BASE" ]; then
        msg="Windows is being downloaded, please wait..."
      fi

    else

      BASE=$(basename "${VERSION%%\?*}")
      : "${BASE//+/ }"; printf -v BASE '%b' "${_//%/\\x}"
      BASE=$(echo "$BASE" | sed -e 's/[^A-Za-z0-9._-]/_/g')

      if ! skipInstall && [ ! -f "$STORAGE/$BASE" ]; then
        msg="Image '$BASE' is being downloaded, please wait..."
      fi

    fi

    [[ "${BASE,,}" == "custom."* ]] && BASE="windows.iso"

  fi

  html "$msg"

  [ -z "$MANUAL" ] && MANUAL="N"

  if [ -f "$STORAGE/$BASE" ]; then

    # Check if the ISO was already processed by our script
    magic=$(dd if="$STORAGE/$BASE" seek=0 bs=1 count=1 status=none | tr -d '\000')
    magic="$(printf '%s' "$magic" | od -A n -t x1 -v | tr -d ' \n')"

    if [[ "$magic" == "16" ]]; then

      if hasDisk || [[ "$MANUAL" = [Yy1]* ]]; then
        return 1
      fi

    fi

    EXTERNAL="Y"
    CUSTOM="$BASE"

  else

    if skipInstall; then
      BASE=""
      return 1
    fi

  fi

  mkdir -p "$TMP"

  if [ ! -f "$STORAGE/$CUSTOM" ]; then
    CUSTOM=""
    ISO="$TMP/$BASE"
  else
    ISO="$STORAGE/$CUSTOM"
  fi

  rm -f "$TMP/$BASE"
  return 0
}

downloadImage() {

  local iso="$1"
  local url="$2"
  local progress
  rm -f "$iso"

  if [[ "$EXTERNAL" != [Yy1]* ]]; then

    cd "$TMP"
    if ! /run/mido.sh "$url"; then
      return 1
    fi
    cd /run

    [ ! -f "$iso" ] && return 1
    return 0
  fi

  info "Downloading $BASE as boot image..."

  # Check if running with interactive TTY or redirected to docker log
  if [ -t 1 ]; then
    progress="--progress=bar:noscroll"
  else
    progress="--progress=dot:giga"
  fi

  { wget "$url" -O "$iso" -q --no-check-certificate --show-progress "$progress"; rc=$?; } || :
  (( rc != 0 )) && error "Failed to download $url, reason: $rc" && exit 60

  [ ! -f "$iso" ] && return 1
  return 0
}

extractImage() {

  local iso="$1"
  local dir="$2"
  local size size_gb space space_gb

  local msg="Extracting downloaded ISO image..."
  [ -n "$CUSTOM" ] && msg="Extracting local ISO image..."
  info "$msg" && html "$msg"

  size=$(stat -c%s "$iso")
  size_gb=$(( (size + 1073741823)/1073741824 ))
  space=$(df --output=avail -B 1 "$TMP" | tail -n 1)
  space_gb=$(( (space + 1073741823)/1073741824 ))

  if ((size<10000000)); then
    error "Invalid ISO file: Size is smaller than 10 MB" && exit 62
  fi

  if (( size > space )); then
    error "Not enough free space in $STORAGE, have $space_gb GB available but need at least $size_gb GB." && exit 63
  fi

  rm -rf "$dir"

  if ! 7z x "$iso" -o"$dir" > /dev/null; then
    error "Failed to extract ISO file!"
    exit 66
  fi

  return 0
}

findVersion() {

  local name="$1"
  local detected=""

  [[ "${name,,}" == *"windows 11"* ]] && detected="win11x64"
  [[ "${name,,}" == *"windows 8"* ]] && detected="win81x64"
  [[ "${name,,}" == *"windows 7"* ]] && detected="win7x64"
  [[ "${name,,}" == *"windows vista"* ]] && detected="winvistax64"
  [[ "${name,,}" == *"server 2022"* ]] && detected="win2022-eval"
  [[ "${name,,}" == *"server 2019"* ]] && detected="win2019-eval"
  [[ "${name,,}" == *"server 2016"* ]] && detected="win2016-eval"

  if [[ "${name,,}" == *"windows 10"* ]]; then
    if [[ "${name,,}" == *"enterprise ltsc"* ]]; then
      detected="win10x64-ltsc"
    else
      detected="win10x64"
    fi
  fi

  echo "$detected"
  return 0
}

detectImage() {

  XML=""

  if [ -n "$CUSTOM" ]; then
    DETECTED=""
  else
    if [ -z "$DETECTED" ] && [[ "$EXTERNAL" != [Yy1]* ]]; then
      DETECTED="$VERSION"
    fi
  fi

  if [ -n "$DETECTED" ]; then
    if [ -f "/run/assets/$DETECTED.xml" ]; then
      [[ "$MANUAL" != [Yy1]* ]] && XML="$DETECTED.xml"
      return 0
    fi
    warn "image type is '$DETECTED', but no matching XML file exists!"
    return 0
  fi

  info "Detecting Windows version from ISO image..."

  local dir="$1"
  local tag result name name2
  local loc="$dir/sources/install.wim"
  [ ! -f "$loc" ] && loc="$dir/sources/install.esd"

  if [ ! -f "$loc" ]; then
    warn "failed to locate 'install.wim' or 'install.esd' in ISO image, $FB"
    BOOT_MODE="windows_legacy"
    return 1
  fi

  tag="DISPLAYNAME"
  result=$(wimlib-imagex info -xml "$loc" | tr -d '\000')
  name=$(sed -n "/$tag/{s/.*<$tag>\(.*\)<\/$tag>.*/\1/;p}" <<< "$result")
  DETECTED=$(findVersion "$name")

  if [ -z "$DETECTED" ]; then

    tag="PRODUCTNAME"
    name2=$(sed -n "/$tag/{s/.*<$tag>\(.*\)<\/$tag>.*/\1/;p}" <<< "$result")
    [ -z "$name" ] && name="$name2"
    DETECTED=$(findVersion "$name2")

  fi

  if [ -n "$DETECTED" ]; then

    if [ -f "/run/assets/$DETECTED.xml" ]; then
      [[ "$MANUAL" != [Yy1]* ]] && XML="$DETECTED.xml"
      info "Detected image of type: '$DETECTED'"
    else
      warn "detected image of type '$DETECTED', but no matching XML file exists, $FB."
    fi

  else

    if [ -z "$name" ]; then
      warn "failed to determine Windows version from image, $FB"
    else
      warn "failed to determine Windows version from string '$name', $FB"
    fi

  fi
}

prepareImage() {

  local iso="$1"
  local dir="$2"

  if [[ "${BOOT_MODE,,}" == "windows" ]]; then
    if [[ "${DETECTED,,}" != "win7x64"* ]] && [[ "${DETECTED,,}" != "winvistax64"* ]]; then

      if [ -f "$dir/$ETFS" ] && [ -f "$dir/$EFISYS" ]; then
        return 0
      fi

      if [ ! -f "$dir/$ETFS" ]; then
        warn "failed to locate file 'etfsboot.com' in ISO image, falling back to legacy boot!"
      else
        warn "failed to locate file 'efisys_noprompt.bin' in ISO image, falling back to legacy boot!"
      fi

    fi
  fi

  ETFS="boot.img"
  BOOT_MODE="windows_legacy"

  local len offset
  len=$(isoinfo -d -i "$iso" | grep "Nsect " | grep -o "[^ ]*$")
  offset=$(isoinfo -d -i "$iso" | grep "Bootoff " | grep -o "[^ ]*$")

  if ! dd "if=$iso" "of=$dir/$ETFS" bs=2048 "count=$len" "skip=$offset" status=none; then
    error "Failed to extract boot image from ISO!"
    exit 67
  fi

  return 0
}

updateImage() {

  local iso="$1"
  local dir="$2"
  local asset="/run/assets/$3"
  local index result

  [ ! -f "$asset" ] && return 0
  replaceXML "$dir" "$asset"

  local loc="$dir/sources/boot.wim"
  [ ! -f "$loc" ] && loc="$dir/sources/boot.esd"

  if [ ! -f "$loc" ]; then
    warn "failed to locate 'boot.wim' or 'boot.esd' in ISO image, $FB"
    BOOT_MODE="windows_legacy"
    return 1
  fi

  info "Adding XML file for automatic installation..."

  index="1"
  result=$(wimlib-imagex info -xml "$loc" | tr -d '\000')

  if [[ "${result^^}" == *"<IMAGE INDEX=\"2\">"* ]]; then
    index="2"
  fi

  if ! wimlib-imagex update "$loc" "$index" --command "add $asset /autounattend.xml" > /dev/null; then
    warn "failed to add XML to ISO image, $FB"
    return 1
  fi

  return 0
}

buildImage() {

  local dir="$1"
  local cat="BOOT.CAT"
  local label="${BASE%.*}"
  local log="/run/shm/iso.log"
  local size size_gb space space_gb

  label="${label::30}"
  local out="$TMP/$label.tmp"
  rm -f "$out"

  local msg="Updating ISO image..."
  info "$msg" && html "$msg"

  size=$(du -h -b --max-depth=0 "$dir" | cut -f1)
  size_gb=$(( (size + 1073741823)/1073741824 ))
  space=$(df --output=avail -B 1 "$TMP" | tail -n 1)
  space_gb=$(( (space + 1073741823)/1073741824 ))

  if (( size > space )); then
    error "Not enough free space in $STORAGE, have $space_gb GB available but need at least $size_gb GB."
    return 1
  fi

  if [[ "${BOOT_MODE,,}" != "windows_legacy" ]]; then

    if ! genisoimage -o "$out" -b "$ETFS" -no-emul-boot -c "$cat" -iso-level 4 -J -l -D -N -joliet-long -relaxed-filenames -V "$label" \
                     -udf -boot-info-table -eltorito-alt-boot -eltorito-boot "$EFISYS" -no-emul-boot -allow-limited-size -quiet "$dir" 2> "$log"; then
      [ -f "$log" ] && echo "$(<"$log")"
      return 1
    fi

  else

    if !  genisoimage -o "$out" -b "$ETFS" -no-emul-boot -c "$cat" -iso-level 2 -J -l -D -N -joliet-long -relaxed-filenames -V "$label" \
                      -udf -allow-limited-size -quiet "$dir" 2> "$log"; then
      [ -f "$log" ] && echo "$(<"$log")"
      return 1
    fi

  fi

  local error=""
  local hide="Warning: creating filesystem that does not conform to ISO-9660."

  [ -f "$log" ] && error="$(<"$log")"
  [[ "$error" != "$hide" ]] && echo "$error"

  if [ -f "$STORAGE/$BASE" ]; then
    error "File $STORAGE/$BASE does already exist?!"
    return 1
  fi

  mv "$out" "$STORAGE/$BASE"
  return 0
}

######################################

if ! startInstall; then

  if [ -f "$STORAGE/windows.old" ]; then
    BOOT_MODE="windows_legacy"
  fi

  rm -rf "$TMP"
  return 0
fi

if [ ! -f "$ISO" ]; then
  if ! downloadImage "$ISO" "$VERSION"; then
    error "Failed to download $VERSION"
    exit 61
  fi
fi

if ! extractImage "$ISO" "$DIR"; then
  abortInstall "$ISO"
  return 0
fi

if ! detectImage "$DIR"; then
  abortInstall "$ISO"
  return 0
fi

if ! prepareImage "$ISO" "$DIR"; then
  abortInstall "$ISO"
  return 0
fi

if ! updateImage "$ISO" "$DIR" "$XML"; then
  abortInstall "$ISO"
  return 0
fi

rm -f "$ISO"

if ! buildImage "$DIR"; then
  error "Failed to build image!"
  exit 65
fi

finishInstall "$STORAGE/$BASE"

html "Successfully prepared image for installation..."
return 0

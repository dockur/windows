#!/usr/bin/env bash
set -Eeuo pipefail

: "${MANUAL:=""}"
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
    touch "$STORAGE/windows.bios"
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
    /run/mido.sh "$url"
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
  7z x "$iso" -o"$dir" > /dev/null

  if [ ! -f "$dir/$ETFS" ] || [ ! -f "$dir/$EFISYS" ]; then

    if [ ! -f "$dir/$ETFS" ]; then
      warn "failed to locate file 'etfsboot.com' in ISO image, $FB"
    else
      warn "failed to locate file 'efisys_noprompt.bin' in ISO image, $FB"
    fi

    BOOT_MODE="windows_legacy"
    return 1
  fi

  return 0
}

findVersion() {

  local name="$1"
  local detected=""

  [[ "${name,,}" == *"windows 11"* ]] && detected="win11x64"
  [[ "${name,,}" == *"windows 10"* ]] && detected="win10x64"
  [[ "${name,,}" == *"windows 8"* ]] && detected="win81x64"
  [[ "${name,,}" == *"server 2022"* ]] && detected="win2022-eval"
  [[ "${name,,}" == *"server 2019"* ]] && detected="win2019-eval"
  [[ "${name,,}" == *"server 2016"* ]] && detected="win2016-eval"

  echo "$detected"
  return 0
}

selectXML() {

  local dir="$1"
  local tag result name name2 detected

  XML=""
  [[ "$MANUAL" == [Yy1]* ]] && return 0

  if [[ "$EXTERNAL" != [Yy1]* ]] && [ -z "$CUSTOM" ]; then
    XML="$VERSION.xml"
    [ -f "/run/assets/$XML" ] && return 0
  fi

  info "Detecting Windows version from ISO image..."

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
  detected=$(findVersion "$name")

  if [ -z "$detected" ]; then

    tag="PRODUCTNAME"
    name2=$(sed -n "/$tag/{s/.*<$tag>\(.*\)<\/$tag>.*/\1/;p}" <<< "$result")
    [ -z "$name" ] && name="$name2"
    detected=$(findVersion "$name2")

  fi

  if [ -n "$detected" ]; then

    if [ -f "/run/assets/$detected.xml" ]; then
      XML="$detected.xml"
      echo "Detected image of type '$detected', which supports automatic installation."
    else
      warn "detected image of type '$detected', but no matching XML file exists, $FB."
    fi

  else

    if [ -z "$name" ]; then
      warn "failed to detect Windows version from image, $FB"
    else
      if [[ "${name,,}" == "windows 7" ]]; then
        BOOT_MODE="windows_legacy"
        warn "detected Windows 7 image, $FB"
        return 1
      else
        warn "failed to detect Windows version from string '$name', $FB"
      fi
    fi

  fi

  return 0
}

updateImage() {

  local dir="$1"
  local asset="$2"
  local index result

  [ ! -f "$asset" ] && return 0
  replaceXML "$dir" "$asset"

  local loc="$dir/sources/boot.wim"
  [ ! -f "$loc" ] && loc="$dir/sources/boot.esd"

  if [ ! -f "$loc" ]; then
    warn "failed to locate 'boot.wim' or 'boot.esd' in ISO image, $FB"
    return 1
  fi

  info "Adding XML file for automatic installation..."

  index="1"
  result=$(wimlib-imagex info -xml "$loc" | tr -d '\000')

  if [[ "${result^^}" == *"<IMAGE INDEX=\"2\">"* ]]; then
    index="2"
  fi

  wimlib-imagex update "$loc" "$index" --command "add $asset /autounattend.xml" > /dev/null

  return 0
}

buildImage() {

  local dir="$1"
  local cat="BOOT.CAT"
  local label="${BASE%.*}"
  local size size_gb space space_gb

  label="${label::30}"
  local out="$TMP/$label.tmp"
  rm -f "$out"

  local msg="Generating updated ISO image..."
  info "$msg" && html "$msg"

  size=$(du -h -b --max-depth=0 "$dir" | cut -f1)
  size_gb=$(( (size + 1073741823)/1073741824 ))
  space=$(df --output=avail -B 1 "$TMP" | tail -n 1)
  space_gb=$(( (space + 1073741823)/1073741824 ))

  if (( size > space )); then
    error "Not enough free space in $STORAGE, have $space_gb GB available but need at least $size_gb GB." && exit 63
  fi

  genisoimage -b "$ETFS" -no-emul-boot -c "$cat" -iso-level 4 -J -l -D -N -joliet-long -relaxed-filenames -quiet -V "$label" -udf \
                         -boot-info-table -eltorito-alt-boot -eltorito-boot "$EFISYS" -no-emul-boot -o "$out" -allow-limited-size "$dir"

  if [ -f "$STORAGE/$BASE" ]; then
    error "File $STORAGE/$BASE does already exist?!" && exit 64
  fi

  mv "$out" "$STORAGE/$BASE"
  return 0
}

######################################

if ! startInstall; then

  if [ -f "$STORAGE/windows.bios" ]; then
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

if ! selectXML "$DIR"; then
  abortInstall "$ISO"
  return 0
fi

if ! updateImage "$DIR" "/run/assets/$XML"; then
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

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
[[ "${VERSION,,}" == "win8" ]] && VERSION="win81x64"
[[ "${VERSION,,}" == "win81" ]] && VERSION="win81x64"

[[ "${VERSION,,}" == "7" ]] && VERSION="win7x64"
[[ "${VERSION,,}" == "win7" ]] && VERSION="win7x64"

[[ "${VERSION,,}" == "vista" ]] && VERSION="winvistax64"
[[ "${VERSION,,}" == "winvista" ]] && VERSION="winvistax64"

[[ "${VERSION,,}" == "xp" ]] && VERSION="winxpx86"
[[ "${VERSION,,}" == "winxp" ]] && VERSION="winxpx86"

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

[[ "${VERSION,,}" == "2012" ]] && VERSION="win2012r2-eval"
[[ "${VERSION,,}" == "win2012" ]] && VERSION="win2012r2-eval"

[[ "${VERSION,,}" == "2008" ]] && VERSION="win2008r2"
[[ "${VERSION,,}" == "win2008" ]] && VERSION="win2008r2"

[[ "${VERSION,,}" == "ltsc10" ]] && VERSION="win10x64-enterprise-ltsc-eval"
[[ "${VERSION,,}" == "10ltsc" ]] && VERSION="win10x64-enterprise-ltsc-eval"
[[ "${VERSION,,}" == "win10-ltsc" ]] && VERSION="win10x64-enterprise-ltsc-eval"
[[ "${VERSION,,}" == "win10x64-ltsc" ]] && VERSION="win10x64-enterprise-ltsc-eval"

if [[ "${VERSION,,}" == "win10x64-enterprise-ltsc-eval" ]]; then
  DETECTED="win10x64-ltsc"
fi

if [[ "${VERSION,,}" == "win7x64" ]]; then
  DETECTED="win7x64"
  VERSION="https://dl.bobpony.com/windows/7/en_windows_7_enterprise_with_sp1_x64_dvd_u_677651.iso"
fi

if [[ "${VERSION,,}" == "winvistax64" ]]; then
  DETECTED="winvistax64"
  VERSION="https://dl.bobpony.com/windows/vista/en_windows_vista_sp2_x64_dvd_342267.iso"
fi

if [[ "${VERSION,,}" == "winxpx86" ]]; then
  DETECTED="winxpx86"
  VERSION="https://dl.bobpony.com/windows/xp/professional/en_windows_xp_professional_with_service_pack_3_x86_cd_vl_x14-73974.iso"
fi

if [[ "${VERSION,,}" == "core11" ]]; then
  DETECTED="win11x64"
  VERSION="https://archive.org/download/tiny-11-core-x-64-beta-1/tiny11%20core%20x64%20beta%201.iso"
fi

if [[ "${VERSION,,}" == "tiny11" ]]; then
  DETECTED="win11x64"
  VERSION="https://archive.org/download/tiny11-2311/tiny11%202311%20x64.iso"
fi

if [[ "${VERSION,,}" == "tiny10" ]]; then
  DETECTED="win10x64-ltsc"
  VERSION="https://archive.org/download/tiny-10-23-h2/tiny10%20x64%2023h2.iso"
fi

CUSTOM="custom.iso"

[ ! -f "$STORAGE/$CUSTOM" ] && CUSTOM="Custom.iso"
[ ! -f "$STORAGE/$CUSTOM" ] && CUSTOM="custom.ISO"
[ ! -f "$STORAGE/$CUSTOM" ] && CUSTOM="CUSTOM.ISO"
[ ! -f "$STORAGE/$CUSTOM" ] && CUSTOM="custom.img"
[ ! -f "$STORAGE/$CUSTOM" ] && CUSTOM="Custom.img"
[ ! -f "$STORAGE/$CUSTOM" ] && CUSTOM="custom.IMG"
[ ! -f "$STORAGE/$CUSTOM" ] && CUSTOM="CUSTOM.IMG"

ESD_URL=""
MACHINE="q35"
TMP="$STORAGE/tmp"
DIR="$TMP/unpack"
FB="falling back to manual installation!"
ETFS="boot/etfsboot.com"
EFISYS="efi/microsoft/boot/efisys_noprompt.bin"

printVersion() {

  local id="$1"
  local desc=""

  [[ "$id" == "win7"* ]] && desc="Windows 7"
  [[ "$id" == "win8"* ]] && desc="Windows 8"
  [[ "$id" == "win10"* ]] && desc="Windows 10"
  [[ "$id" == "win11"* ]] && desc="Windows 11"
  [[ "$id" == "winxp"* ]] && desc="Windows XP"
  [[ "$id" == "winvista"* ]] && desc="Windows Vista"
  [[ "$id" == "win2025"* ]] && desc="Windows Server 2025"
  [[ "$id" == "win2022"* ]] && desc="Windows Server 2022"
  [[ "$id" == "win2019"* ]] && desc="Windows Server 2019"
  [[ "$id" == "win2016"* ]] && desc="Windows Server 2016"
  [[ "$id" == "win2012"* ]] && desc="Windows Server 2012"
  [[ "$id" == "win2008"* ]] && desc="Windows Server 2008"
  [[ "$id" == "win10x64-ltsc" ]] && desc="Windows 10 LTSC"

  echo "$desc"
  return 0
}

getName() {

  local file="$1"
  local desc=""

  [[ "${file,,}" == "win11"* ]] && desc="Windows 11"
  [[ "${file,,}" == "win10"* ]] && desc="Windows 10"
  [[ "${file,,}" == "win8.1"* ]] && desc="Windows 8"
  [[ "${file,,}" == "win8"* ]] && desc="Windows 8"
  [[ "${file,,}" == "win7"* ]] && desc="Windows 7"
  [[ "${file,,}" == "winxp"* ]] && desc="Windows XP"
  [[ "${file,,}" == "winvista"* ]] && desc="Windows Vista"
  [[ "${file,,}" == "tiny10"* ]] && desc="Tiny 10"
  [[ "${file,,}" == "tiny11"* ]] && desc="Tiny 11"
  [[ "${file,,}" == "tiny11_core"* ]] && desc="Tiny 11 Core"
  [[ "${file,,}" == *"windows11"* ]] && desc="Windows 11"
  [[ "${file,,}" == *"windows10"* ]] && desc="Windows 10"
  [[ "${file,,}" == *"windows8.1"* ]] && desc="Windows 8"
  [[ "${file,,}" == *"windows8"* ]] && desc="Windows 8"
  [[ "${file,,}" == *"windows7"* ]] && desc="Windows 7"
  [[ "${file,,}" == *"windowsxp"* ]] && desc="Windows XP"
  [[ "${file,,}" == *"windowsvista"* ]] && desc="Windows Vista"
  [[ "${file,,}" == *"windows_11"* ]] && desc="Windows 11"
  [[ "${file,,}" == *"windows_10"* ]] && desc="Windows 10"
  [[ "${file,,}" == *"windows_8.1"* ]] && desc="Windows 8"
  [[ "${file,,}" == *"windows_8"* ]] && desc="Windows 8"
  [[ "${file,,}" == *"windows_7"* ]] && desc="Windows 7"
  [[ "${file,,}" == *"windows_xp"* ]] && desc="Windows XP"
  [[ "${file,,}" == *"windows_vista"* ]] && desc="Windows Vista"
  [[ "${file,,}" == *"server2008"* ]] && desc="Windows Server 2008"
  [[ "${file,,}" == *"server2012"* ]] && desc="Windows Server 2012"
  [[ "${file,,}" == *"server2016"* ]] && desc="Windows Server 2016"
  [[ "${file,,}" == *"server2019"* ]] && desc="Windows Server 2019"
  [[ "${file,,}" == *"server2022"* ]] && desc="Windows Server 2022"
  [[ "${file,,}" == *"server2025"* ]] && desc="Windows Server 2025"
  [[ "${file,,}" == *"server_2008"* ]] && desc="Windows Server 2008"
  [[ "${file,,}" == *"server_2012"* ]] && desc="Windows Server 2012"
  [[ "${file,,}" == *"server_2016"* ]] && desc="Windows Server 2016"
  [[ "${file,,}" == *"server_2019"* ]] && desc="Windows Server 2019"
  [[ "${file,,}" == *"server_2022"* ]] && desc="Windows Server 2022"
  [[ "${file,,}" == *"server_2025"* ]] && desc="Windows Server 2025"

  echo "$desc"
  return 0
}

getVersion() {

  local name="$1"
  local detected=""

  [[ "${name,,}" == *"windows 7"* ]] && detected="win7x64"
  [[ "${name,,}" == *"windows 8"* ]] && detected="win81x64"
  [[ "${name,,}" == *"windows 11"* ]] && detected="win11x64"
  [[ "${name,,}" == *"windows vista"* ]] && detected="winvistax64"
  [[ "${name,,}" == *"server 2025"* ]] && detected="win2025-eval"
  [[ "${name,,}" == *"server 2022"* ]] && detected="win2022-eval"
  [[ "${name,,}" == *"server 2019"* ]] && detected="win2019-eval"
  [[ "${name,,}" == *"server 2016"* ]] && detected="win2016-eval"
  [[ "${name,,}" == *"server 2012"* ]] && detected="win2012r2-eval"
  [[ "${name,,}" == *"server 2008"* ]] && detected="win2008r2"

  if [[ "${name,,}" == *"windows 10"* ]]; then
    if [[ "${name,,}" == *"ltsc"* ]]; then
      detected="win10x64-ltsc"
    else
      detected="win10x64"
    fi
  fi

  echo "$detected"
  return 0
}

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
    echo "$MACHINE" > "$STORAGE/windows.old"
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

  html "Starting Windows..."

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

    else

      BASE=$(basename "${VERSION%%\?*}")
      : "${BASE//+/ }"; printf -v BASE '%b' "${_//%/\\x}"
      BASE=$(echo "$BASE" | sed -e 's/[^A-Za-z0-9._-]/_/g')

    fi

    [[ "${BASE,,}" == "custom."* ]] && BASE="windows.iso"

  fi

  [ -z "$MANUAL" ] && MANUAL="N"

  if [ -f "$STORAGE/$BASE" ]; then

    # Check if the ISO was already processed by our script
    local magic=""
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

getESD() {

  local dir="$1"
  local file="$2"
  local architecture="x64"
  local winCatalog size

  case "${VERSION,,}" in
    win11x64)
      winCatalog="https://go.microsoft.com/fwlink?linkid=2156292"
      ;;
    win10x64)
      winCatalog="https://go.microsoft.com/fwlink/?LinkId=841361"
      ;;
    *)
      error "Invalid ESD version specified: $VERSION"
      return 1
      ;;
  esac

  local msg="Downloading product information from Microsoft..."
  info "$msg" && html "$msg"

  rm -rf "$dir"
  mkdir -p "$dir"

  local wFile="catalog.cab"

  { wget "$winCatalog" -O "$dir/$wFile" -q --no-check-certificate; rc=$?; } || :
  (( rc != 0 )) && error "Failed to download $winCatalog , reason: $rc" && return 1

  cd "$dir"

  if ! cabextract "$wFile" > /dev/null; then
    cd /run
    error "Failed to extract CAB file!" && return 1
  fi

  cd /run

  if [ ! -f "$dir/products.xml" ]; then
    error "Failed to find products.xml!" && return 1
  fi

  local esdLang="en-us"
  local editionName="Professional"
  local edQuery='//File[Architecture="'${architecture}'"][Edition="'${editionName}'"]'

  echo -e '<Catalog>' > "${dir}/products_filter.xml"
  xmllint --nonet --xpath "${edQuery}" "${dir}/products.xml" >> "${dir}/products_filter.xml" 2>/dev/null
  echo -e '</Catalog>'>> "${dir}/products_filter.xml"
  xmllint --nonet --xpath '//File[LanguageCode="'${esdLang}'"]' "${dir}/products_filter.xml" >"${dir}/esd_edition.xml"

  size=$(stat -c%s "${dir}/esd_edition.xml")
  if ((size<20)); then
    error "Failed to find Windows product!" && return 1
  fi

  ESD_URL=$(xmllint --nonet --xpath '//FilePath' "${dir}/esd_edition.xml" | sed -E -e 's/<[\/]?FilePath>//g')

  if [ -z "$ESD_URL" ]; then
    error "Failed to find ESD url!" && return 1
  fi

  rm -rf "$dir"
  return 0
}

downloadImage() {

  local iso="$1"
  local url="$2"
  local file="$iso"
  local desc rc progress

  rm -f "$iso"

  if [[ "$EXTERNAL" != [Yy1]* ]]; then

    file="$iso.PART"
    desc=$(printVersion "$VERSION")
    [ -z "$desc" ] && desc="Windows"

  else

    desc=$(getName "$BASE")
    [ -z "$desc" ] && desc="$BASE"

  fi

  local msg="Downloading $desc..."
  info "$msg" && html "$msg"
  /run/progress.sh "$file" "Downloading $desc ([P])..." &

  if [[ "$EXTERNAL" != [Yy1]* ]]; then

    cd "$TMP"
    { /run/mido.sh "$url"; rc=$?; } || :
    cd /run

    fKill "progress.sh"

    if (( rc == 0 )); then

      [ ! -f "$iso" ] && return 1

      html "Download finished successfully..."
      return 0
    fi

    if [[ "$VERSION" != "win10x64"* ]] && [[ "$VERSION" != "win11x64" ]]; then
      return 1
    fi

    info "Failed to download $desc using Mido, will try a different method now..."

    ISO="$TMP/$VERSION.esd"
    iso="$ISO"
    file="$ISO"
    rm -f "$iso"

    if ! getESD "$TMP/esd" "$iso"; then
      return 1
    fi

    url="$ESD_URL"
    msg="Downloading $desc..."
    info "$msg" && html "$msg"
    /run/progress.sh "$iso" "Downloading $desc ([P])..." &

  fi

  # Check if running with interactive TTY or redirected to docker log
  if [ -t 1 ]; then
    progress="--progress=bar:noscroll"
  else
    progress="--progress=dot:giga"
  fi

  { wget "$url" -O "$iso" -q --no-check-certificate --show-progress "$progress"; rc=$?; } || :

  fKill "progress.sh"
  (( rc != 0 )) && error "Failed to download $url , reason: $rc" && exit 60

  [ ! -f "$iso" ] && return 1

  html "Download finished successfully..."
  return 0
}

extractESD() {

  local iso="$1"
  local dir="$2"
  local size size_gb space space_gb desc

  desc=$(printVersion "$VERSION")
  local msg="Extracting $desc bootdisk..."
  info "$msg" && html "$msg"

  size=16106127360
  size_gb=$(( (size + 1073741823)/1073741824 ))
  space=$(df --output=avail -B 1 "$TMP" | tail -n 1)
  space_gb=$(( (space + 1073741823)/1073741824 ))

  if ((size<10000000)); then
    error "Invalid ESD file: Size is smaller than 10 MB" && exit 62
  fi

  if (( size > space )); then
    error "Not enough free space in $STORAGE, have $space_gb GB available but need at least $size_gb GB." && exit 63
  fi

  rm -rf "$dir"
  mkdir -p "$dir"

  local esdImageCount
  esdImageCount=$(wimlib-imagex info "${iso}" | awk '/Image Count:/ {print $3}')

  wimlib-imagex apply "$iso" 1 "${dir}" --quiet 2>/dev/null || {
    retVal=$?
    error "Extracting bootdisk failed" && return $retVal
  }

  local bootWimFile="${dir}/sources/boot.wim"
  local installWimFile="${dir}/sources/install.wim"

  local msg="Extracting $desc environment..."
  info "$msg" && html "$msg"

  wimlib-imagex export "${iso}" 2 "${bootWimFile}" --compress=LZX --chunk-size 32K --quiet || {
    retVal=$?
    error "Adding WinPE failed" && return ${retVal}
  }

  local msg="Extracting $desc setup..."
  info "$msg" && html "$msg"

  wimlib-imagex export "${iso}" 3 "$bootWimFile" --compress=LZX --chunk-size 32K --boot --quiet || {
   retVal=$?
   error "Adding Windows Setup failed" && return ${retVal}
  }

  local msg="Extracting $desc image..."
  info "$msg" && html "$msg"

  local edition imageIndex imageEdition

  case "${VERSION,,}" in
    win11x64)
      edition="11 pro"
      ;;
    win10x64)
      edition="10 pro"
      ;;
    *)
      error "Invalid version specified: $VERSION"
      return 1
      ;;
  esac

  for (( imageIndex=4; imageIndex<=esdImageCount; imageIndex++ )); do
    imageEdition=$(wimlib-imagex info "${iso}" ${imageIndex} | grep '^Description:' | sed 's/Description:[ \t]*//')
    [[ "${imageEdition,,}" != *"$edition"* ]] && continue
    wimlib-imagex export "${iso}" ${imageIndex} "${installWimFile}" --compress=LZMS --chunk-size 128K --quiet || {
      retVal=$?
      error "Addition of ${imageIndex} to the image failed" && return $retVal
    }
    return 0
  done

  error "Failed to find product in install.wim!"
  return 1
}

extractImage() {

  local iso="$1"
  local dir="$2"
  local desc="downloaded ISO"
  local size size_gb space space_gb

  if [[ "${iso,,}" == *".esd" ]]; then
    if ! extractESD "$iso" "$dir"; then
      error "Failed to extract ESD file!"
      exit 67
    fi
    return 0
  fi

  if [[ "$EXTERNAL" != [Yy1]* ]] && [ -z "$CUSTOM" ]; then
    desc=$(printVersion "$VERSION")
    [ -z "$desc" ] && desc="downloaded ISO"
  fi

  local msg="Extracting $desc image..."
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

detectImage() {

  XML=""
  local dir="$1"

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

    if [[ "${DETECTED,,}" != "winxp"* ]]; then

      local dsc
      dsc=$(printVersion "$DETECTED")
      [ -z "$dsc" ] && dsc="$DETECTED"

      warn "got $dsc, but no matching XML file exists, $FB."
    fi

    return 0
  fi

  info "Detecting Windows version from ISO image..."

  if [ -f "$dir/WIN51" ] || [ -f "$dir/SETUPXP.HTM" ]; then
    DETECTED="winxpx86"
    info "Detected: Windows XP"
    return 0
  fi

  local tag result name name2 desc
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
  DETECTED=$(getVersion "$name")

  if [ -z "$DETECTED" ]; then

    tag="PRODUCTNAME"
    name2=$(sed -n "/$tag/{s/.*<$tag>\(.*\)<\/$tag>.*/\1/;p}" <<< "$result")
    [ -z "$name" ] && name="$name2"
    DETECTED=$(getVersion "$name2")

  fi

  if [ -z "$DETECTED" ]; then
    warn "failed to determine Windows version from string '$name', $FB"
    return 0
  fi

  desc=$(printVersion "$DETECTED")
  [ -z "$desc" ] && desc="$DETECTED"

  if [ -f "/run/assets/$DETECTED.xml" ]; then
    [[ "$MANUAL" != [Yy1]* ]] && XML="$DETECTED.xml"
    info "Detected: $desc"
  else
    warn "detected $desc, but no matching XML file exists, $FB."
  fi

  return 0
}

prepareXP() {

  local iso="$1"
  local dir="$2"
  local arch="x86"
  local target="$dir/I386"

  if [ -d "$dir/AMD64" ]; then
    arch="amd64"
    target="$dir/AMD64"
  fi

  MACHINE="pc-q35-2.10"
  BOOT_MODE="windows_legacy"
  ETFS="[BOOT]/Boot-NoEmul.img"

  [[ "$MANUAL" == [Yy1]* ]] && return 0

  local drivers="$TMP/drivers"
  rm -rf "$drivers"

  if ! 7z x /run/drivers.iso -o"$drivers" > /dev/null; then
    error "Failed to extract driver ISO file!"
    exit 66
  fi

  cp "$drivers/viostor/xp/$arch/viostor.sys" "$target"

  mkdir -p "$dir/\$OEM\$/\$1/Drivers/viostor"
  cp "$drivers/viostor/xp/$arch/viostor.cat" "$dir/\$OEM\$/\$1/Drivers/viostor"
  cp "$drivers/viostor/xp/$arch/viostor.inf" "$dir/\$OEM\$/\$1/Drivers/viostor"
  cp "$drivers/viostor/xp/$arch/viostor.sys" "$dir/\$OEM\$/\$1/Drivers/viostor"

  mkdir -p "$dir/\$OEM\$/\$1/Drivers/NetKVM"
  cp "$drivers/NetKVM/xp/$arch/netkvm.cat" "$dir/\$OEM\$/\$1/Drivers/NetKVM"
  cp "$drivers/NetKVM/xp/$arch/netkvm.inf" "$dir/\$OEM\$/\$1/Drivers/NetKVM"
  cp "$drivers/NetKVM/xp/$arch/netkvm.sys" "$dir/\$OEM\$/\$1/Drivers/NetKVM"

  sed -i '/^\[SCSI.Load\]/s/$/\nviostor=viostor.sys,4/' "$target/TXTSETUP.SIF"
  sed -i '/^\[SourceDisksFiles.'"$arch"'\]/s/$/\nviostor.sys=1,,,,,,4_,4,1,,,1,4/' "$target/TXTSETUP.SIF"
  sed -i '/^\[SCSI\]/s/$/\nviostor=\"Red Hat VirtIO SCSI Disk Device\"/' "$target/TXTSETUP.SIF"
  sed -i '/^\[HardwareIdsDatabase\]/s/$/\nPCI\\VEN_1AF4\&DEV_1001\&SUBSYS_00000000=\"viostor\"/' "$target/TXTSETUP.SIF"
  sed -i '/^\[HardwareIdsDatabase\]/s/$/\nPCI\\VEN_1AF4\&DEV_1001\&SUBSYS_00020000=\"viostor\"/' "$target/TXTSETUP.SIF"
  sed -i '/^\[HardwareIdsDatabase\]/s/$/\nPCI\\VEN_1AF4\&DEV_1001\&SUBSYS_00021AF4=\"viostor\"/' "$target/TXTSETUP.SIF"
  sed -i '/^\[HardwareIdsDatabase\]/s/$/\nPCI\\VEN_1AF4\&DEV_1001\&SUBSYS_00000000=\"viostor\"/' "$target/TXTSETUP.SIF"

  mkdir -p "$dir/\$OEM\$/\$1/Drivers/sata"

  cp -a "$drivers/sata/xp/$arch/." "$dir/\$OEM\$/\$1/Drivers/sata"
  cp -a "$drivers/sata/xp/$arch/." "$target"

  sed -i '/^\[SCSI.Load\]/s/$/\niaStor=iaStor.sys,4/' "$target/TXTSETUP.SIF"
  sed -i '/^\[FileFlags\]/s/$/\niaStor.sys = 16/' "$target/TXTSETUP.SIF"
  sed -i '/^\[SourceDisksFiles.'"$arch"'\]/s/$/\niaStor.cat = 1,,,,,,,1,0,0/' "$target/TXTSETUP.SIF"
  sed -i '/^\[SourceDisksFiles.'"$arch"'\]/s/$/\niaStor.inf = 1,,,,,,,1,0,0/' "$target/TXTSETUP.SIF"
  sed -i '/^\[SourceDisksFiles.'"$arch"'\]/s/$/\niaStor.sys = 1,,,,,,4_,4,1,,,1,4/' "$target/TXTSETUP.SIF"
  sed -i '/^\[SourceDisksFiles.'"$arch"'\]/s/$/\niaStor.sys = 1,,,,,,,1,0,0/' "$target/TXTSETUP.SIF"
  sed -i '/^\[SourceDisksFiles.'"$arch"'\]/s/$/\niaahci.cat = 1,,,,,,,1,0,0/' "$target/TXTSETUP.SIF"
  sed -i '/^\[SourceDisksFiles.'"$arch"'\]/s/$/\niaAHCI.inf = 1,,,,,,,1,0,0/' "$target/TXTSETUP.SIF"
  sed -i '/^\[SCSI\]/s/$/\niaStor=\"Intel\(R\) SATA RAID\/AHCI Controller\"/' "$target/TXTSETUP.SIF"
  sed -i '/^\[HardwareIdsDatabase\]/s/$/\nPCI\\VEN_8086\&DEV_2922\&CC_0106=\"iaStor\"/' "$target/TXTSETUP.SIF"

  rm -f "$target/winnt.sif"
  rm -f "$target/Winnt.sif"
  rm -f "$target/winnt.SIF"
  rm -f "$target/WinNT.sif"
  rm -f "$target/WINNT.sif"
  rm -f "$target/WINNT.SIF"

  local key="M6TF9-8XQ2M-YQK9F-7TBB2-XGG88"
  [[ "${arch,,}" == "amd64" ]] && key="B66VY-4D94T-TPPD4-43F72-8X4FY"

  local sif="$target/WINNT.SIF"
  {       echo "[Data]"
          echo "AutoPartition=1"
          echo "MsDosInitiated=\"0\""
          echo "UnattendedInstall=\"Yes\""
          echo "AutomaticUpdates=\"Yes\""
          echo ""
          echo "[Unattended]"
          echo "UnattendSwitch=Yes"
          echo "UnattendMode=FullUnattended"
          echo "FileSystem=NTFS"
          echo "OemSkipEula=Yes"
          echo "OemPreinstall=Yes"
          echo "Repartition=Yes"
          echo "WaitForReboot=\"No\""
          echo "DriverSigningPolicy=\"Ignore\""
          echo "NonDriverSigningPolicy=\"Ignore\""
          echo "OemPnPDriversPath=\"Drivers\viostor;Drivers\NetKVM;Drivers\sata\""
          echo "NoWaitAfterTextMode=1"
          echo "NoWaitAfterGUIMode=1"
          echo "FileSystem-ConvertNTFS"
          echo "ExtendOemPartition=0"
          echo "Hibernation=\"No\""
          echo ""
          echo "[GuiUnattended]"
          echo "OEMSkipRegional=1"
          echo "OemSkipWelcome=1"
          echo "AdminPassword=*"
          echo "TimeZone=0"
          echo "AutoLogon=Yes"
          echo "AutoLogonCount=65432"
          echo ""
          echo "[UserData]"
          echo "FullName=\"Docker\""
          echo "ComputerName=\"*\""
          echo "OrgName=\"Windows for Docker\""
          echo "ProductKey=$key"
          echo ""
          echo "[Identification]"
          echo "JoinWorkgroup = WORKGROUP"
          echo ""
          echo "[Networking]"
          echo "InstallDefaultComponents=Yes"
          echo ""
          echo "[URL]"
          echo "Home_Page = http://www.google.com"
          echo "Search_Page = http://www.google.com/ie_rsearch.html"
          echo "AutoConfig = 0"
          echo ""
          echo "[RegionalSettings]"
          echo "Language=00000409"
          echo ""
          echo "[TerminalServices]"
          echo "AllowConnections=1"
  } > "$sif"

  return 0
}

prepareLegacy() {

  local iso="$1"
  local dir="$2"

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

prepareImage() {

  local iso="$1"
  local dir="$2"

  if [[ "${BOOT_MODE,,}" == "windows" ]]; then
    if [[ "${DETECTED,,}" != "winxp"* ]] && [[ "${DETECTED,,}" != "win2008"* ]]; then
      if [[ "${DETECTED,,}" != "winvista"* ]] && [[ "${DETECTED,,}" != "win7"* ]]; then

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
  fi

  if [[ "${DETECTED,,}" == "winxp"* ]]; then
    if ! prepareXP "$iso" "$dir"; then
      error "Failed to prepare Windows XP ISO!"
      return 1
    fi
  else
    if ! prepareLegacy "$iso" "$dir"; then
      error "Failed to prepare Windows ISO!"
      return 1
    fi
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
  local size size_gb space space_gb desc

  label="${label::30}"
  local out="$TMP/$label.tmp"
  rm -f "$out"

  desc=$(printVersion "$DETECTED")
  [ -z "$desc" ] && desc="ISO"

  local msg="Building $desc image..."
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

    if [[ "${DETECTED,,}" != "winxp"* ]]; then

      if ! genisoimage -o "$out" -b "$ETFS" -no-emul-boot -c "$cat" -iso-level 2 -J -l -D -N -joliet-long -relaxed-filenames -V "$label" \
                       -udf -allow-limited-size -quiet "$dir" 2> "$log"; then
        [ -f "$log" ] && echo "$(<"$log")"
        return 1
      fi

    else

      if ! genisoimage -o "$out" -b "$ETFS" -no-emul-boot -boot-load-seg 1984 -boot-load-size 4 -c "$cat" -iso-level 2 -J -l -D -N -joliet-long \
                       -relaxed-filenames -V "$label" -quiet "$dir" 2> "$log"; then
        [ -f "$log" ] && echo "$(<"$log")"
        return 1
      fi

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
    MACHINE=$(<"$STORAGE/windows.old")
    [ -z "$MACHINE" ] && MACHINE="q35"
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

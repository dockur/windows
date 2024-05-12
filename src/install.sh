#!/usr/bin/env bash
set -Eeuo pipefail

TMP="$STORAGE/tmp"
DIR="$TMP/unpack"
FB="falling back to manual installation!"
ETFS="boot/etfsboot.com"
EFISYS="efi/microsoft/boot/efisys_noprompt.bin"

hasDisk() {

  [ -b "/disk1" ] && return 0
  [ -b "/dev/disk1" ] && return 0
  [ -b "${DEVICE:-}" ] && return 0
  [ -s "$STORAGE/data.img" ]  && return 0
  [ -s "$STORAGE/data.qcow2" ] && return 0

  return 1
}

skipInstall() {

  local iso="$1"
  local magic byte
  local boot="$STORAGE/windows.boot"
  local previous="$STORAGE/windows.base"

  if [ -f "$previous" ]; then
    previous=$(<"$previous")
    if [ -n "$previous" ]; then
      previous="$STORAGE/$previous"
      if [[ "${previous,,}" != "${iso,,}" ]]; then
        if [ -f "$boot" ] && hasDisk; then
          info "Detected that the version was changed, but ignoring this because Windows is already installed."
          info "Please start with an empty /storage folder, if you want to install a different version of Windows."
          return 0
        fi
        [ -f "$previous" ] && rm -f "$previous"
        return 1
      fi
    fi
  fi

  [ -f "$boot" ] && hasDisk && return 0

  [ ! -f "$iso" ] && return 1
  [ ! -s "$iso" ] && return 1

  # Check if the ISO was already processed by our script
  magic=$(dd if="$iso" seek=0 bs=1 count=1 status=none | tr -d '\000')
  magic="$(printf '%s' "$magic" | od -A n -t x1 -v | tr -d ' \n')"
  byte="16" && [[ "$MANUAL" == [Yy1]* ]] && byte="17"

  if [[ "$magic" != "$byte" ]]; then
    info "The ISO will be processed again because the configuration was changed..."
    return 1
  fi

  return 0
}

startInstall() {

  html "Starting $APP..."

  if [ -z "$CUSTOM" ]; then

    local file="${VERSION/\//}.iso"

    if [[ "${VERSION,,}" == "http"* ]]; then

      file=$(basename "${VERSION%%\?*}")
      : "${file//+/ }"; printf -v file '%b' "${_//%/\\x}"
      file=$(echo "$file" | sed -e 's/[^A-Za-z0-9._-]/_/g')

    fi

    BOOT="$STORAGE/$file"

    ! migrateFiles "$BOOT" "$VERSION" && error "Migration failed!" && exit 57

  fi

  skipInstall "$BOOT" && return 1

  rm -rf "$TMP"
  mkdir -p "$TMP"

  if [ -z "$CUSTOM" ]; then

    ISO=$(basename "$BOOT")
    ISO="$TMP/$ISO"

    if [ -f "$BOOT" ] && [ -s "$BOOT" ]; then
      mv -f "$BOOT" "$ISO"
    fi

  fi

  rm -f "$BOOT"
  return 0
}

finishInstall() {

  local iso="$1"
  local aborted="$2"
  local base byte

  if [ ! -s "$iso" ] || [ ! -f "$iso" ]; then
    error "Failed to find ISO file: $iso" && return 1
  fi

  if [[ "$aborted" != [Yy1]* ]]; then
    # Mark ISO as prepared via magic byte
    byte="16" && [[ "$MANUAL" == [Yy1]* ]] && byte="17"
    if ! printf '%b' "\x$byte" | dd of="$iso" bs=1 seek=0 count=1 conv=notrunc status=none; then
      warn "failed to set magic byte in ISO file: $iso"
    fi
  fi

  rm -f "$STORAGE/windows.old"
  rm -f "$STORAGE/windows.base"
  rm -f "$STORAGE/windows.boot"
  rm -f "$STORAGE/windows.mode"

  cp -f /run/version "$STORAGE/windows.ver"

  if [[ "$iso" == "$STORAGE/"* ]]; then
    if [[ "$aborted" != [Yy1]* ]] || [ -z "$CUSTOM" ]; then
      base=$(basename "$iso")
      echo "$base" > "$STORAGE/windows.base"
    fi
  fi

  if [[ "${PLATFORM,,}" == "x64" ]]; then
    if [[ "${BOOT_MODE,,}" == "windows_legacy" ]]; then
      echo "$BOOT_MODE" > "$STORAGE/windows.mode"
      if [[ "${MACHINE,,}" != "q35" ]]; then
        echo "$MACHINE" > "$STORAGE/windows.old"
      fi
    else
      # Enable secure boot + TPM on manual installs as Win11 requires
      if [[ "$MANUAL" == [Yy1]* ]] || [[ "$aborted" == [Yy1]* ]]; then
        if [[ "${DETECTED,,}" == "win11"* ]]; then
          BOOT_MODE="windows_secure"
          echo "$BOOT_MODE" > "$STORAGE/windows.mode"
        fi
      fi
    fi
  fi

  rm -rf "$TMP"
  return 0
}

abortInstall() {

  local iso="$1"

  [[ "${iso,,}" == *".esd" ]] && exit 60

  if [ -n "$CUSTOM" ]; then
    BOOT="$iso"
    REMOVE="N"
  else
    if [[ "$iso" != "$BOOT" ]]; then
      if ! mv -f "$iso" "$BOOT"; then
        error "Failed to move ISO file: $iso" && return 1
      fi
    fi
  fi

  finishInstall "$BOOT" "Y" && return 0
  return 1
}

detectCustom() {

  local file=""
  local size base

  CUSTOM=""

  if [[ "${VERSION,,}" != "http"* ]]; then
    base="${VERSION/\/storage\//}"
    [[ "$base" == "."* ]] && base="${file:1}"
    [[ "$base" == *"/"* ]] && base=""
    [ -n "$base" ] && file=$(find "$STORAGE" -maxdepth 1 -type f -iname "$base" | head -n 1)
  fi

  [ -z "$file" ] && file=$(find "$STORAGE" -maxdepth 1 -type f -iname custom.iso | head -n 1)
  [ -z "$file" ] && file=$(find "$STORAGE" -maxdepth 1 -type f -iname custom.img | head -n 1)

  base="/custom.iso"
  [ -f "$base" ] && [ -s "$base" ] && file="$base"

  if [ ! -f "$file" ] || [ ! -s "$file" ]; then
    return 0
  fi

  size="$(stat -c%s "$file")"
  [ -z "$size" ] || [[ "$size" == "0" ]] && return 0

  ISO="$file"
  CUSTOM="$ISO"
  BOOT="$STORAGE/windows.$size.iso"

  return 0
}

getESD() {

  local dir="$1"
  local version="$2"
  local editionName
  local winCatalog size

  if ! isESD "${version,,}"; then
    error "Invalid VERSION specified, value \"$version\" is not recognized!" && return 1
  fi

  winCatalog=$(getCatalog "$version" "url")
  editionName=$(getCatalog "$version" "edition")

  local msg="Downloading product information from Microsoft..."
  info "$msg" && html "$msg"

  rm -rf "$dir"
  mkdir -p "$dir"

  local wFile="catalog.cab"
  local xFile="products.xml"
  local eFile="esd_edition.xml"
  local fFile="products_filter.xml"

  { wget "$winCatalog" -O "$dir/$wFile" -q --timeout=10; rc=$?; } || :
  (( rc != 0 )) && error "Failed to download $winCatalog , reason: $rc" && return 1

  cd "$dir"

  if ! cabextract "$wFile" > /dev/null; then
    cd /run
    error "Failed to extract $wFile!" && return 1
  fi

  cd /run

  if [ ! -s "$dir/$xFile" ]; then
    error "Failed to find $xFile in $wFile!" && return 1
  fi

  local esdLang="en-us"
  local edQuery='//File[Architecture="'${PLATFORM}'"][Edition="'${editionName}'"]'

  echo -e '<Catalog>' > "$dir/$fFile"
  xmllint --nonet --xpath "${edQuery}" "$dir/$xFile" >> "$dir/$fFile" 2>/dev/null
  echo -e '</Catalog>'>> "$dir/$fFile"
  xmllint --nonet --xpath '//File[LanguageCode="'${esdLang}'"]' "$dir/$fFile" >"$dir/$eFile"

  size=$(stat -c%s "$dir/$eFile")
  if ((size<20)); then
    error "Failed to find Windows product in $eFile!" && return 1
  fi

  local tag="FilePath"
  ESD=$(xmllint --nonet --xpath "//$tag" "$dir/$eFile" | sed -E -e "s/<[\/]?$tag>//g")

  if [ -z "$ESD" ]; then
    error "Failed to find ESD URL in $eFile!" && return 1
  fi

  tag="Sha1"
  ESD_SUM=$(xmllint --nonet --xpath "//$tag" "$dir/$eFile" | sed -E -e "s/<[\/]?$tag>//g")
  tag="Size"
  ESD_SIZE=$(xmllint --nonet --xpath "//$tag" "$dir/$eFile" | sed -E -e "s/<[\/]?$tag>//g")

  rm -rf "$dir"
  return 0
}

verifyFile() {

  local iso="$1"
  local size="$2"
  local total="$3"
  local check="$4"

  if [ -n "$size" ] && [[ "$total" != "$size" ]] && [[ "$size" != "0" ]]; then
    warn "The downloaded file has an unexpected size: $total bytes, while expected value was: $size bytes. Please report this at $SUPPORT/issues"
  fi

  local hash=""
  local algo="SHA256"

  [ -z "$check" ] && return 0
  [[ "$VERIFY" != [Yy1]* ]] && return 0
  [[ "${#check}" == "40" ]] && algo="SHA1"

  local msg="Verifying downloaded ISO..."
  info "$msg" && html "$msg"

  if [[ "${algo,,}" != "sha256" ]]; then
    hash=$(sha1sum "$iso" | cut -f1 -d' ')
  else
    hash=$(sha256sum "$iso" | cut -f1 -d' ')
  fi

  if [[ "$hash" == "$check" ]]; then
    info "Succesfully verified ISO!" && return 0
  fi

  error "The downloaded file has an invalid $algo checksum: $hash , while expected value was: $check. Please report this at $SUPPORT/issues"

  rm -f "$iso"
  return 1
}

doMido() {

  local iso="$1"
  local version="$2"
  local desc="$3"
  local rc sum size total

  rm -f "$iso"
  rm -f "$iso.PART"

  size=$(getMido "$version" "size")
  sum=$(getMido "$version" "sum")

  local msg="Downloading $desc..."
  info "$msg" && html "$msg"
  /run/progress.sh "$iso.PART" "$size" "Downloading $desc ([P])..." &

  cd "$TMP"
  { /run/mido.sh "${version,,}"; rc=$?; } || :
  cd /run

  fKill "progress.sh"

  if (( rc == 0 )) && [ -f "$iso" ]; then
    total=$(stat -c%s "$iso")
    if [ "$total" -gt 100000000 ]; then
      ! verifyFile "$iso" "$size" "$total" "$sum" && return 1
      html "Download finished successfully..." && return 0
    fi
  fi

  rm -f "$iso"
  rm -f "$iso.PART"

  return 1
}

downloadFile() {

  local iso="$1"
  local url="$2"
  local sum="$3"
  local size="$4"
  local desc="$5"
  local rc total progress domain dots

  rm -f "$iso"

  # Check if running with interactive TTY or redirected to docker log
  if [ -t 1 ]; then
    progress="--progress=bar:noscroll"
  else
    progress="--progress=dot:giga"
  fi

  local msg="Downloading $desc..."
  html "$msg"

  domain=$(echo "$url" | awk -F/ '{print $3}')
  dots=$(echo "$domain" | tr -cd '.' | wc -c)
  (( dots > 1 )) && domain=$(expr "$domain" : '.*\.\(.*\..*\)')

  if [ -n "$domain" ] && [[ "${domain,,}" != *"microsoft.com" ]]; then
    msg="Downloading $desc from $domain..."
  fi

  info "$msg"
  /run/progress.sh "$iso" "$size" "Downloading $desc ([P])..." &

  { wget "$url" -O "$iso" -q --timeout=10 --show-progress "$progress"; rc=$?; } || :

  fKill "progress.sh"

  if (( rc == 0 )) && [ -f "$iso" ]; then
    total=$(stat -c%s "$iso")
    if [ "$total" -gt 100000000 ]; then
      ! verifyFile "$iso" "$size" "$total" "$sum" && return 1
      html "Download finished successfully..." && return 0
    fi
  fi

  error "Failed to download $url , reason: $rc"

  rm -f "$iso"
  return 1
}

downloadImage() {

  local iso="$1"
  local version="$2"
  local tried="n"
  local url sum size base desc

  if [[ "${version,,}" == "http"* ]]; then
    base=$(basename "$iso")
    desc=$(fromFile "$base")
    downloadFile "$iso" "$version" "" "" "$desc" && return 0
    return 1
  fi

  if ! validVersion "$version"; then
    error "Invalid VERSION specified, value \"$version\" is not recognized!" && return 1
  fi

  desc=$(printVersion "$version" "")

  if isMido "$version"; then
    tried="y"
    doMido "$iso" "$version" "$desc" && return 0
  fi

  switchEdition "$version"

  if isESD "$version"; then

    if [[ "$tried" != "n" ]]; then
      info "Failed to download $desc using Mido, will try a diferent method now..."
    fi

    tried="y"

    if getESD "$TMP/esd" "$version"; then
      ISO="${ISO%.*}.esd"
      downloadFile "$ISO" "$ESD" "$ESD_SUM" "$ESD_SIZE" "$desc" && return 0
      ISO="$iso"
    fi

  fi

  for ((i=1;i<=MIRRORS;i++)); do

    url=$(getLink "$i" "$version")

    if [ -n "$url" ]; then
      if [[ "$tried" != "n" ]]; then
        info "Failed to download $desc, will try another mirror now..."
      fi
      tried="y"
      size=$(getSize "$i" "$version")
      sum=$(getHash "$i" "$version")
      downloadFile "$iso" "$url" "$sum" "$size" "$desc" && return 0
    fi

  done

  return 1
}

removeDownload() {

  local iso="$1"

  [ ! -f "$iso" ] && return 0
  [ -n "$CUSTOM" ] && return 0
  ! rm -f "$iso" 2> /dev/null && warn "failed to remove $iso !"

  return 0
}

extractESD() {

  local iso="$1"
  local dir="$2"
  local version="$3"
  local desc="$4"
  local size size_gb space space_gb desc

  local msg="Extracting $desc bootdisk..."
  info "$msg" && html "$msg"

  if [ "$(stat -c%s "$iso")" -lt 100000000 ]; then
    error "Invalid ESD file: Size is smaller than 100 MB" && return 1
  fi

  rm -rf "$dir"
  mkdir -p "$dir"

  size=16106127360
  size_gb=$(( (size + 1073741823)/1073741824 ))
  space=$(df --output=avail -B 1 "$dir" | tail -n 1)
  space_gb=$(( (space + 1073741823)/1073741824 ))

  if (( size > space )); then
    error "Not enough free space in $STORAGE, have $space_gb GB available but need at least $size_gb GB." && return 1
  fi

  local esdImageCount
  esdImageCount=$(wimlib-imagex info "$iso" | awk '/Image Count:/ {print $3}')

  wimlib-imagex apply "$iso" 1 "$dir" --quiet 2>/dev/null || {
    retVal=$?
    error "Extracting $desc bootdisk failed" && return $retVal
  }

  local bootWimFile="$dir/sources/boot.wim"
  local installWimFile="$dir/sources/install.wim"

  local msg="Extracting $desc environment..."
  info "$msg" && html "$msg"

  wimlib-imagex export "$iso" 2 "$bootWimFile" --compress=none --quiet || {
    retVal=$?
    error "Adding WinPE failed" && return ${retVal}
  }

  local msg="Extracting $desc setup..."
  info "$msg" && html "$msg"

  wimlib-imagex export "$iso" 3 "$bootWimFile" --compress=none --boot --quiet || {
   retVal=$?
   error "Adding Windows Setup failed" && return ${retVal}
  }

  if [[ "${PLATFORM,,}" == "x64" ]]; then
    LABEL="CCCOMA_X64FRE_EN-US_DV9"
  else
    LABEL="CPBA_A64FRE_EN-US_DV9"
  fi

  local msg="Extracting $desc image..."
  info "$msg" && html "$msg"

  local edition imageIndex imageEdition
  edition=$(getCatalog "$version" "name")

  if [ -z "$edition" ]; then
    error "Invalid VERSION specified, value \"$version\" is not recognized!" && return 1
  fi

  for (( imageIndex=4; imageIndex<=esdImageCount; imageIndex++ )); do
    imageEdition=$(wimlib-imagex info "$iso" ${imageIndex} | grep '^Description:' | sed 's/Description:[ \t]*//')
    [[ "${imageEdition,,}" != "${edition,,}" ]] && continue
    wimlib-imagex export "$iso" ${imageIndex} "$installWimFile" --compress=LZMS --chunk-size 128K --quiet || {
      retVal=$?
      error "Addition of $imageIndex to the $desc image failed" && return $retVal
    }
    return 0
  done

  error "Failed to find product '$edition' in install.wim!" && return 1
}

extractImage() {

  local iso="$1"
  local dir="$2"
  local version="$3"
  local desc="local ISO"
  local size size_gb space space_gb

  if [ -z "$CUSTOM" ]; then
    desc="downloaded ISO"
    if [[ "$version" != "http"* ]]; then
      desc=$(printVersion "$version" "$desc")
    fi
  fi

  if [[ "${iso,,}" == *".esd" ]]; then
    extractESD "$iso" "$dir" "$version" "$desc" && return 0
    return 1
  fi

  local msg="Extracting $desc image..."
  info "$msg" && html "$msg"

  rm -rf "$dir"
  mkdir -p "$dir"

  size=$(stat -c%s "$iso")
  size_gb=$(( (size + 1073741823)/1073741824 ))
  space=$(df --output=avail -B 1 "$dir" | tail -n 1)
  space_gb=$(( (space + 1073741823)/1073741824 ))

  if ((size<100000000)); then
    error "Invalid ISO file: Size is smaller than 100 MB" && return 1
  fi

  if (( size > space )); then
    error "Not enough free space in $STORAGE, have $space_gb GB available but need at least $size_gb GB." && return 1
  fi

  rm -rf "$dir"

  if ! 7z x "$iso" -o"$dir" > /dev/null; then
    error "Failed to extract ISO file: $iso" && return 1
  fi

  LABEL=$(isoinfo -d -i "$iso" | sed -n 's/Volume id: //p')

  return 0
}

setXML() {

  local file="/custom.xml"
  [ ! -f "$file" ] || [ ! -s "$file" ] && file="$STORAGE/custom.xml"
  [ ! -f "$file" ] || [ ! -s "$file" ] && file="/run/assets/custom.xml"
  [ ! -f "$file" ] || [ ! -s "$file" ] && file="$1"
  [ ! -f "$file" ] || [ ! -s "$file" ] && file="/run/assets/$DETECTED.xml"
  [ ! -f "$file" ] || [ ! -s "$file" ] && return 1

  XML="$file"
  return 0
}

getPlatform() {

  local xml="$1"
  local tag="ARCH"
  local platform="x64"
  local arch

  arch=$(sed -n "/$tag/{s/.*<$tag>\(.*\)<\/$tag>.*/\1/;p}" <<< "$xml")

  case "${arch,,}" in
    "0" ) platform="x86" ;;
    "9" ) platform="x64" ;;
    "12" )platform="arm64" ;;
  esac

  echo "$platform"
  return 0
}

hasVersion() {

  local id="$1"
  local tag="$2"
  local xml="$3"
  local edition

  [ ! -f "/run/assets/$id.xml" ] && return 1

  edition=$(printEdition "$id" "")
  [ -z "$edition" ] && return 1
  [[ "${xml,,}" != *"<${tag,,}>${edition,,}</${tag,,}>"* ]] && return 1

  return 0
}

selectVersion() {

  local tag="$1"
  local xml="$2"
  local platform="$3"
  local id name prefer

  name=$(sed -n "/$tag/{s/.*<$tag>\(.*\)<\/$tag>.*/\1/;p}" <<< "$xml")
  [[ "$name" == *"Operating System"* ]] && name=""
  [ -z "$name" ] && return 0

  id=$(fromName "$name" "$platform")
  [ -z "$id" ] && warn "Unknown ${tag,,}: '$name'" && return 0

  prefer="$id-enterprise"
  hasVersion "$prefer" "$tag" "$xml" && echo "$prefer" && return 0

  prefer="$id-ultimate"
  hasVersion "$prefer" "$tag" "$xml" && echo "$prefer" && return 0

  prefer="$id"
  hasVersion "$prefer" "$tag" "$xml" && echo "$prefer" && return 0

  prefer=$(getVersion "$name" "$platform")

  echo "$prefer"
  return 0
}

checkPlatform() {

  local xml="$1"
  local platform compat

  platform=$(getPlatform "$xml")

  case "${platform,,}" in
    "x86" ) compat="x64" ;;
    "x64" ) compat="$platform" ;;
    "arm64" ) compat="$platform" ;;
    * ) compat="${PLATFORM,,}" ;;
  esac

  [[ "${compat,,}" == "${PLATFORM,,}" ]] && return 0

  error "You cannot boot ${platform^^} images on a $PLATFORM CPU!"
  return 1
}

detectVersion() {

  local xml="$1"
  local id platform

  platform=$(getPlatform "$xml")
  id=$(selectVersion "DISPLAYNAME" "$xml" "$platform")
  [ -z "$id" ] && id=$(selectVersion "PRODUCTNAME" "$xml" "$platform")
  [ -z "$id" ] && id=$(selectVersion "NAME" "$xml" "$platform")

  echo "$id"
  return 0
}

detectImage() {

  local dir="$1"
  local version="$2"
  local desc msg

  XML=""

  if [ -z "$DETECTED" ] && [ -z "$CUSTOM" ]; then
    [[ "${version,,}" != "http"* ]] && DETECTED="$version"
  fi

  if [ -n "$DETECTED" ]; then

    [[ "${DETECTED,,}" == "winxp"* ]] && return 0

    if ! setXML "" && [[ "$MANUAL" != [Yy1]* ]]; then
      MANUAL="Y"
      desc=$(printEdition "$DETECTED" "this version")
      warn "the answer file for $desc was not found ($DETECTED.xml), $FB."
    fi

    return 0
  fi

  info "Detecting version from ISO image..."

  if [ -f "$dir/WIN51" ] || [ -f "$dir/SETUPXP.HTM" ]; then
    [ -d "$dir/AMD64" ] && DETECTED="winxpx64" || DETECTED="winxpx86"
    desc=$(printEdition "$DETECTED" "Windows XP")
    info "Detected: $desc"
    return 0
  fi

  local src loc info
  src=$(find "$dir" -maxdepth 1 -type d -iname sources | head -n 1)

  if [ ! -d "$src" ]; then
    [[ "${PLATFORM,,}" == "x64" ]] && BOOT_MODE="windows_legacy"
    warn "failed to locate 'sources' folder in ISO image, $FB" && return 1
  fi

  loc=$(find "$src" -maxdepth 1 -type f -iname install.wim | head -n 1)
  [ ! -f "$loc" ] && loc=$(find "$src" -maxdepth 1 -type f -iname install.esd | head -n 1)

  if [ ! -f "$loc" ]; then
    [[ "${PLATFORM,,}" == "x64" ]] && BOOT_MODE="windows_legacy"
    warn "failed to locate 'install.wim' or 'install.esd' in ISO image, $FB" && return 1
  fi

  info=$(wimlib-imagex info -xml "$loc" | tr -d '\000')
  ! checkPlatform "$info" && exit 67

  DETECTED=$(detectVersion "$info")

  if [ -z "$DETECTED" ]; then
    msg="Failed to determine Windows version from image"
    if setXML "" || [[ "$MANUAL" == [Yy1]* ]]; then
      info "${msg}!"
    else
      MANUAL="Y"
      warn "${msg}, $FB."
    fi
    return 0
  fi

  desc=$(printEdition "$DETECTED" "$DETECTED")

  info "Detected: $desc"
  setXML "" && return 0

  msg="the answer file for $desc was not found ($DETECTED.xml)"
  local fallback="/run/assets/${DETECTED%%-*}.xml"

  if setXML "$fallback" || [[ "$MANUAL" == [Yy1]* ]]; then
    [[ "$MANUAL" != [Yy1]* ]] && warn "${msg}."
  else
    MANUAL="Y"
    warn "${msg}, $FB."
  fi

  return 0
}

prepareImage() {

  local iso="$1"
  local dir="$2"
  local missing

  case "${DETECTED,,}" in
    "winxp"* )
      BOOT_MODE="windows_legacy"
      prepareXP "$iso" "$dir" && return 0
      error "Failed to prepare Windows XP ISO!" && return 1
      ;;
    "winvista"* | "win7"* | "win2008"* )
      BOOT_MODE="windows_legacy" ;;
  esac

  if [[ "${BOOT_MODE,,}" != "windows_legacy" ]]; then

    [ -f "$dir/$ETFS" ] && [ -f "$dir/$EFISYS" ] && return 0

    missing=$(basename "$dir/$EFISYS")
    [ ! -f "$dir/$ETFS" ] && missing=$(basename "$dir/$ETFS")
    warn "failed to locate file '${missing,,}' in ISO image!"

    [[ "${PLATFORM,,}" == "arm64" ]] && return 1
    BOOT_MODE="windows_legacy"
  fi

  prepareLegacy "$iso" "$dir" && return 0

  error "Failed to extract boot image from ISO!"
  return 1
}

updateImage() {

  local dir="$1"
  local asset="$2"
  local file="autounattend.xml"
  local org="${file/.xml/.org}"
  local dat="${file/.xml/.dat}"
  local desc path src loc xml index result

  if [ ! -s "$asset" ] || [ ! -f "$asset" ]; then
    asset=""
    if [[ "$MANUAL" != [Yy1]* ]]; then
      MANUAL="Y"
      warn "no answer file provided, $FB."
    fi
  fi

  src=$(find "$dir" -maxdepth 1 -type d -iname sources | head -n 1)

  if [ ! -d "$src" ]; then
    [[ "${PLATFORM,,}" == "x64" ]] && BOOT_MODE="windows_legacy"
    warn "failed to locate 'sources' folder in ISO image, $FB" && return 1
  fi

  loc=$(find "$src" -maxdepth 1 -type f -iname boot.wim | head -n 1)
  [ ! -f "$loc" ] && loc=$(find "$src" -maxdepth 1 -type f -iname boot.esd | head -n 1)

  if [ ! -f "$loc" ]; then
    [[ "${PLATFORM,,}" == "x64" ]] && BOOT_MODE="windows_legacy"
    warn "failed to locate 'boot.wim' or 'boot.esd' in ISO image, $FB" && return 1
  fi

  index="1"
  result=$(wimlib-imagex info -xml "$loc" | tr -d '\000')

  if [[ "${result^^}" == *"<IMAGE INDEX=\"2\">"* ]]; then
    index="2"
  fi

  if wimlib-imagex extract "$loc" "$index" "/$file" "--dest-dir=$TMP" >/dev/null 2>&1; then
    if ! wimlib-imagex extract "$loc" "$index" "/$dat" "--dest-dir=$TMP" >/dev/null 2>&1; then
      if ! wimlib-imagex extract "$loc" "$index" "/$org" "--dest-dir=$TMP" >/dev/null 2>&1; then
        if ! wimlib-imagex update "$loc" "$index" --command "rename /$file /$org" > /dev/null; then
          warn "failed to backup original answer file ($file)."
        fi
      fi
    fi
    rm -f "$TMP/$dat"
    rm -f "$TMP/$org"
    rm -f "$TMP/$file"
  fi

  if [[ "$MANUAL" != [Yy1]* ]]; then

    xml=$(basename "$asset")
    info "Adding $xml for automatic installation..."

    if ! wimlib-imagex update "$loc" "$index" --command "add $asset /$file" > /dev/null; then
      MANUAL="Y"
      warn "failed to add answer file ($xml) to ISO image, $FB"
    else
      wimlib-imagex update "$loc" "$index" --command "add $asset /$dat" > /dev/null || true
    fi

  fi

  if [[ "$MANUAL" == [Yy1]* ]]; then

    wimlib-imagex update "$loc" "$index" --command "delete --force /$file" > /dev/null || true

    if wimlib-imagex extract "$loc" "$index" "/$org" "--dest-dir=$TMP" >/dev/null 2>&1; then
      if ! wimlib-imagex update "$loc" "$index" --command "add $TMP/$org /$file" > /dev/null; then
        warn "failed to restore original answer file ($org)."
      fi
      rm -f "$TMP/$org"
    fi

  fi

  local find="$file"
  [[ "$MANUAL" == [Yy1]* ]] && find="$org"
  path=$(find "$dir" -maxdepth 1 -type f -iname "$find" | head -n 1)

  if [ -f "$path" ]; then
    if [[ "$MANUAL" != [Yy1]* ]]; then
      mv -f "$path" "${path%.*}.org"
    else
      mv -f "$path" "${path%.*}.xml"
    fi
  fi

  return 0
}

copyOEM() {

  local dir="$1"
  local folder="/oem"
  local src

  [ ! -d "$folder" ] && folder="/OEM"
  [ ! -d "$folder" ] && folder="$STORAGE/oem"
  [ ! -d "$folder" ] && folder="$STORAGE/OEM"
  [ ! -d "$folder" ] && return 0

  local msg="Copying OEM folder to image..."
  info "$msg" && html "$msg"

  src=$(find "$dir" -maxdepth 1 -type d -iname sources | head -n 1)

  if [ ! -d "$src" ]; then
    error "failed to locate 'sources' folder in ISO image!" && return 1
  fi

  local dest="$src/\$OEM\$/\$1/"
  mkdir -p "$dest"

  if ! cp -r "$folder" "$dest"; then
    error "Failed to copy OEM folder!" && return 1
  fi

  return 0
}

buildImage() {

  local dir="$1"
  local failed="N"
  local cat="BOOT.CAT"
  local log="/run/shm/iso.log"
  local base size size_gb space space_gb desc

  if [ -f "$BOOT" ]; then
    error "File $BOOT does already exist?!" && return 1
  fi

  base=$(basename "$BOOT")
  local out="$TMP/${base%.*}.tmp"
  rm -f "$out"

  desc=$(printVersion "$DETECTED" "ISO")

  local msg="Building $desc image..."
  info "$msg" && html "$msg"

  size=$(du -h -b --max-depth=0 "$dir" | cut -f1)
  size_gb=$(( (size + 1073741823)/1073741824 ))
  space=$(df --output=avail -B 1 "$TMP" | tail -n 1)
  space_gb=$(( (space + 1073741823)/1073741824 ))

  if (( size > space )); then
    error "Not enough free space in $STORAGE, have $space_gb GB available but need at least $size_gb GB." && return 1
  fi

  [ -z "$LABEL" ] && LABEL="Windows"

  if [[ "${BOOT_MODE,,}" != "windows_legacy" ]]; then

    if ! genisoimage -o "$out" -b "$ETFS" -no-emul-boot -c "$cat" -iso-level 4 -J -l -D -N -joliet-long -relaxed-filenames -V "${LABEL::30}" \
                     -udf -boot-info-table -eltorito-alt-boot -eltorito-boot "$EFISYS" -no-emul-boot -allow-limited-size -quiet "$dir" 2> "$log"; then
      failed="Y"
    fi

  else

    if [[ "${DETECTED,,}" != "winxp"* ]]; then

      if ! genisoimage -o "$out" -b "$ETFS" -no-emul-boot -c "$cat" -iso-level 2 -J -l -D -N -joliet-long -relaxed-filenames -V "${LABEL::30}" \
                       -udf -allow-limited-size -quiet "$dir" 2> "$log"; then
        failed="Y"
      fi

    else

      if ! genisoimage -o "$out" -b "$ETFS" -no-emul-boot -boot-load-seg 1984 -boot-load-size 4 -c "$cat" -iso-level 2 -J -l -D -N -joliet-long \
                       -relaxed-filenames -V "${LABEL::30}" -quiet "$dir" 2> "$log"; then
        failed="Y"
      fi

    fi
  fi

  if [[ "$failed" != "N" ]]; then
    [ -s "$log" ] && echo "$(<"$log")"
    error "Failed to build image!" && return 1
  fi

  local error=""
  local hide="Warning: creating filesystem that does not conform to ISO-9660."

  [ -s "$log" ] && error="$(<"$log")"
  [[ "$error" != "$hide" ]] && echo "$error"

  ! mv -f "$out" "$BOOT" && return 1
  return 0
}

bootWindows() {

  rm -rf "$TMP"

  if [ ! -f "$BOOT" ] || [ ! -s "$BOOT" ]; then
    BOOT="/custom.iso"
    [ ! -f "$BOOT" ] && BOOT="${STORAGE}$BOOT"
  fi

  [[ "${PLATFORM,,}" == "arm64" ]] && VGA="virtio-gpu"

  if [ -s "$STORAGE/windows.mode" ] && [ -f "$STORAGE/windows.mode" ]; then
    BOOT_MODE=$(<"$STORAGE/windows.mode")
    if [ -s "$STORAGE/windows.old" ] && [ -f "$STORAGE/windows.old" ]; then
      [[ "${PLATFORM,,}" == "x64" ]] && MACHINE=$(<"$STORAGE/windows.old")
    fi
    return 0
  fi

  # Migrations

  [[ "${PLATFORM,,}" != "x64" ]] && return 0

  if [ -f "$STORAGE/windows.old" ]; then
    MACHINE=$(<"$STORAGE/windows.old")
    [ -z "$MACHINE" ] && MACHINE="q35"
    BOOT_MODE="windows_legacy"
    echo "$BOOT_MODE" > "$STORAGE/windows.mode"
    return 0
  fi

  local creation="1.10"
  local minimal="2.14"

  if [ -f "$STORAGE/windows.ver" ]; then
    creation=$(<"$STORAGE/windows.ver")
    [[ "${creation}" != *"."* ]] && creation="$minimal"
  fi

  # Force secure boot on installs created prior to v2.14
  if (( $(echo "$creation < $minimal" | bc -l) )); then
    if [[ "${BOOT_MODE,,}" == "windows" ]]; then
      BOOT_MODE="windows_secure"
      echo "$BOOT_MODE" > "$STORAGE/windows.mode"
      if [ -f "$STORAGE/windows.rom" ] && [ ! -f "$STORAGE/$BOOT_MODE.rom" ]; then
        mv -f "$STORAGE/windows.rom" "$STORAGE/$BOOT_MODE.rom"
      fi
      if [ -f "$STORAGE/windows.vars" ] && [ ! -f "$STORAGE/$BOOT_MODE.vars" ]; then
        mv -f "$STORAGE/windows.vars" "$STORAGE/$BOOT_MODE.vars"
      fi
    fi
  fi

  return 0
}

######################################

! parseVersion && exit 58
! detectCustom && exit 59

if ! startInstall; then
  bootWindows && return 0
  exit 68
fi

if [ ! -s "$ISO" ] || [ ! -f "$ISO" ]; then
  if ! downloadImage "$ISO" "$VERSION"; then
    rm -f "$ISO" 2> /dev/null || true
    exit 61
  fi
fi

if ! extractImage "$ISO" "$DIR" "$VERSION"; then
  rm -f "$ISO" 2> /dev/null || true
  exit 62
fi

if ! detectImage "$DIR" "$VERSION"; then
  abortInstall "$ISO" && return 0
  exit 60
fi

if ! prepareImage "$ISO" "$DIR"; then
  abortInstall "$ISO" && return 0
  exit 60
fi

if ! updateImage "$DIR" "$XML"; then
  abortInstall "$ISO" && return 0
  exit 60
fi

if ! removeDownload "$ISO"; then
  exit 64
fi

if ! copyOEM "$DIR"; then
  exit 63
fi

if ! buildImage "$DIR"; then
  exit 65
fi

if ! finishInstall "$BOOT" "N"; then
  exit 69
fi

html "Successfully prepared image for installation..."
return 0

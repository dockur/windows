#!/usr/bin/env bash
set -Eeuo pipefail

ESD_URL=""
TMP="$STORAGE/tmp"
DIR="$TMP/unpack"
FB="falling back to manual installation!"
ETFS="boot/etfsboot.com"
EFISYS="efi/microsoft/boot/efisys_noprompt.bin"

hasDisk() {

  [ -b "${DEVICE:-}" ] && return 0

  if [ -s "$STORAGE/data.img" ] || [ -s "$STORAGE/data.qcow2" ]; then
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
  local aborted="$2"

  if [ ! -s "$iso" ] || [ ! -f "$iso" ]; then
    error "Failed to find ISO file: $iso" && return 1
  fi

  if [ -w "$iso" ] && [[ "$aborted" != [Yy1]* ]]; then
    # Mark ISO as prepared via magic byte
    if ! printf '\x16' | dd of="$iso" bs=1 seek=0 count=1 conv=notrunc status=none; then
      error "Failed to set magic byte in ISO file: $iso" && return 1
    fi
  fi

  rm -f "$STORAGE/windows.ver"
  rm -f "$STORAGE/windows.old"
  rm -f "$STORAGE/windows.boot"
  rm -f "$STORAGE/windows.mode"

  cp /run/version "$STORAGE/windows.ver"

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

  if [[ "$iso" != "$STORAGE/$BASE" ]]; then
    if ! mv -f "$iso" "$STORAGE/$BASE"; then
      error "Failed to move ISO file: $iso" && return 1
    fi
  fi

  finishInstall "$STORAGE/$BASE" "Y" && return 0

  return 1
}

startInstall() {

  html "Starting Windows..."

  [ -z "$MANUAL" ] && MANUAL="N"

  if [ -f "$STORAGE/$CUSTOM" ]; then

    EXTERNAL="Y"
    BASE="$CUSTOM"

  else

    CUSTOM=""

    if [[ "${VERSION,,}" != "http"* ]]; then

      EXTERNAL="N"
      BASE="$VERSION.iso"

    else

      EXTERNAL="Y"
      BASE=$(basename "${VERSION%%\?*}")
      : "${BASE//+/ }"; printf -v BASE '%b' "${_//%/\\x}"
      BASE=$(echo "$BASE" | sed -e 's/[^A-Za-z0-9._-]/_/g')

    fi
  fi

  if [[ "${PLATFORM,,}" == "x64" ]]; then
    ! migrateFiles "$BASE" "$VERSION" && error "Migration failed!" && exit 57
  fi

  if skipInstall; then
    [ ! -f "$STORAGE/$BASE" ] && BASE=""
    [[ "${PLATFORM,,}" == "arm64" ]] && VGA="virtio-gpu"
    return 1
  fi

  if [ -f "$STORAGE/$BASE" ]; then

    # Check if the ISO was already processed by our script
    local magic=""
    magic=$(dd if="$STORAGE/$BASE" seek=0 bs=1 count=1 status=none | tr -d '\000')
    magic="$(printf '%s' "$magic" | od -A n -t x1 -v | tr -d ' \n')"

    if [[ "$magic" == "16" ]]; then

      if hasDisk || [[ "$MANUAL" == [Yy1]* ]]; then
        return 1
      fi

    fi

    EXTERNAL="Y"
    CUSTOM="$BASE"

  fi

  rm -rf "$TMP"
  mkdir -p "$TMP"

  if [ ! -f "$STORAGE/$CUSTOM" ]; then
    CUSTOM=""
    ISO="$TMP/$BASE"
  else
    ISO="$STORAGE/$CUSTOM"
  fi

  return 0
}

detectCustom() {

  CUSTOM=$(find "$STORAGE" -maxdepth 1 -type f -iname windows.iso -printf "%f\n" | head -n 1)
  [ -z "$CUSTOM" ] && CUSTOM=$(find "$STORAGE" -maxdepth 1 -type f -iname custom.iso -printf "%f\n" | head -n 1)
  [ -z "$CUSTOM" ] && CUSTOM=$(find "$STORAGE" -maxdepth 1 -type f -iname boot.iso -printf "%f\n" | head -n 1)
  [ -z "$CUSTOM" ] && CUSTOM=$(find "$STORAGE" -maxdepth 1 -type f -iname custom.img -printf "%f\n" | head -n 1)

  if [ -z "$CUSTOM" ] && [[ "${VERSION,,}" != "http"* ]]; then
    FN="${VERSION/\/storage\//}"
    [[ "$FN" == "."* ]] && FN="${FN:1}"
    CUSTOM=$(find "$STORAGE" -maxdepth 1 -type f -iname "$FN" -printf "%f\n" | head -n 1)
  fi

  return 0
}

getESD() {

  local dir="$1"
  local version="$2"
  local winCatalog size

  case "${version,,}" in
    "win11${PLATFORM,,}")
      winCatalog="https://go.microsoft.com/fwlink?linkid=2156292"
      ;;
    "win10${PLATFORM,,}")
      winCatalog="https://go.microsoft.com/fwlink/?LinkId=841361"
      ;;
    *)
      error "Invalid VERSION specified, value \"$version\" is not recognized!" && return 1
      ;;
  esac

  local msg="Downloading product information from Microsoft..."
  info "$msg" && html "$msg"

  rm -rf "$dir"
  mkdir -p "$dir"

  local wFile="catalog.cab"
  local xFile="products.xml"
  local eFile="esd_edition.xml"
  local fFile="products_filter.xml"

  { wget "$winCatalog" -O "$dir/$wFile" -q; rc=$?; } || :
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
  local editionName="Professional"
  local edQuery='//File[Architecture="'${PLATFORM}'"][Edition="'${editionName}'"]'

  echo -e '<Catalog>' > "$dir/$fFile"
  xmllint --nonet --xpath "${edQuery}" "$dir/$xFile" >> "$dir/$fFile" 2>/dev/null
  echo -e '</Catalog>'>> "$dir/$fFile"
  xmllint --nonet --xpath '//File[LanguageCode="'${esdLang}'"]' "$dir/$fFile" >"$dir/$eFile"

  size=$(stat -c%s "$dir/$eFile")
  if ((size<20)); then
    error "Failed to find Windows product in $eFile!" && return 1
  fi

  ESD_URL=$(xmllint --nonet --xpath '//FilePath' "$dir/$eFile" | sed -E -e 's/<[\/]?FilePath>//g')

  if [ -z "$ESD_URL" ]; then
    error "Failed to find ESD URL in $eFile!" && return 1
  fi

  rm -rf "$dir"
  return 0
}

doMido() {

  local iso="$1"
  local version="$2"
  local desc="$3"
  local rc

  rm -f "$iso"
  rm -f "$iso.PART"

  local msg="Downloading $desc..."
  info "$msg" && html "$msg"
  /run/progress.sh "$iso.PART" "Downloading $desc ([P])..." &

  cd "$TMP"
  { /run/mido.sh "${version,,}"; rc=$?; } || :
  cd /run

  fKill "progress.sh"

  if (( rc == 0 )) && [ -f "$iso" ]; then
    if [ "$(stat -c%s "$iso")" -gt 100000000 ]; then
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
  local desc="$3"
  local rc progress domain

  rm -f "$iso"

  # Check if running with interactive TTY or redirected to docker log
  if [ -t 1 ]; then
    progress="--progress=bar:noscroll"
  else
    progress="--progress=dot:giga"
  fi

  local msg="Downloading $desc..."

  domain=$(echo "$url" | awk -F/ '{print $3}')
  domain=$(expr "$domain" : '.*\.\(.*\..*\)')
  [[ "${domain,,}" != *"microsoft.com" ]] && msg="Downloading $desc from $domain..."

  info "$msg" && html "$msg"
  /run/progress.sh "$iso" "Downloading $desc ([P])..." &

  { wget "$url" -O "$iso" -q --show-progress "$progress"; rc=$?; } || :

  fKill "progress.sh"

  if (( rc == 0 )) && [ -f "$iso" ]; then
    if [ "$(stat -c%s "$iso")" -gt 100000000 ]; then
      html "Download finished successfully..." && return 0
    fi
  fi

  rm -f "$iso"
  error "Failed to download $url , reason: $rc"

  return 1
}

downloadImage() {

  local iso="$1"
  local version="$2"
  local tried="n"
  local url desc

  if [[ "${version,,}" == "http"* ]]; then

    desc=$(getName "$BASE" "$BASE")
    downloadFile "$iso" "$version" "$desc" && return 0
    return 1

  fi

  if ! validVersion "$version"; then
    error "Invalid VERSION specified, value \"$version\" is not recognized!" && return 1
  fi

  if [[ "${PLATFORM,,}" == "x64" ]]; then
    desc=$(printVersion "$version" "Windows")
  else
    desc=$(printVersion "$version" "Windows for ${PLATFORM}")
  fi

  if [[ "${PLATFORM,,}" == "x64" ]]; then
    if isMido "$version"; then
      tried="y"
      doMido "$iso" "$version" "$desc" && return 0
    fi
    switchEdition "$version"
  fi

  if isESD "$version"; then

    if [[ "$tried" != "n" ]]; then
      info "Failed to download $desc using Mido, will try a diferent method now..."
    fi

    tried="y"

    if getESD "$TMP/esd" "$version"; then
      ISO="$TMP/$version.esd"
      downloadFile "$ISO" "$ESD_URL" "$desc" && return 0
      ISO="$TMP/$BASE"
    fi

  fi

  url=$(getLink "$version")

  if [ -n "$url" ]; then

    if [[ "$tried" != "n" ]]; then
      info "Failed to download $desc from Microsoft, will try another mirror now..."
    fi

    tried="y"
    downloadFile "$iso" "$url" "$desc" && return 0

  fi

  url=$(secondLink "$version")

  if [ -n "$url" ]; then

    if [[ "$tried" != "n" ]]; then
      info "Failed to download $desc, will try another mirror now..."
    fi

    tried="y"
    downloadFile "$iso" "$url" "$desc" && return 0

  fi

  return 1
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
  esdImageCount=$(wimlib-imagex info "${iso}" | awk '/Image Count:/ {print $3}')

  wimlib-imagex apply "$iso" 1 "${dir}" --quiet 2>/dev/null || {
    retVal=$?
    error "Extracting $desc bootdisk failed" && return $retVal
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

  case "${version,,}" in
    "win11${PLATFORM,,}")
      edition="11 pro"
      ;;
    "win10${PLATFORM,,}")
      edition="10 pro"
      ;;
    *)
      error "Invalid VERSION specified, value \"$version\" is not recognized!" && return 1
      ;;
  esac

  for (( imageIndex=4; imageIndex<=esdImageCount; imageIndex++ )); do
    imageEdition=$(wimlib-imagex info "${iso}" ${imageIndex} | grep '^Description:' | sed 's/Description:[ \t]*//')
    [[ "${imageEdition,,}" != *"$edition"* ]] && continue
    wimlib-imagex export "${iso}" ${imageIndex} "${installWimFile}" --compress=LZMS --chunk-size 128K --quiet || {
      retVal=$?
      error "Addition of ${imageIndex} to the $desc image failed" && return $retVal
    }
    return 0
  done

  error "Failed to find product in install.wim!" && return 1
}

extractImage() {

  local iso="$1"
  local dir="$2"
  local version="$3"
  local desc="downloaded ISO"
  local size size_gb space space_gb

  if [[ "$EXTERNAL" != [Yy1]* ]] && [ -z "$CUSTOM" ]; then
    desc=$(printVersion "$version" "downloaded ISO")
  fi

  if [[ "${iso,,}" == *".esd" ]]; then
    extractESD "$iso" "$dir" "$version" "$desc" && return 0
    return 1
  fi

  local msg="Extracting $desc image..."
  [ -n "$CUSTOM" ] && msg="Extracting local ISO image..."
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

  return 0
}

detectImage() {

  XML=""
  local dsc
  local dir="$1"

  if [ -n "$CUSTOM" ]; then
    if [ -f "/run/assets/custom.xml" ]; then
      DETECTED="custom"
    else
      DETECTED=""
    fi
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

      dsc=$(printVersion "$DETECTED" "$DETECTED")

      warn "got $dsc, but no matching file called $DETECTED.xml exists, $FB."
    fi

    return 0
  fi

  info "Detecting Windows version from ISO image..."

  if [[ "${PLATFORM,,}" == "x64" ]]; then
    if [ -f "$dir/WIN51" ] || [ -f "$dir/SETUPXP.HTM" ]; then
      if [ -d "$dir/AMD64" ]; then
        DETECTED="winxpx64"
      else
        DETECTED="winxpx86"
      fi
      dsc=$(printVersion "$DETECTED" "$DETECTED")
      info "Detected: $dsc"
      return 0
    fi
  fi

  local src loc tag result name name2 desc
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

    tag="NAME"
    name3=$(sed -n "/$tag/{s/.*<$tag>\(.*\)<\/$tag>.*/\1/;p}" <<< "$result")
    [ -z "$name" ] && name="$name3"
    DETECTED=$(getVersion "$name3")

  fi

  if [ -z "$DETECTED" ]; then

    tag="DESCRIPTION"
    name4=$(sed -n "/$tag/{s/.*<$tag>\(.*\)<\/$tag>.*/\1/;p}" <<< "$result")
    [ -z "$name" ] && name="$name4"
    DETECTED=$(getVersion "$name4")

  fi

  if [ -z "$DETECTED" ]; then
    warn "failed to determine Windows version from string '$name', $FB" && return 0
  fi

  desc=$(printVersion "$DETECTED" "$DETECTED")

  if [ -f "/run/assets/$DETECTED.xml" ]; then
    [[ "$MANUAL" != [Yy1]* ]] && XML="$DETECTED.xml"
    info "Detected: $desc"
  else
    warn "detected $desc, but no matching file called $DETECTED.xml exists, $FB."
  fi

  return 0
}

prepareImage() {

  local iso="$1"
  local dir="$2"

  if [[ "${BOOT_MODE,,}" != "windows_legacy" ]]; then
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

  [[ "${PLATFORM,,}" == "arm64" ]] && return 1

  if [[ "${DETECTED,,}" == "winxp"* ]]; then
    if ! prepareXP "$iso" "$dir"; then
      error "Failed to prepare Windows XP ISO!" && return 1
    fi
  else
    if ! prepareLegacy "$iso" "$dir"; then
      error "Failed to prepare Windows ISO!" && return 1
    fi
  fi

  return 0
}

updateImage() {

  local iso="$1"
  local dir="$2"
  local asset="/run/assets/$3"
  local path src loc xml index result

  [ ! -s "$asset" ] || [ ! -f "$asset" ] && return 0

  path=$(find "$dir" -maxdepth 1 -type f -iname autounattend.xml | head -n 1)
  [ -n "$path" ] && cp "$asset" "$path"

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

  xml=$(basename "$asset")
  info "Adding $xml for automatic installation..."

  index="1"
  result=$(wimlib-imagex info -xml "$loc" | tr -d '\000')

  if [[ "${result^^}" == *"<IMAGE INDEX=\"2\">"* ]]; then
    index="2"
  fi

  if ! wimlib-imagex update "$loc" "$index" --command "add $asset /autounattend.xml" > /dev/null; then
    warn "failed to add $xml to ISO image, $FB" && return 1
  fi

  return 0
}

copyOEM() {
  local dir="$1"
  local folder="$STORAGE/oem"
  local src

  [ ! -d "$folder" ] && folder="$STORAGE/OEM"
  [ ! -d "$folder" ] && folder="$STORAGE/shared/oem"
  [ ! -d "$folder" ] && folder="$STORAGE/shared/OEM"
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
  local label="${BASE%.*}"
  local log="/run/shm/iso.log"
  local size size_gb space space_gb desc

  label="${label::30}"
  local out="$TMP/$label.tmp"
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

  if [[ "${BOOT_MODE,,}" != "windows_legacy" ]]; then

    if ! genisoimage -o "$out" -b "$ETFS" -no-emul-boot -c "$cat" -iso-level 4 -J -l -D -N -joliet-long -relaxed-filenames -V "$label" \
                     -udf -boot-info-table -eltorito-alt-boot -eltorito-boot "$EFISYS" -no-emul-boot -allow-limited-size -quiet "$dir" 2> "$log"; then
      failed="Y"
    fi

  else

    if [[ "${DETECTED,,}" != "winxp"* ]]; then

      if ! genisoimage -o "$out" -b "$ETFS" -no-emul-boot -c "$cat" -iso-level 2 -J -l -D -N -joliet-long -relaxed-filenames -V "$label" \
                       -udf -allow-limited-size -quiet "$dir" 2> "$log"; then
        failed="Y"
      fi

    else

      if ! genisoimage -o "$out" -b "$ETFS" -no-emul-boot -boot-load-seg 1984 -boot-load-size 4 -c "$cat" -iso-level 2 -J -l -D -N -joliet-long \
                       -relaxed-filenames -V "$label" -quiet "$dir" 2> "$log"; then
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

  if [ -f "$STORAGE/$BASE" ]; then
    error "File $STORAGE/$BASE does already exist?!" && return 1
  fi

  mv "$out" "$STORAGE/$BASE"
  return 0
}

bootWindows() {

  rm -rf "$TMP"

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
        mv "$STORAGE/windows.rom" "$STORAGE/$BOOT_MODE.rom"
      fi
      if [ -f "$STORAGE/windows.vars" ] && [ ! -f "$STORAGE/$BOOT_MODE.vars" ]; then
        mv "$STORAGE/windows.vars" "$STORAGE/$BOOT_MODE.vars"
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

if ! detectImage "$DIR"; then
  abortInstall "$ISO" && return 0
  exit 60
fi

if ! prepareImage "$ISO" "$DIR"; then
  abortInstall "$ISO" && return 0
  exit 60
fi

if ! updateImage "$ISO" "$DIR" "$XML"; then
  abortInstall "$ISO" && return 0
  exit 60
fi

if ! rm -f "$ISO" 2> /dev/null; then
  BASE="windows.iso"
  ISO="$STORAGE/$BASE"
  rm -f  "$ISO"
fi

if ! copyOEM "$DIR"; then
  exit 63
fi

if ! buildImage "$DIR"; then
  exit 65
fi

if ! finishInstall "$STORAGE/$BASE" "N"; then
  exit 69
fi

html "Successfully prepared image for installation..."
return 0

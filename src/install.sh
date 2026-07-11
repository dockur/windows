#!/usr/bin/env bash
set -Eeuo pipefail

ETFS="boot/etfsboot.com"
FB="falling back to manual installation!"
EFISYS="efi/microsoft/boot/efisys_noprompt.bin"

backup () {

  local count=1
  local iso="$1"
  local name="unknown"
  local root="$STORAGE/backups"
  local previous="$STORAGE/windows.base"

  if [ -f "$previous" ]; then

    previous=$(<"$previous")
    previous="${previous//[![:print:]]/}"

    [ -n "$previous" ] && name="${previous%.*}"

  fi

  if ! makeDir "$root"; then
    error "Failed to create directory \"$root\" !"
    return 1
  fi

  local folder="$name"
  local dir="$root/$folder"

  while [ -d "$dir" ]
  do
    (( count++ ))
    folder="${name}.${count}"
    dir="$root/$folder"
  done

  if ! makeDir "$dir"; then
    error "Failed to create directory \"$dir\" !"
    return 1
  fi

  [ -f "$iso" ] && mv -f "$iso" "$dir/"
  find "$STORAGE" -maxdepth 1 -type f -iname 'data.*' -not -iname '*.iso' -exec mv -n {} "$dir/" \;
  find "$STORAGE" -maxdepth 1 -type f -iname 'windows.*' -not -iname '*.iso' -exec mv -n {} "$dir/" \;
  find "$STORAGE" -maxdepth 1 -type f \( -iname '*.rom' -or -iname '*.vars' \) -exec mv -n {} "$dir/" \;

  [ -z "$(ls -A "$dir")" ] && rm -rf "$dir"
  [ -z "$(ls -A "$root")" ] && rm -rf "$root"

  return 0
}

skipInstall() {

  local iso="$1"
  local method=""
  local magic byte
  local boot="$STORAGE/windows.boot"
  local previous="$STORAGE/windows.base"

  if [ -f "$previous" ]; then

    previous=$(<"$previous")
    previous="${previous//[![:print:]]/}"

    if [ -n "$previous" ]; then
      if [[ "${STORAGE,,}/${previous,,}" != "${iso,,}" ]]; then

        if ! hasDisk; then

          rm -f "$STORAGE/$previous"
          return 1

        fi

        if [[ "${iso,,}" == "${STORAGE,,}/windows."* ]]; then
          method="your custom .iso file was changed"
        else
          if [[ "${previous,,}" != "windows."* ]]; then
            method="the VERSION variable was changed"
          else
            method="your custom .iso file was removed"

            if [ -f "$boot" ]; then
              info "Detected that $method, will be ignored."
              return 0
            fi

          fi
        fi

        info "Detected that $method, a backup of your previous installation will be saved..."
        ! backup "$STORAGE/$previous" && error "Backup failed!"

        return 1

      fi
    fi

  fi

  [ -f "$boot" ] && hasDisk && return 0

  [ ! -f "$iso" ] && return 1
  [ ! -s "$iso" ] && return 1

  # Check if the ISO was already processed by our script
  magic=$(dd if="$iso" bs=1 count=1 status=none | tr -d '\000')
  magic="$(printf '%s' "$magic" | od -A n -t x1 -v | tr -d ' \n')"
  byte="16" && enabled "$MANUAL" && byte="17"

  if [[ "$magic" != "$byte" ]]; then

    info "The ISO will be processed again because the configuration was changed..."
    return 1

  fi

  return 0
}

startInstall() {

  html "Starting $APP..."

  if [ -z "$CUSTOM" ]; then

    local file="${VERSION//\//}.iso"

    if [[ "${VERSION,,}" == "http"* ]]; then

      file=$(basename "${VERSION%%\?*}")
      printf -v file '%b' "${file//%/\\x}"
      file="${file//[!A-Za-z0-9._-]/_}"

    else

      local language
      language=$(getLanguage "$LANGUAGE" "culture")
      language="${language%%-*}"

      if [ -n "$language" ] && [[ "${language,,}" != "en" ]]; then
        file="${VERSION//\//}_${language,,}.iso"
      fi

    fi

    BOOT="$STORAGE/$file"

  fi

  TMP="$STORAGE/tmp"
  rm -rf "$TMP"

  skipInstall "$BOOT" && return 1

  if hasDisk; then
    ! backup "" && error "Backup failed!"
  fi

  if ! makeDir "$TMP"; then
    error "Failed to create directory \"$TMP\" !" && exit 50
  fi

  if [ -z "$CUSTOM" ]; then

    ISO=$(basename "$BOOT")
    ISO="$TMP/$ISO"

    if [ -f "$BOOT" ] && [ -s "$BOOT" ]; then
      mv -f "$BOOT" "$ISO"
    fi

  fi

  rm -f "$BOOT"

  find "$STORAGE" -maxdepth 1 -type f -iname 'data.*' -not -iname '*.iso' -delete
  find "$STORAGE" -maxdepth 1 -type f -iname 'windows.*' -not -iname '*.iso' -delete
  find "$STORAGE" -maxdepth 1 -type f \( -iname '*.rom' -or -iname '*.vars' \) -delete

  return 0
}

checkFreeSpace() {

  local dir="$1"
  local size="$2"
  local size_gb space space_gb

  size_gb=$(formatBytes "$size")
  space=$(df --output=avail -B 1 "$dir" | tail -n 1)
  space_gb=$(formatBytes "$space")

  if (( size > space )); then
    error "Not enough free space in $STORAGE, have $space_gb available but need at least $size_gb."
    return 1
  fi

  return 0
}

finishInstall() {

  local iso="$1"
  local aborted="$2"
  local base byte

  if [ ! -s "$iso" ] || [ ! -f "$iso" ]; then
    error "Failed to find ISO file: $iso" && return 1
  fi

  if [[ "$iso" == "$STORAGE/"* ]]; then
    if ! setOwner "$iso"; then
      error "Failed to set the owner for \"$iso\" !"
      return 1
    fi
  fi

  if [[ "$aborted" != [Yy1]* ]]; then
    # Mark ISO as prepared via magic byte
    byte="16" && enabled "$MANUAL" && byte="17"
    if ! printf '%b' "\x$byte" | dd of="$iso" bs=1 seek=0 count=1 conv=notrunc status=none; then
      warn "failed to set magic byte in ISO file: $iso"
    fi
  fi

  local file="$STORAGE/windows.ver"
  cp -f /etc/version "$file" || return 1

  if ! setOwner "$file"; then
    error "Failed to set the owner for \"$file\" !"
    return 1
  fi

  if [[ "$iso" == "$STORAGE/"* ]]; then
    if [[ "$aborted" != [Yy1]* ]] || [ -z "$CUSTOM" ]; then
      base=$(basename "$iso")
      writeState "base" "$base" || return 1
    fi
  fi

  if [[ "${PLATFORM,,}" == "x64" ]]; then
    if [[ "${BOOT_MODE,,}" == "windows_legacy" ]]; then
      writeState "mode" "$BOOT_MODE" || return 1
      if [[ "${MACHINE,,}" != "q35" ]]; then
        writeState "old" "$MACHINE" || return 1
      fi
    else
      # Enable secure boot + TPM on manual installs as Win11 requires
      if enabled "$MANUAL" || [[ "$aborted" == [Yy1]* ]]; then
        if [[ "${DETECTED,,}" == "win11"* ]]; then
          BOOT_MODE="windows_secure"
          writeState "mode" "$BOOT_MODE" || return 1
        fi
      fi
      # Enable secure boot on multi-socket systems to workaround freeze
      if [ -n "$SOCKETS" ] && [[ "$SOCKETS" != "1" ]]; then
        BOOT_MODE="windows_secure"
        writeState "mode" "$BOOT_MODE" || return 1
      fi
    fi
  fi

  if [ -n "${ARGS:-}" ]; then
    ARGUMENTS="$ARGS ${ARGUMENTS:-}"
    writeState "args" "$ARGS" || return 1
  fi

  if [ -n "${VGA:-}" ] && [[ "${VGA:-}" != "virtio"* ]]; then
    writeState "vga" "$VGA" || return 1
  fi

  if [ -n "${USB:-}" ] && [[ "${USB:-}" != "qemu-xhci"* ]]; then
    writeState "usb" "$USB" || return 1
  fi

  if [ -n "${DISK_TYPE:-}" ] && [[ "${DISK_TYPE:-}" != "scsi" ]]; then
    writeState "type" "$DISK_TYPE" || return 1
  fi

  if [ -n "${ADAPTER:-}" ] && [[ "${ADAPTER:-}" != "virtio-net-pci" ]]; then
    writeState "net" "$ADAPTER" || return 1
  fi

  rm -rf "$TMP"
  return 0
}

abortInstall() {

  local dir="$1"
  local iso="$2"
  local efi

  [[ "${iso,,}" == *".esd" ]] && exit 60
  enabled "${UNPACK:-}" && exit 60

  efi=$(find "$dir" -maxdepth 1 -type d -iname efi -print -quit)

  if [ -z "$efi" ]; then
    [[ "${PLATFORM,,}" == "x64" ]] && BOOT_MODE="windows_legacy"
  fi

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

findFile() {

  local dir file base
  local fname="$1"
  local boot="$STORAGE/windows.boot"

  dir=$(find / -maxdepth 1 -type d -iname "$fname" -print -quit)
  [ ! -d "$dir" ] && dir=$(find "$STORAGE" -maxdepth 1 -type d -iname "$fname" -print -quit)

  if [ -d "$dir" ]; then
    if ! hasDisk || [ ! -f "$boot" ]; then
      error "The bind $dir maps to a file that does not exist!" && return 1
    fi
  fi

  file=$(find / -maxdepth 1 -type f -iname "$fname" -print -quit)
  [ ! -s "$file" ] && file=$(find "$STORAGE" -maxdepth 1 -type f -iname "$fname" -print -quit)

  if [ ! -s "$file" ] && [[ "${VERSION,,}" != "http"* ]]; then
    base=$(basename "$VERSION")
    file="$STORAGE/$base"
  fi

  if [ ! -f "$file" ] || [ ! -s "$file" ]; then
    return 0
  fi

  local size
  size="$(stat -c%s "$file")"
  [ -z "$size" ] || [[ "$size" == "0" ]] && return 0

  ISO="$file"
  CUSTOM="$file"
  BOOT="$STORAGE/windows.$size.iso"

  return 0
}

detectCustom() {

  CUSTOM=""

  ! findFile "custom.iso" && return 1
  [ -n "$CUSTOM" ] && return 0

  ! findFile "boot.iso" && return 1
  [ -n "$CUSTOM" ] && return 0

  return 0
}

getEsdField() {

  local list="$1"
  local index="$2"

  sed -n "${index}p" <<< "$list" | tr -cd '0-9'

  return 0
}

extractESD() {

  local iso="$1"
  local dir="$2"
  local version="$3"
  local desc="$4"

  local msg ret index
  local minSize freeSpace bootPad installPad
  local info count totals links
  local bootTotal bootLinks bootSize
  local wimTotal wimLinks wimSize
  local installSize
  local bootWim installWim
  local edition imgEdition

  minSize=100000000
  freeSpace=9606127360
  bootPad=60000000
  installPad=3000000

  msg="Extracting $desc bootdisk"
  info "$msg..." && html "$msg..."

  if [ "$(stat -c%s "$iso")" -lt "$minSize" ]; then
    error "Invalid ESD file: Size is smaller than 100 MB"
    return 1
  fi

  rm -rf "$dir"

  if ! makeDir "$dir"; then
    error "Failed to create directory \"$dir\" !"
    return 1
  fi

  checkFreeSpace "$dir" "$freeSpace" || return 1

  info=$(wimlib-imagex info "$iso") || {
    error "Cannot read ESD file information!"
    return 1
  }

  count=$(awk '/Image Count:/ {print $3}' <<< "$info")

  if [[ ! "$count" =~ ^[0-9]+$ ]]; then
    error "Cannot read the image count in ESD file!"
    return 1
  fi

  if (( count < 3 )); then
    error "Invalid ESD file: expected at least 3 images, found $count."
    return 1
  fi

  totals=$(grep "Total Bytes:" <<< "$info" || true)
  links=$(grep "Hard Link Bytes:" <<< "$info" || true)

  bootTotal=$(getEsdField "$totals" 1)
  bootLinks=$(getEsdField "$links" 1)

  if [[ ! "$bootTotal" =~ ^[0-9]+$ ]] || [[ ! "$bootLinks" =~ ^[0-9]+$ ]]; then
    error "Cannot read bootdisk size from ESD file!"
    return 1
  fi

  bootSize=$(( bootTotal - bootLinks ))

  wimTotal=$(getEsdField "$totals" 3)
  wimLinks=$(getEsdField "$links" 3)

  if [[ ! "$wimTotal" =~ ^[0-9]+$ ]] || [[ ! "$wimLinks" =~ ^[0-9]+$ ]]; then
    error "Cannot read boot.wim size from ESD file!"
    return 1
  fi

  wimSize=$(( wimTotal - wimLinks + bootPad ))

  /run/progress.sh "$dir" "$bootSize" "$msg ([P])..." &

  index="1"
  wimlib-imagex apply "$iso" "$index" "$dir" --quiet 2>/dev/null || {
    ret=$?
    fKill "progress.sh"
    error "Extracting $desc bootdisk failed ($ret)"
    return 1
  }

  fKill "progress.sh"

  bootWim="$dir/sources/boot.wim"
  installWim="$dir/sources/install.wim"

  msg="Extracting $desc environment"
  info "$msg..." && html "$msg..."

  index="2"
  /run/progress.sh "$bootWim" "$wimSize" "$msg ([P])..." &

  wimlib-imagex export "$iso" "$index" "$bootWim" --compress=none --quiet || {
    ret=$?
    fKill "progress.sh"
    error "Adding WinPE failed ($ret)"
    return 1
  }

  fKill "progress.sh"

  msg="Extracting $desc setup"
  info "$msg..."

  index="3"
  /run/progress.sh "$bootWim" "$wimSize" "$msg ([P])..." &

  wimlib-imagex export "$iso" "$index" "$bootWim" --compress=none --boot --quiet || {
    ret=$?
    fKill "progress.sh"
    error "Adding Windows Setup failed ($ret)"
    return 1
  }

  fKill "progress.sh"

  if [[ "${PLATFORM,,}" == "x64" ]]; then
    LABEL="CCCOMA_X64FRE_EN-US_DV9"
  else
    LABEL="CPBA_A64FRE_EN-US_DV9"
  fi

  msg="Extracting $desc image"
  info "$msg..." && html "$msg..."

  edition=$(getCatalog "$version" "name")

  if [ -z "$edition" ]; then
    error "Invalid VERSION specified, value \"$version\" is not recognized!"
    return 1
  fi

  for (( index=4; index<=count; index++ )); do

    imgEdition=$(wimlib-imagex info "$iso" "$index" | grep '^Description:' | sed 's/Description:[ \t]*//')
    [[ "${imgEdition,,}" != "${edition,,}" ]] && continue

    installSize=$(stat -c%s "$iso")
    installSize=$(( installSize + installPad ))

    /run/progress.sh "$installWim" "$installSize" "$msg ([P])..." &

    wimlib-imagex export "$iso" "$index" "$installWim" --compress=LZMS --chunk-size 128K --quiet || {
      ret=$?
      fKill "progress.sh"
      error "Addition of $index to the $desc image failed ($ret)"
      return 1
    }

    fKill "progress.sh"
    return 0

  done

  fKill "progress.sh"
  error "Failed to find product '$edition' in install.wim!"
  return 1
}

extractImage() {

  local iso="$1"
  local dir="$2"
  local version="$3"
  local desc="local ISO"
  local file size

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

  local msg="Extracting $desc image"
  info "$msg..." && html "$msg..."

  rm -rf "$dir"

  if ! makeDir "$dir"; then
    error "Failed to create directory \"$dir\" !" && return 1
  fi

  size=$(stat -c%s "$iso")

  if (( size < 100000000 )); then
    error "Invalid ISO file: Size is smaller than 100 MB" && return 1
  fi

  checkFreeSpace "$dir" "$size" || return 1

  rm -rf "$dir"
  /run/progress.sh "$dir" "$size" "$msg ([P])..." &

  if ! 7z x "$iso" -o"$dir" > /dev/null; then
    fKill "progress.sh"
    error "Failed to extract ISO file: $iso" && return 1
  fi

  fKill "progress.sh"

  if ! enabled "${UNPACK:-}"; then

    LABEL=$(isoinfo -d -i "$iso" | sed -n 's/Volume id: //p') || LABEL=""

  else

    file=$(find "$dir" -maxdepth 1 -type f -iname "*.iso" -print -quit)

    if [ -z "$file" ]; then
      error "Failed to find any .iso file in archive!" && return 1
    fi

    if ! 7z x "$file" -o"$dir" > /dev/null; then
      error "Failed to extract archive!" && return 1
    fi

    LABEL=$(isoinfo -d -i "$file" | sed -n 's/Volume id: //p') || LABEL=""
    rm -f "$file" || warn "Failed to remove temporary ISO file: $file"

  fi

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
    "12" ) platform="arm64" ;;
  esac

  echo "$platform"
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

detectLanguage() {

  local xml="$1"
  local lang=""

  if [[ "$xml" == *"LANGUAGE><DEFAULT>"* ]]; then
    lang="${xml#*LANGUAGE><DEFAULT>}"
    lang="${lang%%<*}"
  else
    if [[ "$xml" == *"FALLBACK><DEFAULT>"* ]]; then
      lang="${xml#*FALLBACK><DEFAULT>}"
      lang="${lang%%<*}"
    fi
  fi

  if [ -z "$lang" ]; then
   warn "Language could not be detected from ISO!" && return 0
  fi

  local culture
  culture=$(getLanguage "$lang" "culture")
  [ -n "$culture" ] && LANGUAGE="$lang" && return 0

  warn "Invalid language detected: \"$lang\""
  return 0
}

setXML() {

  local file="/custom.xml"

  if [ -d "$file" ]; then
    error "The bind $file maps to a file that does not exist!" && exit 67
  fi

  [ ! -f "$file" ] || [ ! -s "$file" ] && file="$STORAGE/custom.xml"
  [ ! -f "$file" ] || [ ! -s "$file" ] && file="/run/assets/custom.xml"
  [ ! -f "$file" ] || [ ! -s "$file" ] && file="$1"
  [ ! -f "$file" ] || [ ! -s "$file" ] && file="/run/assets/$DETECTED.xml"
  [ ! -f "$file" ] || [ ! -s "$file" ] && return 1

  XML="$file"
  return 0
}

detectImage() {

  local dir="$1"
  local version="$2"
  local desc msg language

  XML=""

  if [ -z "$DETECTED" ] && [ -z "$CUSTOM" ]; then
    [[ "${version,,}" != "http"* ]] && DETECTED="$version"
  fi

  if [ -n "$DETECTED" ]; then

    skipVersion "${DETECTED,,}" && return 0

    if ! setXML "" && ! enabled "$MANUAL"; then
      MANUAL="Y"
      desc=$(printEdition "$DETECTED" "this version")
      warn "the answer file for $desc was not found ($DETECTED.xml), $FB."
    fi

    return 0
  fi

  info "Detecting version from ISO image..."

  if detectLegacy "$dir"; then
    desc=$(printEdition "$DETECTED" "$DETECTED")
    info "Detected: $desc"
    return 0
  fi

  local src wim info
  src=$(find "$dir" -maxdepth 1 -type d -iname sources -print -quit)

  if [ ! -d "$src" ]; then
    warn "failed to locate 'sources' folder in ISO image, $FB" && return 1
  fi

  wim=$(find "$src" -maxdepth 1 -type f \( -iname install.wim -or -iname install.esd \) -print -quit)

  if [ ! -f "$wim" ]; then
    warn "failed to locate 'install.wim' or 'install.esd' in ISO image, $FB" && return 1
  fi

  if ! info=$(wimlib-imagex info -xml "$wim" | iconv -f UTF-16LE -t UTF-8); then
    warn "failed to read Windows image information, $FB"
    return 1
  fi

  checkPlatform "$info" || exit 67

  DETECTED=$(detectVersion "$info")

  if [ -z "$DETECTED" ]; then
    msg="Failed to determine Windows version from image"
    if setXML "" || enabled "$MANUAL"; then
      info "${msg}!"
    else
      MANUAL="Y"
      warn "${msg}, $FB."
    fi
    return 0
  fi

  desc=$(printEdition "$DETECTED" "$DETECTED")
  detectLanguage "$info"

  if [[ "${LANGUAGE,,}" != "en" && "${LANGUAGE,,}" != "en-"* ]]; then
    language=$(getLanguage "$LANGUAGE" "desc")
    desc+=" ($language)"
  fi

  info "Detected: $desc"
  setXML "" && return 0

  if [[ "$DETECTED" == "win81x86"* || "$DETECTED" == "win10x86"* ]]; then
    error "The 32-bit version of $desc is not supported!" && return 1
  fi

  msg="the answer file for $desc was not found ($DETECTED.xml)"
  local fallback="/run/assets/${DETECTED%%-*}.xml"

  if setXML "$fallback" || enabled "$MANUAL"; then
    ! enabled "$MANUAL" && warn "${msg}."
  else
    MANUAL="Y"
    warn "${msg}, $FB."
  fi

  return 0
}

prepareImage() {

  local iso="$1"
  local dir="$2"
  local desc missing

  desc=$(printVersion "$DETECTED" "$DETECTED")

  setMachine "$DETECTED" "$iso" "$dir" "$desc" || return 1
  skipVersion "$DETECTED" && return 0

  if [[ "${BOOT_MODE,,}" != "windows_legacy" ]]; then

    [ -f "$dir/$ETFS" ] && [ -f "$dir/$EFISYS" ] && return 0

    missing=$(basename "$dir/$EFISYS")
    [ ! -f "$dir/$ETFS" ] && missing=$(basename "$dir/$ETFS")

    error "Failed to locate file \"${missing,,}\" in ISO image!"
    return 1
  fi

  prepareLegacy "$iso" "$dir" "$desc" && return 0

  error "Failed to extract boot image from ISO image!"
  return 1
}

updateXML() {

  local asset="$1"
  local language="$2"
  local culture region user admin pass pw keyboard

  [ -z "$HEIGHT" ] && HEIGHT="720"
  [ -z "$WIDTH" ] && WIDTH="1280"

  sed -i "s/>Windows for Docker</>$APP for $ENGINE</g" "$asset"
  sed -i "s/<VerticalResolution>1080<\/VerticalResolution>/<VerticalResolution>$HEIGHT<\/VerticalResolution>/g" "$asset"
  sed -i "s/<HorizontalResolution>1920<\/HorizontalResolution>/<HorizontalResolution>$WIDTH<\/HorizontalResolution>/g" "$asset"

  culture=$(getLanguage "$language" "culture")

  if [ -n "$culture" ] && [[ "${culture,,}" != "en-us" ]]; then
    sed -i "s/<UILanguage>en-US<\/UILanguage>/<UILanguage>$culture<\/UILanguage>/g" "$asset"
  fi

  region="$REGION"
  [ -z "$region" ] && region="$culture"

  if [ -n "$region" ] && [[ "${region,,}" != "en-us" ]]; then
    sed -i "s/<UserLocale>en-US<\/UserLocale>/<UserLocale>$region<\/UserLocale>/g" "$asset"
    sed -i "s/<SystemLocale>en-US<\/SystemLocale>/<SystemLocale>$region<\/SystemLocale>/g" "$asset"
  fi

  keyboard="$KEYBOARD"
  [ -z "$keyboard" ] && keyboard="$culture"

  if [ -n "$keyboard" ] && [[ "${keyboard,,}" != "en-us" ]]; then
    sed -i "s/<InputLocale>en-US<\/InputLocale>/<InputLocale>$keyboard<\/InputLocale>/g" "$asset"
    sed -i "s/<InputLocale>0409:00000409<\/InputLocale>/<InputLocale>$keyboard<\/InputLocale>/g" "$asset"
  fi

  user=$(echo "$USERNAME" | sed 's/[^[:alnum:]@!._-]//g')

  if [ -n "$user" ]; then
    sed -i "s/-name \"Docker\"/-name \"$user\"/g" "$asset"
    sed -i "s/<Name>Docker<\/Name>/<Name>$user<\/Name>/g" "$asset"
    sed -i "s/where name=\"Docker\"/where name=\"$user\"/g" "$asset"
    sed -i "s/<FullName>Docker<\/FullName>/<FullName>$user<\/FullName>/g" "$asset"
    sed -i "s/<Username>Docker<\/Username>/<Username>$user<\/Username>/g" "$asset"
  fi

  [ -n "$PASSWORD" ] && pass="$PASSWORD" || pass="admin"

  pw=$(printf '%s' "${pass}Password" | iconv -f utf-8 -t utf-16le | base64 -w 0)
  admin=$(printf '%s' "${pass}AdministratorPassword" | iconv -f utf-8 -t utf-16le | base64 -w 0)

  sed -i "s|<Value>password<\/Value>|<Value>$admin<\/Value>|g" "$asset"
  sed -i "s|<PlainText>true<\/PlainText>|<PlainText>false<\/PlainText>|g" "$asset"
  sed -i -z "s|<Password>...........<Value \/>|<Password>\n          <Value>$pw<\/Value>|g" "$asset"
  sed -i -z "s|<Password>...............<Value \/>|<Password>\n              <Value>$pw<\/Value>|g" "$asset"
  sed -i -z "s|<AdministratorPassword>...........<Value \/>|<AdministratorPassword>\n          <Value>$admin<\/Value>|g" "$asset"
  sed -i -z "s|<AdministratorPassword>...............<Value \/>|<AdministratorPassword>\n              <Value>$admin<\/Value>|g" "$asset"

  if [ -n "$EDITION" ]; then
    [[ "${EDITION^^}" == "CORE" ]] && EDITION="STANDARDCORE"
    sed -i "s/SERVERSTANDARD<\/Value>/SERVER${EDITION^^}<\/Value>/g" "$asset"
  fi

  if [ -n "$KEY" ]; then
    sed -i '/<ProductKey>/,/<\/ProductKey>/d' "$asset"
    sed -i "s/<\/UserData>/  <ProductKey>\n          <Key>${KEY}<\/Key>\n          <WillShowUI>OnError<\/WillShowUI>\n        <\/ProductKey>\n      <\/UserData>/g" "$asset"
  fi

  return 0
}

addDriver() {

  local id="$1"
  local path="$2"
  local target="$3"
  local driver="$4"
  local desc=""
  local folder=""

  if [ -z "$id" ]; then
    warn "no Windows version specified for \"$driver\" driver!" && return 0
  fi

  case "${id,,}" in
    "win7x86"* ) folder="w7/x86" ;;
    "win7x64"* ) folder="w7/amd64" ;;
    "win81x64"* ) folder="w8.1/amd64" ;;
    "win10x64"* ) folder="w10/amd64" ;;
    "win11x64"* ) folder="w11/amd64" ;;
    "win2025"* ) folder="2k25/amd64" ;;
    "win2022"* ) folder="2k22/amd64" ;;
    "win2019"* ) folder="2k19/amd64" ;;
    "win2016"* ) folder="2k16/amd64" ;;
    "win2012"* ) folder="2k12R2/amd64" ;;
    "win2008"* ) folder="2k8R2/amd64" ;;
    "win10arm64"* ) folder="w10/ARM64" ;;
    "win11arm64"* ) folder="w11/ARM64" ;;
    "winvistax86"* ) folder="2k8/x86" ;;
    "winvistax64"* ) folder="2k8/amd64" ;;
  esac

  if [ -z "$folder" ]; then
    desc=$(printVersion "$id" "$id")
    if [[ "${id,,}" != *"x86"* ]]; then
      warn "no \"$driver\" driver available for \"$desc\" !" && return 0
    else
      warn "no \"$driver\" driver available for the 32-bit version of \"$desc\" !" && return 0
    fi
  fi

  [ ! -d "$path/$driver/$folder" ] && return 0

  case "${id,,}" in
    "winvista"* )
      [[ "${driver,,}" == "viorng" ]] && return 0
      ;;
  esac

  local dest="$path/$target/$driver"
  mkdir -p "$dest" || return 1
  cp -Lr "$path/$driver/$folder/." "$dest" || return 1

  return 0
}

addDrivers() {

  local src="$1"
  local tmp="$2"
  local file="$3"
  local index="$4"
  local version="$5"
  local drivers="$tmp/drivers"

  rm -rf "$drivers"
  mkdir -p "$drivers"

  local msg="Adding drivers to image..."
  info "$msg" && html "$msg"

  if [ -z "$version" ]; then
    version="win11x64"
    warn "Windows version unknown, falling back to Windows 11 drivers..."
  fi

  if ! bsdtar -xf /var/drivers.txz -C "$drivers"; then
    error "Failed to extract drivers from archive!" && return 1
  fi

  local target="\$WinPEDriver\$"
  local dest="$drivers/$target"
  mkdir -p "$dest" || return 1

  wimlib-imagex update "$file" "$index" --command "delete --force --recursive /$target" >/dev/null || true

  local driver
  local driver_list=( qxl viofs sriov smbus qxldod viorng viostor viomem NetKVM Balloon vioscsi pvpanic vioinput viogpudo vioserial qemupciserial )

  for driver in "${driver_list[@]}"; do
    addDriver "$version" "$drivers" "$target" "$driver" || return 1
  done

  local dst="$src/\$OEM\$/\$\$/Drivers"
  mkdir -p "$dst" || return 1
  cp -Lr "$dest/." "$dst" || return 1

  case "${version,,}" in
    "win11x64"* | "win2025"* )
      # Workaround Virtio GPU driver bug
      rm -rf "$dest/viogpudo"
      ;;
  esac

  if ! wimlib-imagex update "$file" "$index" --command "add $dest /$target" >/dev/null; then
    return 1
  fi

  rm -rf "$drivers"
  return 0
}

updateImage() {

  local dir="$1"
  local asset="$2"
  local language="$3"
  local tmp="/tmp/install"
  local xml="autounattend.xml"
  local bak="${xml//.xml/.org}"
  local dat="${xml//.xml/.dat}"
  local desc path src wim name info idx

  skipVersion "${DETECTED,,}" && return 0

  if [ ! -s "$asset" ] || [ ! -f "$asset" ]; then
    asset=""
    if ! enabled "$MANUAL"; then
      MANUAL="Y"
      warn "no answer file provided, $FB."
    fi
  fi

  rm -rf "$tmp"
  mkdir -p "$tmp"

  src=$(find "$dir" -maxdepth 1 -type d -iname sources -print -quit)

  if [ ! -d "$src" ]; then
    error "failed to locate 'sources' folder in ISO image, $FB"
    return 1
  fi

  wim=$(find "$src" -maxdepth 1 -type f \( -iname boot.wim -or -iname boot.esd \) -print -quit)

  if [ ! -f "$wim" ]; then
    error "failed to locate 'boot.wim' or 'boot.esd' in ISO image, $FB"
    return 1
  fi

  idx="1"

  if ! info=$(wimlib-imagex info -xml "$wim" | iconv -f UTF-16LE -t UTF-8); then
    warn "failed to read boot image information, $FB"
    MANUAL="Y"
    info=""
  fi

  if [[ "${info^^}" == *"<IMAGE INDEX=\"2\">"* ]]; then
    idx="2"
  fi

  if ! addDrivers "$src" "$tmp" "$wim" "$idx" "$DETECTED"; then
    error "Failed to add drivers to image!"
  fi

  if ! addFolder "$src"; then
    error "Failed to add OEM folder to image!"
  fi

  if wimlib-imagex extract "$wim" "$idx" "/$xml" "--dest-dir=$tmp" >/dev/null 2>&1; then
    if ! wimlib-imagex extract "$wim" "$idx" "/$dat" "--dest-dir=$tmp" >/dev/null 2>&1; then
      if ! wimlib-imagex extract "$wim" "$idx" "/$bak" "--dest-dir=$tmp" >/dev/null 2>&1; then
        if ! wimlib-imagex update "$wim" "$idx" --command "rename /$xml /$bak" > /dev/null; then
          warn "failed to backup original answer file ($xml)."
        fi
      fi
    fi
  fi

  if ! enabled "$MANUAL"; then

    name=$(basename "$asset")
    local answer="$tmp/$name"

    info "Adding $name for automatic installation..."

    if ! cp "$asset" "$answer"; then
      error "Failed to copy answer file to $answer."
      return 1
    fi

    if ! updateXML "$answer" "$language"; then
      error "Failed to update answer file: $answer"
      return 1
    fi

    if ! wimlib-imagex update "$wim" "$idx" --command "add $answer /$xml" > /dev/null; then
      MANUAL="Y"
      warn "failed to add answer file ($name) to ISO image, $FB"
    else
      wimlib-imagex update "$wim" "$idx" --command "add $answer /$dat" > /dev/null || true
    fi

  fi

  if enabled "$MANUAL"; then

    wimlib-imagex update "$wim" "$idx" --command "delete --force /$xml" > /dev/null || true

    if wimlib-imagex extract "$wim" "$idx" "/$bak" "--dest-dir=$tmp" >/dev/null 2>&1; then
      if ! wimlib-imagex update "$wim" "$idx" --command "add $tmp/$bak /$xml" > /dev/null; then
        warn "failed to restore original answer file ($bak)."
      fi
    fi

  fi

  name="$xml"
  enabled "$MANUAL" && name="$bak"
  path=$(find "$dir" -maxdepth 1 -type f -iname "$name" -print -quit)

  if [ -f "$path" ]; then
    if ! enabled "$MANUAL"; then
      if ! mv -f "$path" "${path%.*}.org"; then
        error "Failed to rename answer file: $path"
        return 1
      fi
    else
      if ! mv -f "$path" "${path%.*}.xml"; then
        error "Failed to rename answer file: $path"
        return 1
      fi
    fi
  fi

  rm -rf "$tmp"
  return 0
}

removeImage() {

  local iso="$1"

  [ ! -f "$iso" ] && return 0
  [ -n "$CUSTOM" ] && return 0

  rm -f "$iso" 2> /dev/null || warn "failed to remove $iso !"

  return 0
}

buildImage() {

  local dir="$1"
  local failed=""
  local cat="BOOT.CAT"
  local log="/run/shm/iso.log"
  local base size desc

  if [ -f "$BOOT" ]; then
    error "File $BOOT does already exist?!" && return 1
  fi

  base=$(basename "$BOOT")
  local out="$TMP/${base%.*}.tmp"
  rm -f "$out"

  desc=$(printVersion "$DETECTED" "ISO")

  local msg="Building $desc image"
  info "$msg..." && html "$msg..."

  [ -z "$LABEL" ] && LABEL="Windows"

  if [ ! -f "$dir/$ETFS" ]; then
    error "Failed to locate file \"$ETFS\" in ISO image!" && return 1
  fi

  size=$(du -b --max-depth=0 "$dir" | cut -f1)
  checkFreeSpace "$TMP" "$size" || return 1

  /run/progress.sh "$out" "$size" "$msg ([P])..." &

  if [[ "${BOOT_MODE,,}" != "windows_legacy" ]]; then

    genisoimage -o "$out" -b "$ETFS" -no-emul-boot -c "$cat" -iso-level 4 -J -l -D -N -joliet-long -relaxed-filenames -V "${LABEL::30}" \
                  -udf -boot-info-table -eltorito-alt-boot -eltorito-boot "$EFISYS" -no-emul-boot -allow-limited-size -quiet "$dir" 2> "$log" || failed="y"

  else

    case "${DETECTED,,}" in
      "win2k"* | "winxp"* | "win2003"* )
        genisoimage -o "$out" -b "$ETFS" -no-emul-boot -boot-load-seg 1984 -boot-load-size 4 -c "$cat" -iso-level 2 -J -l -D -N -joliet-long \
                      -relaxed-filenames -V "${LABEL::30}" -quiet "$dir" 2> "$log" || failed="y" ;;
      "win9"* )
        genisoimage -o "$out" -b "$ETFS" -J -r -V "${LABEL::30}" -quiet "$dir" 2> "$log" || failed="y" ;;
      * )
        genisoimage -o "$out" -b "$ETFS" -no-emul-boot -c "$cat" -iso-level 2 -J -l -D -N -joliet-long -relaxed-filenames -V "${LABEL::30}" \
                      -udf -allow-limited-size -quiet "$dir" 2> "$log" || failed="y" ;;
    esac

  fi

  fKill "progress.sh"

  if [ -n "$failed" ]; then
    [ -s "$log" ] && echo "$(<"$log")"
    error "Failed to build image!" && return 1
  fi

  local err=""
  local hide="Warning: creating filesystem that does not conform to ISO-9660."

  [ -s "$log" ] && err="$(<"$log")"
  [[ "$err" != "$hide" ]] && echo "$err"

  mv -f "$out" "$BOOT" || return 1

  if ! setOwner "$BOOT"; then
    error "Failed to set the owner for \"$BOOT\" !"
    return 1
  fi

  return 0
}

bootWindows() {

  ARGS=$(readState "$STORAGE/windows.args") || return 1

  if [ -n "$ARGS" ]; then
    ARGUMENTS="$ARGS ${ARGUMENTS:-}"
  fi

  restoreState "VGA" "$STORAGE/windows.vga" || return 1
  restoreState "USB" "$STORAGE/windows.usb" || return 1
  restoreState "ADAPTER" "$STORAGE/windows.net" || return 1
  restoreState "DISK_TYPE" "$STORAGE/windows.type" || return 1
  restoreState "BOOT_MODE" "$STORAGE/windows.mode" "Y" || return 1

  if [[ "${PLATFORM,,}" == "x64" ]]; then
    restoreState "MACHINE" "$STORAGE/windows.old" "Y" || return 1
  fi

  return 0
}

######################################

! parseVersion && exit 58
! parseLanguage && exit 56
! detectCustom && exit 59

if ! startInstall; then
  bootWindows && return 0
  exit 68
fi

if [ ! -s "$ISO" ] || [ ! -f "$ISO" ]; then
  if ! downloadImage "$ISO" "$VERSION" "$LANGUAGE"; then
    rm -f "$ISO" 2> /dev/null || true
    exit 61
  fi
fi

DIR="$TMP/unpack"

if ! extractImage "$ISO" "$DIR" "$VERSION"; then
  rm -f "$ISO" 2> /dev/null || true
  exit 62
fi

if ! detectImage "$DIR" "$VERSION"; then
  abortInstall "$DIR" "$ISO" && return 0
  exit 60
fi

if ! prepareImage "$ISO" "$DIR"; then
  abortInstall "$DIR" "$ISO" && return 0
  exit 66
fi

if ! updateImage "$DIR" "$XML" "$LANGUAGE"; then
  abortInstall "$DIR" "$ISO" && return 0
  exit 63
fi

if ! removeImage "$ISO"; then
  exit 64
fi

if ! buildImage "$DIR"; then
  exit 65
fi

if ! finishInstall "$BOOT" "N"; then
  exit 69
fi

html "Successfully prepared image for installation..."
return 0

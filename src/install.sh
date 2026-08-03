#!/usr/bin/env bash
set -Eeuo pipefail

startWindows() {

  parseVersion || return 58
  parseLanguage || return 62
  detectCustom || return 64

  if ! startInstall; then
    bootWindows || return 66
    return 0
  fi

  if ! hasImage "$ISO"; then
    if ! downloadImage "$ISO" "$VERSION" "$LANGUAGE"; then
      removeIso "$ISO" && return 68
    fi
  fi

  proceed=0
  extracted=0

  local boot="$BOOT"
  local dir="$TMP/unpack"

  selectWindowsImage "$ISO" "$dir" "$boot" || return $?
  (( proceed )) || return 0

  configureMachine "$ISO" "$dir" "$boot" || return $?
  (( proceed )) || return 0

  prepareWindowsImage "$ISO" "$dir" "$boot" || return $?
  (( proceed )) || return 0

  finishInstall "$BOOT" "N" "$boot" || return 100

  return 0
}

selectWindowsImage() {

  local iso="$1"
  local dir="$2"
  local boot="$3"
  local detect_rc=0

  proceed=0

  # If VERSION is specified we don't need the image metadata.
  if resolveImage "$VERSION"; then

    if ! setImage; then
      abortInstall "$dir" "$iso" "$boot" || return 70
      return 0
    fi

    # Some known image types still require extraction.
    if ! needsExtraction "$DETECTED" "$iso"; then
      proceed=1
      return 0
    fi

    if ! extractImage "$iso" "$dir" "$VERSION"; then
      removeIso "$iso" && return 72
    fi

    extracted=1
    proceed=1
    return 0

  fi

  # Inspect unknown/custom ISOs before falling back to extraction.
  detectIsoImage "$iso" || detect_rc=$?

  # Detection succeeded, so the original ISO can remain untouched.
  if (( detect_rc == 0 )); then
    proceed=1
    return 0
  fi

  # Only return code 1 means direct inspection was unavailable and extraction
  # may still recover the image. Other failures indicate unusable media.
  if (( detect_rc != 1 )); then
    abortInstall "$dir" "$iso" "$boot" || return 76
    return 0
  fi

  if ! extractImage "$iso" "$dir" "$VERSION"; then
    removeIso "$iso" && return 74
  fi

  extracted=1

  # The legacy detector operates on the extracted filesystem.
  if ! detectImage "$dir"; then
    abortInstall "$dir" "$iso" "$boot" || return 76
    return 0
  fi

  proceed=1
  return 0
}

configureMachine() {

  local iso="$1"
  local dir="$2"
  local boot="$3"
  local desc

  proceed=0

  if ! desc=$(printVariant "$DETECTED" "$DETECTED"); then
    abortInstall "$dir" "$iso" "$boot" || return 78
    return 0
  fi

  if ! setMachine "$DETECTED" "$iso" "$dir" "$desc"; then
    abortInstall "$dir" "$iso" "$boot" || return 80
    return 0
  fi

  if ! restoreMachineState; then
    abortInstall "$dir" "$iso" "$boot" || return 82
    return 0
  fi

  # Some media must boot directly and skip all preparation.
  if bootDirect "$DETECTED"; then
    abortInstall "$dir" "$iso" "$boot" || return 83
    return 0
  fi

  proceed=1
  return 0
}

prepareWindowsImage() {

  local iso="$1"
  local dir="$2"
  local boot="$3"

  proceed=0

  # Prefer the helper image method whenever Windows Setup can consume the original
  # ISO directly. This avoids extracting and rebuilding the whole installation media.
  if canUseSetupImage "$DETECTED" "$iso"; then

    if ! stageSetup "$XML" "$LANGUAGE" "$TMP/setup"; then
      abortInstall "$dir" "$iso" "$boot" || return 84
      return 0
    fi

    if ! createSetupImage "$TMP/setup" "$STORAGE/setup.img"; then
      exit 86
    fi

    useOriginalImage "$iso" || return 88

    proceed=1
    return 0

  fi

  # Fall back to extracting and rebuilding when Setup cannot use the original
  # ISO directly, such as legacy media or formats requiring in-place changes.
  if (( ! extracted )); then
    if ! extractImage "$iso" "$dir" "$VERSION"; then
      removeIso "$iso" && return 90
    fi
  fi

  if ! prepareImage "$iso" "$dir"; then
    abortInstall "$dir" "$iso" "$boot" || return 92
    return 0
  fi

  if ! updateImage "$dir" "$XML" "$LANGUAGE"; then
    abortInstall "$dir" "$iso" "$boot" || return 94
    return 0
  fi

  removeImage "$iso" || return 96
  buildImage "$dir" || return 98

  proceed=1
  return 0
}

bootWindows() {

  restoreMachineState || return 1
  restoreBootMode || return 1
  restoreMachine || return 1
  reserveSambaPorts || return 1

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

    REUSED_ISO=""
    [ -s "$BOOT" ] && REUSED_ISO="Y"

    # Use the suggested answer file for a new automatic download. When an
    # existing ISO is reused, leave DETECTED empty so its actual image can
    # be inspected instead.
    if [ -n "$DETECTED" ]; then
      DETECTED_ORG="Y"
    elif [ -z "$REUSED_ISO" ]; then
      DETECTED="$SUGGEST"
    fi

  fi

  TMP="$STORAGE/tmp"

  if ! rm -rf -- "$TMP"; then
    error "Failed to remove directory \"$TMP\" !"
    exit 50
  fi

  local setup="$STORAGE/setup.img"

  if ! rm -f -- "$setup" "${setup}.tmp"; then
    error "Failed to remove setup image \"$setup\" !"
    exit 50
  fi

  local previousBase
  if ! previousBase=$(readState "base"); then
    error "Failed to read the previous installation state!"
    exit 50
  fi

  skipInstall "$BOOT" "$previousBase" && return 1

  if [ -z "$previousBase" ] && hasDisk; then
    if ! backup ""; then
      warn "the backup was incomplete, continuing with installation..."
    fi
  fi

  if ! makeDir "$TMP"; then
    error "Failed to create directory \"$TMP\" !"
    exit 50
  fi

  if [ -z "$CUSTOM" ]; then

    ISO=$(basename "$BOOT")
    ISO="$TMP/$ISO"

    if [ -f "$BOOT" ] && [ -s "$BOOT" ]; then
      if ! mv -f -- "$BOOT" "$ISO"; then
        error "Failed to move ISO file from \"$BOOT\" to \"$ISO\" !"
        exit 50
      fi
    fi

  fi

  if ! rm -f -- "$BOOT"; then
    error "Failed to remove ISO file \"$BOOT\" !"
    exit 50
  fi

  if ! find "$STORAGE" -maxdepth 1 -type f -iname 'data.*' -not -iname '*.iso' -delete; then
    error "Failed to remove obsolete disk files from \"$STORAGE\" !"
    exit 50
  fi

  if ! find "$STORAGE" -maxdepth 1 -type f -iname 'windows.*' -not -iname '*.iso' -delete; then
    error "Failed to remove obsolete Windows files from \"$STORAGE\" !"
    exit 50
  fi

  if ! find "$STORAGE" -maxdepth 1 -type f \( -iname '*.rom' -or -iname '*.vars' \) -delete; then
    error "Failed to remove obsolete firmware files from \"$STORAGE\" !"
    exit 50
  fi

  return 0
}

abortInstall() {

  local dir="$1"
  local iso="$2"
  local boot="$3"
  local efi efi32 efi64

  [[ "${iso,,}" == *".esd" ]] && exit 60
  enabled "${UNPACK:-}" && exit 60

  if [[ "${PLATFORM,,}" == "x64" ]] && [ -d "$dir" ]; then

    efi=$(find "$dir" -maxdepth 1 -type d -iname efi -print -quit)
    efi32=$(find "$dir" -maxdepth 3 -type f \
      -ipath '*/efi/boot/bootia32.efi' -print -quit)
    efi64=$(find "$dir" -maxdepth 3 -type f \
      -ipath '*/efi/boot/bootx64.efi' -print -quit)

    if [ -z "$efi" ] ||
      { [ -n "$efi32" ] && [ -z "$efi64" ]; }; then

      writeState "mode" "windows_legacy" || return 1
      restoreBootMode || return 1

    fi

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

  finishInstall "$BOOT" "Y" "$boot" && return 0
  return 1
}

useOriginalImage() {

  local iso="$1"

  if [ -n "$CUSTOM" ]; then
    BOOT="$iso"
    REMOVE="N"
    return 0
  fi

  if [[ "$iso" != "$BOOT" ]]; then
    if ! mv -f -- "$iso" "$BOOT"; then
      error "Failed to move ISO file: $iso"
      return 1
    fi
  fi

  return 0
}

skipInstall() {

  local iso="$1"
  local previousBase="$2"
  local boot="$STORAGE/windows.boot"

  if [ -n "$previousBase" ]; then
    if [[ "${STORAGE,,}/${previousBase,,}" != "${iso,,}" ]]; then

      if ! hasDisk; then

        if ! rm -f -- "$STORAGE/$previousBase"; then
          error "Failed to remove ISO file \"$STORAGE/$previousBase\" !"
          exit 50
        fi

        return 1

      fi

      local method

      if [[ "${iso,,}" == "${STORAGE,,}/windows."* ]]; then
        method="your custom .iso file was changed"
      else
        if [[ "${previousBase,,}" != "windows."* ]]; then
          method="the VERSION variable was changed"
        else
          method="your custom .iso file was removed"

          if [ -f "$boot" ] && hasData; then
            info "Detected that $method, will be ignored."
            return 0
          fi

        fi
      fi

      info "Detected that $method, a backup of your previous installation will be saved..."

      if ! backup "$STORAGE/$previousBase"; then
        warn "the backup was incomplete, continuing with installation..."
      fi

      return 1

    fi
  fi

  [ -f "$boot" ] && hasData && return 0

  return 1
}

finishInstall() {

  local iso="$1"
  local aborted="$2"
  local boot="$3"
  local base

  if [ ! -s "$iso" ] || [ ! -f "$iso" ]; then
    error "Failed to find ISO file: $iso" && return 1
  fi

  if [[ "$iso" == "$STORAGE/"* ]]; then
    if ! setOwner "$iso"; then
      warn "failed to set the owner for \"$iso\" !"
    fi
  fi

  local file="$STORAGE/windows.ver"
  cp -f /etc/version "$file" || return 1

  if ! setOwner "$file"; then
    warn "Failed to set the owner for \"$file\" !"
  fi

  if [[ "$boot" == "$STORAGE/"* ]]; then
    if [[ "$aborted" != [Yy1]* ]] || [ -z "$CUSTOM" ]; then
      base=$(basename "$boot")
      writeState "base" "$base" || return 1
    fi
  fi

  if [[ "${PLATFORM,,}" == "x64" ]]; then
    if [[ "${BOOT_MODE,,}" == "windows_legacy" ]]; then

      writeState "mode" "$BOOT_MODE" || return 1

    else

      local secure=0

      # Enable secure boot + TPM on manual installs as Win11 requires
      if enabled "$MANUAL" || [[ "$aborted" == [Yy1]* ]]; then
        [[ "${DETECTED,,}" == "win11"* ]] && secure=1
      fi

      if (( secure )); then
        BOOT_MODE="windows_secure"
        writeState "mode" "$BOOT_MODE" || return 1
      fi

    fi
  fi

  reserveSambaPorts || return 1

  rm -rf "$TMP"
  return 0
}

findFile() {

  local dir file base
  local fname="$1"
  local boot="$STORAGE/windows.boot"

  dir=$(find / -maxdepth 1 -type d -iname "$fname" -print -quit)
  [ ! -d "$dir" ] && dir=$(find "$STORAGE" -maxdepth 1 -type d -iname "$fname" -print -quit)

  if [ -d "$dir" ]; then
    if ! hasData || [ ! -f "$boot" ]; then
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

  if [ -z "$size" ] || [[ "$size" == "0" ]]; then
    return 0
  fi

  ISO="$file"
  CUSTOM="$file"
  BOOT="$STORAGE/windows.$size.iso"

  return 0
}

detectCustom() {

  CUSTOM=""

  findFile "custom.iso" || return 1
  [ -n "$CUSTOM" ] && return 0

  findFile "boot.iso" || return 1
  [ -n "$CUSTOM" ] && return 0

  return 0
}

hasImage() {

  local file="$1"

  [ -f "$file" ] && [ -s "$file" ]
}

removeIso() {

  local iso="$1"

  rm -f -- "$iso" 2>/dev/null || :

  return 0
}

needsExtraction() {

  local id="$1"
  local iso="$2"

  bootDirect "$id" && return 1

  skipVersion "$id" ||
    [[ "${iso,,}" == *".esd" ]] ||
    enabled "${UNPACK:-}"
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

extractESD() {

  local iso="$1"
  local dir="$2"
  local version="$3"
  local desc="$4"

  local bootTotal bootLinks
  local wimTotal wimLinks
  local installSize size
  local edition imgEdition
  local bootWim installWim
  local bootSize wimSize
  local index line ret
  local xml metadata count
  local -a fields

  local minSize=100000000
  local freeSpace=9606127360
  local bootPad=60000000
  local installPad=3000000

  local msg="Extracting $desc bootdisk"
  info "$msg..." && html "$msg..."

  if ! size=$(stat -c%s -- "$iso"); then
    error "Failed to determine size of ISO file \"$iso\" !"
    return 1
  fi

  if (( size < minSize )); then
    error "The downloaded ISO file is too small!"
    return 1
  fi

  if ! rm -rf -- "$dir"; then
    error "Failed to remove directory \"$dir\" !"
    return 1
  fi

  if ! makeDir "$dir"; then
    error "Failed to create directory \"$dir\" !"
    return 1
  fi

  checkFreeSpace "$dir" "$freeSpace" || return 1

  if ! xml=$(wimlib-imagex info "$iso" --xml 2>/dev/null |
      iconv -f UTF-16LE -t UTF-8 2>/dev/null); then
    error "Cannot read ESD file information!"
    return 1
  fi

  if ! metadata=$(xmlstarlet sel -t \
      -v 'count(/WIM/IMAGE)' -n \
      -v 'normalize-space(/WIM/IMAGE[@INDEX="1"]/TOTALBYTES)' -n \
      -v 'normalize-space(/WIM/IMAGE[@INDEX="1"]/HARDLINKBYTES)' -n \
      -v 'normalize-space(/WIM/IMAGE[@INDEX="3"]/TOTALBYTES)' -n \
      -v 'normalize-space(/WIM/IMAGE[@INDEX="3"]/HARDLINKBYTES)' -n \
      -m '/WIM/IMAGE[number(@INDEX) >= 4]' \
      -v '@INDEX' -o $'\t' -v 'DESCRIPTION' -n \
      <<< "$xml" 2>/dev/null); then
    error "Cannot read ESD file information!"
    return 1
  fi

  mapfile -t fields <<< "$metadata"

  count="${fields[0]:-}"
  if [[ ! "$count" =~ ^[0-9]+$ ]]; then
    error "Cannot read the image count in ESD file!"
    return 1
  fi

  if (( count < 3 )); then
    error "Invalid ESD file: expected at least 3 images, found $count."
    return 1
  fi

  bootTotal="${fields[1]:-}"
  bootLinks="${fields[2]:-}"

  if [[ ! "$bootTotal" =~ ^[0-9]+$ ]] ||
      [[ ! "$bootLinks" =~ ^[0-9]+$ ]]; then
    error "Cannot read bootdisk size from ESD file!"
    return 1
  fi

  bootSize=$(( bootTotal - bootLinks ))

  wimTotal="${fields[3]:-}"
  wimLinks="${fields[4]:-}"

  if [[ ! "$wimTotal" =~ ^[0-9]+$ ]] ||
      [[ ! "$wimLinks" =~ ^[0-9]+$ ]]; then
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

  wimlib-imagex export "$iso" "$index" "$bootWim" \
    --compress=none --quiet || {
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

  wimlib-imagex export "$iso" "$index" "$bootWim" \
    --compress=none --boot --quiet || {
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

  for line in "${fields[@]:5}"; do

    IFS=$'\t' read -r index imgEdition <<< "$line"

    [[ ! "$index" =~ ^[0-9]+$ ]] && continue
    [[ "${imgEdition,,}" != "${edition,,}" ]] && continue

    installSize=$(( size + installPad ))

    /run/progress.sh "$installWim" "$installSize" "$msg ([P])..." &

    wimlib-imagex export "$iso" "$index" "$installWim" --quiet || {
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
      desc=$(printVariant "$version" "$desc")
    fi
  fi

  if [[ "${iso,,}" == *".esd" ]]; then
    extractESD "$iso" "$dir" "$version" "$desc" && return 0
    return 1
  fi

  local msg="Extracting $desc image"
  info "$msg..." && html "$msg..."

  if ! rm -rf -- "$dir"; then
    error "Failed to remove directory \"$dir\" !"
    return 1
  fi

  if ! makeDir "$dir"; then
    error "Failed to create directory \"$dir\" !"
    return 1
  fi

  size=$(stat -c%s "$iso")

  if (( size < 10000000 )); then
    error "Invalid ISO file: Size is smaller than 10 MB" && return 1
  fi

  checkFreeSpace "$dir" "$size" || return 1

  if ! rm -rf -- "$dir"; then
    error "Failed to remove directory \"$dir\" !"
    return 1
  fi

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
      error "Failed to find any .iso file in archive!"
      return 1
    fi

    if ! 7z x "$file" -o"$dir" > /dev/null; then
      error "Failed to extract archive!"
      return 1
    fi

    LABEL=$(isoinfo -d -i "$file" | sed -n 's/Volume id: //p') || LABEL=""

    if ! mv -f -- "$file" "$iso"; then
      error "Failed to preserve extracted ISO file: $file"
      return 1
    fi

    UNPACK=""

  fi

  return 0
}

setMachine() {

  local id="$1"
  local iso="$2"
  local dir="$3"
  local desc="$4"

  ETFS="boot/etfsboot.com"

  local version=""
  case "${id,,}" in
    "win2k"* )   version="2k" ;;
    "winxp"* )   version="xp" ;;
    "win2003"* ) version="2k3" ;;
  esac

  if [ -n "$version" ]; then

    if ! legacyInstall "$iso" "$dir" "$desc" "$version"; then
      error "Failed to prepare $desc ISO!"
      return 1
    fi

  fi

  if isLegacy "$id"; then

    writeState "mode" "windows_legacy" || return 1

    case "${id,,}" in 
      "win9"* | "win2k"* | "reactos" )
        writeState "vga" "cirrus" || return 1 ;;
      * )
        writeState "vga" "std" || return 1 ;;
    esac

  fi

  restoreBootMode || return 1

  case "${id,,}" in

    "win9"* )

      writeState "usb" "N" || return 1
      writeState "net" "pcnet" || return 1
      writeState "type" "auto" || return 1
      writeState "old" "pc-i440fx-2.4" || return 1 ;;

    "win2k"* )

      writeState "old" "pc" || return 1
      writeState "type" "auto" || return 1
      writeState "net" "rtl8139" || return 1
      writeState "usb" "pci-ohci" || return 1 ;;

    "winxpx"* | "win2003"* )

      writeState "type" "blk" || return 1
      writeState "net" "rtl8139" || return 1
      writeState "sound" "usb-audio" || return 1 ;;

    "reactos" )

      [ -z "${REMOVE:-}" ] && REMOVE="N"

      writeState "old" "pc" || return 1
      writeState "type" "auto" || return 1
      writeState "net" "rtl8139" || return 1
      writeState "usb" "pci-ohci" || return 1 ;;

  esac

  restoreMachine || return 1

  case "${id,,}" in

    "win9"* | "win2k"* | *"x86"* | "reactos" )

      # Legacy 32-bit Windows may enter an incompatible PAE/DEP path when the
      # NX flag is exposed, causing installation failures or repeated resets.

      writeState "flag" "nx=off" || return 1 ;;

  esac

  case "${id,,}" in

    "win9"* | "win2k"* | "winxp"* | "win2003"* | \
    "winvistax86"* | "win7x86"* | "reactos" )

      if isQ35 "$MACHINE"; then

        # pc-q35-2.11 began advertising a synthetic 64-bit PCI MMIO aperture.
        # Older Windows ACPI implementations may reject that resource layout,
        # so retain the pre-2.11 behavior for these guests to prevent a
        # blue screen on XP and others if the 64 bit PCI hole size is >2G.

        writeState "args" "-global q35-pcihost.x-pci-hole64-fix=false" || return 1

      fi ;;

  esac

  return 0
}

prepareImage() {

  local iso="$1"
  local dir="$2"
  local desc missing

  desc=$(printVariant "$DETECTED" "$DETECTED")

  if [[ "${BOOT_MODE,,}" == "windows_legacy" &&
    "${DETECTED,,}" != "win9"* ]]; then
    getBootLoadSize "$iso" "$dir" "$desc" || return 1
  fi

  skipVersion "$DETECTED" && return 0

  if [[ "${BOOT_MODE,,}" == "windows_legacy" ]]; then

    extractBootImage "$iso" "$dir" "$desc" && return 0

    error "Failed to extract boot image from ISO image \"${iso}\"!"
    return 1
  fi

  EFISYS="efi/microsoft/boot/efisys_noprompt.bin"

  [ -f "$dir/$ETFS" ] && [ -s "$dir/$ETFS" ] &&
    [ -f "$dir/$EFISYS" ] && [ -s "$dir/$EFISYS" ] && return 0

  missing=$(basename "$dir/$EFISYS")
  if [ ! -f "$dir/$ETFS" ] || [ ! -s "$dir/$ETFS" ]; then
    missing=$(basename "$dir/$ETFS")
  fi

  error "Failed to locate file \"${missing,,}\" in ISO image!"
  return 1
}

getOemFolder() {

  local folder="/oem"

  [ ! -d "$folder" ] && folder="/OEM"
  [ ! -d "$folder" ] && folder="$STORAGE/oem"
  [ ! -d "$folder" ] && folder="$STORAGE/OEM"
  [ -d "$folder" ] && echo "$folder"

  return 0
}

addFolder() {

  local src="$1"
  local target="${2:-image}"
  local log="${3:-Y}"
  local mode="${4:-copy}"
  local folder file="" source=""
  local dest="$src/\$OEM\$/\$1/OEM"
  local install="$src/.overlay-install.bat"

  folder=$(getOemFolder) || return 1

  [ -z "$folder" ] && [ -z "$COMMAND" ] && return 0

  if enabled "$log"; then
    local msg="Adding OEM files to $target..."
    info "$msg" && html "$msg"
  fi

  if [ "$mode" = "overlay" ]; then

    rm -f -- "$install" || return 1

    if [ -n "$folder" ]; then
      source=$(find -L "$folder" -maxdepth 1 -type f -iname install.bat -print -quit) || return 1

      if [ -n "$source" ]; then
        if ! cp -L -- "$source" "$install"; then
          error "Failed to create a writable copy of $source!"
          return 1
        fi

        file="$install"
      fi
    fi

  else

    mkdir -p "$dest" || return 1

    if [ -n "$folder" ]; then
      cp -Lr "$folder/." "$dest" || return 1
    fi

    file=$(find "$dest" -maxdepth 1 -type f -iname install.bat -print -quit) || return 1

  fi

  if [ -s "$file" ]; then
    normalizeBatch "$file" || return 1
  fi

  if [ -n "$COMMAND" ]; then

    if [ -z "$file" ]; then
      if [ "$mode" = "overlay" ]; then
        file="$install"
      else
        file="$dest/install.bat"
      fi
    fi

    if [ -s "$file" ]; then
      printf '\n' >> "$file" || return 1
    fi

    printf '%s\n' "$COMMAND" >> "$file" || return 1

  fi

  if [ -s "$file" ]; then

    if ! unix2dos -q "$file"; then
      error "Failed to convert $file to DOS format!"
      return 1
    fi

    checkBatch "$file"
  fi

  return 0
}

addDriver() {

  local id="$1"
  local path="$2"
  local target="$3"
  local driver="$4"
  local folder="" desc

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
  local version="$3"
  local file="${4:-}"
  local index="${5:-}"
  local log="${6:-Y}"
  local drivers="$tmp/drivers"

  rm -rf "$drivers"
  mkdir -p "$drivers"

  if enabled "$log"; then
    local msg="Adding drivers to image..."
    info "$msg" && html "$msg"
  fi

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

  if [ -n "$file" ]; then

    if [ -z "$index" ]; then
      error "No boot image index specified!"
      return 1
    fi

    wimlib-imagex update "$file" "$index" --command "delete --force --recursive /$target" >/dev/null || true

  fi

  local driver
  local driver_list=(
    qxl
    viofs
    sriov
    smbus
    qxldod
    viorng
    viostor
    viomem
    NetKVM
    Balloon
    vioscsi
    pvpanic
    vioinput
    viogpudo
    vioserial
    qemupciserial
  )

  for driver in "${driver_list[@]}"; do
    addDriver "$version" "$drivers" "$target" "$driver" || return 1
  done

  local dst="$src/\$OEM\$/\$\$/Drivers"
  mkdir -p "$dst" || return 1
  cp -Lr "$dest/." "$dst" || return 1

  # Install the VirtIO display driver explicitly from SetupComplete.cmd so it
  # cannot disrupt Windows Setup by loading through the WinPE driver path.
  if ! isLegacy "$version"; then
    rm -rf "$dest/viogpudo"
  fi

  if [ -n "$file" ]; then

    if ! wimlib-imagex update "$file" "$index" --command "add $dest /$target" >/dev/null; then
      return 1
    fi

  else

    local winpe="$src/$target"
    rm -rf "$winpe" || return 1
    mkdir -p "$winpe" || return 1
    cp -Lr "$dest/." "$winpe" || return 1

  fi

  rm -rf "$drivers"
  return 0
}

stageSetup() {

  local asset="$1"
  local language="$2"
  local stage="$3"

  skipVersion "${DETECTED,,}" && return 0

  local msg="Creating overlay image..."
  info "$msg" && html "$msg"

  if ! rm -rf -- "$stage"; then
    error "Failed to remove previous image files!"
    return 1
  fi

  if ! mkdir -p "$stage"; then
    error "Failed to create image staging directory!"
    return 1
  fi

  if ! addDrivers "$stage" "$stage" "$DETECTED"; then
    error "Failed to stage Windows drivers!"
    return 1
  fi

  if ! addFolder "$stage" "image" "Y" "overlay"; then
    error "Failed to stage OEM folder!"
    return 1
  fi

  stageAnswer "$asset" "$language" "$stage" || return 1

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
  local desc path src wim name info
  local script=""

  skipVersion "${DETECTED,,}" && return 0

  if [ ! -s "$asset" ] || [ ! -f "$asset" ]; then
    asset=""
    if ! enabled "$MANUAL"; then
      MANUAL="Y"
      warn "no answer file provided, $FB."
    fi
  fi

  rm -rf "$tmp" || return 1
  mkdir -p "$tmp" || return 1

  src=$(find "$dir" -maxdepth 1 -type d -iname sources -print -quit) || return 1

  if [ ! -d "$src" ]; then
    error "failed to locate 'sources' folder in ISO image, $FB"
    return 1
  fi

  wim=$(find "$src" -maxdepth 1 -type f \( -iname boot.wim -or -iname boot.esd \) -print -quit) || return 1

  if [ ! -f "$wim" ]; then
    error "failed to locate 'boot.wim' or 'boot.esd' in ISO image, $FB"
    return 1
  fi

  local idx="1"

  if ! info=$(wimlib-imagex info -xml "$wim" | iconv -f UTF-16LE -t UTF-8); then
    warn "failed to read boot image information, $FB"
    MANUAL="Y"
    info=""
  fi

  if [[ "${info^^}" == *"<IMAGE INDEX=\"2\">"* ]]; then
    idx="2"
  fi

  if ! addDrivers "$src" "$tmp" "$DETECTED" "$wim" "$idx"; then
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

    name=$(basename "$asset") || return 1
    local answer="$tmp/$name"

    info "Adding $name for automatic installation..."

    if ! cp "$asset" "$answer"; then
      error "Failed to copy answer file to $answer."
      return 1
    fi

    removeGeneratedXML "$asset" || return 1

    if [ -z "${CUSTOM_XML:-}" ]; then
      if ! updateXML "$answer" "$language"; then
        error "Failed to update answer file: $answer"
        return 1
      fi
    fi

    if ! updateDiskID "$answer" "${DISK_TYPE:-}" "image"; then
      error "Failed to adjust the Windows installation disk!"
      exit 85
    fi

    validateGeneratedXML "$answer" || return 1

    if [ -z "${CUSTOM_XML:-}" ]; then
      prepareSetupScript "$asset" "$tmp/setup" script || exit 84
    fi

    if ! wimlib-imagex update "$wim" "$idx" --command "add $answer /$xml" > /dev/null; then
      MANUAL="Y"
      warn "failed to add answer file ($name) to ISO image, $FB"
    else
      installSetupScript "$script" "$src" || exit 84

      wimlib-imagex update "$wim" "$idx" --command "add $answer /$dat" > /dev/null || true
    fi

  fi

  if enabled "$MANUAL"; then

    removeGeneratedXML "$asset" || return 1

    wimlib-imagex update "$wim" "$idx" --command "delete --force /$xml" > /dev/null || true

    if wimlib-imagex extract "$wim" "$idx" "/$bak" "--dest-dir=$tmp" >/dev/null 2>&1; then
      if ! wimlib-imagex update "$wim" "$idx" --command "add $tmp/$bak /$xml" > /dev/null; then
        warn "failed to restore original answer file ($bak)."
      fi
    fi

  fi

  name="$xml"
  enabled "$MANUAL" && name="$bak"
  path=$(find "$dir" -maxdepth 1 -type f -iname "$name" -print -quit) || return 1

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

  rm -rf "$tmp" || return 1
  return 0
}

removeImage() {

  local iso="$1"

  [ ! -f "$iso" ] && return 0
  [ -n "$CUSTOM" ] && return 0

  rm -f "$iso" 2> /dev/null || warn "failed to remove $iso !"

  return 0
}

reserveSambaPorts() {

  disabled "${SAMBA:-Y}" && return 0
  disabled "${NETWORK:-Y}" && return 0
  enabled "${DHCP:-N}" && return 0

  # NAT can fall back to user-mode networking after this point,
  # so always protect the Samba listeners for non-DHCP networking.
  HOST_PORTS="${HOST_PORTS:+$HOST_PORTS,}139/tcp,445/tcp"

  return 0
}

backup () {

  local iso="$1"
  local count=1
  local name="unknown"
  local root="$STORAGE/backups"
  local file previous failed=""

  previous=$(readState "base") || return 1
  [ -n "$previous" ] && name="${previous%.*}"

  if ! makeDir "$root"; then
    error "Failed to create directory \"$root\" !"
    return 1
  fi

  local folder="$name"
  local dir="$root/$folder"

  while [ -d "$dir" ]; do
    (( count++ ))
    folder="${name}.${count}"
    dir="$root/$folder"
  done

  if ! makeDir "$dir"; then
    error "Failed to create directory \"$dir\" !"
    return 1
  fi

  if [ -f "$iso" ]; then
    if ! mv -f -- "$iso" "$dir/"; then
      error "Failed to move \"$iso\" to \"$dir\"."
      failed="Y"
    fi
  fi

  while IFS= read -r -d '' file; do
    if ! mv -n -- "$file" "$dir/"; then
      error "Failed to move \"$file\" to \"$dir\"."
      failed="Y"
    fi
  done < <(
    find "$STORAGE" -maxdepth 1 -type f \
      \( -iname 'data.*' -or -iname 'windows.*' -or -iname '*.rom' -or -iname '*.vars' \) \
      -not -iname '*.iso' -print0
  )

  local find_pid=$!

  if ! wait "$find_pid"; then
    error "Failed to enumerate files in \"$STORAGE\"."
    failed="Y"
  fi

  [ -z "$(ls -A "$dir")" ] && rm -rf "$dir"
  [ -z "$(ls -A "$root")" ] && rm -rf "$root"

  [ -n "$failed" ] && return 1

  return 0
}

restoreBootMode() {

  local current="${BOOT_MODE:-}"

  local mode
  mode=$(readState "mode") || return 1

  [ -n "$mode" ] || return 0

  if [[ "${mode,,}" == "windows_legacy" ]]; then
    BOOT_MODE="$mode"
    return 0
  fi

  case "${current,,}" in
    "" | "windows" | "windows_plain" )
      BOOT_MODE="$mode" ;;
  esac

  return 0
}

restoreMachine() {

  [[ "${PLATFORM,,}" != "x64" ]] && return 0
  [[ "${MACHINE,,}" != "q35" ]] && return 0

  MACHINE=""
  restoreState "MACHINE" "old" || return 1
  [ -z "$MACHINE" ] && MACHINE="q35"

  return 0
}

restoreMachineState() {

  restoreState "VGA" "vga" || return 1
  restoreState "USB" "usb" || return 1
  restoreState "SOUND" "sound" || return 1
  restoreState "ADAPTER" "net" || return 1
  restoreState "CPU_MODEL" "cpu" || return 1
  restoreState "DISK_TYPE" "type" || return 1

  mergeState "CPU_FLAGS" "flag" "," || return 1
  mergeState "ARGUMENTS" "args" " " || return 1

  return 0
}

startWindows

return 0

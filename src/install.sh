#!/usr/bin/env bash
set -Eeuo pipefail

startWindows() {

  parseVersion || exit 58
  parseLanguage || exit 62
  detectCustom || exit 64

  if ! startInstall; then
    bootWindows || exit 66
    return 0
  fi

  if ! hasImage "$ISO"; then
    if ! downloadImage "$ISO" "$VERSION" "$LANGUAGE"; then
      removeIso "$ISO" || :
      exit 68
    fi
  fi

  local boot="$BOOT"
  local dir="$TMP/unpack"
  local handled=0 extracted=0

  selectWindowsImage "$ISO" "$dir" "$boot" || exit $?
  (( handled )) && return 0

  configureMachine "$ISO" "$dir" "$boot" || exit $?
  (( handled )) && return 0

  prepareWindowsImage "$ISO" "$dir" "$boot" || exit $?
  (( handled )) && return 0

  finishInstall "$BOOT" "N" "$boot" || exit 100

  return 0
}

selectWindowsImage() {

  local iso="$1"
  local dir="$2"
  local boot="$3"

  local detect_rc=0

  # Known versions already provide the required image metadata.
  if resolveImage "$VERSION"; then

    if ! setImage; then
      skipUnattended "$dir" "$iso" "$boot" || return 70
      handled=1
      return 0
    fi

    if ! needsExtraction "$DETECTED" "$iso"; then
      return 0
    fi

    if ! extractImage "$iso" "$dir" "$VERSION"; then
      removeIso "$iso" || :
      return 72
    fi

    extracted=1
    return 0

  fi

  # Inspect unknown media directly before falling back to extraction.
  detectIsoImage "$iso" || detect_rc=$?

  if (( detect_rc == 0 )); then
    return 0
  fi

  # Only code 1 indicates that extraction may recover detection.
  if (( detect_rc != 1 )); then
    skipUnattended "$dir" "$iso" "$boot" || return 76
    handled=1
    return 0
  fi

  if ! extractImage "$iso" "$dir" "$VERSION"; then
    removeIso "$iso" || :
    return 74
  fi

  extracted=1

  if detectImage "$dir"; then
    return 0
  fi

  skipUnattended "$dir" "$iso" "$boot" || return 76
  handled=1
  return 0
}

configureMachine() {

  local iso="$1"
  local dir="$2"
  local boot="$3"

  local desc

  if ! desc=$(printVariant "$DETECTED" "$DETECTED"); then
    skipUnattended "$dir" "$iso" "$boot" || return 78
    handled=1
    return 0
  fi

  if ! setMachine "$DETECTED" "$iso" "$dir" "$desc"; then
    skipUnattended "$dir" "$iso" "$boot" || return 80
    handled=1
    return 0
  fi

  if ! restoreMachineState; then
    skipUnattended "$dir" "$iso" "$boot" || return 82
    handled=1
    return 0
  fi

  if ! supportsUnattended "$DETECTED"; then
    skipUnattended "$dir" "$iso" "$boot" "N" || return 83
    handled=1
    return 0
  fi

  return 0
}

prepareWindowsImage() {

  local iso="$1"
  local dir="$2"
  local boot="$3"

  # Prefer the original ISO with a small setup image whenever possible.
  if canUseSetupImage "$DETECTED" "$iso"; then

    if ! createOverlay "$XML" "$LANGUAGE" "$TMP/setup"; then
      skipUnattended "$dir" "$iso" "$boot" || return 84
      handled=1
      return 0
    fi

    if ! createSetupImage "$TMP/setup" "$STORAGE/setup.img"; then
      exit 86
    fi

    useOriginalImage "$iso" || return 88
    return 0

  fi

  # Legacy or modifiable media must be extracted, updated, and rebuilt.
  if (( ! extracted )); then
    if ! extractImage "$iso" "$dir" "$VERSION"; then
      removeIso "$iso" || :
      return 90
    fi
  fi

  if ! prepareImage "$iso" "$dir"; then
    skipUnattended "$dir" "$iso" "$boot" || return 92
    handled=1
    return 0
  fi

  if ! updateImage "$dir" "$XML" "$LANGUAGE"; then
    skipUnattended "$dir" "$iso" "$boot" || return 94
    handled=1
    return 0
  fi

  removeImage "$iso" || return 96
  buildImage "$dir" || return 98

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
    local boot="$file"

    if [[ "${VERSION,,}" == "http"* ]]; then

      file=$(basename "${VERSION%%[\?#]*}")
      printf -v file '%b' "${file//%/\\x}"
      file="${file//[!A-Za-z0-9._-]/_}"

      boot="$file"

      if isCompressed "$VERSION" || [[ "${boot,,}" == *.esd ]]; then
        boot="${boot%.*}"
      fi

      [ -n "$boot" ] || boot="download"
      [[ "${boot,,}" == *.iso ]] || boot+=".iso"

      case "${boot,,}" in
        "windows."* )
          error "The download filename \"$file\" uses the reserved \"windows.*\" namespace!"
          exit 58 ;;
      esac

    else

      local language
      language=$(getLanguage "$LANGUAGE" "culture")
      language="${language%%-*}"

      if [ -n "$language" ] && [[ "${language,,}" != "en" ]]; then
        file="${VERSION//\//}_${language,,}.iso"
        boot="$file"
      fi

    fi

    BOOT="$STORAGE/$boot"

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

  if [ -z "$previousBase" ] && hasData; then
    if ! backupPrevious ""; then
      warn "the backup was incomplete, continuing with installation..."
    fi
  fi

  if ! makeDir "$TMP"; then
    error "Failed to create directory \"$TMP\" !"
    exit 50
  fi

  if [ -z "$CUSTOM" ]; then

    if [ -n "$REUSED_ISO" ]; then
      ISO="$TMP/$(basename "$BOOT")"
    else
      ISO="$TMP/$file"
    fi

    # Work from the temporary directory so the persistent source path can
    # later contain either the preserved ISO or the rebuilt installation image.
    if [ -f "$BOOT" ] && [ -s "$BOOT" ]; then
      if ! mv -f -- "$BOOT" "$ISO"; then
        error "Failed to move ISO file from \"$BOOT\" to \"$ISO\" !"
        exit 50
      fi
    fi

  fi

  if ! rm -f -- "$BOOT"; then
    error "Failed to remove obsolete ISO file \"$BOOT\" !"
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

  if [ -z "$CUSTOM" ] && [ -z "$REUSED_ISO" ]; then
    checkMemory || exit 67
  fi

  return 0
}

skipUnattended() {

  local dir="$1"
  local iso="$2"
  local boot="$3"
  local aborted="${4:-Y}"

  local efi efi32 efi64

  # Standalone ESD files and nested archives are not directly bootable media,
  # so they cannot use the manual-install fallback.
  if enabled "${UNPACK:-}" || [[ "${iso,,}" == *".esd" ]]; then
    error "Failed to boot \"$iso\" because it is not a directly bootable ISO image!"
    exit 60
  fi

  # When automatic preparation fails, inspect extracted media to determine
  # whether it can still be booted manually using legacy firmware.
  if enabled "$aborted" && [[ "${PLATFORM,,}" == "x64" ]] && [ -d "$dir" ]; then

    efi=$(find "$dir" -maxdepth 1 -type d -iname efi -print -quit) || return 1
    efi32=$(find "$dir" -maxdepth 3 -type f -ipath '*/efi/boot/bootia32.efi' -print -quit) || return 1
    efi64=$(find "$dir" -maxdepth 3 -type f -ipath '*/efi/boot/bootx64.efi' -print -quit) || return 1

    if [ -z "$efi" ] || { [ -n "$efi32" ] && [ -z "$efi64" ]; }; then

      writeState "mode" "windows_legacy" || return 1
      restoreBootMode || return 1

    fi

  fi

  # Preserve custom media in place. Downloaded or reused media must be moved
  # back to persistent storage before the manual fallback is started.
  useOriginalImage "$iso"

  finishInstall "$BOOT" "$aborted" "$boot" && return 0
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

    # Older releases stored the original download name in windows.base. New
    # releases always store the final ISO name, so migrate legacy state once.
    if [[ "${previousBase,,}" != *.iso ]]; then

      if isCompressed "$previousBase" || [[ "${previousBase,,}" == *.esd ]]; then
        previousBase="${previousBase%.*}"
      fi

      [ -n "$previousBase" ] || previousBase="download"
      previousBase+=".iso"

      if ! writeState "base" "$previousBase"; then
        error "Failed to migrate the previous installation state!"
        exit 50
      fi

    fi

    # A changed source invalidates an unfinished installation. Back up an
    # existing installation, but discard stale media when no disk exists yet.
    if [[ "${STORAGE,,}/${previousBase,,}" != "${iso,,}" ]]; then

      if ! hasData; then

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

      if ! backupPrevious "$STORAGE/$previousBase"; then
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

      # Aborted Win11 installs boot without any answer file present,
      # so enable Secure Boot and TPM to satisfy its hardware checks.
      if [[ "$aborted" == [Yy1]* ]] || enabled "$MANUAL"; then
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

  local fname="$1"

  local dir file base
  local boot="$STORAGE/windows.boot"

  dir=$(find / -maxdepth 1 -type d -iname "$fname" -print -quit) || return 1

  if [ ! -d "$dir" ]; then
    dir=$(find "$STORAGE" -maxdepth 1 -type d -iname "$fname" -print -quit) || return 1
  fi

  if [ -d "$dir" ]; then
    if ! hasDisk || [ ! -f "$boot" ]; then
      error "The bind $dir maps to a file that does not exist!" && return 1
    fi
  fi

  file=$(find / -maxdepth 1 -type f -iname "$fname" -print -quit) || return 1

  if [ ! -s "$file" ]; then
    file=$(find "$STORAGE" -maxdepth 1 -type f -iname "$fname" -print -quit) || return 1
  fi

  if [ ! -s "$file" ] && [[ "${VERSION,,}" != "http"* ]]; then
    base=$(basename "$VERSION")
    file="$STORAGE/$base"
  fi

  if [ ! -f "$file" ] || [ ! -s "$file" ]; then
    return 0
  fi

  local size
  size=$(stat -c%s "$file") || return 1

  if [ -z "$size" ] || [[ "$size" == "0" ]]; then
    return 0
  fi

  ISO="$file"
  CUSTOM="$file"
  # Include the custom ISO size in its persistent name so replacing a
  # bind-mounted ISO is detected as a different installation source.
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

resolveImage() {

  local version="$1"

  XML=""
  FB="falling back to manual installation!"

  [ -z "$DETECTED" ] || return 0

  # Reused and arbitrary URL media must be inspected because their actual
  # contents may no longer match the requested VERSION.
  [ -z "${REUSED_ISO:-}" ] || return 1
  [[ "${version,,}" != "http"* ]] || return 1

  # Only direct-boot custom media can safely bypass content detection.
  if [ -n "$CUSTOM" ]; then
    supportsUnattended "$version" && return 1
    DETECTED="$version"
    return 0
  fi

  local file="/run/assets/$version.xml"

  if [ -s "$file" ]; then
    DETECTED="$version"
    return 0
  fi

  # Evaluation media may reuse the normal edition's answer-file template.
  if [[ "${version,,}" == *"-eval" ]]; then
    local source="/run/assets/${version%-eval}.xml"

    if [ -s "$source" ]; then
      DETECTED="$version"
      return 0
    fi
  fi

  return 1
}

setImage() {

  supportsXML "${DETECTED,,}" || return 0

  setXML "" && return 0
  enabled "$MANUAL" && return 0

  # A missing answer file is a supported manual-install path, not a hard media
  # failure.
  MANUAL="Y"

  local desc
  desc=$(printEdition "$DETECTED" "this version") || return 1

  warn "the answer file for $desc was not found ($DETECTED.xml), $FB."
  return 0
}

needsExtraction() {

  local id="$1"
  local iso="$2"

  # Media without unattended support boots directly from the original ISO.
  if ! supportsUnattended "$id"; then
    return 1
  fi

  # SIF-based legacy installers must be extracted and rebuilt.
  if ! supportsXML "$id"; then
    return 0
  fi

  # Standalone ESD downloads must be extracted before they can be prepared.
  if [[ "${iso,,}" == *".esd" ]]; then
    return 0
  fi

  # Nested archives must be extracted to expose their contained ISO.
  if enabled "${UNPACK:-}"; then
    return 0
  fi

  # Modern bootable ISOs can use the original media with a setup overlay.
  return 1
}

extractImage() {

  local iso="$1"
  local dir="$2"
  local version="$3"

  local file size
  local desc="local ISO"
  local archive="${dir}.archive"
  local target="$dir"

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

  enabled "${UNPACK:-}" && target="$archive"

  if ! rm -rf -- "$dir" "$archive"; then
    error "Failed to remove extraction directories!"
    return 1
  fi

  if ! makeDir "$target"; then
    error "Failed to create directory \"$target\" !"
    return 1
  fi

  if ! size=$(stat -c%s "$iso"); then
    error "Failed to determine ISO file size: $iso"
    return 1
  fi

  if (( size < 10000000 )); then
    error "Invalid ISO file: Size of \"$iso\" is smaller than 10 MB"
    return 1
  fi

  checkFreeSpace "$target" "$size" || return 1

  if ! rm -rf -- "$target"; then
    error "Failed to remove directory \"$target\" !"
    return 1
  fi

  /run/progress.sh "$target" "$size" "$msg ([P])..." &

  if ! 7z x "$iso" -o"$target" > /dev/null; then
    fKill "progress.sh"
    error "Failed to extract ISO file: $iso"
    return 1
  fi

  fKill "progress.sh"

  if ! enabled "${UNPACK:-}"; then

    LABEL=$(isoinfo -d -i "$iso" | sed -n 's/Volume id: //p') || LABEL=""

  else

    # Locate the first root-level ISO in the downloaded archive
    if ! file=$(find "$archive" -maxdepth 1 -type f -iname "*.iso" -print -quit); then
      error "Failed to search for a nested ISO in the extracted archive!"
      return 1
    fi

    if [ -z "$file" ]; then
      error "Failed to find any nested ISO files in the archive!"
      return 1
    fi

    if ! makeDir "$dir"; then
      error "Failed to create directory \"$dir\" !"
      return 1
    fi

    if ! 7z x "$file" -o"$dir" > /dev/null; then
      error "Failed to extract nested ISO file: $file"
      return 1
    fi

    LABEL=$(isoinfo -d -i "$file" | sed -n 's/Volume id: //p') || LABEL=""

    if ! mv -f -- "$file" "$iso"; then
      error "Failed to preserve extracted ISO file: $file"
      return 1
    fi

    if ! rm -rf -- "$archive"; then
      error "Failed to remove directory \"$archive\" !"
      return 1
    fi

    UNPACK=""

  fi

  return 0
}

detectImage() {

  local dir="$1"

  local desc

  info "Detecting version from ISO image..."

  # Marker-based legacy and ReactOS detection must run before looking for a WIM.
  if detectLegacy "$dir" || detectReactOS "$dir"; then
    desc=$(printEdition "$DETECTED" "$DETECTED" "Y") || return 1
    info "Detected: $desc"
    return 0
  fi

  local wim
  wim=$(findImage "$dir") || return 1

  local image_info
  image_info=$(readImageInfo "$wim") || return 1

  detectImageInfo "$image_info"
}

prepareImage() {

  local iso="$1"
  local dir="$2"

  local desc missing

  desc=$(printVariant "$DETECTED" "$DETECTED")

  # Legacy rebuilt media must retain the source ISO's El Torito boot-load size.
  if [[ "${BOOT_MODE,,}" == "windows_legacy" ]]; then
    if [[ "${DETECTED,,}" != "win9"* && "${DETECTED,,}" != "winnt4" ]]; then
      getBootLoadSize "$iso" "$dir" "$desc" || return 1
    fi
  fi

  supportsXML "$DETECTED" || return 0

  if [[ "${BOOT_MODE,,}" == "windows_legacy" ]]; then
    extractBootImage "$iso" "$dir" "$desc" && return 0
    error "Failed to extract boot image from ISO image \"${iso}\"!"
    return 1
  fi

  EFISYS="efi/microsoft/boot/efisys_noprompt.bin"

  # A modern rebuilt ISO requires both its BIOS and no-prompt UEFI boot images.
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
  
  local file="" source="" folder
  local dest="$src/\$OEM\$/\$1/OEM"
  local install="$src/.overlay-install.bat"

  folder=$(getOemFolder) || return 1

  [ -z "$folder" ] && [ -z "$COMMAND" ] && return 0

  if enabled "$log"; then
    local msg="Adding OEM files to $target..."
    info "$msg" && html "$msg"
  fi

  # Setup-image mode cannot modify the original ISO, so create a temporary
  # writable copy of install.bat for the overlay image.
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

  local folder desc

  if [ -z "$id" ]; then
    warn "no Windows version specified for \"$driver\" driver!"
    return 1
  fi

  if ! folder=$(getDriverFolder "$id"); then
    folder=""
  fi

  if [ -z "$folder" ]; then

    desc=$(printVersion "$id" "$id")

    if [[ "${id,,}" == *"x86"* ]]; then
      warn "no \"$driver\" driver available for the 32-bit version of \"$desc\" !"
    else
      warn "no \"$driver\" driver available for \"$desc\" !"
    fi

    return 1
  fi

  [ -d "$path/$driver/$folder" ] || return 0

  case "${id,,}" in
    "winvista"* )
      [[ "${driver,,}" == "viorng" ]] && return 0 ;;
  esac

  local dest="$path/$target/$driver"

  mkdir -p "$dest" || return 1
  cp -Lr "$path/$driver/$folder/." "$dest" || return 1

  return 0
}

selectDrivers() {

  local version="$1"
  local drivers="$2"
  local target="$3"

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

  local driver

  for driver in "${driver_list[@]}"; do
    addDriver "$version" "$drivers" "$target" "$driver" || return 1
  done

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

  rm -rf "$drivers" || return 1
  mkdir -p "$drivers" || return 1

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

    wimlib-imagex update "$file" "$index" \
      --command "delete --force --recursive /$target" >/dev/null || true

  fi

  selectDrivers "$version" "$drivers" "$target" || return 1

  local dst="$src/\$OEM\$/\$\$/Drivers"
  mkdir -p "$dst" || return 1
  cp -Lr "$dest/." "$dst" || return 1

  # Install the VirtIO display driver explicitly from SetupComplete.cmd so it
  # cannot disrupt Windows Setup by loading through the WinPE driver path.
  if ! isLegacy "$version"; then
    rm -rf "$dest/viogpudo" || return 1
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

  rm -rf "$drivers" || return 1
  return 0
}

createOverlay() {

  local asset="$1"
  local language="$2"
  local stage="$3"

  supportsXML "${DETECTED,,}" || return 0

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
    error "Failed to include Windows drivers!"
    return 1
  fi

  if ! addFolder "$stage" "image" "Y" "overlay"; then
    error "Failed to include OEM folder!"
    return 1
  fi

  addAnswerFile "$asset" "$language" "$stage" || return 1

  return 0
}

updateImage() {

  local dir="$1"
  local asset="$2"
  local language="$3"

  local script=""
  local tmp="/tmp/install"
  local xml="autounattend.xml"
  local bak="${xml//.xml/.org}"
  local dat="${xml//.xml/.dat}"
  local desc path src wim name info 

  supportsXML "${DETECTED,,}" || return 0

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

  # Windows Setup normally resides in boot image 2; single-image media uses 1.
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
    return 1
  fi

  if ! addFolder "$src"; then
    error "Failed to add OEM folder to image!"
    return 1
  fi

  # Preserve an original answer file only once. The .dat marker identifies an
  # image where our generated answer file has already been installed.
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
      script=$(prepareSetupScript "$asset" "$tmp/setup") || exit 84
    fi

    if ! wimlib-imagex update "$wim" "$idx" --command "add $answer /$xml" > /dev/null; then
      MANUAL="Y"
      warn "failed to add answer file ($name) to ISO image, $FB"
    else
      installSetupScript "$script" "$src" || exit 84

      wimlib-imagex update "$wim" "$idx" --command "add $answer /$dat" > /dev/null || true
    fi

  fi

  # Manual mode removes generated automation and restores the original answer
  # file when one was backed up earlier.
  if enabled "$MANUAL"; then

    removeGeneratedXML "$asset" || return 1

    wimlib-imagex update "$wim" "$idx" --command "delete --force /$xml" > /dev/null || true

    if wimlib-imagex extract "$wim" "$idx" "/$bak" "--dest-dir=$tmp" >/dev/null 2>&1; then
      if ! wimlib-imagex update "$wim" "$idx" --command "add $tmp/$bak /$xml" > /dev/null; then
        warn "failed to restore original answer file ($bak)."
      fi
    fi

  fi

  # Prevent a root-level answer file from overriding the selected automatic or
  # manual behavior when Windows Setup first boots.
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

backupPrevious () {

  local iso="$1"

  local count=1
  local name="unknown"
  local root="$STORAGE/backups"
  local failed="" file previous

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

  # Wait for the process-substitution find command so enumeration failures are
  # detected rather than being mistaken for a successful backup.
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

checkMemory() {

  local id="$1"
  local desc="${2:-}"
  local required wanted available

  required=$(getRequiredMemory "$id") || return 1

  if [ -z "$desc" ]; then
    desc=$(printVariant "$id" "$id") || return 1
  fi

  # Ensure the final memory allocation also uses this floor.
  RAM_MINIMUM="$required"

  # Refresh host and container memory availability.
  getMemoryInfo

  available=$(( RAM_AVAIL - RAM_SPARE ))
  (( available < 0 )) && available=0

  case "${RAM_SIZE,,}" in
    "max" )
      wanted="$available" ;;
    "half" )
      wanted=$(( RAM_TOTAL / 2 ))
      (( wanted > available )) && wanted="$available" ;;
    * )
      wanted=$(numfmt --from=iec "$RAM_SIZE") || return 1

      if (( wanted < required )); then
        error "$desc requires at least $(formatBytes "$required") of RAM, but RAM_SIZE is set to $(formatBytes "$wanted")."
        return 1
      fi

      (( wanted > available )) && wanted="$available" ;;
  esac

  if (( wanted < required )); then
    error "$desc requires at least $(formatBytes "$required") of RAM, but only $(formatBytes "$wanted") can be allocated."
    return 1
  fi

  return 0
}

restoreBootMode() {

  local current="${BOOT_MODE:-}"

  local mode
  mode=$(readState "mode") || return 1

  [ -n "$mode" ] || return 0

  # A saved legacy mode always wins. A saved modern mode only replaces the
  # default mode and never an explicit user-selected boot configuration.
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

  # Restore the saved machine only when q35 is still the default; an explicit
  # user-selected machine must remain untouched.
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

    "win9"* | "winnt4" )

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

      writeState "old" "pc" || return 1
      writeState "type" "auto" || return 1
      writeState "net" "rtl8139" || return 1
      writeState "usb" "pci-ohci" || return 1 ;;

  esac

  if [[ "${id,,}" == "reactos" ]] && [ -z "$CUSTOM" ]; then
    # The ISO is a Live-CD so we need to disable the data disk
    # as it will be always wiped during the next runs currently.
    REMOVE="N"
    DISK_DISABLE="Y"
  fi

  restoreMachine || return 1

  case "${id,,}" in

    "win9"* | "winnt4" | "win2k"* | *"x86"* | "reactos" )

      # Legacy 32-bit Windows may enter an incompatible PAE/DEP path when the
      # NX flag is exposed, causing installation failures or repeated resets.

      writeState "flag" "nx=off" || return 1 ;;

  esac

  case "${id,,}" in

    "win9"* | "winnt4" | "win2k"* | "winxp"* | "win2003"* | \
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

startWindows

return 0

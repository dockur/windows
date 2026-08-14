#!/usr/bin/env bash
set -Eeuo pipefail

startWindows() {

  parseVersion || {
    error "Failed to parse the Windows version!"
    exit 58
  }

  parseLanguage || {
    error "Failed to parse the Windows language!"
    exit 62
  }

  detectCustom || {
    error "Failed to scan for custom installation media!"
    exit 64
  }

  local rc=0
  startInstall || rc=$?
  (( rc > 1 )) && exit "$rc"

  if (( rc )); then

    bootWindows || {
      error "Failed to boot Windows!"
      exit 66
    }

    return 0

  fi

  if ! hasImage "$ISO"; then

    if ! downloadImage "$ISO" "$VERSION" "$LANGUAGE"; then
      removeImage "$ISO" || :
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

  XML=""
  SYSTEM=""
  FB="falling back to manual installation!"

  normalizeDetected || :

  if [ -n "$DETECTED" ]; then

    if ! setImage; then
      error "Failed to configure the detected Windows image!"
      return 70
    fi

    if ! needsExtraction "$iso"; then

      needsPreparation "$DETECTED" || return 0

    fi

    if ! extractImage "$iso" "$dir" "$VERSION"; then
      error "Failed to extract the Windows installation image!"
      removeImage "$iso" || :
      return 72
    fi

    extracted=1
    return 0

  fi

  # Inspect unknown bootable media directly before falling back to extraction.
  if ! needsExtraction "$iso"; then

    detectIsoImage "$iso" && return 0

    local rc=$?
    if (( rc != 1 )); then
      error "Failed to inspect the Windows installation ISO!"
      return 76
    fi

  elif [[ "${iso,,}" == *.esd ]]; then

    detectESDImage "$iso" && return 0
    error "Failed to inspect the Windows installation ESD!"
    return 76

  fi

  if ! extractImage "$iso" "$dir" "$VERSION"; then
    error "Failed to extract the Windows installation image!"
    removeImage "$iso" || :
    return 74
  fi

  extracted=1

  detectImage "$dir" && return 0

  local rc=$?
  if (( rc != 1 )); then
    error "Failed to detect the extracted Windows installation image!"
    return 76
  fi

  skipUnattended "$dir" "$iso" "$boot" || {
    error "Failed to fall back to manual installation!"
    return 76
  }

  handled=1
  return 0
}

configureMachine() {

  local iso="$1"
  local dir="$2"
  local boot="$3"

  local desc
  desc=$(printVariant "$DETECTED" "$DETECTED") || return 78

  if ! checkMemory "$DETECTED"; then

    if ! isCustomImage; then
      useOriginalImage "$iso" || {
        error "Failed to preserve the original installation image!"
        return 79
      }
    fi

    return 79
  fi

  setDiskMinimum "$DETECTED" || return 79

  if ! setMachine "$DETECTED" "$iso" "$dir" "$desc"; then
    error "Failed to configure the virtual machine for $desc!"
    return 80
  fi

  if ! restoreMachineState; then
    error "Failed to restore the saved machine state!"
    return 82
  fi

  if ! supportsUnattended "$DETECTED"; then

    skipUnattended "$dir" "$iso" "$boot" "N" || {
      error "Failed to fall back to manual installation!"
      return 83
    }
  
    handled=1
    return 0

  fi

  return 0
}

prepareWindowsImage() {

  local iso="$1"
  local dir="$2"
  local boot="$3"

  if [ -n "$SYSTEM" ]; then

    hasImage "$SYSTEM" || {
      error "Failed to find the generated Windows system image!"
      return 94
    }

    removeImage "$iso" || {
      error "Failed to remove the source installation image!"
      return 96
    }

    BOOT="$SYSTEM"
    return 0

  fi

  # Keep all run-specific automation on the setup image for XML-capable media.
  if supportsXML "$DETECTED"; then

    if ! createOverlay "$XML" "$LANGUAGE" "$TMP/setup"; then
      error "Failed to create the Windows setup overlay!"
      return 84
    fi

    if ! createSetupImage "$TMP/setup" "$STORAGE/setup.img"; then
      error "Failed to create the Windows setup image!"
      return 86
    fi

    # Bootable ISOs can be reused unchanged with the generated setup image.
    if (( ! extracted )); then

      useOriginalImage "$iso" || {
        error "Failed to preserve the original installation image!"
        return 88
      }

      return 0
    fi

  fi

  # Extracted modern sources and SIF-based legacy media require a clean rebuild.
  if (( ! extracted )); then

    if ! extractImage "$iso" "$dir" "$VERSION"; then
      error "Failed to extract the Windows installation image!"
      removeImage "$iso" || :
      return 90
    fi
  
  fi

  if ! prepareImage "$iso" "$dir"; then
    error "Failed to prepare the Windows installation image!"
    return 92
  fi

  removeImage "$iso" || {
    error "Failed to remove the source installation image!"
    return 96
  }

  buildImage "$dir" || {
    error "Failed to build the Windows installation image!"
    return 98
  }

  return 0
}

bootWindows() {

  if ! restoreMachineState; then
    error "Failed to restore the saved machine state!"
    return 1
  fi

  if ! restoreBootMode; then
    error "Failed to restore the saved boot mode!"
    return 1
  fi

  if ! restoreMachine; then
    error "Failed to restore the saved machine type!"
    return 1
  fi

  if ! reserveSambaPorts; then
    error "Failed to reserve Samba ports!"
    return 1
  fi

  return 0
}

startInstall() {

  html "Starting $APP..."

  if ! isCustomImage; then

    local file="${VERSION//\//}.iso"
    local boot="$file"

    if isURL "$VERSION"; then

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
          return 58 ;;
      esac

    else

      local language
      if ! language=$(getLanguage "$LANGUAGE" "culture"); then
        error "Failed to determine the Windows language!"
        return 62
      fi

      language="${language%%-*}"

      if [ -n "$language" ] && [[ "${language,,}" != "en" ]]; then
        file="${VERSION//\//}_${language,,}.iso"
        boot="$file"
      fi

    fi

    BOOT="$STORAGE/$boot"

  fi

  TMP="$STORAGE/tmp"

  if ! rm -rf -- "$TMP"; then
    error "Failed to remove directory \"$TMP\" !"
    return 50
  fi

  local setup="$STORAGE/setup.img"

  if ! rm -f -- "$setup" "${setup}.tmp"; then
    error "Failed to remove setup image \"$setup\" !"
    return 50
  fi

  local previousBase
  if ! previousBase=$(readState "base"); then
    error "Failed to read the previous installation state!"
    return 50
  fi

  local rc=0
  skipInstall "$BOOT" "$previousBase" || rc=$?

  (( rc > 1 )) && return "$rc"
  (( rc )) || return 1

  if [ -z "$previousBase" ] && hasInstalledDisk; then

    if ! hasCompletedInstall && ! disabled "${SHUTDOWN:-}"; then
      discardPrevious "" || return 50
    else
      if ! backupPrevious ""; then
        warn "the backup was incomplete, continuing with installation..."
      fi
    fi

  fi

  if ! makeDir "$TMP"; then
    error "Failed to create directory \"$TMP\" !"
    return 50
  fi

  if ! isCustomImage; then

    if hasImage "$BOOT"; then
      ISO="$TMP/$(basename "$BOOT")"
    else
      ISO="$TMP/$file"
    fi

  fi

  # Keep existing media at its persistent path until all storage cleanup has
  # completed successfully, so a later failure cannot strand it under $TMP.
  if isCustomImage || ! hasImage "$BOOT"; then
    if ! rm -f -- "$BOOT"; then
      error "Failed to remove obsolete ISO file \"$BOOT\" !"
      return 50
    fi
  fi

  if ! find "$STORAGE" -maxdepth 1 -type f -iname 'data.*' -not -iname '*.iso' -delete; then
    error "Failed to remove obsolete disk files from \"$STORAGE\" !"
    return 50
  fi

  if ! find "$STORAGE" -maxdepth 1 -type f -iname 'windows.*' -not -iname '*.iso' -delete; then
    error "Failed to remove obsolete Windows files from \"$STORAGE\" !"
    return 50
  fi

  if ! find "$STORAGE" -maxdepth 1 -type f \( -iname '*.rom' -or -iname '*.vars' \) -delete; then
    error "Failed to remove obsolete firmware files from \"$STORAGE\" !"
    return 50
  fi

  if ! isCustomImage && ! isURL "$VERSION"; then
    checkMemory "$VERSION" || return 67
    setDiskMinimum "$VERSION" || return 67
  fi

  # Work from the temporary directory so the persistent source path can
  # later contain either the preserved ISO or the rebuilt installation image.
  if ! isCustomImage && hasImage "$BOOT"; then
    if ! mv -f -- "$BOOT" "$ISO"; then
      error "Failed to move ISO file from \"$BOOT\" to \"$ISO\" !"
      return 50
    fi
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
  if needsExtraction "$iso"; then
    error "Failed to boot \"$iso\" because it is not a directly bootable ISO image!"
    return 1
  fi

  # When automatic preparation fails, inspect extracted media to determine
  # whether it can still be booted manually using legacy firmware.
  if enabled "$aborted" && isPlatform "x64" && [ -d "$dir" ]; then

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
  useOriginalImage "$iso" || return 1

  finishInstall "$BOOT" "$aborted" "$boot" && return 0
  return 1
}

skipInstall() {

  local iso="$1"
  local previousBase="$2"
  local system

  if [ -n "$previousBase" ]; then

    # Older releases stored the original download name in windows.base. Current
    # releases store an ISO source identity, so migrate legacy state once.
    if [[ "${previousBase,,}" != *.iso ]]; then

      if isCompressed "$previousBase" || [[ "${previousBase,,}" == *.esd ]]; then
        previousBase="${previousBase%.*}"
      fi

      [ -n "$previousBase" ] || previousBase="download"
      previousBase+=".iso"

      if ! writeState "base" "$previousBase"; then
        error "Failed to migrate the previous installation state!"
        return 50
      fi

    fi

    # Older releases may have left a rebuilt custom ISO at its synthetic source
    # identity. A completed installation no longer needs that installation media.
    if [[ "${previousBase,,}" == "windows."* ]] && hasCompletedInstall; then

      if ! rm -f -- "$STORAGE/$previousBase"; then
        error "Failed to remove obsolete ISO file \"$STORAGE/$previousBase\" !"
        return 50
      fi

    fi

    # A changed source invalidates an unfinished installation. Back up an
    # existing installation, but discard stale media when no disk exists yet.
    if [[ "${STORAGE,,}/${previousBase,,}" != "${iso,,}" ]]; then

      if ! hasInstalledDisk; then

        if ! rm -f -- "$STORAGE/$previousBase"; then
          error "Failed to remove ISO file \"$STORAGE/$previousBase\" !"
          return 50
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

          if hasCompletedInstall; then
            info "Detected that $method, will be ignored."
            return 0
          fi

        fi
      fi

      if ! hasCompletedInstall && ! disabled "${SHUTDOWN:-}"; then
        discardPrevious "$STORAGE/$previousBase" || return 50
        return 1
      fi

      info "Detected that $method, a backup of your previous installation will be saved..."

      if ! backupPrevious "$STORAGE/$previousBase"; then
        warn "the backup was incomplete, continuing with installation..."
      fi

      return 1

    fi
  fi

  if [ -n "$previousBase" ] && system=$(getSystemImage); then
    BOOT="$system"
    return 0
  fi

  hasData && hasBootMarker && return 0

  return 1
}

finishInstall() {

  local iso="$1"
  local aborted="$2"
  local boot="$3"

  local base secure=0

  if ! hasImage "$iso"; then
    error "Failed to find ISO file: $iso" && return 1
  fi

  if [[ "$iso" == "$STORAGE/"* ]]; then
    if ! setOwner "$iso"; then
      warn "failed to set the owner for \"$iso\" !"
    fi
  fi

  local file="$STORAGE/windows.ver"
  cp -f /etc/version "$file" || {
    error "Failed to save the Windows installation version!"
    return 1
  }

  if ! setOwner "$file"; then
    warn "Failed to set the owner for \"$file\" !"
  fi

  if [[ "$boot" == "$STORAGE/"* ]]; then
    if [[ "$aborted" != [Yy1]* ]] || ! isCustomImage; then

      base=$(basename "$boot")
      writeState "base" "$base" || {
        error "Failed to save the Windows installation source!"
        return 1
      }

    fi
  fi

  if isPlatform "x64"; then
    if isLegacyBoot; then

      writeState "mode" "$BOOT_MODE" || {
        error "Failed to save the Windows boot mode!"
        return 1
      }

    else

      # Aborted Win11 installs boot without any answer file present,
      # so enable Secure Boot and TPM to satisfy its hardware checks.
      if enabled "$aborted" || enabled "$MANUAL"; then
        [[ "${DETECTED,,}" == "win11"* ]] && secure=1
      fi

      if (( secure )); then

        BOOT_MODE="windows_secure"
        writeState "mode" "$BOOT_MODE" || {
          error "Failed to save the Windows boot mode!"
          return 1
        }

      fi

    fi
  fi

  reserveSambaPorts || {
    error "Failed to reserve Samba ports!"
    return 1
  }

  if [ -n "$SYSTEM" ]; then

    if [[ "$SYSTEM" == "$TMP/"* ]]; then

      if ! mv -f -- "$SYSTEM" "$STORAGE/windows.img"; then
        error "Failed to finalize the Windows system image!"
        return 1
      fi

      BOOT="$STORAGE/windows.img"

    else

      if ! hasImage "$SYSTEM"; then
        error "Failed to find the Windows system image!"
        return 1
      fi

      writeState "system" "$SYSTEM" || {
        error "Failed to save the Windows system image!"
        return 1
      }

      BOOT="$SYSTEM"
    fi
  fi

  if ! rm -rf -- "$TMP"; then
    error "Failed to remove directory \"$TMP\" !"
    return 1
  fi

  return 0
}

findFile() {

  local fname="$1"
  local dir file base

  dir=$(find / -maxdepth 1 -type d -iname "$fname" -print -quit) || return 1

  if [ ! -d "$dir" ]; then
    dir=$(find "$STORAGE" -maxdepth 1 -type d -iname "$fname" -print -quit) || return 1
  fi

  if [ -d "$dir" ]; then
    if ! hasSystemImage && { ! hasDisk || ! hasBootMarker; }; then
      error "The bind $dir maps to a file that does not exist!" && return 1
    fi
  fi

  file=$(find / -maxdepth 1 -type f -iname "$fname" -print -quit) || return 1

  if [ ! -s "$file" ]; then
    file=$(find "$STORAGE" -maxdepth 1 -type f -iname "$fname" -print -quit) || return 1
  fi

  if [ ! -s "$file" ] && ! isURL "$VERSION"; then
    base=$(basename "$VERSION")
    file="$STORAGE/$base"
  fi

  if ! hasImage "$file"; then
    return 0
  fi

  local size
  size=$(stat -c%s "$file") || return 1

  if [ -z "$size" ] || [[ "$size" == "0" ]]; then
    return 0
  fi

  ISO="$file"
  CUSTOM="$file"

  # Encode the custom ISO size in a synthetic source identity so replacing a
  # bind-mounted ISO is detected as a different installation source.
  BOOT="$STORAGE/windows.$size.iso"

  return 0
}

normalizeDetected() {

  # Known catalog versions already provide the required image metadata.
  if [ -z "$DETECTED" ] && ! isCustomImage && ! isURL "$VERSION"; then
    DETECTED="$VERSION"
  fi

  DETECTED="${DETECTED/-enterprise-iot/-iot}"
  DETECTED="${DETECTED/-enterprise-ltsc/-ltsc}"

  return 0
}

detectCustom() {

  CUSTOM=""

  findFile "custom.iso" || return 1

  if isCustomImage; then
    DETECTED=""
    return 0
  fi

  findFile "boot.iso" || return 1

  if isCustomImage; then
    DETECTED=""
    return 0
  fi

  return 0
}

isCustomImage() {

  [ -n "${CUSTOM:-}" ]
}

isURL() {

  local value="$1"

  [[ "${value,,}" == "http"* ]]
}

isPlatform() {

  local platform="$1"

  [[ "${PLATFORM,,}" == "${platform,,}" ]]
}

isLegacyBoot() {

  local mode="${BOOT_MODE:-}"
  (( $# )) && mode="$1"

  [[ "${mode,,}" == "windows_legacy" ]]
}

hasBootMarker() {

  [ -f "$STORAGE/windows.boot" ]
}

hasImage() {

  local iso="$1"

  [ -f "$iso" ] && [ -s "$iso" ]
}

getSystemImage() {

  local image

  image=$(readState "system") || return 1

  if [ -n "$image" ]; then
    # Older development builds stored only the basename in windows.system.
    [[ "$image" == /* ]] || image="$STORAGE/$image"
    hasImage "$image" || return 1

    echo "$image"
    return 0
  fi

  image="$STORAGE/windows.img"
  hasImage "$image" || return 1

  echo "$image"
  return 0
}

hasSystemImage() {

  getSystemImage >/dev/null
}

hasInstalledDisk() {

  hasData || hasSystemImage
}

hasCompletedInstall() {

  hasSystemImage && return 0
  hasData && hasBootMarker
}

needsExtraction() {

  local iso="$1"

  enabled "${UNPACK:-}" || [[ "${iso,,}" == *.esd ]]
}

needsPreparation() {

  local id="$1"

  supportsSIF "$id" && return 0

  case "${id,,}" in
    "win9"* )
      supportsUnattended "$id" && return 0 ;;
  esac

  return 1
}

useOriginalImage() {

  local iso="$1"

  if isCustomImage; then
    BOOT="$iso"
  elif [[ "$iso" != "$BOOT" ]]; then
    if ! mv -f -- "$iso" "$BOOT"; then
      error "Failed to move ISO file: $iso"
      return 1
    fi
  fi

  # Keep SYSTEM pointing at the same image when preserving it changes its path.
  if [[ "${SYSTEM:-}" == "$iso" ]]; then
    SYSTEM="$BOOT"
  fi

  return 0
}

removeImage() {

  local iso="$1"

  isCustomImage && return 0

  if ! rm -f -- "$iso" 2>/dev/null; then
    warn "failed to remove image \"$iso\"!"
    return 1
  fi

  return 0
}

setImage() {

  local rc=0

  supportsXML "${DETECTED,,}" || return 0

  setXML "" || rc=$?

  if (( rc == 0 )); then
    return 0
  fi

  enabled "$MANUAL" && return 0

  # Only a genuinely missing answer file may fall back to manual setup.
  (( rc == 1 )) || return "$rc"

  MANUAL="Y"

  local desc
  desc=$(printEdition "$DETECTED" "this version") || return 1

  warn "the answer file for $desc was not found ($DETECTED.xml), $FB."
  return 0
}

detectImage() {

  local dir="$1"
  local desc rc

  info "Detecting version from ISO image..."

  # Marker-based legacy detection must run before looking for a WIM.
  if detectLegacy "$dir"; then

    desc=$(printEdition "$DETECTED" "$DETECTED" "Y") || return 2

    info "Detected: $desc"
    return 0

  else
    rc=$?
    (( rc == 1 )) || return "$rc"
  fi

  if detectReactOS "$dir"; then

    desc=$(printEdition "$DETECTED" "$DETECTED" "Y") || return 2

    info "Detected: $desc"
    return 0

  else
    rc=$?
    (( rc == 1 )) || return "$rc"
  fi

  local wim
  wim=$(findImage "$dir") || return $?

  local image_info
  image_info=$(readImageInfo "$wim") || return $?

  detectImageInfo "$image_info" || {
    error "Failed to process the Windows image metadata!"
    return 2
  }

  return 0
}

prepareImage() {

  local iso="$1"
  local dir="$2"

  local desc missing
  desc=$(printVariant "$DETECTED" "$DETECTED")

  # Use the standard Windows BIOS boot image unless legacy preparation
  # already selected a media-specific El Torito image.
  ETFS="${ETFS:-boot/etfsboot.com}"

  # Legacy rebuilt media must retain the source ISO's El Torito boot-load size.
  if isLegacyBoot; then

    getBootLoadSize "$iso" "$dir" "$desc" || return 1

  fi

  supportsXML "$DETECTED" || return 0

  if isLegacyBoot; then

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
  local mode="${2:-copy}"
  
  local file="" source="" folder
  local dest="$src/\$OEM\$/\$1/OEM"
  local install="$src/.overlay-install.bat"

  if [ "$mode" = "win9x" ]; then
    dest="$src/OEM"
  fi

  folder=$(getOemFolder) || return 1

  [ -z "$folder" ] && [ -z "$COMMAND" ] && return 0

  local msg="Adding OEM files to image..."
  info "$msg" && html "$msg"

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

  local stage="$1"
  local version="$2"

  local drivers="$stage/drivers"
  local msg="Windows version and architecture are unknown; cannot select drivers!"

  rm -rf "$drivers" || return 1
  mkdir -p "$drivers" || return 1

  info "Adding drivers to image..."

  if [ -z "$version" ]; then

    if [ -z "${IMAGE_PLATFORM:-}" ]; then
      error "$msg" && return 1
    fi

    case "${IMAGE_PLATFORM,,}" in
      "x86" )   version="win7x86" ;;
      "x64" )   version="win11x64" ;;
      "arm64" ) version="win11arm64" ;;
      * )       error "$msg" && return 1 ;;
    esac

    local desc
    desc=$(printVersion "$version" "") || return 1

    warn "Windows version unknown, falling back to $desc drivers..."
  fi

  if ! bsdtar -xf /var/drivers.txz -C "$drivers"; then
    error "Failed to extract drivers from archive!" && return 1
  fi

  local target="\$WinPEDriver\$"
  local dest="$drivers/$target"

  mkdir -p "$dest" || return 1

  selectDrivers "$version" "$drivers" "$target" || return 1

  local dst="$stage/\$OEM\$/\$\$/Drivers"
  mkdir -p "$dst" || return 1
  cp -Lr "$dest/." "$dst" || return 1

  # Install the VirtIO display driver explicitly from SetupComplete.cmd so it
  # cannot disrupt Windows Setup by loading through the WinPE driver path.
  if ! isLegacy "$version"; then
    rm -rf "$dest/viogpudo" || return 1
  fi

  local winpe="$stage/$target"
  rm -rf "$winpe" || return 1
  mkdir -p "$winpe" || return 1
  cp -Lr "$dest/." "$winpe" || return 1

  rm -rf "$drivers" || return 1

  return 0
}

normalizeBatch() {

  local file="$1"
  local bom tmp encoding

  [ ! -s "$file" ] && return 0

  bom=$(od -An -N2 -tx1 "$file" | tr -d ' \n') || return 1

  # Convert only BOM-marked UTF-16 files; unmarked ANSI and UTF-8 batch files
  # are deliberately left unchanged.
  case "$bom" in
    "fffe" ) encoding="UTF-16LE" ;;
    "feff" ) encoding="UTF-16BE" ;;
    * ) return 0 ;;
  esac

  if ! tmp=$(mktemp "${file}.XXXXXX"); then
    error "Failed to create temporary batch file!"
    return 1
  fi

  if ! tail -c +3 "$file" | iconv -f "$encoding" -t UTF-8 > "$tmp"; then
    rm -f "$tmp"
    error "Failed to convert $file from $encoding to UTF-8!"
    return 1
  fi

  if ! chmod --reference="$file" "$tmp" || ! mv -f "$tmp" "$file"; then
    rm -f "$tmp"
    error "Failed to replace batch file: $file"
    return 1
  fi

  return 0
}

reportBatchMatches() {

  local file="$1"
  local source="$2"
  local pattern="$3"
  local message="$4"
  local suggestion="$5"

  local matches line
  matches=$(grep -Pin "$pattern" "$file" || true)

  [ -n "$matches" ] || return 0

  warn "$message in $source:"

  while IFS= read -r line; do
    printf '  %s\n' "$line" >&2
  done <<< "$matches"

  printf '  %s\n\n' "$suggestion" >&2

  return 0
}

checkBatch() {

  local file="$1"

  local tmp output
  local matches line
  local enabled_rules

  [ -s "$file" ] || return 0

  if ! tmp=$(mktemp -d /tmp/blinter.XXXXXX); then
    warn "failed to create temporary Blinter directory."
    return 0
  fi

  local source="your install.bat file"
  [ -n "${COMMAND:-}" ] && source="your COMMAND variable"

  # Only check rules that indicate likely execution or behavioural failures.
  enabled_rules="E001,E002,E003,E004,E005,E006,E007,E008"
  enabled_rules+=",E009,E010,E011,E012,E013,E014,E015,E016"
  enabled_rules+=",E017,E018,E019,E020,E021,E022,E023,E024"
  enabled_rules+=",E025,E027,E028,E029,E030,E031,E032,E033,E034"
  enabled_rules+=",W004,W005,W013,W017,W021,W022,W034,W038,W040"

  if enabled "$DEBUG"; then
    if LC_ALL=C grep -Pq '[^\x09\x0D\x20-\x7E]' "$file"; then
      warn "non-ASCII characters were detected in $source and may not execute correctly in Windows Command Prompt."
    fi
  fi

  cat > "$tmp/blinter.ini" <<EOC
[general]
min_severity = warning
show_summary = false

[rules]
enabled_rules = $enabled_rules
EOC

  output=$(
    cd "$tmp"
    python3 -m blinter "$file" 2>&1 || true
  )

  # Remove header.
  output=$(
    awk '
      /^DETAILED ISSUES:/ {
        found = 1
        next
      }

      found && !started {
        if (/^-+$/) {
          started = 1
        }
        next
      }

      started {
        print
      }
    ' <<< "$output"
  )

  output="${output#"${output%%[!$'\r\n ']*}"}"
  output="${output%"${output##*[!$'\r\n ']}"}"

  if grep -Eq '^(ERROR|WARNING|SECURITY) LEVEL ISSUES:$' <<< "$output"; then

    warn "possible issues were detected in $source:"
    printf '\n%s\n\n' "$output" >&2
  fi

  rm -rf "$tmp" || true

  reportBatchMatches \
    "$file" \
    "$source" \
    '(?<!\\)\\host[.]lan[\\]' \
    "invalid single-backslash UNC path detected" \
    'Use "\\host.lan\Data\..." instead of "\host.lan\Data\...".'

  reportBatchMatches \
    "$file" \
    "$source" \
    '(?<![\\[:alnum:]._-])host[.]lan[\\]' \
    "UNC path without leading backslashes detected" \
    'Use "\\host.lan\Data\..." instead of "host.lan\Data\...".'

  reportBatchMatches \
    "$file" \
    "$source" \
    '//host[.]lan/' \
    "invalid forward-slash UNC path detected" \
    'Use "\\host.lan\Data\..." instead of "//host.lan/Data/...".'

  reportBatchMatches \
    "$file" \
    "$source" \
    '\\\\host[.]lan\\shared(?:[\\/]|$)' \
    "invalid Samba share name detected" \
    'The "/shared" folder is exposed to Windows as "\\host.lan\Data".'

  return 0
}

createOverlay() {

  local asset="$1"
  local language="$2"
  local stage="$3"

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

  if ! addDrivers "$stage" "$DETECTED"; then
    error "Failed to include Windows drivers!"
    return 1
  fi

  if ! addFolder "$stage" "overlay"; then
    error "Failed to include OEM folder!"
    return 1
  fi

  addAnswerFile "$asset" "$language" "$stage" || {
    error "Failed to include the Windows answer file!"
    return 1
  }

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

discardPrevious() {

  local iso="$1"

  if [ -n "$iso" ] && [ -f "$iso" ]; then
    if ! rm -f -- "$iso"; then
      error "Failed to remove ISO file \"$iso\" !"
      return 1
    fi
  fi

  if ! find "$STORAGE" -maxdepth 1 -type f \
    \( -iname 'data.*' -or -iname 'windows.*' -or -iname '*.rom' -or -iname '*.vars' \) \
    -not -iname '*.iso' -delete; then
    error "Failed to remove unfinished installation files from \"$STORAGE\" !"
    return 1
  fi

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

  rmdir "$dir" 2>/dev/null || :
  rmdir "$root" 2>/dev/null || :

  [ -n "$failed" ] && return 1

  return 0
}

checkMemory() {

  local id="$1"
  local required name

  required=$(getRequiredMemory "$id") || return
  RAM_MINIMUM="$required"

  name=$(printVersion "$id" "") || return
  checkMemoryRequirement "$name" || return

  return 0
}

setDiskMinimum() {

  local id="$1"
  local required

  required=$(getRequiredDisk "$id") || return
  DISK_MINIMUM="$required"

  return 0
}

startWindows

return 0

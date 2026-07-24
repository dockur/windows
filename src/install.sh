#!/usr/bin/env bash
set -Eeuo pipefail

ETFS="boot/etfsboot.com"
FB="falling back to manual installation!"
EFISYS="efi/microsoft/boot/efisys_noprompt.bin"

backup () {

  local iso="$1"
  local count=1
  local name="unknown"
  local root="$STORAGE/backups"
  local file previous find_pid failed=""

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

  find_pid=$!

  if ! wait "$find_pid"; then
    error "Failed to enumerate files in \"$STORAGE\"."
    failed="Y"
  fi

  [ -z "$(ls -A "$dir")" ] && rm -rf "$dir"
  [ -z "$(ls -A "$root")" ] && rm -rf "$root"

  [ -n "$failed" ] && return 1

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

skipInstall() {

  local iso="$1"
  local method=""
  local magic byte
  local boot="$STORAGE/windows.boot"
  local previous

  previous=$(readState "base") || return 1

  if [ -n "$previous" ]; then
    if [[ "${STORAGE,,}/${previous,,}" != "${iso,,}" ]]; then

      if ! hasDisk; then

        if ! rm -f -- "$STORAGE/$previous"; then
          error "Failed to remove ISO file \"$STORAGE/$previous\" !"
          exit 50
        fi

        return 1

      fi

      if [[ "${iso,,}" == "${STORAGE,,}/windows."* ]]; then
        method="your custom .iso file was changed"
      else
        if [[ "${previous,,}" != "windows."* ]]; then
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

      if ! backup "$STORAGE/$previous"; then
        warn "the backup was incomplete, continuing with installation..."
      fi

      return 1

    fi
  fi

  [ -f "$boot" ] && hasData && return 0

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

  skipInstall "$BOOT" && return 1

  if hasDisk; then
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

finishInstall() {

  local iso="$1"
  local aborted="$2"
  local base byte

  if [ ! -s "$iso" ] || [ ! -f "$iso" ]; then
    error "Failed to find ISO file: $iso" && return 1
  fi

  if [[ "$iso" == "$STORAGE/"* ]]; then
    if ! setOwner "$iso"; then
      warn "failed to set the owner for \"$iso\" !"
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
    warn "Failed to set the owner for \"$file\" !"
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

  if [ -n "${SOUND:-}" ] && [[ "${SOUND:-}" != "intel-hda" ]]; then
    writeState "sound" "$SOUND" || return 1
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

  local msg ret index size
  local minSize freeSpace bootPad
  local info count totals links
  local bootTotal bootLinks bootSize
  local wimTotal wimLinks wimSize
  local installSize installPad
  local bootWim installWim
  local edition imgEdition

  minSize=100000000
  freeSpace=9606127360
  bootPad=60000000
  installPad=3000000

  msg="Extracting $desc bootdisk"
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

  if (( size < 100000000 )); then
    error "Invalid ISO file: Size is smaller than 100 MB" && return 1
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

setMachine() {

  local id="$1"
  local iso="$2"
  local dir="$3"
  local desc="$4"

  case "${id,,}" in
    "win9"* )
      ETFS="[BOOT]/Boot-1.44M.img" ;;
    "win2k"* )
      if ! legacyInstall "$iso" "$dir" "$desc" "2k"; then
        error "Failed to prepare $desc ISO!" && return 1
      fi ;;
    "winxp"* )
      if ! legacyInstall "$iso" "$dir" "$desc" "xp"; then
        error "Failed to prepare $desc ISO!" && return 1
      fi ;;
    "win2003"* )
      if ! legacyInstall "$iso" "$dir" "$desc" "2k3"; then
        error "Failed to prepare $desc ISO!" && return 1
      fi ;;
  esac

  case "${id,,}" in
    "win9"* )
      USB="no"
      VGA="cirrus"
      DISK_TYPE="auto"
      MACHINE="pc-i440fx-2.4"
      BOOT_MODE="windows_legacy"
      [ -z "${ADAPTER:-}" ] && ADAPTER="pcnet" ;;
    "win2k"* )
      VGA="cirrus"
      MACHINE="pc"
      USB="pci-ohci"
      DISK_TYPE="auto"
      BOOT_MODE="windows_legacy"
      [ -z "${ADAPTER:-}" ] && ADAPTER="rtl8139" ;;
    "winxp"* | "win2003"* )
      DISK_TYPE="blk"
      BOOT_MODE="windows_legacy"
      [ -z "${SOUND:-}" ] && SOUND="usb-audio" ;;
    "winvista"* | "win7"* | "win2008"* )
      BOOT_MODE="windows_legacy" ;;
  esac

  case "${id,,}" in
    "winxp"* | "win2003"* | "winvistax86"* | "win7x86"* | "win2008r2x86"* )
      # Prevent bluescreen if 64 bit PCI hole size is >2G.
      ARGS="-global q35-pcihost.x-pci-hole64-fix=false" ;;
  esac

  return 0
}

prepareImage() {

  local iso="$1"
  local dir="$2"
  local desc missing

  desc=$(printVariant "$DETECTED" "$DETECTED")

  setMachine "$DETECTED" "$iso" "$dir" "$desc" || return 1
  skipVersion "$DETECTED" && return 0

  if [[ "${BOOT_MODE,,}" != "windows_legacy" ]]; then

    [ -f "$dir/$ETFS" ] && [ -s "$dir/$ETFS" ] &&
      [ -f "$dir/$EFISYS" ] && [ -s "$dir/$EFISYS" ] && return 0
  
    missing=$(basename "$dir/$EFISYS")
    if [ ! -f "$dir/$ETFS" ] || [ ! -s "$dir/$ETFS" ]; then
      missing=$(basename "$dir/$ETFS")
    fi

    error "Failed to locate file \"${missing,,}\" in ISO image!"
    return 1
  fi

  legacyPrepare "$iso" "$dir" "$desc" && return 0

  error "Failed to extract boot image from ISO image!"
  return 1
}

addFolder() {

  local src="$1"
  local folder="/oem" file=""
  local dest="$src/\$OEM\$/\$1/OEM"

  [ ! -d "$folder" ] && folder="/OEM"
  [ ! -d "$folder" ] && folder="$STORAGE/oem"
  [ ! -d "$folder" ] && folder="$STORAGE/OEM"
  [ ! -d "$folder" ] && folder=""

  [ -z "$folder" ] && [ -z "$COMMAND" ] && return 0

  local msg="Adding OEM files to image..."
  info "$msg" && html "$msg"

  mkdir -p "$dest" || return 1

  if [ -n "$folder" ]; then
    cp -Lr "$folder/." "$dest" || return 1
  fi

  file=$(find "$dest" -maxdepth 1 -type f -iname install.bat -print -quit) || return 1

  if [ -n "$COMMAND" ]; then

    [ -z "$file" ] && file="$dest/install.bat"

    if [ -s "$file" ]; then
      printf '\n' >> "$file" || return 1
    fi

    printf '%s\n' "$COMMAND" >> "$file" || return 1

  fi

  if [ -f "$file" ]; then
    if ! unix2dos -q "$file"; then
      error "Failed to convert $file to DOS format!"
      return 1
    fi
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

    name=$(basename "$asset") || return 1
    local answer="$tmp/$name"

    info "Adding $name for automatic installation..."

    if ! cp "$asset" "$answer"; then
      error "Failed to copy answer file to $answer."
      return 1
    fi

    removeGeneratedXML "$asset" || return 1

    if [ -n "${CUSTOM_XML:-}" ]; then

      if ! xmllint --nonet --noout "$answer"; then
        error "The custom answer file is not valid XML!"
        return 1
      fi

    else

      if ! updateXML "$answer" "$language"; then
        error "Failed to update answer file: $answer"
        return 1
      fi

    fi

    if ! wimlib-imagex update "$wim" "$idx" --command "add $answer /$xml" > /dev/null; then
      MANUAL="Y"
      warn "failed to add answer file ($name) to ISO image, $FB"
    else
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

  desc=$(printVariant "$DETECTED" "ISO")

  local msg="Building $desc image"
  info "$msg..." && html "$msg..."

  [ -z "$LABEL" ] && LABEL="Windows"

  if [ ! -f "$dir/$ETFS" ] || [ ! -s "$dir/$ETFS" ]; then
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
    warn "Failed to set the owner for \"$BOOT\" !"
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
  restoreState "SOUND" "$STORAGE/windows.sound" || return 1
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

return 0

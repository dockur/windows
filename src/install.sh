#!/usr/bin/env bash
set -Eeuo pipefail

ESD_URL=""
MACHINE="q35"
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
    error "Failed to find ISO: $iso" && return 1
  fi

  if [ -w "$iso" ] && [[ "$aborted" != [Yy1]* ]]; then
    # Mark ISO as prepared via magic byte
    if ! printf '\x16' | dd of="$iso" bs=1 seek=0 count=1 conv=notrunc status=none; then
      error "Failed to set magic byte!" && return 1
    fi
  fi

  rm -f "$STORAGE/windows.ver"
  rm -f "$STORAGE/windows.old"
  rm -f "$STORAGE/windows.boot"
  rm -f "$STORAGE/windows.mode"

  cp /run/version "$STORAGE/windows.ver"

  if [[ "${BOOT_MODE,,}" == "windows_legacy" ]]; then
    if [[ "${MACHINE,,}" != "q35" ]]; then
      echo "$MACHINE" > "$STORAGE/windows.old"
    fi
    echo "$BOOT_MODE" > "$STORAGE/windows.mode"
  else
    # Enable secure boot + TPM on manual installs as Win11 requires
    if [[ "$MANUAL" == [Yy1]* ]] || [[ "$aborted" == [Yy1]* ]]; then
      if [[ "${DETECTED,,}" == "win11"* ]]; then
        BOOT_MODE="windows_secure"
        echo "$BOOT_MODE" > "$STORAGE/windows.mode"
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
      error "Failed to move ISO: $iso" && return 1
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
  fi

  ! migrateFiles "$BASE" "$VERSION" && error "Migration failed!" && exit 57

  if skipInstall; then
    [ ! -f "$STORAGE/$BASE" ] && BASE=""
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
      error "Invalid ESD version specified: $version" && return 1
      ;;
  esac

  local msg="Downloading product information from Microsoft..."
  info "$msg" && html "$msg"

  rm -rf "$dir"
  mkdir -p "$dir"

  local wFile="catalog.cab"

  { wget "$winCatalog" -O "$dir/$wFile" -q; rc=$?; } || :
  (( rc != 0 )) && error "Failed to download $winCatalog , reason: $rc" && return 1

  cd "$dir"

  if ! cabextract "$wFile" > /dev/null; then
    cd /run
    error "Failed to extract CAB file!" && return 1
  fi

  cd /run

  if [ ! -s "$dir/products.xml" ]; then
    error "Failed to find products.xml!" && return 1
  fi

  local esdLang="en-us"
  local editionName="Professional"
  local edQuery='//File[Architecture="'${PLATFORM}'"][Edition="'${editionName}'"]'

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
    error "Failed to find ESD URL!" && return 1
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
  local rc progress

  rm -f "$iso"

  # Check if running with interactive TTY or redirected to docker log
  if [ -t 1 ]; then
    progress="--progress=bar:noscroll"
  else
    progress="--progress=dot:giga"
  fi

  local msg="Downloading $desc..."
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
    error "Invalid VERSION value: $version" && return 1
  fi

  desc=$(printVersion "$version" "Windows")

  if isMido "$version"; then
    tried="y"
    doMido "$iso" "$version" "$desc" && return 0
  fi

  if isESD "$version"; then

    [[ "$tried" != "n" ]] && info "Failed to download $desc using Mido, will try a different method now..."

    ISO="$TMP/$version.esd"
    iso="$ISO"

    tried="y"
    rm -rf "$TMP"
    mkdir -p "$TMP"

    if getESD "$TMP/esd" "$version"; then
      downloadFile "$iso" "$ESD_URL" "$desc" && return 0
    fi

  fi

  ISO="$TMP/$BASE"
  iso="$ISO"

  url=$(getLink "$version")

  if [ -n "$url" ]; then

    if [[ "$tried" != "n" ]]; then
      info "Failed to download $desc from Microsoft, will try another mirror now..."
    fi

    tried="y"
    rm -rf "$TMP"
    mkdir -p "$TMP"

    downloadFile "$iso" "$url" "$desc" && return 0

  fi

  url=$(secondLink "$version")

  if [ -n "$url" ]; then

    if [[ "$tried" != "n" ]]; then
      info "Failed to download $desc, will try another mirror now..."
    fi

    tried="y"
    rm -rf "$TMP"
    mkdir -p "$TMP"

    downloadFile "$iso" "$url" "$desc" && return 0

  fi

  return 1
}

extractESD() {

  local iso="$1"
  local dir="$2"
  local size size_gb space space_gb desc

  desc=$(printVersion "$VERSION" "Windows")
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
    "win11${PLATFORM,,}")
      edition="11 pro"
      ;;
    "win10${PLATFORM,,}")
      edition="10 pro"
      ;;
    *)
      error "Invalid version specified: $VERSION" && return 1
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

  error "Failed to find product in install.wim!" && return 1
}

extractImage() {

  local iso="$1"
  local dir="$2"
  local desc="downloaded ISO"
  local size size_gb space space_gb

  if [[ "${iso,,}" == *".esd" ]]; then
    extractESD "$iso" "$dir" && return 0
    return 1
  fi

  if [[ "$EXTERNAL" != [Yy1]* ]] && [ -z "$CUSTOM" ]; then
    desc=$(printVersion "$VERSION" "downloaded ISO")
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
      dsc=$(printVersion "$DETECTED" "$DETECTED")

      warn "got $dsc, but no matching XML file exists, $FB."
    fi

    return 0
  fi

  info "Detecting Windows version from ISO image..."

  if [ -f "$dir/WIN51" ] || [ -f "$dir/SETUPXP.HTM" ]; then
    DETECTED="winxpx86"
    info "Detected: Windows XP" && return 0
  fi

  local src loc tag result name name2 desc
  src=$(find "$dir" -maxdepth 1 -type d -iname sources | head -n 1)

  if [ ! -d "$src" ]; then
    BOOT_MODE="windows_legacy"
    warn "failed to locate 'sources' folder in ISO image, $FB" && return 1
  fi

  loc=$(find "$src" -maxdepth 1 -type f -iname install.wim | head -n 1)
  [ ! -f "$loc" ] && loc=$(find "$src" -maxdepth 1 -type f -iname install.esd | head -n 1)

  if [ ! -f "$loc" ]; then
    BOOT_MODE="windows_legacy"
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
    warn "failed to determine Windows version from string '$name', $FB" && return 0
  fi

  desc=$(printVersion "$DETECTED" "$DETECTED")

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
    error "Failed to extract driver ISO file!" && exit 66
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

  # Windows XP Pro generic key (no activation)
  local key="DR8GV-C8V6J-BYXHG-7PYJR-DB66Y"

  find "$target" -maxdepth 1 -type f -iname winnt.sif -exec rm {} \;

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
          echo "[Branding]"
          echo "BrandIEUsingUnattended=Yes"
          echo ""
          echo "[URL]"
          echo "Home_Page = http://www.google.com"
          echo "Search_Page = http://www.google.com"
          echo ""
          echo "[RegionalSettings]"
          echo "Language=00000409"
          echo ""
          echo "[TerminalServices]"
          echo "AllowConnections=1"
  } | unix2dos > "$target/WINNT.SIF"

  {       echo "Windows Registry Editor Version 5.00"
          echo ""
          echo "[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Security]"
          echo "\"FirstRunDisabled\"=dword:00000001"
          echo "\"AntiVirusOverride\"=dword:00000001"
          echo "\"FirewallOverride\"=dword:00000001"
          echo "\"FirewallDisableNotify\"=dword:00000001"
          echo "\"UpdatesDisableNotify\"=dword:00000001"
          echo "\"AntiVirusDisableNotify\"=dword:00000001"
          echo ""
          echo "[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\wscsvc]"
          echo "\"Start\"=dword:00000004"
          echo ""
          echo "[HKEY_LOCAL_MACHINE\Software\Policies\Microsoft\WindowsFirewall\StandardProfile]"
          echo "\"EnableFirewall\"=dword:00000000"
          echo ""
          echo "[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\SharedAccess]"
          echo "\"Start\"=dword:00000004"
          echo
          echo "[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\StandardProfile\GloballyOpenPorts\List]"
          echo "\"3389:TCP\"=\"3389:TCP:*:Enabled:@xpsp2res.dll,-22009\""
          echo ""
          echo "[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Lsa]"
          echo "\"LimitBlankPasswordUse\"=dword:00000000"
          echo ""
          echo "[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Applets\Tour]"
          echo "\"RunCount\"=dword:00000000"
          echo ""
          echo "[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced]"
          echo "\"HideFileExt\"=dword:00000000"
          echo ""
          echo "[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon]"
          echo "\"DefaultUserName\"=\"Docker\""
          echo "\"DefaultDomainName\"=\"Dockur\""
          echo "\"AltDefaultUserName\"=\"Docker\""
          echo "\"AltDefaultDomainName\"=\"Dockur\""
          echo "\"AutoAdminLogon\"=\"1\""
  } | unix2dos > "$dir/\$OEM\$/install.reg"

  {       echo "Set WshShell = WScript.CreateObject(\"WScript.Shell\")"
          echo "Set WshNetwork = WScript.CreateObject(\"WScript.Network\")"
          echo "Set oMachine = GetObject(\"WinNT://\" & WshNetwork.ComputerName)"
          echo "Set oInfoUser = GetObject(\"WinNT://\" & WshNetwork.ComputerName & \"/Administrator,user\")"
          echo "Set oUser = oMachine.MoveHere(oInfoUser.ADsPath,\"Docker\")"
  } | unix2dos > "$dir/\$OEM\$/admin.vbs"

  {       echo "[COMMANDS]"
          echo "\"REGEDIT /s install.reg\""
          echo "\"Wscript admin.vbs\""
  } | unix2dos > "$dir/\$OEM\$/cmdlines.txt"

  rm -rf "$drivers"
  return 0
}

prepareLegacy() {

  local iso="$1"
  local dir="$2"

  ETFS="boot.img"
  BOOT_MODE="windows_legacy"

  rm -f "$dir/$ETFS"

  local len offset
  len=$(isoinfo -d -i "$iso" | grep "Nsect " | grep -o "[^ ]*$")
  offset=$(isoinfo -d -i "$iso" | grep "Bootoff " | grep -o "[^ ]*$")

  if ! dd "if=$iso" "of=$dir/$ETFS" bs=2048 "count=$len" "skip=$offset" status=none; then
    error "Failed to extract boot image from ISO!" && exit 67
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
  local path src loc index result

  [ ! -s "$asset" ] || [ ! -f "$asset" ] && return 0

  path=$(find "$dir" -maxdepth 1 -type f -iname autounattend.xml | head -n 1)
  [ -n "$path" ] && cp "$asset" "$path"

  src=$(find "$dir" -maxdepth 1 -type d -iname sources | head -n 1)

  if [ ! -d "$src" ]; then
    BOOT_MODE="windows_legacy"
    warn "failed to locate 'sources' folder in ISO image, $FB" && return 1
  fi

  loc=$(find "$src" -maxdepth 1 -type f -iname boot.wim | head -n 1)
  [ ! -f "$loc" ] && loc=$(find "$src" -maxdepth 1 -type f -iname boot.esd | head -n 1)

  if [ ! -f "$loc" ]; then
    BOOT_MODE="windows_legacy"
    warn "failed to locate 'boot.wim' or 'boot.esd' in ISO image, $FB" && return 1
  fi

  info "Adding "$(basename $asset)" for automatic installation..."

  index="1"
  result=$(wimlib-imagex info -xml "$loc" | tr -d '\000')

  if [[ "${result^^}" == *"<IMAGE INDEX=\"2\">"* ]]; then
    index="2"
  fi

  if ! wimlib-imagex update "$loc" "$index" --command "add $asset /autounattend.xml" > /dev/null; then
    warn "failed to add XML to ISO image, $FB" && return 1
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

  if [ -s "$STORAGE/windows.mode" ] && [ -f "$STORAGE/windows.mode" ]; then
    BOOT_MODE=$(<"$STORAGE/windows.mode")
    if [ -s "$STORAGE/windows.old" ] && [ -f "$STORAGE/windows.old" ]; then
      MACHINE=$(<"$STORAGE/windows.old")
    fi
    rm -rf "$TMP"
    return 0
  fi

  # Migrations

  if [ -f "$STORAGE/windows.old" ]; then
    MACHINE=$(<"$STORAGE/windows.old")
    [ -z "$MACHINE" ] && MACHINE="q35"
    BOOT_MODE="windows_legacy"
    echo "$BOOT_MODE" > "$STORAGE/windows.mode"
    rm -rf "$TMP"
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

  rm -rf "$TMP"
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
    rm -f "$ISO"
    exit 61
  fi
fi

if ! extractImage "$ISO" "$DIR"; then
  rm -f "$ISO"
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

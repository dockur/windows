#!/usr/bin/env bash
set -Eeuo pipefail

detectLegacy() {

  local dir="$1"
  local marker

  [[ "${PLATFORM,,}" == "x64" ]] || return 1

  # Legacy media is identified from setup marker files rather than WIM
  # metadata. The order is intentional because several releases share markers.
  marker=$(find "$dir" -maxdepth 1 -type d -iname 'ia64' -print -quit) || return 2

  if [ -n "$marker" ]; then
    error "Windows IA-64 (Itanium) images are not supported by this container!"
    return 2
  fi

  marker=$(find "$dir" -maxdepth 1 -type d -iname WIN95 -print -quit) || return 2

  if [ -n "$marker" ]; then
    DETECTED="win95"
    return 0
  fi

  marker=$(find "$dir" -maxdepth 1 -type d -iname WIN98 -print -quit) || return 2

  if [ -n "$marker" ]; then
    DETECTED="win98"
    return 0
  fi

  marker=$(find "$dir" -maxdepth 1 -type d -iname WIN9X -print -quit) || return 2

  if [ -n "$marker" ]; then
    DETECTED="win9x"
    return 0
  fi

  marker=$(find "$dir" -maxdepth 1 -type f \
    \( \
      -iname CDROM_W.40 -o \
      -iname CDROM_S.40 -o \
      -iname CDROM_TS.40 \
    \) \
    -print -quit) || return 2

  if [ -n "$marker" ]; then
    DETECTED="winnt4"
    return 0
  fi

  marker=$(find "$dir" -maxdepth 1 -type f -iname CDROM_NT.5 -print -quit) || return 2

  if [ -n "$marker" ]; then

    marker=$(find "$dir" -maxdepth 1 -type f \
      \( \
        -iname CDROM_IA.5 -o \
        -iname CDROM_ID.5 -o \
        -iname CDROM_IP.5 -o \
        -iname CDROM_IS.5 \
      \) \
      -print -quit) || return 2

    if [ -n "$marker" ]; then
      DETECTED="win2k"
      return 0
    fi

  fi

  # WIN51 identifies the NT 5.1/5.2 media family; the companion marker then
  # distinguishes XP x86, XP x64, and Server 2003.
  marker=$(find "$dir" -maxdepth 1 -iname WIN51 -print -quit) || return 2
  [ -n "$marker" ] || return 1

  marker=$(find "$dir" -maxdepth 1 -type f -iname WIN51AP -print -quit) || return 2

  if [ -n "$marker" ]; then
    DETECTED="winxpx64"
    return 0
  fi

  marker=$(find "$dir" -maxdepth 1 -type f \
    \( \
      -iname WIN51IC -o \
      -iname WIN51IP -o \
      -iname setupxp.htm \
    \) \
    -print -quit) || return 2

  if [ -n "$marker" ]; then
    DETECTED="winxpx86"
    return 0
  fi

  marker=$(find "$dir" -maxdepth 1 -type f \
    \( \
      -iname WIN51IS -o \
      -iname WIN51IA -o \
      -iname WIN51IB -o \
      -iname WIN51ID -o \
      -iname WIN51IL -o \
      -iname WIN51AA -o \
      -iname WIN51AD -o \
      -iname WIN51AS -o \
      -iname WIN51MA -o \
      -iname WIN51MD -o \
      -iname WIN51MP \
    \) \
    -print -quit) || return 2

  if [ -n "$marker" ]; then
    DETECTED="win2003r2"
    return 0
  fi

  return 1
}

detectReactOS() {

  local dir="$1"
  local marker

  marker=$(find "$dir" -maxdepth 2 -type f \
    \( -ipath '*/reactos/reactos.inf' -o -ipath '*/reactos/unattend.inf' \) -print -quit) || return 2

  [ -n "$marker" ] || return 1

  DETECTED="reactos"
  return 0
}

setMachine() {

  local id="$1"
  local iso="$2"
  local dir="$3"
  local desc="$4"
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

      writeState "old" "pc" || return 1 ;;
      writeState "usb" "N" || return 1
      writeState "net" "pcnet" || return 1
      writeState "type" "auto" || return 1

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

  case "${id,,}" in
    "win9"* | "winnt4" | "reactos" )
      # Do not press enter on boot
      KEYPRESS="N" ;;
  esac

  return 0
}

restoreMachine() {

  # Restore the saved machine only when q35 is still the default;
  # an explicit user-selected machine must remain untouched.
  [[ "${MACHINE,,}" != "q35" ]] && return 0
  [[ "${PLATFORM,,}" != "x64" ]] && return 0

  MACHINE=""
  restoreState "MACHINE" "old" || return 1

  # Migrate existing Win9x installs to QEMU 11
  if [[ "${MACHINE,,}" == "pc-i440fx-2.4" ]]; then
    MACHINE="pc"
    writeState "old" "$MACHINE" || return 1
  fi

  # Migrate existing WinXP installs to QEMU 10
  if [[ "${MACHINE,,}" == "pc-q35-2.10" ]]; then
    MACHINE=""
    rm -f -- "$(stateFile "old")"
  fi

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

extractDrivers() {

  local drivers="$1"

  rm -rf "$drivers" || return 1
  mkdir -p "$drivers" || return 1

  if ! bsdtar -xf /var/drivers.txz -C "$drivers"; then
    error "Failed to extract drivers!"
    return 1
  fi

  return 0
}

copyStorageDriver() {

  local dir="$1"
  local target="$2"
  local driver="$3"
  local arch="$4"
  local drivers="$5"

  local destination="$dir/\$OEM\$/\$1/Drivers/viostor"

  if [ ! -f "$drivers/viostor/$driver/$arch/viostor.sys" ]; then
    error "Failed to locate required storage drivers!"
    return 1
  fi

  cp -L "$drivers/viostor/$driver/$arch/viostor.sys" "$target" || return 1

  mkdir -p "$destination" || return 1
  cp -L "$drivers/viostor/$driver/$arch/viostor.cat" "$destination" || return 1
  cp -L "$drivers/viostor/$driver/$arch/viostor.inf" "$destination" || return 1
  cp -L "$drivers/viostor/$driver/$arch/viostor.sys" "$destination" || return 1

  return 0
}

addNetworkDriver() {

  local dir="$1"
  local driver="$2"
  local arch="$3"
  local drivers="$4"

  local destination="$dir/\$OEM\$/\$1/Drivers/NetKVM"

  if [ ! -f "$drivers/NetKVM/$driver/$arch/netkvm.sys" ]; then
    error "Failed to locate required network drivers!"
    return 1
  fi

  mkdir -p "$destination" || return 1
  cp -L "$drivers/NetKVM/$driver/$arch/netkvm.cat" "$destination" || return 1
  cp -L "$drivers/NetKVM/$driver/$arch/netkvm.inf" "$destination" || return 1
  cp -L "$drivers/NetKVM/$driver/$arch/netkvm.sys" "$destination" || return 1

  return 0
}

addSIFEntry() {

  local file="$1"
  local section="$2"
  local entry="$3"

  local header="[$section]"
  local line ending="lf"

  line=$(grep -Fnx -m 1 "$header" "$file" | cut -d: -f1) || line=""

  if [ -z "$line" ]; then
    line=$(grep -Fnx -m 1 "$header"$'\r' "$file" | cut -d: -f1) || line=""
    ending="crlf"
  fi

  if [ -z "$line" ]; then
    error "Failed to locate section \"$header\" in \"$file\" !"
    return 1
  fi

  local rc=0
  grep -Fqx -e "$entry" -e "$entry"$'\r' "$file" || rc=$?

  if (( rc == 0 )); then
    return 0
  fi

  if (( rc != 1 )); then
    error "Failed to inspect section \"$header\" in \"$file\" !"
    return 1
  fi

  if [[ "$ending" == "crlf" ]]; then
    printf '%s\r\n' "$entry"
  else
    printf '%s\n' "$entry"
  fi | sed -i "${line}r /dev/stdin" "$file" || return 1

  return 0
}

patchStorageDriver() {

  local file="$1"
  local arch="$2"

  # Text-mode setup reads TXTSETUP.SIF before Plug and Play is available, so the
  # VirtIO storage service and hardware IDs must be registered there explicitly.
  addSIFEntry "$file" "SCSI.Load" 'viostor=viostor.sys,4' || return 1
  addSIFEntry "$file" "SourceDisksFiles.$arch" 'viostor.sys=1,,,,,,4_,4,1,,,1,4' || return 1
  addSIFEntry "$file" "SCSI" 'viostor="Red Hat VirtIO SCSI Disk Device"' || return 1
  addSIFEntry "$file" "HardwareIdsDatabase" 'PCI\VEN_1AF4&DEV_1001&SUBSYS_00000000="viostor"' || return 1
  addSIFEntry "$file" "HardwareIdsDatabase" 'PCI\VEN_1AF4&DEV_1001&SUBSYS_00020000="viostor"' || return 1
  addSIFEntry "$file" "HardwareIdsDatabase" 'PCI\VEN_1AF4&DEV_1001&SUBSYS_00021AF4="viostor"' || return 1

  return 0
}

addSataDriver() {

  local dir="$1"
  local target="$2"
  local arch="$3"
  local drivers="$4"
  local file="$5"

  local destination="$dir/\$OEM\$/\$1/Drivers/sata"

  if [ ! -d "$drivers/sata/xp/$arch" ]; then
    error "Failed to locate required SATA drivers!"
    return 1
  fi

  mkdir -p "$destination" || return 1
  cp -Lr "$drivers/sata/xp/$arch/." "$destination" || return 1
  cp -Lr "$drivers/sata/xp/$arch/." "$target" || return 1

  addSIFEntry "$file" "SCSI.Load" 'iaStor=iaStor.sys,4' || return 1
  addSIFEntry "$file" "FileFlags" 'iaStor.sys = 16' || return 1
  addSIFEntry "$file" "SourceDisksFiles.$arch" 'iaStor.cat = 1,,,,,,,1,0,0' || return 1
  addSIFEntry "$file" "SourceDisksFiles.$arch" 'iaStor.inf = 1,,,,,,,1,0,0' || return 1
  addSIFEntry "$file" "SourceDisksFiles.$arch" 'iaStor.sys = 1,,,,,,4_,4,1,,,1,4' || return 1
  addSIFEntry "$file" "SourceDisksFiles.$arch" 'iaStor.sys = 1,,,,,,,1,0,0' || return 1
  addSIFEntry "$file" "SourceDisksFiles.$arch" 'iaahci.cat = 1,,,,,,,1,0,0' || return 1
  addSIFEntry "$file" "SourceDisksFiles.$arch" 'iaAHCI.inf = 1,,,,,,,1,0,0' || return 1
  addSIFEntry "$file" "SCSI" 'iaStor="Intel(R) SATA RAID/AHCI Controller"' || return 1
  addSIFEntry "$file" "HardwareIdsDatabase" 'PCI\VEN_8086&DEV_2922&CC_0106="iaStor"' || return 1

  return 0
}

addLegacyDrivers() {

  local dir="$1"
  local target="$2"
  local driver="$3"
  local arch="$4"
  local drivers="$5"

  local msg="Adding drivers to image..."
  info "$msg" && html "$msg"

  extractDrivers "$drivers" || return 1
  copyStorageDriver "$dir" "$target" "$driver" "$arch" "$drivers" || return 1
  addNetworkDriver "$dir" "$driver" "$arch" "$drivers" || return 1

  local file
  file=$(find "$target" -maxdepth 1 -type f -iname TXTSETUP.SIF -print -quit) || return 1

  if [ -z "$file" ]; then
    error "The file TXTSETUP.SIF could not be found!"
    return 1
  fi

  patchStorageDriver "$file" "$arch" || return 1
  addSataDriver "$dir" "$target" "$arch" "$drivers" "$file" || return 1

  if ! rm -rf "$drivers"; then
    warn "failed to clean temporary driver files!"
  fi

  return 0
}

setLegacyKey() {

  local target="$1"
  local driver="$2"
  local arch="$3"
  local desc="$4"

  local setup pid file block
  setup=$(find "$target" -maxdepth 1 -type f -iname setupp.ini -print -quit) || return 1

  [[ -n "$setup" ]] || return 0
  [[ -z "$KEY" ]] || return 0

  pid=$(<"$setup") || return 1
  pid="${pid%$'\r'}"

  if [[ "$driver" == "2k" ]]; then
    [ "${#pid}" -ge 3 ] || return 0
    echo "${pid::-3}270" > "$setup" || :
    return 0
  fi

  if [[ "$pid" == *"270" ]]; then
    warn "this version of $desc requires a volume license key (VLK), it will ask for one during installation."
    return 0
  fi

  file=$(find "$target" -maxdepth 1 -type f -iname PID.INF -print -quit) || return 1

  if [[ -n "$file" ]]; then

    local key=""

    # Prefer a staging or OEM key already shipped on the media before falling
    # back to Microsoft's documented generic installation keys.
    if [[ "$driver" == "2k3" ]]; then

      block=$(grep -i -A 2 "StagingKey" "$file") || block=""

      if [ -n "$block" ]; then
        key=$(printf '%s\n' "$block" | tail -n 2 | head -n 1) || key=""
      fi

    else

      key="${pid: -8:5}"

      if [[ "${pid^^}" == *"OEM" ]]; then

        block=$(grep -i -A 2 "$key" "$file") || block=""

      else

        block=$(grep -i -m 1 -A 2 "$key" "$file") || block=""

      fi

      if [ -n "$block" ]; then
        key=$(printf '%s\n' "$block" | tail -n 2 | head -n 1) || key=""
      fi

      key="${key#*= }"

    fi

    if [ -n "$key" ]; then
      key="${key%$'\r'}"
      [[ "${#key}" == "29" ]] && KEY="$key"
    fi

  fi

  [[ -n "$KEY" ]] && return 0

  # These are NOT pirated keys, they come from official MS documentation.

  case "${driver,,}" in
    "xp" )

      if [[ "${arch,,}" == "x86" ]]; then
        # Windows XP Professional x86 generic trial key (no activation)
        KEY="DR8GV-C8V6J-BYXHG-7PYJR-DB66Y"
      else
        # Windows XP Professional x64 generic trial key (no activation)
        KEY="B2RBK-7KPT9-4JP6X-QQFWM-PJD6G"
      fi ;;

    "2k3" )

      if [[ "${arch,,}" == "x86" ]]; then
        # Windows Server 2003 Standard x86 generic trial key (no activation)
        KEY="QKDCQ-TP2JM-G4MDG-VR6F2-P9C48"
      else
        # Windows Server 2003 Standard x64 generic trial key (no activation)
        KEY="P4WJG-WK3W7-3HM8W-RWHCK-8JTRY"
      fi ;;

  esac

  if [ "${#pid}" -ge 3 ]; then
    echo "${pid::-3}000" > "$setup" || :
  fi

  return 0
}

writeCommand() {

  local install="$1"

  [ -f "$install" ] || return 0

  if enabled "${LOG:-}"; then
    printf '%s' "\"Script\"=\"cmd /C start \\\"Install\\\" cmd.exe /D /C \\\"\\\"C:\\\\OEM\\\\install.bat\\\" > \\\"C:\\\\OEM\\\\install.log\\\" 2>&1\\\"\""
  else
    printf '%s' "\"Script\"=\"cmd /C start \\\"Install\\\" cmd.exe /D /C \\\"\\\"C:\\\\OEM\\\\install.bat\\\"\\\"\""
  fi

  return 0
}

writeSIF() {

  local target="$1"
  local driver="$2"
  local product="$3"
  local sifHost="$4"
  local sifUsername="$5"
  local sifPassword="$6"
  local sifOrganization="$7"
  local sifWorkgroup="$8"

  find "$target" -maxdepth 1 -type f -iname winnt.sif -delete || return 1

  {
    printf '%s\n' \
      '[Data]' \
      '    AutoPartition=1' \
      '    MsDosInitiated="0"' \
      '    UnattendedInstall="Yes"' \
      '    AutomaticUpdates="Yes"' \
      '' \
      '[Unattended]' \
      '    UnattendSwitch=Yes' \
      '    UnattendMode=FullUnattended' \
      '    OemSkipEula=Yes' \
      '    OemPreinstall=Yes' \
      '    Repartition=Yes' \
      '    WaitForReboot="No"' \
      '    DriverSigningPolicy="Ignore"' \
      '    NonDriverSigningPolicy="Ignore"' \
      '    OemPnPDriversPath="Drivers\viostor;Drivers\NetKVM;Drivers\sata"' \
      '    NoWaitAfterTextMode=1' \
      '    NoWaitAfterGUIMode=1' \
      '    FileSystem=ConvertNTFS' \
      '    ExtendOemPartition=0' \
      '    Hibernation="No"' \
      '' \
      '[GuiUnattended]' \
      '    OEMSkipRegional=1' '    OemSkipWelcome=1' "    AdminPassword=\"$sifPassword\"" '    TimeZone=0'

    if disabled "$AUTOLOGIN"; then
      printf '%s\n' '    AutoLogon=No'
    else
      printf '%s\n' \
        '    AutoLogon=Yes' '    AutoLogonCount=65432'
    fi

    printf '%s\n' \
      '' \
      '[UserData]' \
      "    FullName=\"$sifUsername\"" \
      "    ComputerName=\"$sifHost\"" \
      "    OrgName=\"$sifOrganization\"" \
      "    $product" \
      '' \
      '[Identification]' \
      "    JoinWorkgroup = \"$sifWorkgroup\"" \
      '' \
      '[Display]' \
      '    BitsPerPel=32' \
      "    XResolution=$WIDTH" \
      "    YResolution=$HEIGHT" \
      '' \
      '[Networking]' \
      '    InstallDefaultComponents=Yes' \
      '' \
      '[Branding]' \
      '    BrandIEUsingUnattended=Yes' \
      '' \
      '[URL]' \
      '    Home_Page = http://www.google.com' \
      '    Search_Page = http://www.google.com' '' '[TerminalServices]' '    AllowConnections=1' ''
  } | unix2dos > "$target/WINNT.SIF" || return 1

  if [[ "$driver" == "2k3" ]]; then
    {
      printf '%s\n' \
        '[Components]' \
        '    TerminalServer=On' '' '[LicenseFilePrintData]' '    AutoMode=PerServer' '    AutoUsers=5' ''
    } | unix2dos >> "$target/WINNT.SIF" || return 1
  fi

  return 0
}

writeRegistry() {

  local dir="$1"
  local shortcut="$2"
  local oem="$3"
  local regUsername="$4"
  local regPassword="$5"

  {
    printf '%s\n' \
      'Windows Registry Editor Version 5.00' \
      '' \
      '[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Security]' \
      '"FirstRunDisabled"=dword:00000001' \
      '"UpdatesDisableNotify"=dword:00000001' \
      '"FirewallDisableNotify"=dword:00000001' \
      '"AntiVirusDisableNotify"=dword:00000001' \
      '' \
      '[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\wscsvc]' \
      '"Start"=dword:00000004' \
      '' \
      '[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\StandardProfile\GloballyOpenPorts\List]' \
      '"3389:TCP"="3389:TCP:*:Enabled:@xpsp2res.dll,-22009"' \
      '' \
      '[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Applets\Tour]' \
      '"RunCount"=dword:00000000' \
      '' \
      '[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced]' \
      '"HideFileExt"=dword:00000000' \
      '' \
      '[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer]' \
      '"NoWelcomeScreen"="1"' \
      '' \
      '[HKEY_CURRENT_USER\Software\Microsoft\Internet Connection Wizard]' \
      '"Completed"="1"' \
      '"Desktopchanged"="1"' '' '[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon]'

    if disabled "$AUTOLOGIN"; then
      printf '%s\n' '"AutoAdminLogon"="0"'
    else
      printf '%s\n' \
        '"AutoAdminLogon"="1"' "\"DefaultUserName\"=\"$regUsername\"" "\"DefaultPassword\"=\"$regPassword\""
    fi

    printf '%s\n' \
      '' \
      '[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Video\{23A77BF7-ED96-40EC-AF06-9B1F4867732A}\0000]' \
      '"DefaultSettings.BitsPerPel"=dword:00000020' \
      "\"DefaultSettings.XResolution\"=dword:$XHEX" \
      "\"DefaultSettings.YResolution\"=dword:$YHEX" \
      '' \
      '[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Hardware Profiles\Current\System\CurrentControlSet\Control\VIDEO\{23A77BF7-ED96-40EC-AF06-9B1F4867732A}\0000]' \
      '"DefaultSettings.BitsPerPel"=dword:00000020' \
      "\"DefaultSettings.XResolution\"=dword:$XHEX" \
      "\"DefaultSettings.YResolution\"=dword:$YHEX" \
      '' \
      '[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\RunOnce]' \
      '"ScreenSaver"="reg add \"HKCU\\Control Panel\\Desktop\" /f /v \"SCRNSAVE.EXE\" /t REG_SZ /d \"off\""' \
      '"ScreenSaverOff"="reg add \"HKCU\\Control Panel\\Desktop\" /f /v \"ScreenSaveActive\" /t REG_SZ /d \"0\""'

    if enabled "$shortcut"; then
      printf '%s\n' '"SharedDrive"="cmd /C net use Z: \\\\host.lan\\Data /persistent:yes"'
    fi

    printf '%s\n' "$oem" ''
  } | unix2dos > "$dir/\$OEM\$/install.reg" || return 1

  return 0
}

appendRegistry() {

  local dir="$1"
  local driver="$2"

  if [[ "$driver" == "2k" ]]; then
    {
      printf '%s\n' \
        '[HKEY_USERS\.DEFAULT\Software\Microsoft\Windows\CurrentVersion\Runonce]' '"^SetupICWDesktop"=-' ''
    } | unix2dos >> "$dir/\$OEM\$/install.reg" || return 1
  fi

  if [[ "$driver" == "2k3" ]]; then
    {
      printf '%s\n' \
        '[HKEY_CURRENT_USER\Software\Microsoft\Windows NT\CurrentVersion\srvWiz]' \
        '@=dword:00000000' \
        '' \
        '[HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\ServerOOBE\SecurityOOBE]' \
        '"DontLaunchSecurityOOBE"=dword:00000000' ''
    } | unix2dos >> "$dir/\$OEM\$/install.reg" || return 1
  fi

  return 0
}

writeVBS() {

  local dir="$1"
  local username="$2"
  local shortcut="$3"

  # Locate the built-in Administrator by its RID 500 SID rather than its
  # localized display name, then rename that account to the requested username.

  {
    printf '%s\n' \
      'Set WshShell = WScript.CreateObject("WScript.Shell")' \
      'Set WshNetwork = WScript.CreateObject("WScript.Network")' \
      'Set Domain = GetObject("WinNT://" & WshNetwork.ComputerName)' \
      '' \
      'Function DecodeSID(binSID)' \
      '  ReDim o(LenB(binSID))' \
      '' \
      '  For i = 1 To LenB(binSID)' \
      '    o(i-1) = AscB(MidB(binSID, i, 1))' \
      '  Next' \
      '' \
      '  sid = "S-" & CStr(o(0)) & "-" & OctetArrayToString _' \
      '        (Array(o(2), o(3), o(4), o(5), o(6), o(7)))' \
      '  For i = 8 To (4 * o(1) + 4) Step 4' \
      '    sid = sid & "-" & OctetArrayToString _' \
      '          (Array(o(i+3), o(i+2), o(i+1), o(i)))' \
      '  Next' \
      '' \
      '  DecodeSID = sid' \
      'End Function' \
      '' \
      'Function OctetArrayToString(arr)' \
      '  v = 0' \
      '  For i = 0 To UBound(arr)' \
      '    v = v * 256 + arr(i)' \
      '  Next' \
      '' \
      '  OctetArrayToString = CStr(v)' \
      'End Function' \
      '' \
      'For Each DomainItem in Domain' \
      '  If DomainItem.Class = "User" Then' \
      '    sid = DecodeSID(DomainItem.Get("objectSID"))' \
      '    If Left(sid, 9) = "S-1-5-21-" And Right(sid, 4) = "-500" Then' \
      '      LocalAdminADsPath = DomainItem.ADsPath' \
      '      Exit For' \
      '    End If' '  End If' 'Next' '' "Call Domain.MoveHere(LocalAdminADsPath, \"$username\")" ''

    if enabled "$shortcut"; then
      printf '%s\n' \
        'Set oLink = WshShell.CreateShortcut(WshShell.SpecialFolders("Desktop") & "\Shared.lnk")' \
        'With oLink' '  .TargetPath = "\\host.lan\Data"' '  .Save' 'End With' 'Set oLink = Nothing' ''
    fi
  } | unix2dos > "$dir/\$OEM\$/install.vbs" || return 1

  {
    printf '%s\n' \
      '[COMMANDS]' '"REGEDIT /s install.reg"' '"Wscript install.vbs"' ''
  } | unix2dos > "$dir/\$OEM\$/cmdlines.txt" || return 1

  return 0
}

disableAutoReboot() {

  local target="$1"

  local file rc=0
  local pattern='^[[:space:]]*HKLM[[:space:]]*,[[:space:]]*"SYSTEM\\CurrentControlSet\\Control\\CrashControl"[[:space:]]*,[[:space:]]*"AutoReboot"[[:space:]]*,[[:space:]]*[^,]*,'

  file=$(find "$target" -maxdepth 1 -type f -iname HIVESYS.INF -print -quit) || return 1

  if [ -z "$file" ]; then
    error "The file HIVESYS.INF could not be found!"
    return 1
  fi

  # Keep setup crashes visible instead of immediately rebooting into an
  # opaque installation loop.
  grep -Eqi "${pattern}[[:space:]]*[^,;[:space:]]+" "$file" || rc=$?

  case "$rc" in
    0 )
      sed -i -E "s|(${pattern})[[:space:]]*[^,;[:space:]]+|\\1 0|I" "$file" || :
      ;;
    1 )
      printf '%s\n' \
        'HKLM,"SYSTEM\CurrentControlSet\Control\CrashControl","AutoReboot",0x00010001,0' |
        unix2dos >> "$file" || :
      ;;
  esac

  return 0
}

legacyInstall() {

  local dir="$2"
  local desc="$3"
  local driver="$4"

  local shortcut="Y"
  local drivers="/tmp/drivers"

  if disabled "$SHORTCUT" || disabled "${SAMBA:-Y}"; then
    shortcut="N"
  fi

  if [ -n "$DOMAIN" ]; then
    error "The DOMAIN variable is not supported for $desc!"
    return 1
  fi

  ETFS="[BOOT]/Boot-NoEmul.img"

  if [ ! -f "$dir/$ETFS" ] || [ ! -s "$dir/$ETFS" ]; then
    error "Failed to locate file \"$ETFS\" in $desc ISO image!"
    return 1
  fi

  # Legacy media uses directory names rather than metadata to identify the
  # architecture and the text-mode setup source tree.
  local arch="amd64"
  [ ! -d "$dir/AMD64" ] && arch="x86"

  local target="$dir/AMD64"
  [[ "${arch,,}" == "x86" ]] && target="$dir/I386"

  if [ ! -d "$target" ]; then
    error "Failed to locate directory \"$target\" in $desc ISO image!"
    return 1
  fi

  if [[ "${driver,,}" == "xp" || "${driver,,}" == "2k3" ]]; then
    addLegacyDrivers "$dir" "$target" "$driver" "$arch" "$drivers" || return 1
  fi

  disableAutoReboot "$target" || return 1
  setLegacyKey "$target" "$driver" "$arch" "$desc" || return 1
  validateProductKey "$KEY" || return 1

  local product=""
  [ -n "$KEY" ] && product="ProductID=$KEY"

  mkdir -p "$dir/\$OEM\$" || return 1

  if ! addFolder "$dir"; then
    error "Failed to add OEM folder to image!"
    return 1
  fi

  local oem=""
  local install=""
  local oem_dir="$dir/\$OEM\$/\$1/OEM"

  if [ -d "$oem_dir" ]; then
    install=$(find \
      "$oem_dir" -maxdepth 1 -type f -iname install.bat -print -quit
    ) || return 1
  fi

  oem=$(writeCommand "$install") || return 1

  [ -z "$WIDTH" ] && WIDTH="1280"
  [ -z "$HEIGHT" ] && HEIGHT="720"

  validateResolution "WIDTH" "$WIDTH" 320 || return 1
  validateResolution "HEIGHT" "$HEIGHT" 200 || return 1
  validateMembership || return 1
  validateComputerName "$HOST" || return 1

  validateLegacyText "APP" "$APP" "$desc" || return 1
  validateLegacyText "ENGINE" "$ENGINE" "$desc" || return 1

  if [[ "$driver" == "2k" ]]; then
    validateLegacyEncoding "APP" "$APP" "$desc" || return 1
    validateLegacyEncoding "ENGINE" "$ENGINE" "$desc" || return 1
  fi

  XHEX=$(printf '%08x\n' "$((10#$WIDTH))") || return 1
  YHEX=$(printf '%08x\n' "$((10#$HEIGHT))") || return 1

  local username="${USERNAME:-Docker}"
  local password="${PASSWORD:-admin}"
  local workgroup="${WORKGROUP:-WORKGROUP}"

  local sifHost sifUsername sifPassword sifOrganization sifWorkgroup
  local regUsername regPassword

  validateLegacyUsername "$username" "$desc" || return 1
  validatePassword "$password" "$desc" || return 1

  if [[ "$driver" == "2k" ]]; then
    validateLegacyEncoding "USERNAME" "$username" "$desc" || return 1
    validateLegacyEncoding "PASSWORD" "$password" "$desc" || return 1
    validateLegacyEncoding "WORKGROUP" "$workgroup" "$desc" || return 1
  fi

  # WINNT.SIF and .reg files use different escaping rules, so prepare their
  # values independently before generating either file.
  sifHost=$(escapeSIFValue "${HOST:-*}") || return 1
  sifUsername=$(escapeSIFValue "$username") || return 1
  sifPassword=$(escapeSIFValue "$password") || return 1
  sifOrganization=$(escapeSIFValue "$APP for $ENGINE") || return 1
  sifWorkgroup=$(escapeSIFValue "$workgroup") || return 1
  regUsername=$(escapeRegistryValue "$username") || return 1
  regPassword=$(escapeRegistryValue "$password") || return 1

  writeSIF \
    "$target" \
    "$driver" \
    "$product" "$sifHost" "$sifUsername" "$sifPassword" "$sifOrganization" "$sifWorkgroup" || return 1

  writeRegistry "$dir" "$shortcut" "$oem" "$regUsername" "$regPassword" || return 1

  appendRegistry "$dir" "$driver" || return 1
  writeVBS "$dir" "$username" "$shortcut" || return 1

  return 0
}

escapeSIFValue() {

  local s="$1"

  s=${s//%/%%}
  s=${s//\"/\"\"}

  printf '%s' "$s"
  return 0
}

escapeRegistryValue() {

  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

validateLegacyText() {

  local name="$1"
  local value="$2"
  local desc="${3:-}"

  local suffix=""
  [ -n "$desc" ] && suffix=" for $desc"

  if [[ "$value" =~ [[:cntrl:]] ]]; then
    error "The $name variable cannot contain control characters$suffix!"
    return 1
  fi

  if [[ "$value" == *'"'* ]]; then
    error "The $name variable cannot contain double quotes$suffix!"
    return 1
  fi

  return 0
}

validateLegacyUsername() {

  local value="$1"
  local desc="${2:-}"

  local suffix=""
  [ -n "$desc" ] && suffix=" for $desc"

  if [ -z "$value" ]; then
    error "The USERNAME variable cannot be empty$suffix!"
    return 1
  fi

  if [ "${#value}" -gt 20 ]; then
    error "The USERNAME variable cannot contain more than 20 characters$suffix!"
    return 1
  fi

  if [[ "$value" =~ [[:cntrl:]] ]]; then
    error "The USERNAME variable cannot contain control characters$suffix!"
    return 1
  fi

  case "$value" in
    *'"'* | *'/'* | *\\* | *'['* | *']'* | *':'* | *';'* | *'|'* | *'='* | \
    *','* | *'+'* | *'*'* | *'?'* | *'<'* | *'>'* | *'%'* )
      error "The USERNAME variable contains unsupported characters$suffix!"
      return 1 ;;
  esac

  if [[ "$value" == *"." ]]; then
    error "The USERNAME variable cannot end with a period$suffix!"
    return 1
  fi

  if [[ "$value" =~ ^[.[:space:]]+$ ]]; then
    error "The USERNAME variable cannot consist only of spaces or periods$suffix!"
    return 1
  fi

  case "${value^^}" in

    "NONE" )
      error "The USERNAME value \"NONE\" is reserved by Windows$suffix!"
      return 1 ;;

    "ADMINISTRATOR" | "GUEST" | "DEFAULTACCOUNT" | "WDAGUTILITYACCOUNT" | "WSIACCOUNT" )
      error "The USERNAME value \"$value\" is reserved for a built-in Windows account$suffix!"
      return 1 ;;

  esac

  return 0
}

validateLegacyEncoding() {

  local name="$1"
  local value="$2"
  local desc="${3:-}"

  local suffix=""
  [ -n "$desc" ] && suffix=" for $desc"

  if LC_ALL=C grep -q '[^ -~]' <<< "$value"; then
    error "The $name variable may only contain printable ASCII characters$suffix!"
    return 1
  fi

  return 0
}

return 0

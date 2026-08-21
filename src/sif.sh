#!/usr/bin/env bash
set -Eeuo pipefail

SIFInstall() {

  local dir="$2"
  local desc="$3"
  local driver="$4"

  local shortcut="Y"
  local drivers="/tmp/drivers"

  local msg="Preparing $desc installation..."
  info "$msg" && html "$msg"

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

  case "${driver,,}" in

    "2k" )
      # Windows 2000 keeps its existing storage/network path, but still needs
      # the QBochs display package staged for Plug and Play setup.
      extractDrivers "$drivers" || return 1

      if ! addDisplayDriver "$dir" "$driver" "$arch" "$drivers"; then
        rm -rf "$drivers" || :
        return 1
      fi

      if ! rm -rf "$drivers"; then
        warn "failed to clean temporary driver files!"
      fi ;;

    "xp" )

      addLegacyDrivers "$dir" "$target" "$driver" "$arch" "$drivers" || return 1 ;;

    "2k3" )

      if [[ "${arch,,}" == "x86" ]]; then
        error "The 32-bit version of $desc is not supported!" && return 1
      fi
  
      addLegacyDrivers "$dir" "$target" "$driver" "$arch" "$drivers" || return 1 ;;
  
  esac

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

  [ -z "$WIDTH" ] && WIDTH="1024"
  [ -z "$HEIGHT" ] && HEIGHT="768"

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
  local culture region keyboard timezone
  local localeID inputLocaleID keyboardID

  culture=$(getLanguage "$LANGUAGE" "culture") || return 1
  [ -z "$culture" ] && culture="en-US"
  region="${REGION:-$culture}"
  keyboard="${KEYBOARD:-en-US}"
  localeID=$(getLocaleID "$region") || return 1
  inputLocaleID=$(getInputLocaleID "$keyboard") || return 1
  keyboardID=$(getKeyboardID "$keyboard") || return 1
  timezone=$(getTimeZone "$region" "nt5") || return 1

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
    "$product" "$sifHost" "$sifUsername" "$sifPassword" "$sifOrganization" "$sifWorkgroup" \
    "$localeID" "$inputLocaleID" "$keyboardID" "$timezone" || return 1

  writeRegistry "$dir" "$shortcut" "$oem" "$regUsername" "$regPassword" || return 1

  appendRegistry "$dir" "$driver" || return 1
  writeVBS "$dir" "$username" "$shortcut" "$driver" || return 1

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
  addQXLDriver "$dir" "$driver" "$arch" "$drivers" || return 1
  addDisplayDriver "$dir" "$driver" "$arch" "$drivers" || return 1
  addDisplayTrust "$target" "$driver" "$arch" "$drivers" || return 1
  addBalloonDriver "$dir" "$driver" "$arch" "$drivers" || return 1

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

addQXLDriver() {

  local dir="$1"
  local driver="$2"
  local arch="$3"
  local drivers="$4"

  local source="$drivers/qxl/$driver/$arch"
  local destination="$dir/\$OEM\$/\$1/Drivers/QXL"

  # The legacy QXL package is named for XP but its x86 INF targets XP and
  # later NT x86 releases, so it is also suitable to keep around for 2003 x86.
  if [ ! -d "$source" ] && [[ "${arch,,}" == "x86" ]]; then
    source="$drivers/qxl/xp/x86"
  fi

  [ -d "$source" ] || return 0

  local file

  for file in qxl.cat qxl.inf qxl.sys qxldd.dll; do

    if [ ! -f "$source/$file" ]; then
      error "Failed to locate required QXL display driver file: $file"
      return 1
    fi

  done

  mkdir -p "$destination" || return 1
  cp -Lr "$source/." "$destination" || return 1

  return 0
}

addDisplayDriver() {

  local dir="$1"
  local driver="$2"
  local arch="$3"
  local drivers="$4"

  local qbochs_arch="$arch"
  [[ "${qbochs_arch,,}" == "amd64" ]] && qbochs_arch="x64"

  local source="$drivers/qbochs/$driver/$qbochs_arch"
  local destination="$dir/\$OEM\$/\$1/Drivers/QBochs"

  if [ ! -d "$source" ]; then
    error "Failed to locate required QBochs display driver directory: $source"
    return 1
  fi

  local files="qbochs.inf qbochs.sys"
  [[ "$driver" == "2k3" ]] && files+=" qbochs.cat"

  local file

  for file in $files; do

    if [ ! -f "$source/$file" ]; then
      error "Failed to locate required QBochs display driver file: $file"
      return 1
    fi

  done

  mkdir -p "$destination" || return 1

  for file in $files; do
    cp -L "$source/$file" "$destination/$file" || return 1
  done

  return 0
}

addDisplayTrust() {

  local target="$1"
  local driver="$2"
  local arch="$3"
  local drivers="$4"

  [[ "$driver" == "2k3" ]] || return 0

  local qbochs_arch="$arch"
  [[ "${qbochs_arch,,}" == "amd64" ]] && qbochs_arch="x64"

  local cat="$drivers/qbochs/$driver/$qbochs_arch/qbochs.cat"

  if [ ! -s "$cat" ]; then
    error "Failed to locate required QBochs catalog: $cat"
    return 1
  fi

  local hive
  hive=$(find "$target" -maxdepth 1 -type f -iname HIVESFT.INF -print -quit) || return 1

  if [ -z "$hive" ]; then
    error "The file HIVESFT.INF could not be found!"
    return 1
  fi

  local temp
  temp=$(mktemp -d) || return 1

  local pem="$temp/qbochs.pem"
  local der="$temp/qbochs.der"

  # Windows catalog files are PKCS#7 SignedData. Extract the certificate
  # embedded by SignTool; this is the certificate SetupAPI verifies.
  if ! openssl pkcs7 -inform DER -in "$cat" -print_certs -out "$pem"; then
    rm -rf "$temp" || :
    error "Failed to read the QBochs catalog certificate!"
    return 1
  fi

  local count
  count=$(grep -c '^-----BEGIN CERTIFICATE-----$' "$pem") || count=0

  if (( count != 1 )); then
    rm -rf "$temp" || :
    error "The QBochs catalog does not contain exactly one certificate!"
    return 1
  fi

  if ! openssl x509 -in "$pem" -outform DER -out "$der" 2>/dev/null; then
    rm -rf "$temp" || :
    error "Failed to extract the QBochs catalog certificate!"
    return 1
  fi

  local thumbprint
  thumbprint=$(openssl x509 -in "$pem" -sha1 -fingerprint -noout |
    sed -E 's/^[^=]*=//; s/://g') || {
      rm -rf "$temp" || :
      return 1
    }
  thumbprint="${thumbprint^^}"

  if [[ ! "$thumbprint" =~ ^[0-9A-F]{40}$ ]]; then
    rm -rf "$temp" || :
    error "Failed to determine the QBochs certificate thumbprint!"
    return 1
  fi

  local size
  size=$(stat -c '%s' "$der") || {
    rm -rf "$temp" || :
    return 1
  }

  if (( size <= 0 )); then
    rm -rf "$temp" || :
    error "The QBochs certificate is empty!"
    return 1
  fi

  # A Windows serialized certificate element is three little-endian DWORDs:
  # FILE_ELEMENT_CERT_TYPE (0x20), X509_ASN_ENCODING (1), DER length,
  # followed by the DER certificate itself.
  local header
  printf -v header '20,00,00,00,01,00,00,00,%02X,%02X,%02X,%02X' \
    $(( size & 0xFF )) \
    $(( (size >> 8) & 0xFF )) \
    $(( (size >> 16) & 0xFF )) \
    $(( (size >> 24) & 0xFF ))

  local body
  body=$(od -An -v -tx1 "$der" |
    awk 'BEGIN { sep="" }
         { for (i = 1; i <= NF; i++) { printf "%s%s", sep, toupper($i); sep="," } }
         END { print "" }') || {
      rm -rf "$temp" || :
      return 1
    }

  rm -rf "$temp" || return 1

  if [ -z "$body" ]; then
    error "Failed to encode the QBochs certificate!"
    return 1
  fi

  local blob="$header,$body"
  local store='SOFTWARE\Microsoft\SystemCertificates'

  addSIFEntry "$hive" "AddReg" \
    "HKLM,\"$store\\Root\\Certificates\\$thumbprint\",\"Blob\",0x00000001,$blob" || return 1
  addSIFEntry "$hive" "AddReg" \
    "HKLM,\"$store\\TrustedPublisher\\Certificates\\$thumbprint\",\"Blob\",0x00000001,$blob" || return 1

  return 0
}

addBalloonDriver() {

  local dir="$1"
  local driver="$2"
  local arch="$3"
  local drivers="$4"

  local source="$drivers/Balloon/$driver/$arch"
  local destination="$dir/\$OEM\$/\$1/Drivers/Balloon"

  local file

  for file in balloon.cat balloon.inf balloon.sys blnsvr.exe; do

    if [ ! -f "$source/$file" ]; then
      error "Failed to locate required Balloon driver file: $file"
      return 1
    fi

  done

  mkdir -p "$destination" || return 1
  cp -Lr "$source/." "$destination" || return 1

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
  local localeID="$9"
  local inputLocaleID="${10}"
  local keyboardID="${11}"
  local timezone="${12}"

  find "$target" -maxdepth 1 -type f -iname winnt.sif -delete || return 1

  {
    printf '%s\n' \
      '[Data]' \
      '    AutoPartition=1' \
      '    MsDosInitiated="0"' \
      '    UnattendedInstall="Yes"' \
      '    AutomaticUpdates="No"' \
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
      '    OemPnPDriversPath="Drivers\viostor;Drivers\NetKVM;Drivers\sata;Drivers\QXL;Drivers\QBochs;Drivers\Balloon"' \
      '    NoWaitAfterTextMode=1' \
      '    NoWaitAfterGUIMode=1' \
      '    FileSystem=ConvertNTFS' \
      '    ExtendOemPartition=0' \
      '    Hibernation="No"' \
      '' \
      '[GuiUnattended]' \
      '    OEMSkipRegional=1' \
      '    OemSkipWelcome=1' \
      "    AdminPassword=\"$sifPassword\"" \
      "    TimeZone=$timezone"

    if disabled "$AUTOLOGIN"; then
      printf '%s\n' \
        '    AutoLogon=No'
    else
      printf '%s\n' \
        '    AutoLogon=Yes' \
        '    AutoLogonCount=65432'
    fi

    printf '%s\n' \
      '' \
      '[RegionalSettings]' \
      "    InputLocale=$inputLocaleID:$keyboardID" \
      "    SystemLocale=$localeID" \
      "    UserLocale=$localeID" \
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
      '    Search_Page = http://www.google.com' \
      '' \
      '[TerminalServices]' \
      '    AllowConnections=1' \
      '    NoHelpPopup=1' \
      ''
  } | unix2dos > "$target/WINNT.SIF" || return 1

  if [[ "$driver" == "2k3" ]]; then
    {
      printf '%s\n' \
        '[Components]' \
        '    TerminalServer=On' \
        '' \
        '[LicenseFilePrintData]' \
        '    AutoMode=PerServer' \
        '    AutoUsers=5' \
        ''
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
      '[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\NetworkProvider]' \
      '"RestoreConnection"=dword:00000000' \
      '' \
      '[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU]' \
      '"NoAutoUpdate"=dword:00000001' \
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

    if enabled "$shortcut"; then
      printf '%s\n' \
        '' \
        '[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Session Manager\DOS Devices]' \
        '"Z:"="\\Device\\LanmanRedirector\\;Z:00000000000003e7\\host.lan\\Data"' \
        ''
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
      '[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\RunOnce]'

    printf '%s\n' "$oem" ''
  } | unix2dos > "$dir/\$OEM\$/install.reg" || return 1

  return 0
}

appendRegistry() {

  local dir="$1"
  local driver="$2"

  if [[ "$driver" == "2k" || "$driver" == "xp" || "$driver" == "2k3" ]]; then
    {
      printf '%s\n' \
        '[HKEY_CURRENT_USER\Control Panel\Desktop]' \
        '"SCRNSAVE.EXE"="off"' \
        '"ScreenSaveActive"="0"' \
        '"DragFullWindows"="1"' \
        '"MenuShowDelay"="100"' \
        '' \
        '[HKEY_CURRENT_USER\Control Panel\Desktop\WindowMetrics]' \
        '"MinAnimate"="0"' \
        '' \
        '[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer]' \
        '"link"=hex:00,00,00,00' ''
    } | unix2dos >> "$dir/\$OEM\$/install.reg" || return 1
  fi

  if [[ "$driver" == "xp" || "$driver" == "2k3" ]]; then
    {
      printf '%s\n' \
        '[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\RunOnce]' \
        '"PowerPolicy"="Wscript.exe C:\\OEM\\NT5POWER.VBS"' ''
    } | unix2dos >> "$dir/\$OEM\$/install.reg" || return 1
  fi

  if [[ "$driver" == "2k" ]]; then
    {
      printf '%s\n' \
        '[HKEY_CURRENT_USER\Control Panel\PowerCfg]' \
        '"CurrentPowerPolicy"="3"' \
        '' \
        '[HKEY_CURRENT_USER\Control Panel\PowerCfg\PowerPolicies\3]' \
        '"Policies"=hex:01,00,00,00,00,00,00,00,01,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,32,32,00,00,04,00,00,00,04,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,01,64,64,64,64,00,00' \
        '' \
        '[HKEY_USERS\.DEFAULT\Software\Microsoft\Windows\CurrentVersion\Runonce]' \
        '"^SetupICWDesktop"=-' ''
    } | unix2dos >> "$dir/\$OEM\$/install.reg" || return 1
  fi

  if [[ "$driver" == "2k" || "$driver" == "2k3" ]]; then
    {
      printf '%s\n' \
        '[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer]' \
        '"NoActiveDesktop"=dword:00000001' ''
    } | unix2dos >> "$dir/\$OEM\$/install.reg" || return 1
  fi

  if [[ "$driver" == "2k3" ]]; then
    {
      printf '%s\n' \
        '[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows NT\Reliability]' \
        '"ShutdownReasonOn"=dword:00000000' \
        '' \
        '[HKEY_CURRENT_USER\Software\Microsoft\Windows NT\CurrentVersion\srvWiz]' \
        '@=dword:00000000' \
        '' \
        '[HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\ServerOOBE\SecurityOOBE]' \
        '"DontLaunchSecurityOOBE"=dword:00000000' \
        '' \
        '[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\R2Setup]' \
        '"cd2chain"=dword:00000000' ''
    } | unix2dos >> "$dir/\$OEM\$/install.reg" || return 1
  fi

  return 0
}

writeVBS() {

  local dir="$1"
  local username="$2"
  local shortcut="$3"
  local driver="$4"
  local balloonExe="$dir/\$OEM\$/\$1/Drivers/Balloon/blnsvr.exe"
  local power="$dir/\$OEM\$/\$1/OEM/NT5POWER.VBS"

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

    if [ -f "$balloonExe" ]; then
      printf '%s\n' \
        'Result = WshShell.Run("sc.exe query BalloonService", 0, True)' \
        'If Result <> 0 Then' \
        '  Result = WshShell.Run(Chr(34) & "C:\Drivers\Balloon\blnsvr.exe" & Chr(34) & " -i", 0, True)' \
        'End If' \
        ''
    fi
  } | unix2dos > "$dir/\$OEM\$/install.vbs" || return 1

  if [[ "$driver" == "xp" || "$driver" == "2k3" ]]; then
    mkdir -p "$(dirname "$power")" || return 1

    {
      printf '%s\n' \
        'On Error Resume Next' \
        'Set Shell = WScript.CreateObject("WScript.Shell")' \
        'Set FSO = WScript.CreateObject("Scripting.FileSystemObject")' \
        'PowerCfg = Shell.ExpandEnvironmentStrings("%SystemRoot%\System32\POWERCFG.EXE")' \
        '' \
        'Shell.RegWrite "HKCU\Control Panel\Desktop\SCRNSAVE.EXE", "off", "REG_SZ"' \
        'Shell.RegWrite "HKCU\Control Panel\Desktop\ScreenSaveActive", "0", "REG_SZ"' \
        '' \
        'If FSO.FileExists(PowerCfg) Then' \
        '  Policy = 3' \
        '  Cmd = Chr(34) & PowerCfg & Chr(34) & " /CHANGE " & Policy & " /NUMERICAL "' \
        '  For Each Setting In Array("/monitor-timeout-ac", "/monitor-timeout-dc", "/disk-timeout-ac", "/disk-timeout-dc", "/standby-timeout-ac", "/standby-timeout-dc")' \
        '    Shell.Run Cmd & Setting & " 0", 0, True' \
        '  Next' \
        '  Shell.Run Chr(34) & PowerCfg & Chr(34) & " /SETACTIVE 3 /NUMERICAL", 0, True' \
        'End If' \
        ''
    } | unix2dos > "$power" || return 1
  else
    rm -f -- "$power" || return 1
  fi

  {
    printf '%s\n' \
      '[COMMANDS]' \
      '"REGEDIT /s install.reg"' \
      '"Wscript install.vbs"' \
      ''
  } | unix2dos > "$dir/\$OEM\$/cmdlines.txt" || return 1

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

getInputLocaleID() {

  local input="${1//_/-}"
  local result
  input="${input,,}"

  # NT5 InputLocale stores the input-language ID separately from the keyboard
  # layout ID. For a raw KLID, its low word is the corresponding language ID.
  if [[ "$input" =~ ^keyboard[-_]([0-9a-f]{8})$ ]]; then
    result="${BASH_REMATCH[1]:4:4}"
    printf '%s\n' "${result^^}"
    return 0
  fi

  if [[ "$input" =~ ^([0-9a-f]{8})$ ]]; then
    result="${BASH_REMATCH[1]:4:4}"
    printf '%s\n' "${result^^}"
    return 0
  fi

  getLocaleID "$input"
  return $?
}

return 0

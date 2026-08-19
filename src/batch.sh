#!/usr/bin/env bash
set -Eeuo pipefail

Win9xInstall() {

  local id="$1"
  local dir="$3"
  local desc="$4"

  local shortcut="Y"
  local setup="SETUP"
  local share='\\host.lan\Data'
  local options="/ID /IS /IQ /IT"
  local monitor="Plug and Play Monitor"
  local target folder

  local msg="Preparing $desc installation..."
  info "$msg" && html "$msg"

  if disabled "$SHORTCUT" || disabled "${SAMBA:-Y}"; then
    shortcut="N"
  fi

  if [ -n "$DOMAIN" ]; then
    error "The DOMAIN variable is not supported for $desc!"
    return 1
  fi

  monitor="Plug and Play Monitor (VESA DDC)"

  case "${id,,}" in
    "win95"* )
      folder="WIN95"
      options="/IW $options"
      share='\\Host\Data' ;;
    "win98"* )
      folder="WIN98"
      options="/P J /IE /NF $options" ;;
    "win9x"* )
      folder="WIN9X"
      options="/P J /IE /NF $options" ;;
    * )
      error "Unknown version: $id"
      return 1 ;;
  esac

  target=$(find "$dir" -maxdepth 1 -type d -iname "$folder" -print -quit) || return 1

  if [ -z "$target" ]; then
    error "Failed to locate the $folder Setup folder in $desc ISO image!"
    return 1
  fi

  if [[ "${id,,}" == "win95"* ]]; then
    validateWin95OSR2 "$target" "$desc" || return 1
  fi

  [ -z "$WIDTH" ] && WIDTH="1024"
  [ -z "$HEIGHT" ] && HEIGHT="768"

  validateResolution "WIDTH" "$WIDTH" 320 || return 1
  validateResolution "HEIGHT" "$HEIGHT" 200 || return 1

  # Express setup still needs concrete identity values. If NameAndOrg is absent,
  # Windows 9x stops during GUI setup for the user's name/company; if Network is
  # missing the identity fields, it later stops for the computer name/workgroup.
  # Win9x has no useful "*" computer-name generator, so provide a valid default
  # when HOST was not configured.
  local host="${HOST:-Docker}"
  local username="${USERNAME:-Docker}"
  local workgroup="${WORKGROUP:-WORKGROUP}"
  local culture region timezone

  if ! disabled "$AUTOLOGIN"; then
    username="Docker"
  fi

  validateComputerName "$host" || return 1

  culture=$(getLanguage "$LANGUAGE" "culture") || return 1
  [ -z "$culture" ] && culture="en-US"
  region="${REGION:-$culture}"
  timezone=$(getTimeZone "$region" "win9x") || return 1

  # Reuse the normal OEM-folder preparation so /OEM and COMMAND behave like the
  # other Windows paths, but place the user payload directly at C:\OEM in the
  # generated Win9x system image.
  local win9x_oem="$dir/OEM"
  local install=""

  if ! addFolder "$dir" "win9x"; then
    error "Failed to add OEM folder to image!"
    return 1
  fi

  if [ -d "$win9x_oem" ]; then
    install=$(find "$win9x_oem" -maxdepth 1 -type f -iname install.bat -print -quit) || return 1
  fi

  # MSBATCH.INF and WINNT.SIF both use quoted INF-style values. Reuse the SIF
  # escaping helper so quotes and percent signs cannot alter the answer file.
  local batchHost batchUsername batchOrganization batchWorkgroup batchKey=""
  batchHost=$(escapeSIFValue "$host") || return 1
  batchUsername=$(escapeSIFValue "$username") || return 1
  batchOrganization=$(escapeSIFValue "$APP for $ENGINE") || return 1
  batchWorkgroup=$(escapeSIFValue "$workgroup") || return 1

  if [ -n "$KEY" ]; then
    batchKey=$(escapeSIFValue "$KEY") || return 1
  fi

  if ! disabled "$AUTOLOGIN"; then
    stageWin9xPasswordList "$target" "$desc" || return 1
  fi

  if enabled "$shortcut" || [ -n "$install" ] || [[ "${id,,}" == "win95"* || "${id,,}" == "win9x"* ]]; then
    stageWin9xHide "$target" "$desc" || return 1
  fi

  if [[ "${id,,}" == "win9x"* ]]; then
    stageWin9xWait "$target" "$desc" || return 1
  fi

  if [ -n "$install" ] || [[ "${id,,}" == "win95"* || "${id,,}" == "win9x"* ]]; then
    stageWin9xPostSetup "$target" "$desc" "$install" "$id" || return 1
  fi

  stageWin9xDMA "$target" "$desc" || return 1
  stageWin9xScandiskConfig "$target" "$desc" || return 1

  # Reuse the same driver archive extraction used by the XP/2003 path. All
  # Windows 9x support files live together under win9x/ in that archive.
  local drivers="/tmp/drivers"
  local win9x="$drivers/win9x"
  local patcher="$win9x/patcher9x/patcher9x"
  local patcher_dos="$patcher.img"
  local qemouse="$win9x/qemouse"
  local display="$win9x/vmdisp9x"
  local audio95="$win9x/alcx95"
  local audiowdm="$win9x/alcxwdm"

  extractDrivers "$drivers" || return 1

  if [ -z "${BIOS:-}" ]; then
    local bios="$win9x/bios/win9x.bin"

    if [ ! -s "$bios" ]; then
      rm -rf "$drivers" || :
      error "Failed to locate the Windows 9x BIOS!"
      return 1
    fi

    BIOS="$TMP/win9x.bin"

    if ! cp -f -- "$bios" "$BIOS"; then
      rm -rf "$drivers" || :
      error "Failed to prepare the Windows 9x BIOS!"
      return 1
    fi
  fi

  if [ ! -f "$patcher" ] || [ ! -f "$patcher_dos" ]; then
    rm -rf "$drivers" || :
    error "Failed to locate Patcher9x!"
    return 1
  fi

  if [ ! -f "$qemouse/qemouse.drv" ]; then
    rm -rf "$drivers" || :
    error "Failed to locate the Windows 9x QEMouse driver!"
    return 1
  fi

  if ! patchWin9xSetupFiles "$id" "$target" "$desc" "$patcher" "$qemouse" "$display"; then
    rm -rf "$drivers" || :
    return 1
  fi

  if [[ "${id,,}" == "win95"* ]]; then
    # QEMU AC97 is a normal PCI PnP device, so keep its Win95 VxD driver beside
    # the retained C:\SETUP source.
    if ! stageWin95AC97Driver "$target" "$audio95" "$desc"; then
      rm -rf "$drivers" || :
      return 1
    fi
  elif [[ "${id,,}" == "win98"* || "${id,,}" == "win9x"* ]]; then
    # Win98/Me use the WDM package from the same driver archive. Stage it beside
    # C:\SETUP and add a QEMU-specific INF match for the emulated Intel AC97 PCI ID.
    if ! stageWin98MeAC97Driver "$target" "$audiowdm" "$desc"; then
      rm -rf "$drivers" || :
      return 1
    fi
  fi

  # Keep Win95's product-type and online-service changes together in the same
  # loose SETUPPP.INF. This prevents MSN/Online Services from being installed
  # at all, and also handles the no-key OEM product type when needed.
  if [[ "${id,,}" == "win95"* ]]; then
    patchWin95SetupComponents "$target" "$desc" "$batchKey" || {
      rm -rf "$drivers" || :
      return 1
    }
  fi

  if ! stageWin9xDosPatcher "$target" "$desc" "$patcher_dos"; then
    rm -rf "$drivers" || :
    return 1
  fi

  if ! stageWin9xSetupOverrides "$target" "$desc" "$qemouse"; then
    rm -rf "$drivers" || :
    return 1
  fi

  if ! stageWin9xFinalAutoexec "$target" "$setup" "$options" "$desc" "$id"; then
    rm -rf "$drivers" || :
    return 1
  fi

  if enabled "$shortcut" && ! stageWin9xSharedShortcut "$target" "$desc" "$share"; then
    rm -rf "$drivers" || :
    return 1
  fi

  if [[ "${id,,}" == "win9x"* ]]; then
    if ! stageWinMeFinalBootFiles "$dir" "$target" "$desc" ||
      ! stageWinMeBootActivation "$target" "$desc" ||
      ! stageWinMePowerPolicy "$target" "$desc" ||
      ! stageWinMeFinalSetup "$target" "$desc"; then
      rm -rf "$drivers" || :
      return 1
    fi
  fi

  # Do not copy optical-media AutoRun metadata onto the system disk; Explorer
  # otherwise treats C: like the installation CD and runs its default action.
  find "$dir" -maxdepth 1 -type f -iname 'AUTORUN.INF' -delete || return 1

  # Generate MSBATCH.INF after the Setup-source staging is complete.
  writeWin9xAnswerFile \
    "$target" "$id" "$setup" "$monitor" \
    "$batchHost" "$batchUsername" "$batchOrganization" "$batchWorkgroup" \
    "$batchKey" "$shortcut" "$install" "$timezone" "$share" || return 1

  # Build the hard-disk system image from the setup files themselves. Do not rely
  # on a particular El Torito floppy-image filename: some perfectly valid Win9x
  # discs expose a differently named boot image, while the required DOS system
  # files are already present in the installation cabinets.
  if ! createWin9xSystemImage "$dir" "$TMP/windows.img" "$desc" "$folder" "$options" "$id"; then
    rm -rf "$drivers" || :
    return 1
  fi

  rm -rf "$drivers" || :
  SYSTEM="$TMP/windows.img"

  return 0
}

validateWin95OSR2() {

  local dir="$1"
  local desc="$2"
  local format

  format=$(find "$dir" -maxdepth 1 -type f -iname 'FORMAT.COM' -print -quit) || return 1

  if [ -z "$format" ]; then
    error "Failed to locate FORMAT.COM in $desc setup files!"
    return 1
  fi

  # FAT32 support was introduced with Windows 95 OSR2. Require the setup
  # FORMAT.COM itself to carry the FAT32 marker so pre-OSR2 media fail before
  # any setup files are modified. The existing image builder performs the full
  # structural validation of that FAT32 boot template later.
  if ! LC_ALL=C grep -aFq 'FAT32   ' "$format"; then
    error "Unsupported $desc ISO image: Windows 95 OSR2 or newer is required!"
    return 1
  fi

  return 0
}

stageWin9xPasswordList() {

  local dir="$1"
  local desc="$2"
  local target="$dir/DOCKER.PWL"

  if ! base64 -d <<'EOF' | gzip -dc > "$target"
H4sIAAAAAAACA3vc1DqNkWEUMPwf2SCIifIghKSj0rXqtq9ePF4Yukz50lmmIyebzcx+z7vIcKxZ
6S7PpN8sV44Jzlq1dhnfPs2iBxq536xPbXn9o/X+LEe7Ra6/5kfHNX57zqt/9cKFnAV5Eoc1bvTP
Uts5yVhW6XnWRtOdrdK2swELaJAzsAIAAA==
EOF
  then
    error "Failed to create DOCKER.PWL in $desc setup files!"
    return 1
  fi

  if [ "$(wc -c < "$target")" -ne 688 ]; then
    error "Failed to verify DOCKER.PWL in $desc setup files!"
    return 1
  fi

  return 0
}

stageWin9xHide() {

  local dir="$1"
  local desc="$2"
  local target="$dir/HIDE.EXE"

  if ! base64 -d <<'EOF' | gzip -dc > "$target"
H4sIAAAAAAACA/ONYiAbNDBQDgJcGRh8GBlRxB4wMDFyg8SYkAQFkDCDA4QGyrNApWE0gwIDXB8T
TKMAMg2nIH4AcjQYqA92CKDagw70SlIrSkAMRga4X1D8CwQJYERb8F90h4ADQ+exBjulUkG3BjuG
Egcgs4TZ7fVnt9dCIL5Bg51CCUeDHSdI8B2IwwrklIJUgKQFsxjC/ovuARqSBTTsABJNFFiBFEgn
BCDhhg1cA4q/AOJPAtj53q5Bfq4+xkZ6Lj4+IL57aolzfm5uYl6KT2ZeqiNQJDwzz7UiNRnIcq3I
LAkoyk9OLS5mGOkAAN77EFsABAAA
EOF
  then
    error "Failed to create HIDE.EXE in $desc setup files!"
    return 1
  fi

  if [ "$(wc -c < "$target")" -ne 1024 ]; then
    error "Failed to verify HIDE.EXE in $desc setup files!"
    return 1
  fi

  return 0
}

stageWin9xWait() {

  local dir="$1"
  local desc="$2"
  local target="$dir/WAIT.EXE"

  if ! base64 -d <<'EOF' | gzip -dc > "$target"
H4sICEFjhGoCA1dBSVQtMjAyNjA4MTgtMTU1Ni5FWEUA842qYGBkYGBgYUAFDgyEQQUQ88nv4mPYwnlWcQejz1nFkIzMYoWC
ovz0osRcheTEvLz8EoWkVIWi0jyFzDwFF/9ghdz8lFQ9FQaGAFcGBh9GFgbH5JYsmHkPGJgYuRn5GBiYkBwkAMUwV4HYTAhp
uLsDEBwmmEYBZBrJGBBbgYFBA5/ngFbpMJAOfIDmiuCR1ytJrSgB0nKMDHC/oAc+0IgEvaKUxJJEBobVUAGwOjYMJzroQZQx
sIDMM8DplQN6Rak5+clQPzlAzePAUOfEMApGFAgP+y8aoODA0MXR8FOpVNKBfxuHQ/NPpRKW1pOln3sL/gNF+V0+vBZp+KlY
xNtbwNhQwajQ+aH862umzmNdbJ0H/510a/ipUPSl5UApdxbTf1EfkFlu//m3nWg5UBIGNKlUs4sNyPQ0vGSjVGLf+IsJmFDL
zXu9GDuaGAyAal3EGDtPAXU/fK0BVKJYJANVIoJQwiIGVvHoNVvnxddMhiePNYKEGRpswVQpB8zeDBD/v2gIkNn843+pfLdp
BJDZbQsSyHjBzMDw/xpEyXWgdMnbLAaItrj4w/9VQWHwX9UHTIaASZDeM8Me/AcCUDqA0RYKiLQxTwFSnmEDCUDxPCBuAOJp
CrjFGBhcKzJLAoryk1OLi4E899QS5/zc3MS8FJ/MvFRHiIhbZk6qY0lJUWZSaUlqMUiQITgnNbWAwds1yM/Vx9hILyUnZzSv
0gQIQOoEFoMAgxqD+QbbDPYanDA4a3DZ4J7BE4MPBv8NOAz5DEUMpQxHg2o4AgCe4TcIAAoAAA==
EOF
  then
    error "Failed to create WAIT.EXE in $desc setup files!"
    return 1
  fi

  if [ "$(wc -c < "$target")" -ne 2560 ]; then
    error "Failed to verify WAIT.EXE in $desc setup files!"
    return 1
  fi

  return 0
}

stageWin9xPostSetup() {

  local dir="$1"
  local desc="$2"
  local install="$3"
  local id="$4"
  local target="$dir/POST9X.BAT"

  # Windows 95 can reach its first real desktop without the extra Setup reboot
  # used by the established 98/Me post-setup path. Run FirstLogon and finish its
  # pending file operations in a hidden housekeeping shell so the next normal
  # reboot does not re-enter WININIT. Launch the OEM install in its own visible
  # command window and wait for it so install.bat keeps its debugging behavior.
  if [[ "${id,,}" == "win95"* ]]; then
    {
      printf '%s\n' \
        '@ECHO OFF' \
        'C:\WINDOWS\RUNDLL.EXE SETUPX.DLL,InstallHinfSection Win9x.FirstLogon 4 C:\WINDOWS\MSBATCH.INF' \
        'COPY /Y C:\SETUP\W9XAUTO.BAT C:\AUTOEXEC.BAT >NUL' \
        'DEL C:\SETUP\PATCH9X.RUN >NUL' \
        'IF EXIST C:\WINDOWS\DESKTOP\ONLINE~1 C:\WINDOWS\COMMAND\DELTREE.EXE /Y C:\WINDOWS\DESKTOP\ONLINE~1 >NUL'

      if [ -n "$install" ]; then
        if enabled "${LOG:-}"; then
          printf '%s\n' 'START /W C:\WINDOWS\COMMAND.COM /C C:\OEM\install.bat > C:\OEM\install.log'
        else
          printf '%s\n' 'START /W C:\WINDOWS\COMMAND.COM /C C:\OEM\install.bat'
        fi
      fi

    } | unix2dos > "$target" || {
      error "Failed to create post-desktop setup script for $desc!"
      return 1
    }

    return 0
  fi

  local marker="$dir/POST9X.NEW"
  local cleanup="$dir/POST9X.REG"

  {
    printf '%s\n' \
      '@ECHO OFF' \
      'IF NOT EXIST C:\WINDOWS\POST9X.RDY GOTO END'

    printf '%s\n' 'START /W C:\WINDOWS\REGEDIT.EXE /S C:\WINDOWS\POST9X.REG'

    printf '%s\n' \
      'DEL C:\WINDOWS\POST9X.REG >NUL' \
      'DEL C:\WINDOWS\POST9X.RDY >NUL'

    if [[ "${id,,}" == "win9x"* ]]; then
      printf '%s\n' 'DEL C:\SETUP\PATCH9X.RUN >NUL'
    fi

    if [ -n "$install" ]; then
      if enabled "${LOG:-}"; then
        printf '%s\n' 'CALL C:\OEM\install.bat > C:\OEM\install.log'
      else
        printf '%s\n' 'CALL C:\OEM\install.bat'
      fi
    fi

    printf '%s\n' ':END'

  } | unix2dos > "$target" || {
    error "Failed to create post-desktop setup script for $desc!"
    return 1
  }

  # Remove the persistent Run value without re-entering SETUPX.DLL from the
  # desktop batch. REGEDIT /S performs the one registry cleanup silently.
  {
    printf '%s\n' \
      'REGEDIT4' \
      '' \
      '[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Run]' \
      '"PostSetup"=-'

  } | unix2dos > "$cleanup" || {
    error "Failed to create post-desktop registry cleanup for $desc!"
    return 1
  }

  # Stage a real marker file for Setup to copy into the Windows directory.
  # Win9x.FirstLogon adds a WININIT.INI rename so the following reboot promotes
  # POST9X.NEW to POST9X.RDY before the final desktop starts.
  if ! printf 'Ready\r\n' > "$marker"; then
    error "Failed to create post-desktop marker for $desc!"
    return 1
  fi

  return 0
}

stageWin9xDMA() {

  local dir="$1"
  local desc="$2"
  local target="$dir/WIN9XDMA.EXE"

  # Keep the Win9x DMA helper embedded alongside HIDE.EXE so the driver
  # archive stays unchanged. It updates both enumerated ESDI disks and the
  # persistent ESDI_506.PDR controller DMA flags used after a reboot.
  if ! base64 -d <<'EOF' | gzip -dc > "$target"
H4sIAAAAAAACA+1WT4gbZRR/yeaQtutm0A22a4sTnPViN8w3XYWqC0kzKQ1N7TRx41KjNSZDk5h/
TGZKVtrSks0hHXIR60F69lxhKUtAGrpVD9oq4qoYkVzUDd3DwsIS8M/4vpmkpuxS9SII++DLzPu9
N795v998zOTE6QrYAMABD4YP/j4quMaebI7B4q47niVb+I7n5XSmzJaU4lklkWeTiUKhqLJvyqyi
FdhMgRVPRtl8MSV7OQApCBC2jUDHsZAd8HXAbttjG7OGGQzE9NdgKnpu/6vsGB64n9gHFzLDxyEa
jGsswIsPE8fjfPDvo4e87EPqXlWuqHhct/cHcmw1H69/w6ukEmoC4B2bBZiinFuekc+ryLlisj8r
3+/bvaXvCOzETmwTs9FXYpfXruMuq3ekrDMLaWB9kMZddMlwg8cHtZarZmAjaTdyHK/P/IblxiJ3
HaH0JZPAULlR49taS2VmRpDHVfsI4e4t/GmInNMkncUeRp+ifMYKZXwfq/U4N0raafr6iVGScZNk
l0mipe/l8GqHlB3JQgyLe+l1WkQPc47mbhwhy2J5XFotYHP1thMvPNgIc0yTwdrqBwgiMpG1pZ+h
vciRnsATk8ft9JhnDsPdQyzQfdvAUDmnles4FVUa6B6g+DRnwXg3xvLn4FZ/vqFar5me6FPUIH2G
lsim6VCUzr+fzn/foavUoffAMh2no/JZKl+7qI9yzTk6tA9vOS2tNmAg8DQK5JtJKvBjMAUeIy2f
tEQlSksjCEmkJaVLltBxfcoUurJdz4V+j7FizXtf5tFuyHKDsfIsGG4GaS7fplvk9TOvvrZMd0x1
zamf51j0aj/ZpM+pztd/ql/AzSDFIqcMt8M0Rnu8ep5z2DRGd3DHDvfKzk/EFwx05Wh9HRWZZMh1
Zd9CWz3kd92wo6Ip142NxsWb9Y3qZ2zVmHAFfmyUbtY/rX7BVv/ArHf4V+2xI1f2+Rfa2l3SJq3n
J1zvtu7ZSQvZlo1JU8skvbsxaaqfZMzfnonTZ/L5TjwQwYKWjwejYggCuUS5DGKm/JaoZM7JIJ7w
BzRFkQtqbn62LKfAFp0vq3I+3kcDxYKqFHNRWY1HZeVcJimX4yZHPJ1KglRUVJNHAcp+5ln+OW8p
pUBIDCKxGAnFgvxwQnBr0p0HQ8fvhj6kFY/1bV0fwmqIMZ7t32t7EX8a1zQuEddcvy/r+Wd1gIh8
NpArluXj8ryVUasw8VvZyZJcwCxY6eenNFmZjyVymmxBFENvhpFgJaNKShGNKoNfjPml0CHBm8rl
4Hgw8lIw3E/+42Cs/w6P8gd4wuf5Rf5LvsN3+Q3+d/4RwhGBzJAImSNXyYdkmXxFfiC/kE1iF/YI
TwhPCTHhrvC18L3QEX4W1oSdr+n/L/4EP8bQ8wAMAAA=
EOF
  then
    error "Failed to create WIN9XDMA.EXE in $desc setup files!"
    return 1
  fi

  if [ "$(wc -c < "$target")" -ne 3072 ]; then
    error "Failed to verify WIN9XDMA.EXE in $desc setup files!"
    return 1
  fi

  return 0
}

stageWin9xScandiskConfig() {

  local dir="$1"
  local desc="$2"
  local target="$dir/W9XSCAN.INI"

  # Boot-time ScanDisk is started in /CUSTOM mode after an unclean shutdown.
  # Keep filesystem repair enabled while removing every normal interactive
  # decision and summary screen. A surface scan is intentionally excluded: it
  # is unnecessary for routine forced-poweroff recovery and would make booting
  # a large virtual disk take an excessive amount of time.
  {
    printf '%s\n' \
      '[Environment]' \
      'LfnCheck=On' \
      '' \
      '[Custom]' \
      'DriveSummary=Off' \
      'AllSummary=Off' \
      'Surface=Never' \
      'CheckHost=Never' \
      'SaveLog=Append' \
      'Undo=Never' \
      'DS_Header=Fix' \
      'FAT_Media=Fix' \
      'Okay_Entries=Fix' \
      'Bad_Chain=Fix' \
      'Crosslinks=Fix' \
      'Boot_Sector=Fix' \
      'Invalid_MDFAT=Fix' \
      'DS_Crosslinks=Fix' \
      'DS_LostClust=Fix' \
      'DS_Signatures=Fix' \
      'Mismatch_FAT=Fix' \
      'Bad_Clusters=Fix' \
      'Bad_Entries=Delete' \
      'LostClust=Save' \
      ''
  } | unix2dos > "$target" || {
    error "Failed to create SCANDISK.INI in $desc setup files!"
    return 1
  }

  return 0
}

patchWin9xSetupFiles() {

  local id="$1"
  local target="$2"
  local desc="$3"
  local patcher="$4"
  local qemouse="$5"
  local display="$6"

  chmod 755 "$patcher" || {
    error "Failed to make Patcher9x executable!"
    return 1
  }

  local patch_output
  local patch_args=(-auto -unselect creg)

  [[ "${id,,}" == "win9x"* ]] && patch_args=(-auto)

  if ! patch_output=$("$patcher" "${patch_args[@]}" "$target" 2>&1); then
    [ -z "$patch_output" ] || printf '%s\n' "$patch_output" >&2
    error "Failed to patch $desc setup files!"
    return 1
  fi

  if [[ "${id,,}" == "win9x"* ]]; then
    patchWinMeBaseComponents "$target" "$desc" || return 1
  fi

  stageWin9xDisplayDriver "$target" "$display" "$desc" || return 1

  if ! mv -f -- \
    "$target/VMDISP9X/vmdisp9x.inf" \
    "$target/VMDISP9X/qemumini.drv" \
    "$target/VMDISP9X/qemumini.vxd" \
    "$target/VMDISP9X/vmhal9x.dll" \
    "$target/VMDISP9X/vmhal486.dll" \
    "$target/VMDISP9X/vmdisp9x.dll" \
    "$target/"; then
    error "Failed to stage the Windows 9x display driver in the setup source!"
    return 1
  fi

  rm -rf -- "$target/VMDISP9X" || return 1

  # Use QEMouse directly in the MINI.CAB GUI Setup environment for every Win9x
  # release, so the setup mouse path does not depend on a DOS INT 33h TSR.
  integrateWin9xSetupMouse "$target" "$desc" "$qemouse/qemouse.drv" || return 1

  return 0
}

stageWin95AC97Driver() {

  local dir="$1"
  local audio="$2"
  local desc="$3"
  local source name

  if [ ! -d "$audio" ] || [ -z "$(find "$audio" -maxdepth 1 -type f -print -quit)" ]; then
    error "Failed to locate the Windows 95 AC97 driver payload!"
    return 1
  fi

  # Keep the driver payload self-contained: drivers.tar.xz owns the exact files
  # and this path simply stages everything present in win9x/alcx95/. This avoids
  # having to update an installer-side filename list when the payload changes.
  if ! cp -a -- "$audio"/. "$dir"/; then
    error "Failed to stage the Windows 95 AC97 driver payload!"
    return 1
  fi

  # Verify every top-level file copied byte-for-byte without hard-coding the
  # payload contents. Subdirectories, if ever added, are copied by cp -a above.
  while IFS= read -r -d '' source; do
    name="${source##*/}"
    if [ ! -f "$dir/$name" ] || ! cmp -s -- "$source" "$dir/$name"; then
      error "Failed to verify the staged Windows 95 AC97 driver file $name!"
      return 1
    fi
  done < <(find "$audio" -maxdepth 1 -type f -print0)

  # Validate the critical invariants of the Win95 VxD package without rewriting
  # vendor files: QEMU's PCI ID, PnP/SB-emulation registration, and every file
  # referenced by the INF must be present and non-empty.
  if ! python3 - "$dir" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
required_files = (
    'VALCX95.INF',
    'VALCX95.VXD',
    'ALCX95.DRV',
    'ALCX95.INI',
    'ALSWWT.DRV',
    'ALSWWT16.DLL',
    'SWWTAC97.DAT',
    'SWWTAC97.TON',
)

for name in required_files:
    path = root / name
    if not path.is_file() or path.stat().st_size == 0:
        raise SystemExit(f'AC97 payload file missing or empty: {name}')

data = (root / 'VALCX95.INF').read_bytes().replace(b'\r\n', b'\n').lower()

required_inf = (
    b'signature="$chicago$"',
    b'class=media',
    b'%alcich.devicedesc%=alcaud, pci\\ven_8086&dev_2415',
    b'%alcaud_sb.devicedesc%=alcsb, virtual\\alc_sbemulation',
    b'hkr,drivers,sbemulation,,"yes"',
    b'copyfiles=alcaud.copylist, alcwtb.copylist, alcini.copylist',
)
for item in required_inf:
    if item not in data:
        raise SystemExit(f'AC97 INF verification failed for {item!r}.')

def section(name: bytes) -> bytes:
    marker = b'[' + name + b']'
    try:
        body = data.split(marker, 1)[1]
    except IndexError:
        raise SystemExit(f'AC97 INF section missing: {name.decode()}')
    return body.split(b'\n[', 1)[0]

destinations = section(b'destinationdirs')
for item in (
    b'defaultdestdir=11',
    b'alcaud.copylist=11',
    b'alcwtb.copylist=10',
    b'alcini.copylist=10',
):
    if item not in destinations:
        raise SystemExit(f'AC97 destination verification failed for {item!r}.')

copy_sections = {
    b'alcaud.copylist': (
        b'valcx95.vxd',
        b'alcx95.drv',
        b'alswwt.drv',
        b'alswwt16.dll',
        b'swwtac97.ton',
    ),
    b'alcwtb.copylist': (b'swwtac97.dat',),
    b'alcini.copylist': (b'alcx95.ini',),
}
for name, items in copy_sections.items():
    body = section(name)
    for item in items:
        if item not in body:
            raise SystemExit(
                f'AC97 copy-list verification failed in {name!r} for {item!r}.'
            )

source_files = section(b'sourcedisksfiles')
for name in required_files[1:]:
    if name.lower().encode() not in source_files:
        raise SystemExit(f'AC97 source-file verification failed for {name}.')
PY
  then
    error "Failed to verify the Windows 95 AC97 PCI driver payload!"
    return 1
  fi

  return 0
}

stageWin98MeAC97Driver() {

  local dir="$1"
  local audio="$2"
  local desc="$3"
  local source name

  if [ ! -d "$audio" ] || [ -z "$(find "$audio" -maxdepth 1 -type f -print -quit)" ]; then
    error "Failed to locate the Windows 98/Me AC97 WDM driver payload!"
    return 1
  fi

  # Keep both vendor INFs and every referenced payload file together in the
  # retained setup source. OtherDevicePath already makes C:\SETUP an OEM PnP
  # search path while Windows is enumerating the AC97 controller.
  if ! cp -a -- "$audio"/. "$dir"/; then
    error "Failed to stage the Windows 98/Me AC97 WDM driver payload!"
    return 1
  fi

  # Verify every top-level archive file before creating the QEMU compatibility
  # INF below, so the vendor payload itself remains byte-for-byte unchanged.
  while IFS= read -r -d '' source; do
    name="${source##*/}"
    if [ ! -f "$dir/$name" ] || ! cmp -s -- "$source" "$dir/$name"; then
      error "Failed to verify the staged Windows 98/Me AC97 driver file $name!"
      return 1
    fi
  done < <(find "$audio" -maxdepth 1 -type f -print0)

  # The supplied Realtek WDM INFs contain Intel ICH matches but no generic
  # PCI\VEN_8086&DEV_2415 entry used by QEMU's AC97 device. Derive an unsigned
  # 8.3-compatible OEM INF from Alcxwdm0.inf, preserving the vendor INF itself.
  # Removing CatalogFile avoids claiming the generated INF is covered by the
  # vendor catalog after adding the QEMU hardware ID.
  if ! python3 - "$dir" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
required_files = (
    'Alcxwdm0.inf',
    'Alcxwdm1.inf',
    'Alcxwdm.cat',
    'ALCXWDM.SYS',
    'Soundman.exe',
    'ALSndMgr.cpl',
    'alsndmgr.wav',
)

for name in required_files:
    path = root / name
    if not path.is_file() or path.stat().st_size == 0:
        raise SystemExit(f'AC97 WDM payload file missing or empty: {name}')

vendor = root / 'Alcxwdm0.inf'
raw = vendor.read_bytes()
normalized = raw.replace(b'\r\n', b'\n').lower()

for item in (
    b'signature="$chicago$"',
    b'class=media',
    b'[avance]',
    b'[ac97aud]',
    b'alcxwdm.sys',
    b'alsoinstall=ks.registration(ks.inf), wdmaudio.registration(wdmaudio.inf)',
    b'hkr,drivers\\wave\\wdmaud.drv,driver,,wdmaud.drv',
    b'alcxwdm.sys=222',
    b'soundman.exe=222',
    b'alsndmgr.cpl=222',
    b'alsndmgr.wav=222',
):
    if item not in normalized:
        raise SystemExit(f'AC97 WDM installation invariant missing: {item!r}.')

newline = b'\r\n' if b'\r\n' in raw else b'\n'
clone = raw
clone, catalog_count = re.subn(
    br'(?im)^[ \t]*CatalogFile[ \t]*=[^\r\n]*(?:\r?\n)',
    b'',
    clone,
    count=1,
)
if catalog_count != 1:
    raise SystemExit(f'Unexpected AC97 WDM CatalogFile count: {catalog_count}.')

generic = re.compile(
    br'(?im)^[ \t]*%ALCAUD\.Desc%[ \t]*=[ \t]*AC97AUD[ \t]*,[ \t]*'
    br'PCI\\VEN_8086&DEV_2415[ \t]*(?:\r?$)'
)

if not generic.search(clone):
    section = re.search(br'(?im)^\[Avance\][ \t]*(?:\r?\n)', clone)
    if section is None:
        raise SystemExit('AC97 WDM [Avance] section missing.')
    entry = b'%ALCAUD.Desc%=AC97AUD,\tPCI\\VEN_8086&DEV_2415' + newline
    clone = clone[:section.end()] + entry + clone[section.end():]

matches = generic.findall(clone)
if len(matches) != 1:
    raise SystemExit(
        f'Unexpected QEMU AC97 generic hardware-ID count: {len(matches)} (expected 1).'
    )

if re.search(br'(?im)^[ \t]*CatalogFile[ \t]*=', clone):
    raise SystemExit('Generated QEMU AC97 INF still references the vendor catalog.')

output = root / 'QEMUAC97.INF'
output.write_bytes(clone)
if not output.is_file() or output.stat().st_size == 0:
    raise SystemExit('Failed to create QEMUAC97.INF.')
PY
  then
    error "Failed to prepare the Windows 98/Me AC97 WDM PCI driver!"
    return 1
  fi

  return 0
}

patchWin95SetupComponents() {

  local target="$1"
  local desc="$2"
  local batchKey="$3"
  local setuppp="$target/SETUPPP.INF"
  local layout="$target/LAYOUT.INF"

  # Win95 OSR2 normally keeps SETUPPP.INF in PRECOPY*.CAB, while some later
  # media exposes it directly. A loose copy selected by LAYOUT.INF lets us
  # suppress MSN/Online Services before Setup creates their desktop objects.
  if [ ! -s "$setuppp" ]; then
    extractWin9xCabFile "$target" 'SETUPPP.INF' "$setuppp" "$desc" || return 1
  fi

  if [ ! -s "$layout" ]; then
    extractWin9xCabFile "$target" 'LAYOUT.INF' "$layout" "$desc" || return 1
  fi

  if ! python3 - "$setuppp" "$layout" "$batchKey" <<'PY'
from pathlib import Path
import re
import sys

setuppp = Path(sys.argv[1])
layout = Path(sys.argv[2])
has_key = bool(sys.argv[3])

setup_data = setuppp.read_bytes()
setup_lines = setup_data.splitlines(keepends=True)

if not has_key:
    product_re = re.compile(
        br'^([ \t]*ProductType[ \t]*=[ \t]*)9([ \t]*)(\r?\n)?$',
        re.IGNORECASE,
    )
    matches = []

    for index, line in enumerate(setup_lines):
        match = product_re.match(line)
        if match:
            matches.append((index, match))

    if len(matches) != 1:
        print(
            f"Unexpected Windows 95 ProductType=9 count: {len(matches)} (expected 1).",
            file=sys.stderr,
        )
        raise SystemExit(1)

    index, match = matches[0]
    setup_lines[index] = (
        match.group(1)
        + b'1'
        + match.group(2)
        + (match.group(3) or b'')
    )

# MOS.INF installs The Microsoft Network and online registration. MSINFO.INF
# installs the OSR2 Online Services material. Remove every active reference but
# preserve comments and every unrelated byte in SETUPPP.INF.
blocked = (b'MOS.INF', b'MSINFO.INF')
filtered = []

for line in setup_lines:
    stripped = line.lstrip(b' \t')
    upper = stripped.upper()

    if stripped.startswith(b';') or not any(name in upper for name in blocked):
        filtered.append(line)

setup_data = b''.join(filtered)

for line in setup_data.splitlines():
    stripped = line.lstrip(b' \t')
    upper = stripped.upper()

    if not stripped.startswith(b';') and any(name in upper for name in blocked):
        print("Failed to remove a Windows 95 online-service setup reference.", file=sys.stderr)
        raise SystemExit(1)

if not has_key:
    product_one = re.compile(
        br'^[ \t]*ProductType[ \t]*=[ \t]*1[ \t]*$',
        re.IGNORECASE,
    )
    if sum(bool(product_one.match(line.rstrip(b'\r'))) for line in setup_data.splitlines()) != 1:
        print("Failed to verify the Windows 95 ProductType=1 change.", file=sys.stderr)
        raise SystemExit(1)

layout_data = layout.read_bytes()
layout_lines = layout_data.splitlines(keepends=True)
layout_re = re.compile(
    br'^([ \t]*SETUPPP\.INF[ \t]*=[ \t]*)[0-9]+,([^,\r\n]*,)[0-9]+([^\r\n]*)(\r?\n)?$',
    re.IGNORECASE,
)
layout_matches = []

for index, line in enumerate(layout_lines):
    match = layout_re.match(line)
    if match:
        layout_matches.append((index, match))

if len(layout_matches) != 1:
    print(
        f"Unexpected Windows 95 SETUPPP.INF layout-entry count: {len(layout_matches)} (expected 1).",
        file=sys.stderr,
    )
    raise SystemExit(1)

setuppp_size = len(setup_data)
index, match = layout_matches[0]
layout_lines[index] = (
    match.group(1)
    + b'0,'
    + match.group(2)
    + str(setuppp_size).encode('ascii')
    + match.group(3)
    + (match.group(4) or b'')
)

setuppp.write_bytes(setup_data)
layout.write_bytes(b''.join(layout_lines))

verify_layout = layout.read_bytes().splitlines()
expected = re.compile(
    br'^[ \t]*SETUPPP\.INF[ \t]*=[ \t]*0,[^,\r\n]*,'
    + str(setuppp_size).encode('ascii')
    + br'(?:,|[ \t]*$)',
    re.IGNORECASE,
)

if sum(bool(expected.match(line)) for line in verify_layout) != 1:
    print("Failed to verify the Windows 95 SETUPPP.INF layout entry.", file=sys.stderr)
    raise SystemExit(1)
PY
  then
    error "Failed to patch the Windows 95 setup components!"
    return 1
  fi

  return 0
}

patchWinMeBaseComponents() {

  local target="$1"
  local desc="$2"
  local wmp="$target/WMP.INF"
  local mplayer2="$target/MPLAYER2.INF"
  local setuppp="$target/SETUPPP.INF"

  # Windows Me installs WMP7 as a base setup option. The Online Services/MSN
  # setup path is pulled in by SETUPPP.INF, so suppress it at the source rather
  # than installing those components and deleting their desktop objects later.
  extractWin9xCabFile "$target" 'WMP.INF' "$wmp" "$desc" || return 1

  # Preserve loose setup INFs if an earlier patcher already staged them.
  if [ ! -s "$mplayer2" ]; then
    extractWin9xCabFile "$target" 'MPLAYER2.INF' "$mplayer2" "$desc" || return 1
  fi

  if [ ! -s "$setuppp" ]; then
    extractWin9xCabFile "$target" 'SETUPPP.INF' "$setuppp" "$desc" || return 1
  fi

  if [ "$(grep -Ec '^[[:space:]]*InstallWMP7[[:space:]]*$' "$wmp")" -ne 1 ]; then
    error "Failed to locate the Windows Me WMP7 base setup option!"
    return 1
  fi

  if [ "$(grep -Eio '/Shortcuts' "$mplayer2" | wc -l)" -ne 2 ]; then
    error "Failed to locate the Windows Me Media Player shortcut commands!"
    return 1
  fi

  if ! grep -Eiq '^[[:space:]]*([^;].*)?OLS\.INF' "$setuppp" ||
    ! grep -Eiq '^[[:space:]]*([^;].*)?MSNCLNUP\.INF' "$setuppp"; then
    error "Failed to locate the Windows Me Online Services setup references!"
    return 1
  fi

  if ! sed -i \
    -e '/^[[:space:]]*InstallWMP7[[:space:]]*$/d' "$wmp"; then
    error "Failed to disable Windows Me WMP7 setup!"
    return 1
  fi

  if ! sed -i -E 's/[[:space:]]+\/[Ss][Hh][Oo][Rr][Tt][Cc][Uu][Tt][Ss]//g' "$mplayer2"; then
    error "Failed to disable Windows Me Media Player shortcuts!"
    return 1
  fi

  if ! sed -i \
    -E -e '/^[[:space:]]*([^;].*)?[Oo][Ll][Ss]\.[Ii][Nn][Ff]/d' \
    -e '/^[[:space:]]*([^;].*)?[Mm][Ss][Nn][Cc][Ll][Nn][Uu][Pp]\.[Ii][Nn][Ff]/d' "$setuppp"; then
    error "Failed to disable Windows Me Online Services setup!"
    return 1
  fi

  if grep -Eq '^[[:space:]]*InstallWMP7[[:space:]]*$' "$wmp" ||
    grep -Eiq '/Shortcuts' "$mplayer2" ||
    grep -Eiq '^[[:space:]]*([^;].*)?(OLS\.INF|MSNCLNUP\.INF)' "$setuppp"; then
    error "Failed to verify the Windows Me desktop component changes!"
    return 1
  fi

  return 0
}

stageWin9xDisplayDriver() {

  local target="$1"
  local source="$2"
  local desc="$3"

  local dest="$target/VMDISP9X"
  local file

  for file in \
    vmdisp9x.inf \
    qemumini.drv \
    qemumini.vxd \
    vmhal9x.dll \
    vmhal486.dll \
    vmdisp9x.dll; do

    if [ ! -f "$source/$file" ]; then
      error "Failed to locate required Windows 9x display driver file: $file"
      return 1
    fi

  done

  rm -rf -- "$dest" || return 1
  mkdir -p "$dest" || return 1

  if ! cp -f -- \
    "$source/vmdisp9x.inf" \
    "$source/qemumini.drv" \
    "$source/qemumini.vxd" \
    "$source/vmhal9x.dll" \
    "$source/vmhal486.dll" \
    "$source/vmdisp9x.dll" \
    "$dest/"; then

    error "Failed to add the display driver to $desc setup files!"
    return 1
  fi

  # VMDisp9x's DDC flag makes Win9x enumerate a Plug and Play monitor after
  # the display driver starts. The unattended setup already selects the monitor
  # and display mode, and VMDisp9x carries a fixed mode list, so disable DDC in
  # our staged copy to avoid a second monitor PnP pass.
  if ! grep -Eq '^[[:space:]]*HKR,DEFAULT,DDC,,1[[:space:]]*$' "$dest/vmdisp9x.inf"; then
    error "Failed to locate the DDC setting in the Windows 9x display driver!"
    return 1
  fi

  if ! sed -i 's/HKR,DEFAULT,DDC,,1/HKR,DEFAULT,DDC,,0/' "$dest/vmdisp9x.inf" ||
    ! grep -Eq '^[[:space:]]*HKR,DEFAULT,DDC,,0[[:space:]]*$' "$dest/vmdisp9x.inf"; then
    error "Failed to disable DDC in the Windows 9x display driver!"
    return 1
  fi

  return 0
}

integrateWin9xSetupMouse() {

  local dir="$1"
  local desc="$2"
  local driver="$3"

  local cab
  cab=$(find "$dir" -maxdepth 1 -type f -iname 'MINI.CAB' -print -quit) || return 1

  if [ -z "$cab" ]; then
    error "Failed to locate MINI.CAB in $desc ISO image!"
    return 1
  fi

  if [ ! -f "$driver" ]; then
    error "Failed to locate the mouse driver for $desc MINI.CAB!"
    return 1
  fi

  local temp="$TMP/win9x-mini"
  local files="$temp/files"
  local rebuilt="$temp/MINI.CAB"
  local system
  local -a entries=()

  rm -rf -- "$temp" || return 1
  mkdir -p "$files" || return 1

  if ! cabextract -q -d "$files" "$cab"; then
    rm -rf -- "$temp" || :
    error "Failed to extract MINI.CAB from $desc ISO image!"
    return 1
  fi

  system=$(find "$files" -type f -iname 'SYSTEM.INI' -print -quit) || return 1

  if [ -z "$system" ]; then
    rm -rf -- "$temp" || :
    error "Failed to locate SYSTEM.INI in $desc MINI.CAB!"
    return 1
  fi

  if ! cp -f -- "$driver" "$files/QEMOUSE.DRV"; then
    rm -rf -- "$temp" || :
    error "Failed to add the mouse driver to $desc MINI.CAB!"
    return 1
  fi

  if ! grep -Eqi '^[[:space:]]*mouse\.drv[[:space:]]*=' "$system"; then
    rm -rf -- "$temp" || :
    error "Failed to locate the mouse driver setting in $desc MINI.CAB!"
    return 1
  fi

  if ! dos2unix "$system" >/dev/null 2>&1 ||
    ! sed -i -E 's/^([[:space:]]*mouse\.drv[[:space:]]*=[[:space:]]*).*$/\1qemouse.drv/I' "$system" ||
    ! unix2dos "$system" >/dev/null 2>&1; then
    rm -rf -- "$temp" || :
    error "Failed to configure the mouse driver in $desc mini-Windows setup!"
    return 1
  fi

  if ! grep -Eqi '^[[:space:]]*mouse\.drv[[:space:]]*=[[:space:]]*qemouse\.drv[[:space:]]*$' "$system"; then
    rm -rf -- "$temp" || :
    error "Failed to verify the mouse driver setting in $desc MINI.CAB!"
    return 1
  fi

  mapfile -d '' entries < <(find "$files" -type f -print0)

  if (( ${#entries[@]} == 0 )); then
    rm -rf -- "$temp" || :
    error "Failed to enumerate files from $desc MINI.CAB!"
    return 1
  fi

  if ! gcab -c -z -n "$rebuilt" "${entries[@]}" >/dev/null; then
    rm -rf -- "$temp" || :
    error "Failed to rebuild $desc MINI.CAB!"
    return 1
  fi

  if ! cabextract -q -l "$rebuilt" >/dev/null 2>&1; then
    rm -rf -- "$temp" || :
    error "Failed to verify the rebuilt $desc MINI.CAB!"
    return 1
  fi

  if ! mv -f -- "$rebuilt" "$cab"; then
    rm -rf -- "$temp" || :
    error "Failed to replace $desc MINI.CAB!"
    return 1
  fi

  rm -rf -- "$temp" || :

  return 0
}

stageWin9xDosPatcher() {

  local dir="$1"
  local desc="$2"
  local image="$3"
  local file

  if [ ! -f "$image" ]; then
    error "Failed to locate the Windows 9x DOS Patcher9x image!"
    return 1
  fi

  # The official Patcher9x DOS image carries the DJGPP executable together with
  # CWSDPMI. Keep both beside each other in the retained C:\SETUP source so the
  # patcher can run from real mode before Windows starts.
  for file in PATCH9X.EXE CWSDPMI.EXE; do

    rm -f -- "$dir/$file" || return 1

    if ! mcopy -o -i "$image" "::/$file" "$dir/$file" >/dev/null 2>&1 ||
      [ ! -s "$dir/$file" ]; then
      error "Failed to stage $file for $desc!"
      return 1
    fi

  done

  # Stage the marker under a dormant name. MSBATCH promotes it to PATCH9X.RUN
  # only during its late file-copy phase, leaving the already-working early
  # Setup reboots untouched. Win95/98 remove it in Win9x.FirstLogon; WinMe
  # keeps it through Setup and removes it from the post-setup stage.
  if ! printf 'Pending\r\n' > "$dir/PATCH9X.NEW"; then
    error "Failed to stage the Patcher9x run marker for $desc!"
    return 1
  fi

  return 0
}

stageWin9xSetupOverrides() {

  local dir="$1"
  local desc="$2"
  local qemouse="$3"
  local layout="$dir/LAYOUT.INF"
  local mouse="$qemouse/qemouse.drv"
  local scandisk="$dir/W9XSCAN.INI"
  local mouse_target="$dir/MOUSE.DRV"
  local scandisk_target="$dir/SCANDISK.INI"
  local layout_temp="$TMP/win9x-layout-files"
  local cab extracted existing layout_name
  local mouse_size scandisk_size
  local -a precopy_cabs=() other_cabs=() extracted_layouts=() layouts=()

  if [ ! -f "$mouse" ]; then
    error "Failed to locate qemouse.drv!"
    return 1
  fi

  if [ ! -f "$scandisk" ]; then
    error "Failed to locate the staged SCANDISK.INI configuration!"
    return 1
  fi

  # Make Setup's own source filenames contain our desired payloads. This avoids
  # competing CopyFiles destinations entirely: every normal Setup copy or later
  # reinstall of MOUSE.DRV/SCANDISK.INI resolves to these same loose files.
  if [ ! -s "$layout" ]; then
    extractWin9xCabFile "$dir" 'LAYOUT.INF' "$layout" "$desc" || return 1
  fi

  # Windows 98 splits its setup source map across LAYOUT.INF, LAYOUT1.INF and
  # LAYOUT2.INF. Stage every numbered LAYOUT file available in the cabinets, but
  # never overwrite an already-loose copy because earlier setup patches may have
  # modified it. Win95/Me simply keep whichever LAYOUT files their media carries.
  rm -rf -- "$layout_temp" || return 1
  mkdir -p "$layout_temp/files" || return 1

  mapfile -d '' precopy_cabs < <(
    find "$dir" -maxdepth 1 -type f -iname 'PRECOPY*.CAB' -print0 | sort -z
  )
  mapfile -d '' other_cabs < <(
    find "$dir" -maxdepth 1 -type f -iname '*.CAB' ! -iname 'PRECOPY*.CAB' -print0 | sort -z
  )

  for cab in "${precopy_cabs[@]}" "${other_cabs[@]}"; do

    rm -rf -- "$layout_temp/files" || return 1
    mkdir -p "$layout_temp/files" || return 1

    cabextract -q \
      -F 'LAYOUT*.INF' \
      -F 'layout*.inf' \
      -d "$layout_temp/files" "$cab" >/dev/null 2>&1 || :

    mapfile -d '' extracted_layouts < <(
      find "$layout_temp/files" -type f -iname 'LAYOUT*.INF' -print0 | sort -z
    )

    for extracted in "${extracted_layouts[@]}"; do

      layout_name=$(basename "$extracted")
      layout_name="${layout_name^^}"

      if [[ ! "$layout_name" =~ ^LAYOUT[0-9]*\.INF$ ]]; then
        continue
      fi

      existing=$(find "$dir" -maxdepth 1 -type f -iname "$layout_name" -print -quit) || return 1

      if [ -n "$existing" ] && [ -s "$existing" ]; then
        continue
      fi

      if [ -n "$existing" ]; then
        rm -f -- "$existing" || return 1
      fi

      if ! cp -f -- "$extracted" "$dir/$layout_name"; then
        rm -rf -- "$layout_temp" || :
        error "Failed to stage $layout_name from $desc setup files!"
        return 1
      fi

    done

  done

  rm -rf -- "$layout_temp" || return 1

  mapfile -d '' layouts < <(
    find "$dir" -maxdepth 1 -type f -iregex '.*/LAYOUT[0-9]*\.INF' -print0 | sort -z
  )

  if (( ${#layouts[@]} == 0 )); then
    error "Failed to locate the $desc setup source layout files!"
    return 1
  fi

  if ! cp -f -- "$mouse" "$mouse_target" ||
    ! cmp -s -- "$mouse" "$mouse_target"; then
    error "Failed to replace the $desc MOUSE.DRV setup source!"
    return 1
  fi

  if ! cp -f -- "$scandisk" "$scandisk_target" ||
    ! cmp -s -- "$scandisk" "$scandisk_target"; then
    error "Failed to replace the $desc SCANDISK.INI setup source!"
    return 1
  fi

  mouse_size=$(stat -c %s -- "$mouse_target") || return 1
  scandisk_size=$(stat -c %s -- "$scandisk_target") || return 1

  # Search the complete LAYOUT*.INF set for each stock source entry, then patch
  # the one file that owns it. Point that entry at disk 0 with no source
  # subdirectory and record the loose replacement's uncompressed size.
  if ! python3 - "$mouse_size" "$scandisk_size" "${layouts[@]}" <<'PY'
from pathlib import Path
import re
import sys

replacements = {
    b'MOUSE.DRV': int(sys.argv[1]),
    b'SCANDISK.INI': int(sys.argv[2]),
}
layouts = [Path(value) for value in sys.argv[3:]]
contents = {
    layout: layout.read_bytes().splitlines(keepends=True)
    for layout in layouts
}
changed = set()

for name, size in replacements.items():
    pattern = re.compile(
        br'^([ \t]*' + re.escape(name) + br'[ \t]*=[ \t]*)'
        br'[0-9]+,[^,\r\n]*,[0-9]+([^\r\n]*)(\r?\n)?$',
        re.IGNORECASE,
    )
    matches = []

    for layout, lines in contents.items():
        for index, line in enumerate(lines):
            match = pattern.match(line)
            if match:
                matches.append((layout, index, match))

    if len(matches) != 1:
        print(
            f"Unexpected {name.decode('ascii')} layout-entry count across "
            f"LAYOUT*.INF: {len(matches)} (expected 1).",
            file=sys.stderr,
        )
        raise SystemExit(1)

    layout, index, match = matches[0]
    contents[layout][index] = (
        match.group(1)
        + b'0,,'
        + str(size).encode('ascii')
        + match.group(2)
        + (match.group(3) or b'')
    )
    changed.add(layout)

for layout in changed:
    layout.write_bytes(b''.join(contents[layout]))

verify = {
    layout: layout.read_bytes().splitlines()
    for layout in layouts
}
for name, size in replacements.items():
    expected = re.compile(
        br'^[ \t]*' + re.escape(name) + br'[ \t]*=[ \t]*0,,'
        + str(size).encode('ascii')
        + br'(?:,|[ \t]*$)',
        re.IGNORECASE,
    )
    count = sum(
        bool(expected.match(line))
        for lines in verify.values()
        for line in lines
    )
    if count != 1:
        print(
            f"Failed to verify the {name.decode('ascii')} layout override "
            f"across LAYOUT*.INF.",
            file=sys.stderr,
        )
        raise SystemExit(1)
PY
  then
    error "Failed to update the $desc setup source layout!"
    return 1
  fi

  rm -f -- "$scandisk" || return 1
  return 0
}

stageWin9xFinalAutoexec() {

  local target="$1"
  local setup="$2"
  local options="$3"
  local desc="$4"
  local id="$5"

  local temp="$TMP/win9x-final-autoexec"
  local autoexec="$temp/AUTOEXEC.BAT"

  rm -rf -- "$temp" || return 1
  mkdir -p "$temp" || return 1

  if ! writeWin9xAutoexec "$autoexec" "$setup" "$options" "$id"; then
    rm -rf -- "$temp" || :
    return 1
  fi

  if ! cp -f -- "$autoexec" "$target/W9XAUTO.BAT" ||
    ! cmp -s -- "$autoexec" "$target/W9XAUTO.BAT"; then
    rm -rf -- "$temp" || :
    error "Failed to stage the final $desc AUTOEXEC.BAT source file!"
    return 1
  fi

  rm -rf -- "$temp" || :
  return 0
}

stageWin9xSharedShortcut() {

  local dir="$1"
  local desc="$2"
  local share="$3"
  local target="$dir/SHARED.LNK"

  # Use the native network PIDL layout from a Shell-generated Windows 98 link.
  # Keep that known-good structure byte-for-byte for the normal host.lan target,
  # and resize only its server/share PIDL items when Win95 needs the NetBIOS name.
  if ! python3 - "$target" "$share" <<'PY'
from pathlib import Path
import hashlib
import struct
import sys

target = Path(sys.argv[1])
share = sys.argv[2].encode('ascii')

template = bytes.fromhex(
    '4c0000000114020000000000c000000000000046410000001000000000000000'
    '0000000000000000000000000000000000000000000000000300000000000000'
    '0000000000000000000000003b0014001f2d602c8d20ea3a6910a2d708002b30'
    '309d10004000005c5c686f73742e6c616e001500c000005c5c686f73742e6c61'
    '6e5c446174610000001d00433a5c57494e444f57535c53595354454d5c534845'
    '4c4c33322e444c4c00000000'
)

if len(template) != 172:
    raise SystemExit('Native Shared link template size verification failed.')
if hashlib.sha256(template).hexdigest() != '5e5bbcc3e32b1dea7a7a742dc648f85d9aca801b874d60066899d770aa7700a5':
    raise SystemExit('Native Shared link template hash verification failed.')
if not share.startswith(b'\\\\'):
    raise SystemExit('Shared link target is not a UNC path.')

server, separator, name = share[2:].partition(b'\\')
if not server or not separator or not name or b'\\' in name:
    raise SystemExit('Shared link target must contain one server and one share name.')

# The working Win98 link contains a 20-byte Network Neighborhood root PIDL,
# followed by a server item (type 0x40) and a share item (type 0xC0).
header = template[:76]
old_id_size = struct.unpack_from('<H', template, 76)[0]
old_id_list = template[78:78 + old_id_size]
root_size = struct.unpack_from('<H', old_id_list, 0)[0]
root_item = old_id_list[:root_size]
tail = template[78 + old_id_size:]

if root_size != 20 or root_item != bytes.fromhex('14001f2d602c8d20ea3a6910a2d708002b30309d'):
    raise SystemExit('Native Shared link root PIDL verification failed.')

server_name = b'\\\\' + server + b'\0'
share_name = share + b'\0'
server_item = struct.pack('<H', 5 + len(server_name)) + b'\x40\x00\x00' + server_name
share_item = struct.pack('<H', 5 + len(share_name)) + b'\xc0\x00\x00' + share_name
id_list = root_item + server_item + share_item + b'\x00\x00'
link = header + struct.pack('<H', len(id_list)) + id_list + tail

# Rebuilding the normal Win98/Me target must reproduce the extracted working
# shortcut exactly; Win95 changes only the two variable PIDL strings and sizes.
if share == b'\\\\host.lan\\Data' and link != template:
    raise SystemExit('Native Shared link template reproduction failed.')

target.write_bytes(link)
data = target.read_bytes()

if data != link:
    raise SystemExit('Shared link write verification failed.')
if struct.unpack_from('<I', data, 20)[0] != 0x00000041:
    raise SystemExit('Shared link flags verification failed.')
if struct.unpack_from('<H', data, 76)[0] != len(id_list):
    raise SystemExit('Shared link PIDL size verification failed.')
if server_name not in data or share_name not in data:
    raise SystemExit('Shared link UNC target verification failed.')
if b'C:\\WINDOWS\\SYSTEM\\SHELL32.DLL' not in data:
    raise SystemExit('Shared link icon verification failed.')
PY
  then
    error "Failed to create the Shared desktop shortcut for $desc!"
    return 1
  fi

  return 0
}

writeWin9xAutoexec() {

  local output="$1"
  local setup="$2"
  local options="$3"
  local id="$4"
  local patch_options="-auto -unselect creg"

  [[ "${id,,}" == "win9x"* ]] && patch_options="-auto"

  {
    printf '%s\n' '@ECHO OFF'

    if [[ "${id,,}" == "win95"* ]]; then
      printf '%s\n' 'SET BLASTER=A220 I5 D1 T2'
    fi

    printf '%s\n' \
      'IF EXIST C:\WINDOWS\WIN.COM GOTO WINDOWS' \
      'ECHO.' \
      'ECHO Starting Windows Setup, please wait...' \
      'ECHO.' \
      "IF NOT EXIST C:\\${setup}\\XMSMMGR.EXE GOTO SETUP" \
      "IF NOT EXIST C:\\${setup}\\SMARTDRV.EXE GOTO SETUP" \
      "C:\\${setup}\\XMSMMGR.EXE >NUL" \
      "C:\\${setup}\\SMARTDRV.EXE C+ /Q 16384 16384 >NUL" \
      ':SETUP' \
      "C:\\${setup}\\SETUP.EXE $options" \
      'GOTO END' \
      ':WINDOWS' \
      'IF NOT EXIST C:\WINDOWS\SYSTEM\KERNEL32.DLL GOTO STARTWIN' \
      'IF NOT EXIST C:\WINDOWS\SYSTEM\VMM32.VXD GOTO STARTWIN'

    # WinMe RunServices may invoke WinMeBoot more than once during one Setup boot.
    # Clear its same-boot latch only here, at the next real AUTOEXEC boot boundary.
    if [[ "${id,,}" == "win9x"* ]]; then
      printf '%s\n' 'IF EXIST C:\SETUP\MEBOOT.BOOT DEL C:\SETUP\MEBOOT.BOOT >NUL'
    fi

    printf '%s\n' \
      'IF NOT EXIST C:\SETUP\PATCH9X.RUN GOTO STARTWIN' \
      'IF NOT EXIST C:\SETUP\PATCH9X.EXE GOTO STARTWIN' \
      'IF NOT EXIST C:\SETUP\CWSDPMI.EXE GOTO STARTWIN' \
      "CD C:\\SETUP" \
      "PATCH9X.EXE $patch_options C:\\WINDOWS\\SYSTEM >NUL" \
      "CD C:\\" \
      ':STARTWIN'

    if [[ "${id,,}" == "win95"* || "${id,,}" == "win98"* ]]; then
      printf '%s\n' 'C:\WINDOWS\WIN.COM'
    fi

    printf '%s\n' \
      ':END' \
      ''
  } | unix2dos > "$output" || return 1

  return 0
}

stageWinMeFinalBootFiles() {

  local dir="$1"
  local target="$2"
  local desc="$3"

  local temp="$TMP/winme-final-boot"
  local cbs winboot size signature

  rm -rf -- "$temp" || return 1
  mkdir -p "$temp/nettools" || return 1

  cbs=$(find "$dir" -type f -ipath '*/TOOLS/NETTOOLS/FAC/CBS.DTA' -print -quit) || return 1

  if [ -z "$cbs" ]; then
    rm -rf -- "$temp" || :
    error "Failed to locate the Windows Me NETTOOLS CBS.DTA archive!"
    return 1
  fi

  if ! cabextract -q -L -F 'WINBOOT.SYS' -d "$temp/nettools" "$cbs" >/dev/null 2>&1; then
    rm -rf -- "$temp" || :
    error "Failed to extract the Windows Me NETTOOLS WINBOOT.SYS!"
    return 1
  fi

  winboot=$(find "$temp/nettools" -type f -iname 'WINBOOT.SYS' -print -quit) || return 1

  if [ -z "$winboot" ] || [ ! -s "$winboot" ]; then
    rm -rf -- "$temp" || :
    error "Failed to locate the extracted Windows Me NETTOOLS WINBOOT.SYS!"
    return 1
  fi

  size=$(stat -c %s -- "$winboot") || return 1
  signature=$(dd if="$winboot" bs=1 count=2 status=none | od -An -tx1 | tr -d ' \n') || return 1

  if (( size != 118784 )) || [[ "${signature,,}" != "4d5a" ]]; then
    rm -rf -- "$temp" || :
    error "Unexpected Windows Me NETTOOLS WINBOOT.SYS format!"
    return 1
  fi

  if ! cp -f -- "$winboot" "$target/MEIO.SYS" ||
    ! cmp -s -- "$winboot" "$target/MEIO.SYS"; then
    rm -rf -- "$temp" || :
    error "Failed to stage the final Windows Me IO.SYS source file!"
    return 1
  fi

  if ! extractWin9xCabFile "$target" 'COMMAND.COM' "$target/MECOM.COM" "$desc" ||
    ! extractWin9xCabFile "$target" 'REGENV32.EXE' "$target/MEREGENV.EXE" "$desc"; then
    rm -rf -- "$temp" || :
    return 1
  fi

  # Enable the normal real-mode path in the localized Windows Me COMMAND.COM.
  # These are the three guarded substitutions used by the established Me DOS
  # mode patch; do not include its unrelated hidden-file display tweaks.
  if ! patchWinMeBinaryPatterns "$target/MECOM.COM" 'Windows Me COMMAND.COM' \
    '7510b80e' 'eb10b80e' \
    '0300750b8b' '0300eb0b8b' \
    '128b1608' '448b1608'; then
    rm -rf -- "$temp" || :
    return 1
  fi

  # REGENV32 otherwise rewrites CONFIG.SYS and AUTOEXEC.BAT on every restart.
  # Redirect those writes to .WIN files so our real-mode startup remains intact.
  if ! patchWinMeBinaryPatterns "$target/MEREGENV.EXE" 'Windows Me REGENV32.EXE' \
    '434f4e4649472e535953' '434f4e4649472e57494e' \
    '4155544f455845432e424154' '4155544f455845432e57494e'; then
    rm -rf -- "$temp" || :
    return 1
  fi

  rm -rf -- "$temp" || :
  return 0
}

extractWin9xCabFile() {

  local dir="$1"
  local name="$2"
  local output="$3"
  local desc="$4"

  local temp="$TMP/win9x-cab-file"
  local cab extracted find_pid
  local -a precopy_cabs=() other_cabs=()

  rm -rf -- "$temp" || return 1
  mkdir -p "$temp" || return 1
  rm -f -- "$output" || return 1

  mapfile -d '' precopy_cabs < <(
    find "$dir" -maxdepth 1 -type f -iname 'PRECOPY*.CAB' -print0
  )

  find_pid=$!

  if ! wait "$find_pid"; then
    rm -rf -- "$temp" || :
    error "Failed to enumerate $desc setup cabinets!"
    return 1
  fi

  mapfile -d '' other_cabs < <(
    find "$dir" -maxdepth 1 -type f -iname '*.CAB' ! -iname 'PRECOPY*.CAB' -print0
  )

  find_pid=$!

  if ! wait "$find_pid"; then
    rm -rf -- "$temp" || :
    error "Failed to enumerate $desc setup cabinets!"
    return 1
  fi

  for cab in "${precopy_cabs[@]}" "${other_cabs[@]}"; do

    rm -rf -- "$temp/files" || return 1
    mkdir -p "$temp/files" || return 1

    if ! cabextract -q -L -F "$name" -d "$temp/files" "$cab" >/dev/null 2>&1; then
      continue
    fi

    extracted=$(find "$temp/files" -type f -iname "$name" -print -quit) || return 1

    if [ -n "$extracted" ] && [ -s "$extracted" ]; then
      if ! cp -f -- "$extracted" "$output" || ! cmp -s -- "$extracted" "$output"; then
        rm -rf -- "$temp" || :
        error "Failed to extract $name from $desc setup files!"
        return 1
      fi

      rm -rf -- "$temp" || :
      return 0
    fi

  done

  rm -rf -- "$temp" || :
  error "Failed to locate $name in $desc setup cabinets!"
  return 1
}

patchWinMeBinaryPatterns() {

  local file="$1"
  local desc="$2"
  shift 2

  if (( $# == 0 || $# % 2 != 0 )); then
    error "Invalid binary patch definition for $desc!"
    return 1
  fi

  if ! python3 - "$file" "$desc" "$@" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
desc = sys.argv[2]
args = sys.argv[3:]

data = path.read_bytes()
original = data

for index in range(0, len(args), 2):
    old = bytes.fromhex(args[index])
    new = bytes.fromhex(args[index + 1])

    if len(old) != len(new):
        print(f"Invalid {desc} patch length.", file=sys.stderr)
        raise SystemExit(1)

    count = data.count(old)
    if count != 1:
        print(
            f"Unexpected {desc} patch signature count for {args[index]}: {count} (expected 1).",
            file=sys.stderr,
        )
        raise SystemExit(1)

    data = data.replace(old, new, 1)

if data == original:
    print(f"No changes were made while patching {desc}.", file=sys.stderr)
    raise SystemExit(1)

path.write_bytes(data)
PY
  then
    error "Failed to patch $desc!"
    return 1
  fi

  return 0
}

stageWinMeBootActivation() {

  local dir="$1"
  local desc="$2"
  local target="$dir/MEBOOT.BAT"

  # RunServices can invoke this more than once during a single Setup boot.
  # MEBOOT.BOOT is a same-boot latch cleared by AUTOEXEC on the next real reboot;
  # MEBOOT1.RUN persists across that boundary so activation occurs only then.
  {
    printf '%s\n' \
      '@ECHO OFF' \
      'IF EXIST C:\SETUP\MEBOOT.RUN GOTO END' \
      'IF EXIST C:\SETUP\MEBOOT.BOOT GOTO END' \
      'ECHO 1>C:\SETUP\MEBOOT.BOOT' \
      'IF EXIST C:\SETUP\MEBOOT1.RUN GOTO ACTIVATE' \
      'ECHO 1>C:\SETUP\MEBOOT1.RUN' \
      'GOTO END' \
      ':ACTIVATE' \
      'IF NOT EXIST C:\SETUP\MEREGENV.EXE GOTO END' \
      'IF NOT EXIST C:\SETUP\MECOM.COM GOTO END' \
      'IF NOT EXIST C:\SETUP\MEIO.SYS GOTO END' \
      'IF NOT EXIST C:\WINDOWS\COMMAND\ATTRIB.EXE GOTO END' \
      'COPY /Y C:\SETUP\MEREGENV.EXE C:\WINDOWS\SYSTEM\REGENV32.EXE >NUL' \
      'IF ERRORLEVEL 1 GOTO END' \
      'COPY /Y C:\SETUP\MECOM.COM C:\WINDOWS\COMMAND.COM >NUL' \
      'IF ERRORLEVEL 1 GOTO END' \
      'COPY /Y C:\SETUP\MECOM.COM C:\COMMAND.COM >NUL' \
      'IF ERRORLEVEL 1 GOTO END' \
      'C:\WINDOWS\COMMAND\ATTRIB.EXE -R -S -H C:\IO.SYS >NUL' \
      'IF ERRORLEVEL 1 GOTO END' \
      'COPY /Y C:\SETUP\MEIO.SYS C:\IO.SYS >NUL' \
      'IF ERRORLEVEL 1 GOTO IOFAIL' \
      'C:\WINDOWS\COMMAND\ATTRIB.EXE +R +S +H C:\IO.SYS >NUL' \
      'ECHO 1>C:\SETUP\MEBOOT.RUN' \
      'GOTO END' \
      ':IOFAIL' \
      'C:\WINDOWS\COMMAND\ATTRIB.EXE +R +S +H C:\IO.SYS >NUL' \
      ':END' \
      ''
  } | unix2dos > "$target" || {
    error "Failed to create the Windows Me boot activation script for $desc!"
    return 1
  }

  return 0
}

stageWinMePowerPolicy() {

  local dir="$1"
  local desc="$2"
  local target="$dir/MEPOWER.EXE"

  # Read WinMe's existing global power policy through POWRPROF.DLL, change only
  # the AC/DC power-button actions to ShutdownOff, then write the policy back.
  # This preserves all other Setup-selected power-policy fields.
  if ! base64 -d <<'EOF' | gzip -dc > "$target"
H4sIAAAAAAACA/ONqmBgZGBgYGFABQ4MhEEFEPPJ7+Jj2MJ5VnEHo89ZxZCMzGKFgqL89KLEXIXk
xLy8/BKFpFSFotI8hcw8BRf/YIXc/JRUPRUGhgBXBgYfRmaGGT+bs2DmPWBgYuRm5GNgYEJykAAU
w1wFYjMhpFmQHQzlMME0CiDTSMaAgAIDgw0+zxkwMIgwkA4CFPDr0ytJrSgB0j4wBzFhBj7QiAS9
opTEkkQGhl1QAbA6Now4ctArSs3JT4baaQBVx4GhzolhFIwCLCCs8c0BINX5LOy/aISCA0PLgVKO
LMb/ogFA9g5Qeut0UWEBYgGgfAxMngkin8UAoRuPgIyIO3xmFAw5YKOASAsLFCDllwuS2FogO0IB
e9pJgYoXAekOBdxiDAyuFZklAUX5yanFxUBeUGpiintOflJiTkB5UUB+TmZyJVA0vCizJBVD2Ns1
yM/Vx9hILyUnhyHAPzwoIMjfDcwZBVQBApC6g8dAwkDHwMLAwWA0SEYSAACNZnNTAAoAAA==
EOF
  then
    error "Failed to create MEPOWER.EXE in $desc setup files!"
    return 1
  fi

  if [ "$(wc -c < "$target")" -ne 2560 ]; then
    error "Failed to verify MEPOWER.EXE in $desc setup files!"
    return 1
  fi

  return 0
}

stageWinMeFinalSetup() {

  local dir="$1"
  local desc="$2"
  local target="$dir/MEFINAL.BAT"

  {
    printf '%s\n' \
      '@ECHO OFF' \
      'C:\WINDOWS\RUNDLL.EXE SETUPX.DLL,InstallHinfSection WinMe.FinalSetup 4 C:\WINDOWS\MSBATCH.INF' \
      'C:\WINDOWS\MEPOWER.EXE' \
      'C:\WINDOWS\WIN9XDMA.EXE' \
      'IF EXIST C:\WINDOWS\DESKTOP\ONLINE~1 C:\WINDOWS\COMMAND\DELTREE.EXE /Y C:\WINDOWS\DESKTOP\ONLINE~1 >NUL' \
      'ECHO DONE>C:\WINDOWS\MEFINAL.DONE'

  } | unix2dos > "$target" || {
    error "Failed to create final Windows Me setup script for $desc!"
    return 1
  }

  return 0
}

writeWin9xAnswerFile() {

  local target="$1"
  local id="$2"
  local setup="$3"
  local monitor="$4"
  local batchHost="$5"
  local batchUsername="$6"
  local batchOrganization="$7"
  local batchWorkgroup="$8"
  local batchKey="$9"
  local shortcut="${10}"
  local install="${11}"
  local timezone="${12}"
  local share="${13}"

  local addReg="OPKInstall,Win9x.Machine,Win9x.PCMCIA,Win9x.Power,Win9x.UserDefault,Win9x.BrowserDefault,Win9x.ActiveSetup"
  local updateInis="Win9x.SystemIni,Win9x.SystemCb"
  local firstLogonAddReg="Win9x.User,Win9x.Regwiz,Win9x.BrowserUser,Win9x.PowerUser"
  local firstLogonDelReg="Win9x.Welcome,Win9x.MSN,Win9x.ICWDesktop"
  local firstLogonDelFiles="Win9x.PatcherMarker,Win9x.Connect,Win9x.ConnectAll,Win9x.OnlineServices"
  local firstLogonUpdateInis="Win9x.OnlineServicesFolder"
  local copyFiles="" post="" hide="" installDelReg=""
  local culture region keyboard localeID keyboardID

  if [[ "${id,,}" == "win9x"* ]]; then
    addReg="${addReg%,Win9x.ActiveSetup},WinMe.ActiveSetup"
    firstLogonAddReg="Win9x.Regwiz"
    firstLogonDelReg="Win9x.Welcome"
    firstLogonDelFiles=""
    firstLogonUpdateInis=""
    updateInis+=",WinMe.MouseInf"
  elif [[ "${id,,}" == "win95"* || "${id,,}" == "win98"* ]]; then
    firstLogonDelFiles="${firstLogonDelFiles/Win9x.PatcherMarker,/}"
  fi

  addReg+=",Win9x.Shutdown"

  if [[ "${id,,}" == "win95"* ]]; then
    addReg+=",Win95.DisplayMode,Win95.PCINIC,Win95.Welcome"
    firstLogonAddReg+=",Win95.SuspendMenu,Win95.InternetIcon"
    firstLogonUpdateInis=""
    installDelReg="Win95.InitShell,Win9x.Welcome"
  fi

  culture=$(getLanguage "$LANGUAGE" "culture") || return 1
  [ -z "$culture" ] && culture="en-US"
  region="${REGION:-$culture}"
  keyboard="${KEYBOARD:-en-US}"
  localeID=$(getLocaleID "$region") || return 1
  keyboardID=$(getKeyboardID "$keyboard") || return 1

  if ! disabled "$AUTOLOGIN"; then
    copyFiles+=",Win9x.Password"
  fi

  if [ -n "$install" ] || [[ "${id,,}" == "win95"* || "${id,,}" == "win9x"* ]]; then
    post="Y"
    copyFiles+=",Win9x.Post"
  fi

  if [[ "${id,,}" == "win9x"* ]]; then
    copyFiles+=",WinMe.Final,WinMe.Power,WinMe.Wait"
  fi

  if enabled "$shortcut" || [ -n "$install" ] || [[ "${id,,}" == "win95"* || "${id,,}" == "win9x"* ]]; then
    hide="Y"
    copyFiles+=",Win9x.Hide"
  fi

  if enabled "$shortcut"; then
    copyFiles+=",Win9x.SharedShortcut"
  fi

  addReg+=",OEMDrivers"

  if [[ "${id,,}" == "win9x"* ]]; then
    addReg+=",WinMe.BootService"
  fi

  # Every supported Windows 95 release is OSR2 or newer, so the same DMA
  # helper is used for Windows 95, Windows 98 and Windows Me.
  addReg+=",Win9x.StorageActiveSetup"
  copyFiles+=",Win9x.DMA"

  # Enable the installed-system repatch only in the late MSBATCH file-copy
  # phase. The temporary AUTOEXEC already checks PATCH9X.RUN, so earlier Setup
  # reboots continue exactly as before this change.
  copyFiles+=",Win9x.PatcherEnable"

  # Strip the leading separator left by the common CopyFiles append logic.
  copyFiles="${copyFiles#,}"

  # Cap the memory Win9x itself can address at 4 GiB without changing QEMU's
  # RAM_SIZE. Setup may use SYSTEM.CB for its minimal protected-mode/fallback
  # startup, so keep the limit in both SYSTEM.INI and SYSTEM.CB.
  {
    printf '%s\n' \
      '[BatchSetup]' \
      'Version=3.0 (32-bit)' \
      '' \
      '[Version]' \
      "Signature=\"\$CHICAGO\$\"" \
      'AdvancedINF=2.5' \
      'LayoutFile=layout.inf' \
      '' \
      '[SourceDisksNames]' \
      '22="Windows Setup",,0' \
      '' \
      '[SourceDisksFiles]' \
      'PATCH9X.NEW=22' \
      'WIN9XDMA.EXE=22'

    if [[ "${id,,}" == "win9x"* ]]; then
      printf '%s\n' \
        'MEFINAL.BAT=22' \
        'MEPOWER.EXE=22' \
        'WAIT.EXE=22'
    fi

    if ! disabled "$AUTOLOGIN"; then
      printf '%s\n' 'DOCKER.PWL=22'
    fi

    if enabled "$hide"; then
      printf '%s\n' 'HIDE.EXE=22'
    fi

    if enabled "$shortcut"; then
      printf '%s\n' 'SHARED.LNK=22'
    fi

    if enabled "$post"; then
      if [[ "${id,,}" == "win95"* ]]; then
        printf '%s\n' 'POST9X.BAT=22'
      else
        printf '%s\n' \
          'POST9X.BAT=22' \
          'POST9X.NEW=22' \
          'POST9X.REG=22'
      fi
    fi

    printf '%s\n' \
      '' \
      '[Install]' \
      "CopyFiles=$copyFiles" \
      "UpdateInis=$updateInis" \
      "AddReg=$addReg"

    if [ -n "$installDelReg" ]; then
      printf '%s\n' "DelReg=$installDelReg"
    fi

    printf '%s\n' \
      '' \
      '[OPKInstall]' \
      'HKLM,"SOFTWARE\Microsoft\Windows\CurrentVersion","ProductId",,"12345-OEM-1234567-12345"' \
      'HKLM,"SOFTWARE\Microsoft\Windows\CurrentVersion","ProductKey",,"CDKey"' \
      "HKLM,\"SOFTWARE\Microsoft\Windows\CurrentVersion\",\"RegisteredOwner\",,\"$batchUsername\"" \
      "HKLM,\"SOFTWARE\Microsoft\Windows\CurrentVersion\",\"RegisteredOrganization\",,\"$batchOrganization\""

    if [[ "${id,,}" == "win95"* ]] && enabled "$post"; then
      printf '%s\n' \
        'HKLM,"SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce","Win9xSetup",,"C:\WINDOWS\HIDE.EXE C:\WINDOWS\COMMAND.COM /C C:\WINDOWS\POST9X.BAT"'
    else
      printf '%s\n' \
        'HKLM,"SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce","Win9xSetup",,"%25%\rundll.exe setupx.dll,InstallHinfSection Win9x.FirstLogon 4 %10%\msbatch.inf"'
    fi

    if enabled "$shortcut"; then
      printf '%s\n' \
        "HKLM,\"SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Run\",\"SharedDrive\",,\"C:\\WINDOWS\\HIDE.EXE C:\\WINDOWS\\NET.EXE USE Z: $share\""
    fi

    if enabled "$post" && [[ "${id,,}" != "win95"* ]]; then
      printf '%s\n' \
        'HKLM,"SOFTWARE\Microsoft\Windows\CurrentVersion\Run","PostSetup",,"C:\WINDOWS\HIDE.EXE C:\WINDOWS\COMMAND.COM /C C:\WINDOWS\POST9X.BAT"'
    fi

    if ! disabled "$AUTOLOGIN"; then
      printf '%s\n' \
        'HKLM,"Network\Logon","UserProfiles",0x00010001,0' \
        'HKLM,"Network\Logon","username",,"Docker"'
    fi

    printf '%s\n' ''
    writeWin9xMachineRegistry

    printf '%s\n' \
      '' \
      '[Win9x.Shutdown]' \
      'HKLM,"System\CurrentControlSet\Control\Shutdown","FastReboot",,"0"' \
      '' \
      '[Win9x.PCMCIA]' \
      'HKLM,"System\CurrentControlSet\Services\Class\PCMCIA","SkipWizardForBatchSetup",,1' \
      '' \
      '[OEMDrivers]' \
      "HKLM,\"SOFTWARE\\Microsoft\\Windows\\CurrentVersion\",\"OtherDevicePath\",,\"C:\\WINDOWS\\INF\\OTHER;C:\\$setup\""

    if [[ "${id,,}" == "win95"* ]]; then
      printf '%s\n' \
        '' \
        '[Win95.DisplayMode]' \
        'HKLM,"Config\0001\Display\Settings","BitsPerPixel",,"16"' \
        "HKLM,\"Config\\0001\\Display\\Settings\",\"Resolution\",,\"$WIDTH,$HEIGHT\"" \
        '' \
        '[Win95.PCINIC]' \
        'HKLM,"System\CurrentControlSet\Services\Class\Net\0000","DisableWarning",,"1"' \
        '' \
        '[Win95.SuspendMenu]' \
        'HKLM,"Enum\Root\*PNP0C05\0000","APMMenuSuspend",1,00' \
        '' \
        '[Win95.InternetIcon]' \
        'HKCR,"CLSID\{FBF23B42-E3F0-101B-8488-00AA003E56F8}\Shell\Open\Command",,,"""C:\Program Files\Internet Explorer\IEXPLORE.EXE"""'
    fi

    if [[ "${id,,}" == "win9x"* ]]; then
      printf '%s\n' \
        '' \
        '[WinMe.BootService]' \
        'HKLM,"SOFTWARE\Microsoft\Windows\CurrentVersion\RunServices","WinMeBoot",,"C:\SETUP\HIDE.EXE C:\SETUP\MECOM.COM /C C:\SETUP\MEBOOT.BAT"' \
        '' \
        '[WinMe.ActiveSetup]' \
        'HKLM,"SOFTWARE\Microsoft\Active Setup\Installed Components\~BatchSetupx",,,">Batch 9x - General Settings"' \
        'HKLM,"SOFTWARE\Microsoft\Active Setup\Installed Components\~BatchSetupx","IsInstalled",0x00000001,01,00,00,00' \
        'HKLM,"SOFTWARE\Microsoft\Active Setup\Installed Components\~BatchSetupx","Version",,"3,0,0,0"' \
        'HKLM,"SOFTWARE\Microsoft\Active Setup\Installed Components\~BatchSetupx","StubPath",,"%10%\HIDE.EXE %10%\COMMAND.COM /C %10%\MEFINAL.BAT"' \
        'HKLM,"SOFTWARE\Microsoft\Active Setup\Installed Components\~BatchWaitx",,,">Batch 9x - Final Settings Wait"' \
        'HKLM,"SOFTWARE\Microsoft\Active Setup\Installed Components\~BatchWaitx","IsInstalled",0x00000001,01,00,00,00' \
        'HKLM,"SOFTWARE\Microsoft\Active Setup\Installed Components\~BatchWaitx","Version",,"3,0,0,0"' \
        'HKLM,"SOFTWARE\Microsoft\Active Setup\Installed Components\~BatchWaitx","StubPath",,"%10%\WAIT.EXE C:\WINDOWS\MEFINAL.DONE"'
    fi

    printf '%s\n' \
      '' \
      '[Win9x.FirstLogon]' \
      "AddReg=$firstLogonAddReg"

    if [ -n "$firstLogonDelReg" ]; then
      printf '%s\n' "DelReg=$firstLogonDelReg"
    fi

    if [ -n "$firstLogonDelFiles" ]; then
      printf '%s\n' "DelFiles=$firstLogonDelFiles"
    fi

    if [[ "${id,,}" == "win98"* ]]; then
      [ -n "$firstLogonUpdateInis" ] && firstLogonUpdateInis+=","
      firstLogonUpdateInis+="Win9x.PatcherCleanup"
    fi

    if [[ "${id,,}" != "win95"* ]]; then
      [ -n "$firstLogonUpdateInis" ] && firstLogonUpdateInis+=","
      firstLogonUpdateInis+="Win9x.AutoexecFinal"
    fi

    if enabled "$post" && [[ "${id,,}" != "win95"* ]]; then
      [ -n "$firstLogonUpdateInis" ] && firstLogonUpdateInis+=","
      firstLogonUpdateInis+="Win9x.PostMarker"
    fi

    if [ -n "$firstLogonUpdateInis" ]; then
      printf '%s\n' "UpdateInis=$firstLogonUpdateInis"
    fi

    printf '%s\n' ''
    writeWin9xUserRegistry "$id"

    printf '%s\n' ''
    writeWin9xBrowserPowerRegistry

    printf '%s\n' ''
    writeWin9xStorageRegistry

    printf '%s\n' ''
    writeWin9xCleanupRegistry

    if [[ "${id,,}" == "win9x"* ]]; then
      printf '%s\n' \
        '' \
        '[WinMe.FinalSetup]' \
        'AddReg=Win9x.User,Win9x.BrowserUser,Win9x.PowerUser' \
        'DelReg=Win9x.MSN,Win9x.ICWDesktop' \
        'DelFiles=Win9x.Connect,Win9x.ConnectAll,Win9x.OnlineServices,WinMe.MediaPlayer,WinMe.MediaPlayerAll' \
        '' \
        '[WinMe.MouseInf]' \
        '%17%\msmouse.inf,Std.Copy,"mouse.drv"' \
        '' \
        '[WinMe.MediaPlayer]' \
        '"Windows Media Player.lnk"' \
        '' \
        '[WinMe.MediaPlayerAll]' \
        '"Windows Media Player.lnk"' \
        '' \
        '[WinMe.Final]' \
        'MEFINAL.BAT' \
        '' \
        '[WinMe.Power]' \
        'MEPOWER.EXE' \
        '' \
        '[WinMe.Wait]' \
        'WAIT.EXE'
    fi

    printf '%s\n' \
      '' \
      '[Win9x.PatcherEnable]' \
      'PATCH9X.RUN,PATCH9X.NEW,,4' \
      '' \
      '[Win9x.PatcherMarker]' \
      'PATCH9X.RUN' \
      '' \
      '[Win9x.AutoexecFinal]' \
      '%10%\wininit.ini,Rename,,"C:\AUTOEXEC.BAT=C:\SETUP\W9XAUTO.BAT"'

    if ! disabled "$AUTOLOGIN"; then
      printf '%s\n' \
        '' \
        '[Win9x.Password]' \
        'DOCKER.PWL'
    fi

    if enabled "$hide"; then
      printf '%s\n' \
        '' \
        '[Win9x.Hide]' \
        'HIDE.EXE'
    fi

    if [[ "${id,,}" == "win95"* || "${id,,}" == "win98"* ]]; then
      printf '%s\n' \
        '' \
        '[Win9x.PatcherCleanup]' \
        '%10%\wininit.ini,Rename,,"NUL=C:\SETUP\PATCH9X.RUN"'
    fi

    if enabled "$post"; then
      if [[ "${id,,}" == "win95"* ]]; then
        printf '%s\n' \
          '' \
          '[Win9x.Post]' \
          'POST9X.BAT'
      else
        printf '%s\n' \
          '' \
          '[Win9x.Post]' \
          'POST9X.BAT' \
          'POST9X.NEW' \
          'POST9X.REG' \
          '' \
          '[Win9x.PostMarker]' \
          '%10%\wininit.ini,Rename,,"C:\WINDOWS\POST9X.RDY=C:\WINDOWS\POST9X.NEW"'
      fi
    fi

    printf '%s\n' \
      '' \
      '[Win9x.DMA]' \
      'WIN9XDMA.EXE'

    printf '%s\n' \
      '' \
      '[DestinationDirs]' \
      'Win9x.PatcherEnable=30,SETUP' \
      'Win9x.PatcherMarker=30,SETUP' \
      'Win9x.Connect=10,Desktop' \
      'Win9x.ConnectAll=10,alluse~1\desktop' \
      'Win9x.OnlineServices=10,Desktop\Online~1'

    if [[ "${id,,}" == "win9x"* ]]; then
      printf '%s\n' \
        'WinMe.Final=10' \
        'WinMe.Power=10' \
        'WinMe.Wait=10' \
        'WinMe.MediaPlayer=10,Desktop' \
        'WinMe.MediaPlayerAll=10,alluse~1\desktop'
    fi

    if enabled "$hide"; then
      printf '%s\n' 'Win9x.Hide=10'
    fi

    if enabled "$shortcut"; then
      printf '%s\n' 'Win9x.SharedShortcut=10,Desktop'
    fi

    if ! disabled "$AUTOLOGIN"; then
      printf '%s\n' 'Win9x.Password=10'
    fi

    if enabled "$post"; then
      printf '%s\n' 'Win9x.Post=10'
    fi

    printf '%s\n' 'Win9x.DMA=10'

    if enabled "$shortcut"; then
      printf '%s\n' \
        '' \
        '[Win9x.SharedShortcut]' \
        'SHARED.LNK'
    fi

    printf '%s\n' \
      '' \
      '[Win9x.SystemIni]' \
      '%10%\system.ini,386Enh,,"MaxPhysPage=100000"' \
      '%10%\system.ini,vcache,,"MaxFileCache=65536"'

    if ! disabled "$AUTOLOGIN"; then
      printf '%s\n' '%10%\system.ini,"Password Lists",,"DOCKER=C:\WINDOWS\DOCKER.PWL"'
    fi

    printf '%s\n' \
      '' \
      '[Win9x.SystemCb]' \
      '%10%\system.cb,386Enh,,"MaxPhysPage=100000"' \
      '' \
      '[Setup]' \
      'Express=1' \
      'InstallDir="C:\WINDOWS"' \
      'InstallType=3'

    # When KEY is supplied, pass it through so retail media does not stop later
    # for the product-key dialog. Leave it absent otherwise because some OEM
    # media handles its product identification differently.
    if [ -n "$batchKey" ]; then
      printf 'ProductKey="%s"\n' "$batchKey"
    fi

    printf '%s\n' \
      'EBD=0' \
      'ShowEula=0' \
      'Network=1' \
      'DevicePath=1' \
      'NoPrompt2Boot=1' \
      "TimeZone=$timezone" \
      'System=0' \
      'Display=0' \
      'PenWinWarning=0' \
      '' \
      '[OptionalComponents]'

    if [[ "${id,,}" == "win98"* ]]; then
      printf '%s\n' \
        '"America Online"=0' \
        '"AT&T WorldNet Service"=0' \
        '"CompuServe"=0' \
        '"Prodigy Internet"=0'
    elif [[ "${id,,}" == "win9x"* ]]; then
      printf '%s\n' \
        '"America Online"=0' \
        '"AT&T WorldNet Service"=0' \
        '"Prodigy Internet"=0' \
        '"EarthLink"=0'
    fi

    printf '%s\n' \
      '"The Microsoft Network"=0' \
      '"Online Services"=0' \
      '' \
      '[NameAndOrg]' \
      "Name=\"$batchUsername\"" \
      "Org=\"$batchOrganization\"" \
      'Display=0' \
      '' \
      '[System]' \
      "Locale=L$localeID" \
      "SelectedKeyboard=KEYBOARD_$keyboardID" \
      "DisplChar=16,$WIDTH,$HEIGHT" \
      "Monitor=\"$monitor\"" \
      '' \
      '[Network]' \
      "ComputerName=\"$batchHost\"" \
      "Workgroup=\"$batchWorkgroup\"" \
      'PrimaryLogon=Windows' \
      'DefaultProtocol=MSTCP' \
      'Clients=VREDIR' \
      'Protocols=MSTCP'

    if [[ "${id,,}" == "win95"* ]]; then
      printf '%s\n' \
        'NetCards=PCI\VEN_1022&DEV_2000' \
        'IgnoreDetectedNetCards=1' \
        'ValidateNetCardResources=0'
    fi

    printf '%s\n' \
      'Display=0' \
      '' \
      '[MSTCP]' \
      'DHCP=1' \
      '' \
      '[VREDIR]' \
      'ValidatedLogon=0' \
      ''

    if [[ "${id,,}" == "win95"* ]]; then
      printf '%s\n' '[Printers]'
    fi
  } | unix2dos > "$target/MSBATCH.INF" || return 1

  return 0
}

writeWin9xUserRegistry() {

  local id="$1"

  printf '%s\n' \
    '[Win9x.UserDefault]' \
    'HKU,".DEFAULT\Control Panel\Desktop","SCRNSAVE.EXE",,""' \
    'HKU,".DEFAULT\Control Panel\Desktop","ScreenSaveActive",,"0"' \
    'HKU,".DEFAULT\Control Panel\Desktop","DragFullWindows",,"1"' \
    'HKU,".DEFAULT\Control Panel\Desktop","MenuShowDelay",,"100"' \
    'HKU,".DEFAULT\Control Panel\Desktop","FontSmoothing",,"1"' \
    'HKU,".DEFAULT\Control Panel\Desktop","SmoothScroll",0x00010001,0' \
    'HKU,".DEFAULT\Control Panel\Desktop\WindowMetrics","MinAnimate",,"0"' \
    'HKU,".DEFAULT\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced","HideFileExt",0x00010001,0' \
    'HKU,".DEFAULT\Software\Microsoft\Windows\CurrentVersion\Explorer\CabinetState","Settings",1,0c,00,02,00,0a,01,00,00,60,00,00,00' \
    'HKU,".DEFAULT\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer","NoActiveDesktop",0x00010001,1' \
    'HKU,".DEFAULT\Software\Microsoft\Windows\CurrentVersion\Explorer","link",1,00,00,00,00'

  if ! disabled "$AUTOLOGIN"; then
    printf '%s\n' \
      'HKU,".DEFAULT\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer","NoLogOff",0x00010001,1'

    if [[ "${id,,}" == "win9x"* ]]; then
      printf '%s\n' \
        'HKU,".DEFAULT\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced","StartMenuLogoff",0x00010001,0' \
        'HKU,".DEFAULT\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer","StartMenuLogOff",0x00010001,1'
    fi
  fi

  printf '%s\n' \
    '' \
    '[Win9x.User]' \
    'HKCU,"Control Panel\Desktop","SCRNSAVE.EXE",,""' \
    'HKCU,"Control Panel\Desktop","ScreenSaveActive",,"0"' \
    'HKCU,"Control Panel\Desktop","DragFullWindows",,"1"' \
    'HKCU,"Control Panel\Desktop","MenuShowDelay",,"100"' \
    'HKCU,"Control Panel\Desktop","FontSmoothing",,"1"' \
    'HKCU,"Control Panel\Desktop","SmoothScroll",0x00010001,0' \
    'HKCU,"Control Panel\Desktop\WindowMetrics","MinAnimate",,"0"' \
    'HKCU,"Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced","HideFileExt",0x00010001,0' \
    'HKCU,"Software\Microsoft\Windows\CurrentVersion\Explorer\CabinetState","Settings",1,0c,00,02,00,0a,01,00,00,60,00,00,00' \
    'HKCU,"Software\Microsoft\Windows\CurrentVersion\Policies\Explorer","NoActiveDesktop",0x00010001,1' \
    'HKCU,"Software\Microsoft\Windows\CurrentVersion\Explorer","link",1,00,00,00,00'

  if ! disabled "$AUTOLOGIN"; then
    printf '%s\n' \
      'HKCU,"Software\Microsoft\Windows\CurrentVersion\Policies\Explorer","NoLogOff",0x00010001,1'

    if [[ "${id,,}" == "win9x"* ]]; then
      printf '%s\n' \
        'HKCU,"Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced","StartMenuLogoff",0x00010001,0' \
        'HKCU,"Software\Microsoft\Windows\CurrentVersion\Policies\Explorer","StartMenuLogOff",0x00010001,1'
    fi
  fi
}

writeWin9xMachineRegistry() {

  printf '%s\n' \
    '[Win9x.Machine]' \
    'HKU,".DEFAULT\Control Panel\Desktop","FontSmoothing",,"1"' \
    'HKLM,"Software\Microsoft\Windows\CurrentVersion\FS Templates",,,"Server"' \
    'HKLM,"Software\Microsoft\Windows\CurrentVersion\FS Templates\Server","NameCache",1,a9,0a,00,00' \
    'HKLM,"Software\Microsoft\Windows\CurrentVersion\FS Templates\Server","PathCache",1,40,00,00,00' \
    'HKLM,"System\CurrentControlSet\Control\FileSystem","NameCache",1,a9,0a,00,00' \
    'HKLM,"System\CurrentControlSet\Control\FileSystem","PathCache",1,40,00,00,00' \
    'HKLM,"System\CurrentControlSet\Control\FileSystem","ReadAheadThreshold",1,00,00,01,00' \
    'HKLM,"System\CurrentControlSet\Control\FileSystem\CDFS","CacheSize",1,ac,09,00,00' \
    'HKLM,"System\CurrentControlSet\Control\FileSystem\CDFS","Prefetch",1,e4,00,00,00' \
    'HKLM,"Software\Microsoft\Windows\CurrentVersion\Policies\Explorer","NoDevMgrUpdate",0x00010001,1' \
    'HKLM,"Software\Microsoft\Windows\CurrentVersion\Policies\Explorer","NoWindowsUpdate",0x00010001,1'
}

writeWin9xBrowserPowerRegistry() {

  printf '%s\n' \
    '[Win9x.Power]' \
    'HKLM,"Software\Microsoft\Windows\CurrentVersion\Controls Folder\PowerCfg\PowerPolicies\3","Policies",0x00000001,01,00,00,00,02,00,00,00,02,00,00,00,02,00,00,00,02,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,32,32,00,00,02,00,00,00,04,00,00,c0,00,00,00,00,02,00,00,00,04,00,00,c0,00,00,00,00' \
    'HKU,".DEFAULT\Control Panel\PowerCfg","CurrentPowerPolicy",,"3"' \
    'HKU,".DEFAULT\Control Panel\PowerCfg\PowerPolicies\3","Policies",0x00000001,01,00,00,00,02,00,00,00,01,00,00,00,00,00,00,00,02,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,32,32,00,00,04,00,00,00,05,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,01,64,64,64,64,00,00' \
    '' \
    '[Win9x.BrowserDefault]' \
    'HKU,".DEFAULT\Software\Microsoft\Internet Connection Wizard","Completed",1,01,00,00,00' \
    'HKU,".DEFAULT\Software\Microsoft\Internet Connection Wizard","DesktopChanged",0x00010001,1' \
    'HKU,".DEFAULT\Software\Microsoft\Windows\CurrentVersion\Internet Settings","EnableAutodial",0x00010001,0' \
    'HKU,".DEFAULT\Software\Microsoft\Windows\CurrentVersion\Internet Settings","NoNetAutodial",0x00010001,0' \
    'HKU,".DEFAULT\Software\Microsoft\Windows\CurrentVersion\Internet Settings","ProxyEnable",0x00010001,0' \
    'HKU,".DEFAULT\Software\Microsoft\Internet Explorer\Main","Start Page",,"http://www.google.com"' \
    'HKU,".DEFAULT\Software\Microsoft\Internet Explorer\Main","First Home Page",,"http://www.google.com"' \
    'HKU,".DEFAULT\Software\Microsoft\Internet Explorer\Main","Default_Page_URL",,"http://www.google.com"' \
    'HKU,".DEFAULT\Software\Microsoft\Internet Explorer\Main","Search Page",,"http://www.google.com"' \
    'HKU,".DEFAULT\Software\Microsoft\Internet Explorer\Main","Search Bar",,"http://www.google.com"' \
    '' \
    '[Win9x.ActiveSetup]' \
    'HKLM,"SOFTWARE\Microsoft\Active Setup\Installed Components\>BatchSetupx",,,">Batch 9x - General Settings"' \
    'HKLM,"SOFTWARE\Microsoft\Active Setup\Installed Components\>BatchSetupx","IsInstalled",0x00000001,01,00,00,00' \
    'HKLM,"SOFTWARE\Microsoft\Active Setup\Installed Components\>BatchSetupx","Version",,"3,0,0,0"' \
    'HKLM,"SOFTWARE\Microsoft\Active Setup\Installed Components\>BatchSetupx","StubPath",,"%25%\rundll.exe setupx.dll,InstallHinfSection Win9x.Browser 4 %10%\msbatch.inf"' \
    '' \
    '[Win9x.Browser]' \
    'AddReg=Win9x.BrowserUser,Win9x.PowerUser' \
    'DelReg=Win9x.MSN,Win9x.ICWDesktop' \
    'DelFiles=Win9x.Connect,Win9x.ConnectAll' \
    '' \
    '[Win9x.PowerUser]' \
    'HKCU,"Control Panel\PowerCfg","CurrentPowerPolicy",,"3"' \
    'HKCU,"Control Panel\PowerCfg\PowerPolicies\3","Policies",0x00000001,01,00,00,00,02,00,00,00,01,00,00,00,00,00,00,00,02,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,32,32,00,00,04,00,00,00,05,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,01,64,64,64,64,00,00' \
    '' \
    '[Win9x.BrowserUser]' \
    'HKCU,"Software\Microsoft\Internet Connection Wizard","Completed",1,01,00,00,00' \
    'HKCU,"Software\Microsoft\Internet Connection Wizard","DesktopChanged",0x00010001,1' \
    'HKCU,"Software\Microsoft\Windows\CurrentVersion\Internet Settings","EnableAutodial",0x00010001,0' \
    'HKCU,"Software\Microsoft\Windows\CurrentVersion\Internet Settings","NoNetAutodial",0x00010001,0' \
    'HKCU,"Software\Microsoft\Windows\CurrentVersion\Internet Settings","ProxyEnable",0x00010001,0' \
    'HKCU,"Software\Microsoft\Internet Explorer\Main","Start Page",,"http://www.google.com"' \
    'HKCU,"Software\Microsoft\Internet Explorer\Main","First Home Page",,"http://www.google.com"' \
    'HKCU,"Software\Microsoft\Internet Explorer\Main","Default_Page_URL",,"http://www.google.com"' \
    'HKCU,"Software\Microsoft\Internet Explorer\Main","Search Page",,"http://www.google.com"' \
    'HKCU,"Software\Microsoft\Internet Explorer\Main","Search Bar",,"http://www.google.com"'
}

writeWin9xStorageRegistry() {

  printf '%s\n' \
    '[Win9x.StorageActiveSetup]' \
    'HKLM,"SOFTWARE\Microsoft\Active Setup\Installed Components\>BatchStoragex",,,">Batch 9x - Storage Settings"' \
    'HKLM,"SOFTWARE\Microsoft\Active Setup\Installed Components\>BatchStoragex","IsInstalled",0x00000001,01,00,00,00' \
    'HKLM,"SOFTWARE\Microsoft\Active Setup\Installed Components\>BatchStoragex","Version",,"3,0,0,0"' \
    'HKLM,"SOFTWARE\Microsoft\Active Setup\Installed Components\>BatchStoragex","StubPath",,"%10%\WIN9XDMA.EXE"'
}

writeWin9xCleanupRegistry() {

  printf '%s\n' \
    '[Win95.InitShell]' \
    'HKLM,"SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce","InitShell",,,' \
    '' \
    '[Win95.Welcome]' \
    'HKU,".DEFAULT\Software\Microsoft\Windows\CurrentVersion\Explorer\Tips","Show",1,00' \
    '' \
    '[Win9x.Welcome]' \
    'HKLM,"Software\Microsoft\Windows\CurrentVersion\Run","Welcome",,,' \
    '' \
    '[Win9x.Regwiz]' \
    'HKLM,"Software\Microsoft\Windows\CurrentVersion\Welcome\Regwiz",@,1,01,00,00,00' \
    'HKLM,"Software\Microsoft\Windows\CurrentVersion","RegDone",1,01,00,00,00' \
    '' \
    '[Win9x.MSN]' \
    'HKLM,"SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\{4B876A40-4EE8-11D1-811E-00C04FB98EEC}",,,' \
    'HKLM,"SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\{88667D10-10F0-11D0-8150-00AA00BF8457}",,,' \
    'HKCU,"SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\{4B876A40-4EE8-11D1-811E-00C04FB98EEC}",,,' \
    'HKCU,"SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\{88667D10-10F0-11D0-8150-00AA00BF8457}",,,' \
    'HKU,".DEFAULT\Software\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\{4B876A40-4EE8-11D1-811E-00C04FB98EEC}",,,' \
    'HKU,".DEFAULT\Software\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\{88667D10-10F0-11D0-8150-00AA00BF8457}",,,' \
    '' \
    '[Win9x.ICWDesktop]' \
    'HKLM,"SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce","^SetupICWDesktop",,,' \
    'HKCU,"SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce","^SetupICWDesktop",,,' \
    'HKU,".DEFAULT\Software\Microsoft\Windows\CurrentVersion\RunOnce","^SetupICWDesktop",,,' \
    'HKCU,"Software\Microsoft\Internet Connection Wizard","ShellNext",,,' \
    'HKU,".DEFAULT\Software\Microsoft\Internet Connection Wizard","ShellNext",,,' \
    '' \
    '[Win9x.Connect]' \
    'connec~1.lnk' \
    '"Connect to the Internet.lnk"' \
    '' \
    '[Win9x.ConnectAll]' \
    'connec~1.lnk' \
    '"Connect to the Internet.lnk"' \
    '' \
    '[Win9x.OnlineServices]' \
    'aol.lnk' \
    'americ~1.lnk' \
    'at&two~1.lnk' \
    'compus~1.lnk' \
    'prodig~1.lnk' \
    'themic~1.lnk' \
    'aboutt~1.lnk' \
    'abouto~1.txt' \
    'services.txt' \
    '' \
    '[Win9x.OnlineServicesFolder]' \
    'wininit.ini,DIRNUL,,"%25%\Desktop\Online~1=1"'
}

createWin9xSystemImage() {

  local dir="$1"
  local image="$2"
  local desc="$3"
  local source="$4"
  local options="$5"
  local id="$6"

  local temp="$TMP/win9x-image"
  local config="$temp/mtools.conf"
  local autoexec="$temp/AUTOEXEC.BAT"
  local msdos="$temp/MSDOS.SYS"
  local tmp="${image}.tmp"
  local size=$((4177 * 255 * 63 * 512))
  local start=63
  local sectors=$((size / 512 - start))
  local offset=$((start * 512))
  local entry find_pid setup_dir
  local fs attributes required
  local setup="SETUP"
  local entries=()

  local msg="Creating system image..."
  info "$msg" && html "$msg"

  rm -rf -- "$temp" || return 1
  mkdir -p "$temp" || return 1
  rm -f -- "$tmp" || return 1

  # mtools can create a perfectly valid FAT32 filesystem, including its BPB,
  # FSInfo sector and backup boot area, but its generic boot code cannot start
  # Windows 9x. Microsoft FORMAT.COM carries the matching DOS FAT32 bootstrap
  # as a three-sector template, so use the copy supplied by the installation
  # media instead of embedding Microsoft's boot code in this script.
  #
  # Do not assume where FORMAT.COM lives. Windows 95 OSR2, Windows 98 and
  # Windows Me media use different setup layouts, and customized media may move
  # the file again. Search all FORMAT.COM copies and select the first one that
  # contains a structurally valid FAT32 boot template.
  local format=""
  local template=""
  local template_base=0
  local format_size sig boot_sig fsinfo_lead fsinfo_struct
  local -a formats=() signatures=()

  mapfile -d '' formats < <(
    find "$dir" -type f -iname 'FORMAT.COM' -print0
  )

  find_pid=$!

  if ! wait "$find_pid"; then
    error "Failed to enumerate FORMAT.COM files in $desc ISO image!"
    return 1
  fi

  if (( ${#formats[@]} == 0 )); then
    error "Failed to locate FORMAT.COM in $desc ISO image!"
    return 1
  fi

  for format in "${formats[@]}"; do

    format_size=$(stat -c %s -- "$format") || return 1
    signatures=()

    # FAT32 places the filesystem type string at offset 0x52 in the extended
    # BPB. Searching for only this standard marker intentionally avoids tying
    # the code to the exact Windows 98 machine-code bytes that follow it; a
    # Windows 95 OSR2 or Windows Me FORMAT.COM may contain a different loader.
    mapfile -t signatures < <(
      LC_ALL=C grep -aobF 'FAT32   ' "$format" | cut -d: -f1
    )

    for sig in "${signatures[@]}"; do

      [[ "$sig" =~ ^[0-9]+$ ]] || continue
      (( sig >= 0x52 )) || continue

      local candidate=$((sig - 0x52))

      # The Microsoft Win9x FAT32 bootstrap occupies three 512-byte sectors.
      # Reject truncated matches before probing the fixed signatures below.
      (( candidate + 0x600 <= format_size )) || continue

      # Validate the candidate by FAT32 structure rather than by one particular
      # release's loader bytes:
      #
      #   +0x1fe  boot-sector signature (55 aa)
      #   +0x200  FSInfo lead signature (RRaA)
      #   +0x3e4  FSInfo structure signature (rrAa)
      #   +0x3fe  FSInfo-sector signature (55 aa)
      #   +0x5fe  third boot-sector signature (55 aa)
      #
      # Requiring all five makes an accidental "FAT32   " string elsewhere in
      # FORMAT.COM extremely unlikely to be mistaken for the boot template.
      boot_sig=$(dd if="$format" bs=1 skip="$((candidate + 0x1fe))" count=2 status=none | xxd -p) || return 1
      [[ "$boot_sig" == "55aa" ]] || continue

      fsinfo_lead=$(dd if="$format" bs=1 skip="$((candidate + 0x200))" count=4 status=none | xxd -p) || return 1
      [[ "$fsinfo_lead" == "52526141" ]] || continue

      fsinfo_struct=$(dd if="$format" bs=1 skip="$((candidate + 0x3e4))" count=4 status=none | xxd -p) || return 1
      [[ "$fsinfo_struct" == "72724161" ]] || continue

      boot_sig=$(dd if="$format" bs=1 skip="$((candidate + 0x3fe))" count=2 status=none | xxd -p) || return 1
      [[ "$boot_sig" == "55aa" ]] || continue

      boot_sig=$(dd if="$format" bs=1 skip="$((candidate + 0x5fe))" count=2 status=none | xxd -p) || return 1
      [[ "$boot_sig" == "55aa" ]] || continue

      template="$format"
      template_base="$candidate"
      break 2

    done

  done

  if [ -z "$template" ]; then
    error "Failed to locate a Windows 9x FAT32 boot template in FORMAT.COM!"
    return 1
  fi

  # The system image is sparse, so reserving its full logical 32 GiB size
  # would reject valid hosts unnecessarily. The extracted ISO tree is a
  # conservative upper bound for the files copied into this image; add 64 MiB
  # for FAT metadata and other filesystem overhead.
  required=$(du -sb -- "$dir" | cut -f1) || return 1
  [[ "$required" =~ ^[0-9]+$ ]] || return 1
  required=$((required + 64 * 1024 * 1024))
  checkFreeSpace "$(dirname "$image")" "$required" || return 1

  fs=$(stat -f -c %T "$(dirname "$tmp")") || return 1

  if [[ "${fs,,}" == "btrfs" ]]; then
    touch "$tmp" || return 1
    { chattr +C "$tmp"; } || :
    attributes=$(lsattr "$tmp") || return 1
    if [[ "$attributes" != *"C"* ]]; then
      error "Failed to disable COW for $desc system image $tmp on ${fs^^} filesystem!"
    fi
  fi

  truncate -s "$size" "$tmp" || return 1

  printf 'drive w: file="%s" partition=1 fat_bits=32 cylinders=4177 heads=255 sectors=63 mformat_only\n' \
    "$tmp" > "$config" || return 1

  # Let mtools create all volume-specific FAT32 data. In particular, the BPB
  # contains the geometry, FAT size, root cluster, FSInfo sector and backup boot
  # sector locations for this image. Those values must survive the Microsoft
  # boot-code transplant below, so FORMAT.COM is deliberately not passed to
  # mformat as a whole-sector template.
  if ! MTOOLSRC="$config" mpartition -I -c -a -T 0x0c -b "$start" -l "$sectors" w: ||
    ! MTOOLSRC="$config" mformat -F -m 0xf8 -H "$start" w:; then

    rm -f -- "$tmp"
    error "Failed to create the $desc FAT32 system image!"
    return 1
  fi

  # BIOS loads the MBR at physical address 0000:7c00, which is also the address
  # where a partition boot sector (VBR) expects to run. We therefore cannot read
  # the VBR directly on top of the MBR and then continue executing the MBR:
  # INT 13h completes the disk transfer before returning, so the instructions
  # following that interrupt would already have been replaced by VBR bytes.
  #
  # Relocate the complete 512-byte MBR from 0000:7c00 to 0000:0600 first. The
  # far jump below continues at offset 0x1e in that relocated copy (0000:061e).
  # Only then do we read CHS 0/1/1 -- LBA 63 with this 63-sector geometry -- back
  # into 0000:7c00 and transfer control to the Microsoft FAT32 boot sector.
  #
  # DL is deliberately left untouched: BIOS supplies the boot drive number in
  # DL, and the INT 13h read must use that same hard disk.
  printf '%b' \
    '\xfa\x31\xc0\x8e\xd0\xbc\x00\x7c\x8e\xd8\x8e\xc0\xfb\xfc' \
    '\xbe\x00\x7c\xbf\x00\x06\xb9\x00\x01\xf3\xa5' \
    '\xea\x1e\x06\x00\x00' \
    '\x31\xc0\x8e\xc0\xbb\x00\x7c\xb8\x01\x02\xb9\x01\x00\xb6\x01' \
    '\xcd\x13\x72\x05\xea\x00\x7c\x00\x00\xcd\x18\xeb\xfe' |
    dd of="$tmp" bs=1 seek=0 conv=notrunc status=none || return 1

  # FAT32 stores the location of its backup boot sector in BPB_BkBootSec at
  # offset 0x32. Read both the reserved-sector count and that pointer from the
  # BPB generated by mformat rather than assuming Microsoft's usual sector 6.
  # If a backup exists, patch it together with the primary boot area so recovery
  # never falls back to mtools' non-Windows bootstrap.
  local reserved_bytes backup_bytes reserved backup_sector backup_offset
  local reserved_lo reserved_hi backup_lo backup_hi
  local -a boot_targets=("$offset")

  reserved_bytes=$(dd if="$tmp" bs=1 skip="$((offset + 0x0e))" count=2 status=none | od -An -tu1) || return 1
  read -r reserved_lo reserved_hi <<< "$reserved_bytes"
  [[ "$reserved_lo" =~ ^[0-9]+$ && "$reserved_hi" =~ ^[0-9]+$ ]] || return 1
  reserved=$((reserved_lo | reserved_hi << 8))

  backup_bytes=$(dd if="$tmp" bs=1 skip="$((offset + 0x32))" count=2 status=none | od -An -tu1) || return 1
  read -r backup_lo backup_hi <<< "$backup_bytes"
  [[ "$backup_lo" =~ ^[0-9]+$ && "$backup_hi" =~ ^[0-9]+$ ]] || return 1
  backup_sector=$((backup_lo | backup_hi << 8))

  if (( backup_sector != 0 && backup_sector != 0xffff )); then

    # We copy three sectors of boot/FSInfo data starting at the backup pointer,
    # therefore all three must fit inside the FAT32 reserved area.
    if (( backup_sector + 2 >= reserved )); then
      rm -f -- "$tmp"
      error "Invalid FAT32 backup boot sector generated by mtools!"
      return 1
    fi

    backup_offset=$((offset + backup_sector * 512))
    boot_targets+=("$backup_offset")

  fi

  # ms-sys' Windows 95/98/Me FAT32 writer does not overwrite the complete
  # 1536-byte template. It deliberately preserves the volume-specific fields
  # created by the formatter and replaces only these three ranges:
  #
  #   0x000..0x00a  jump instruction + OEM identifier        (11 bytes)
  #   0x052..0x3e7  boot code + static FSInfo data           (918 bytes)
  #   0x3f0..0x5ff  FSInfo trailer + second-stage boot code   (528 bytes)
  #
  # Two regions are intentionally left untouched:
  #
  #   0x00b..0x051  FAT32 BPB/extended BPB generated by mformat
  #   0x3e8..0x3ef  current free-cluster and next-free hints from mformat
  #
  # The source offsets are relative to the FAT32 template we located inside
  # FORMAT.COM, so neither the ISO layout nor FORMAT.COM's internal layout is
  # hardcoded. Apply the same transplant to the backup boot area when present.
  local target_base

  for target_base in "${boot_targets[@]}"; do

    dd if="$template" of="$tmp" bs=1 \
      skip="$template_base" seek="$target_base" count=11 \
      conv=notrunc status=none || return 1

    dd if="$template" of="$tmp" bs=1 \
      skip="$((template_base + 0x52))" seek="$((target_base + 0x52))" count=918 \
      conv=notrunc status=none || return 1

    dd if="$template" of="$tmp" bs=1 \
      skip="$((template_base + 0x3f0))" seek="$((target_base + 0x3f0))" count=528 \
      conv=notrunc status=none || return 1

    # The Microsoft template intentionally leaves the FAT32 extended BPB alone.
    # Set its BIOS drive number explicitly because QEMU exposes the system image as
    # hard disk 0x80, regardless of what default mformat happened to write there.
    printf '%b' '\x80' |
      dd of="$tmp" bs=1 seek="$((target_base + 0x40))" conv=notrunc status=none || return 1

  done

  # Verify both the partition table and the FAT32 structures after patching.
  # The checks cover all three Microsoft boot sectors, not only sector zero, so
  # a wrong FORMAT.COM match or an off-by-one copy cannot silently produce an
  # image that merely looks bootable from its first 55 aa signature.
  local active mbrsig vbrsig stage2sig fstype target_fsinfo_lead target_fsinfo_struct drive
  active=$(dd if="$tmp" bs=1 skip=446 count=1 status=none | od -An -tu1 | tr -d ' ') || return 1
  mbrsig=$(dd if="$tmp" bs=1 skip=510 count=2 status=none | xxd -p) || return 1
  vbrsig=$(dd if="$tmp" bs=1 skip="$((offset + 0x1fe))" count=2 status=none | xxd -p) || return 1
  stage2sig=$(dd if="$tmp" bs=1 skip="$((offset + 0x5fe))" count=2 status=none | xxd -p) || return 1
  fstype=$(dd if="$tmp" bs=1 skip="$((offset + 0x52))" count=8 status=none) || return 1
  target_fsinfo_lead=$(dd if="$tmp" bs=1 skip="$((offset + 0x200))" count=4 status=none | xxd -p) || return 1
  target_fsinfo_struct=$(dd if="$tmp" bs=1 skip="$((offset + 0x3e4))" count=4 status=none | xxd -p) || return 1
  drive=$(dd if="$tmp" bs=1 skip="$((offset + 0x40))" count=1 status=none | od -An -tu1 | tr -d ' ') || return 1

  if [[ "$active" != "128" || "$mbrsig" != "55aa" || "$vbrsig" != "55aa" ||
        "$stage2sig" != "55aa" || "$fstype" != "FAT32   " ||
        "$target_fsinfo_lead" != "52526141" || "$target_fsinfo_struct" != "72724161" ||
        "$drive" != "128" ]]; then
    rm -f -- "$tmp"
    error "Failed to make the $desc FAT32 system image bootable!"
    return 1
  fi

  if (( backup_sector != 0 && backup_sector != 0xffff )); then

    vbrsig=$(dd if="$tmp" bs=1 skip="$((backup_offset + 0x1fe))" count=2 status=none | xxd -p) || return 1
    stage2sig=$(dd if="$tmp" bs=1 skip="$((backup_offset + 0x5fe))" count=2 status=none | xxd -p) || return 1
    fstype=$(dd if="$tmp" bs=1 skip="$((backup_offset + 0x52))" count=8 status=none) || return 1
    drive=$(dd if="$tmp" bs=1 skip="$((backup_offset + 0x40))" count=1 status=none | od -An -tu1 | tr -d ' ') || return 1

    if [[ "$vbrsig" != "55aa" || "$stage2sig" != "55aa" ||
          "$fstype" != "FAT32   " || "$drive" != "128" ]]; then
      rm -f -- "$tmp"
      error "Failed to update the $desc FAT32 backup boot record!"
      return 1
    fi

  fi

  # The CD boot image is not part of the Windows 9x installation contract.
  # Retail, OEM and repacked discs may use a differently named El Torito image
  # or omit an extracted floppy image entirely. The setup cabinets are a much
  # better source for the DOS kernel files because Setup itself ships them.
  #
  # The exact cabinet containing the DOS boot files varies between Windows 9x
  # releases, so do not hardcode a cabinet number. Search every PRECOPY cabinet
  # first and only fall back to the remaining CABs for unusual OEM/repacked
  # media.
  #
  # Windows 95/98 use the setup-media WINBOOT.SYS kernel together with
  # COMMAND.COM. Windows Me uses its Emergency Boot Disk variants for this
  # temporary real-mode setup bootstrap instead. In both cases publish the
  # kernel as IO.SYS and the command interpreter as COMMAND.COM on the generated
  # boot volume.
  local cab source_name target_name extracted
  local kernel_source="WINBOOT.SYS"
  local command_source="COMMAND.COM"
  local cab_temp="$temp/cab"
  local -a precopy_cabs=() other_cabs=()

  if [[ "${id,,}" == "win9x"* ]]; then
    kernel_source="WINBOOT.EBD"
    command_source="COMMAND.EBD"
  fi

  mapfile -d '' precopy_cabs < <(
    find "$dir" -type f -iname 'PRECOPY*.CAB' -print0
  )

  find_pid=$!

  if ! wait "$find_pid"; then
    rm -f -- "$tmp"
    error "Failed to enumerate Windows 9x setup cabinets!"
    return 1
  fi

  mapfile -d '' other_cabs < <(
    find "$dir" -type f -iname '*.CAB' ! -iname 'PRECOPY*.CAB' -print0
  )

  find_pid=$!

  if ! wait "$find_pid"; then
    rm -f -- "$tmp"
    error "Failed to enumerate Windows 9x setup cabinets!"
    return 1
  fi

  if (( ${#precopy_cabs[@]} == 0 && ${#other_cabs[@]} == 0 )); then
    rm -f -- "$tmp"
    error "Failed to locate Windows 9x setup cabinets in $desc ISO image!"
    return 1
  fi

  for source_name in "$command_source" "$kernel_source"; do

    if [[ "$source_name" == "$kernel_source" ]]; then
      target_name="IO.SYS"
    else
      target_name="COMMAND.COM"
    fi

    extracted=""

    for cab in "${precopy_cabs[@]}" "${other_cabs[@]}"; do

      rm -rf -- "$cab_temp" || return 1
      mkdir -p "$cab_temp" || return 1

      # -F avoids unpacking a complete cabinet just to obtain one small system
      # file. -L normalizes the extracted name so case differences in localized
      # or repacked media do not matter; find below remains case-insensitive as
      # an additional safeguard. A cabinet that simply lacks the requested file
      # is not an error here: continue with the next candidate.
      if ! cabextract -q -L -F "$source_name" -d "$cab_temp" "$cab" >/dev/null 2>&1; then
        continue
      fi

      extracted=$(find "$cab_temp" -type f -iname "$source_name" -print -quit) || return 1

      if [ -n "$extracted" ] && [ -s "$extracted" ]; then
        cp -f -- "$extracted" "$temp/$target_name" || return 1
        break
      fi

    done

    if [ ! -s "$temp/$target_name" ]; then
      rm -f -- "$tmp"
      error "Failed to extract $source_name from the Windows 9x setup cabinets!"
      return 1
    fi

  done

  rm -rf -- "$cab_temp" || :

  if [[ "${id,,}" == "win9x"* ]]; then
    if ! patchWinMeDosFile "$temp/IO.SYS" "IO.SYS" ||
      ! patchWinMeDosFile "$temp/COMMAND.COM" "COMMAND.COM"; then
      rm -f -- "$tmp"
      return 1
    fi
  fi

  local boot_gui=0
  [[ "${id,,}" == "win9x"* ]] && boot_gui=1

  {
    printf '%s\n' \
      '[Options]' \
      "BootGUI=$boot_gui" \
      'BootDelay=0' \
      'AutoScan=2' \
      'Logo=0' \
      ''
  } | unix2dos > "$msdos" || return 1

  # Copy the DOS system files before anything else. Older DOS boot sectors
  # expect IO.SYS and MSDOS.SYS at the start of a freshly formatted volume.
  MTOOLSRC="$config" mcopy "$temp/IO.SYS" w:/IO.SYS || return 1
  MTOOLSRC="$config" mcopy "$msdos" w:/MSDOS.SYS || return 1
  MTOOLSRC="$config" mcopy "$temp/COMMAND.COM" w:/COMMAND.COM || return 1

  MTOOLSRC="$config" mattrib +h +s +r w:/IO.SYS w:/MSDOS.SYS || return 1

  # Windows 95/98 keep BootGUI disabled and start WIN.COM explicitly from
  # AUTOEXEC.BAT, matching the known-good setup path. Windows Me keeps its normal
  # BootGUI transition because its alternate real-mode boot activation depends on it.

  # Setup only needs its release-specific source directory. Keeping the rest
  # of the optical-media root off C: avoids exposing unrelated CD contents in
  # the installed system. Rename the retained source to C:\SETUP so it cannot
  # be confused with the installed C:\WINDOWS directory.
  setup_dir=$(find "$dir" -mindepth 1 -maxdepth 1 -type d -iname "$source" -print -quit) || return 1

  if [ -z "$setup_dir" ]; then
    rm -f -- "$tmp"
    error "Failed to locate the $source Setup folder in $desc ISO image!"
    return 1
  fi

  entries=("$setup_dir")
  [ -d "$dir/OEM" ] && entries+=("$dir/OEM")

  for entry in "${entries[@]}"; do

    if ! MTOOLSRC="$config" mcopy -Q -s "$entry" w:/; then
      rm -f -- "$tmp"
      error "Failed to copy $desc file: $entry"
      return 1
    fi

  done

  if ! MTOOLSRC="$config" mren "w:/$source" "w:/$setup" ||
    ! MTOOLSRC="$config" mattrib +h +s "w:/$setup"; then
    rm -f -- "$tmp"
    error "Failed to rename or hide the $desc setup folder in the system image!"
    return 1
  fi

  writeWin9xAutoexec "$autoexec" "$setup" "$options" "$id" || return 1

  MTOOLSRC="$config" mcopy -o "$autoexec" w:/AUTOEXEC.BAT || return 1

  if ! MTOOLSRC="$config" mdir "w:/$setup/SETUP.EXE" >/dev/null; then
    rm -f -- "$tmp"
    error "Failed to verify the $desc system image!"
    return 1
  fi

  if [[ "${fs,,}" == "btrfs" ]]; then
    attributes=$(lsattr "$tmp") || return 1
    if [[ "$attributes" != *"C"* ]]; then
      warn "COW (copy on write) is not disabled for $desc system image $tmp on ${fs^^} filesystem!"
    fi
  fi

  if ! mv -f -- "$tmp" "$image"; then
    rm -f -- "$tmp"
    error "Failed to save $desc system image: $image"
    return 1
  fi

  if ! setOwner "$image"; then
    warn "Failed to set the owner for \"$image\" !"
  fi

  rm -rf -- "$temp" || :

  return 0
}

patchWinMeDosFile() {

  local file="$1"
  local name="$2"
  local expected_size expected_offset expected_hex patch_offset
  local actual_size actual_hex patched

  case "$name" in
    "IO.SYS" )
      expected_size=116736
      expected_offset=$((0x3a8))
      expected_hex="fa8075098db69900"
      patch_offset=$((0x3aa)) ;;

    "COMMAND.COM" )
      expected_size=93040
      expected_offset=$((0x650c))
      expected_hex="1580fa037510b80e"
      patch_offset=$((0x6510)) ;;

    * )
      error "Unsupported Windows Me DOS bootstrap file: $name"
      return 1 ;;
  esac

  actual_size=$(stat -c %s -- "$file") || return 1

  if (( actual_size != expected_size )); then
    error "Unexpected Windows Me $name size: $actual_size bytes (expected $expected_size)!"
    return 1
  fi

  actual_hex=$(dd if="$file" bs=1 skip="$expected_offset" count=8 status=none | xxd -p -c 8) || return 1

  if [[ "${actual_hex,,}" != "$expected_hex" ]]; then
    error "Unexpected Windows Me $name bootstrap data at offset 0x$(printf '%X' "$expected_offset")!"
    return 1
  fi

  # Windows Me deliberately disables its normal real-mode DOS path. Match the
  # guarded patches used by Rufus: change the relevant conditional branch in
  # each original Me DOS file to an unconditional jump.
  if ! printf '\xeb' | dd of="$file" bs=1 seek="$patch_offset" count=1 conv=notrunc status=none; then
    error "Failed to patch Windows Me $name!"
    return 1
  fi

  patched=$(dd if="$file" bs=1 skip="$patch_offset" count=1 status=none | xxd -p) || return 1

  if [[ "${patched,,}" != "eb" ]]; then
    error "Failed to verify the Windows Me $name bootstrap patch!"
    return 1
  fi

  return 0
}

return 0

#!/usr/bin/env bash
set -Eeuo pipefail

setMachine() {

  local id="$1"
  local iso="$2"
  local dir="$3"
  local desc="$4"

  if isLegacy "$id"; then

    if ! legacyInstall "$id" "$iso" "$dir" "$desc"; then
      error "Failed to prepare $desc ISO!"
      return 1
    fi

    writeState "mode" "windows_legacy" || return 1

    case "${id,,}" in

      "win9"* | "winnt4" | "win2k"* | "reactos" )

        writeState "old" "pc" || return 1
        writeState "type" "auto" || return 1 ;;

    esac

    case "${id,,}" in

      "winnt4" )
        writeState "vga" "cirrus" || return 1 ;;

      *) writeState "vga" "std" || return 1 ;;

    esac

    case "${id,,}" in

      "win9"* | "winnt4" )

        writeState "usb" "N" || return 1
        writeState "port" "on" || return 1
        writeState "net" "pcnet" || return 1
        writeState "sound" "AC97" || return 1 ;;

      "win2k"* )

        writeState "net" "rtl8139" || return 1
        writeState "usb" "pci-ohci" || return 1
        writeState "sound" "usb-audio" || return 1 ;;

      "winxpx"* | "win2003"* )

        writeState "type" "blk" || return 1
        writeState "net" "rtl8139" || return 1
        writeState "sound" "usb-audio" || return 1 ;;

      "reactos" )

        writeState "sound" "AC97" || return 1
        writeState "net" "rtl8139" || return 1
        writeState "usb" "pci-ohci" || return 1

        if isReactOSLiveCD "$iso"; then
          SYSTEM="$iso"
          createMarker "kill" || return 1
        fi ;;

    esac
  fi

  restoreMachine || return 1
  restoreBootMode || return 1

  case "${id,,}" in

    "win95" | "winnt4" )

      # Windows 95 does not support ACPI so disable graceful shutdown
      createMarker "kill" || return 1 ;;

  esac

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

      else

        writeState "args" "-global PIIX4_PM.acpi-root-pci-hotplug=off" || return 1

      fi ;;

  esac

  return 0
}

restoreMachine() {

  isPlatform "x64" || return 0

  # Restore the saved machine only when q35 is still the default;
  # an explicit user-selected machine must remain untouched.
  [[ "${MACHINE,,}" != "q35" ]] && return 0

  MACHINE=""
  restoreState "MACHINE" "old" || return 1

  # Migrate existing Win9x installs to QEMU 11
  if [[ "${MACHINE,,}" == "pc-i440fx-2.4" ]]; then
    MACHINE="pc"
    writeState "old" "$MACHINE" || return 1
  fi

  [ -z "$MACHINE" ] && MACHINE="q35"

  return 0
}

restoreMachineState() {

  restoreState "VGA" "vga" || return 1
  restoreState "USB" "usb" || return 1
  restoreState "SOUND" "sound" || return 1
  restoreState "ADAPTER" "net" || return 1
  restoreState "VMPORT" "port" || return 1
  restoreState "CPU_MODEL" "cpu" || return 1
  restoreState "DISK_TYPE" "type" || return 1

  if [ -z "${BIOS:-}" ] && [ -s "$(stateFile "bios")" ]; then
    BIOS="$(stateFile "bios")"
  fi

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

legacyInstall() {

  local id="$1"
  local iso="$2"
  local dir="$3"
  local desc="$4"

  case "${id,,}" in
    "win9"* )
      Win9xInstall "$id" "$iso" "$dir" "$desc" || return 1 ;;
    "win2k"* )
      SIFInstall "$iso" "$dir" "$desc" "2k" || return 1 ;;
    "winxp"* )
      SIFInstall "$iso" "$dir" "$desc" "xp" || return 1 ;;
    "win2003"* )
      SIFInstall "$iso" "$dir" "$desc" "2k3" || return 1 ;;
  esac

  return 0
}

isReactOSLiveCD() {

  local iso="$1"
  local files

  files=$(bsdtar -tf "$iso" 2>/dev/null) || return 1

  ! grep -Ei '(^|/)reactos/txtsetup\.sif(;1)?$' <<< "$files" >/dev/null
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

detectLegacy() {

  local dir="$1"
  local marker

  isPlatform "x64" || return 1

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

return 0

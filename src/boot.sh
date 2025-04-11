#!/usr/bin/env bash
set -Eeuo pipefail

# Docker environment variables
: "${BIOS:=""}"         # BIOS file
: "${TPM:="N"}"         # Disable TPM
: "${SMM:="N"}"         # Disable SMM

BOOT_DESC=""
BOOT_OPTS=""

SECURE="off"
[[ "$SMM" == [Yy1]* ]] && SECURE="on"
[ -n "$BIOS" ] && BOOT_MODE="custom"

case "${BOOT_MODE,,}" in
  "uefi" | "" )
    BOOT_MODE="uefi"
    ROM="OVMF_CODE_4M.fd"
    VARS="OVMF_VARS_4M.fd"
    ;;
  "secure" )
    SECURE="on"
    BOOT_DESC=" securely"
    ROM="OVMF_CODE_4M.secboot.fd"
    VARS="OVMF_VARS_4M.secboot.fd"
    ;;
  "windows" | "windows_plain" )
    ROM="OVMF_CODE_4M.fd"
    VARS="OVMF_VARS_4M.fd"
    ;;
  "windows_secure" )
    TPM="Y"
    SECURE="on"
    BOOT_DESC=" securely"
    ROM="OVMF_CODE_4M.ms.fd"
    VARS="OVMF_VARS_4M.ms.fd"
    ;;
  "windows_legacy" )
    HV="N"
    SECURE="on"
    BOOT_DESC=" (legacy)"
    [ -z "${USB:-}" ] && USB="usb-ehci,id=ehci"
    ;;
  "legacy" )
    BOOT_DESC=" with SeaBIOS"
    ;;
  "custom" )
    BOOT_OPTS="-bios $BIOS"
    BOOT_DESC=" with custom BIOS file"
    ;;
  *)
    error "Unknown BOOT_MODE, value \"${BOOT_MODE}\" is not recognized!"
    exit 33
    ;;
esac

if [[ "${BOOT_MODE,,}" == "windows"* ]]; then
  BOOT_OPTS+=" -rtc base=utc"
  BOOT_OPTS+=" -global ICH9-LPC.disable_s3=1"
  BOOT_OPTS+=" -global ICH9-LPC.disable_s4=1"
fi

case "${BOOT_MODE,,}" in
  "uefi" | "secure" | "windows" | "windows_plain" | "windows_secure" )

    OVMF="/usr/share/OVMF"
    DEST="$STORAGE/${BOOT_MODE,,}"

    if [ ! -s "$DEST.rom" ] || [ ! -f "$DEST.rom" ]; then
      [ ! -s "$OVMF/$ROM" ] || [ ! -f "$OVMF/$ROM" ] && error "UEFI boot file ($OVMF/$ROM) not found!" && exit 44
      cp "$OVMF/$ROM" "$DEST.rom"
    fi

    if [ ! -s "$DEST.vars" ] || [ ! -f "$DEST.vars" ]; then
      [ ! -s "$OVMF/$VARS" ] || [ ! -f "$OVMF/$VARS" ]&& error "UEFI vars file ($OVMF/$VARS) not found!" && exit 45
      cp "$OVMF/$VARS" "$DEST.vars"
    fi

    if [[ "${BOOT_MODE,,}" == "secure" ]] || [[ "${BOOT_MODE,,}" == "windows_secure" ]]; then
      BOOT_OPTS+=" -global driver=cfi.pflash01,property=secure,value=on"
    fi

    BOOT_OPTS+=" -drive file=$DEST.rom,if=pflash,unit=0,format=raw,readonly=on"
    BOOT_OPTS+=" -drive file=$DEST.vars,if=pflash,unit=1,format=raw"

    ;;
esac

MSRS="/sys/module/kvm/parameters/ignore_msrs"
if [ -e "$MSRS" ]; then
  result=$(<"$MSRS")
  result="${result//[![:print:]]/}"
  if [[ "$result" == "0" ]] || [[ "${result^^}" == "N" ]]; then
    echo 1 | tee "$MSRS" > /dev/null 2>&1 || true
  fi
fi

CLOCKSOURCE="tsc"
[[ "${ARCH,,}" == "arm64" ]] && CLOCKSOURCE="arch_sys_counter"
CLOCK="/sys/devices/system/clocksource/clocksource0/current_clocksource"

if [ ! -f "$CLOCK" ]; then
  warn "file \"$CLOCK\" cannot not found?"
else
  result=$(<"$CLOCK")
  result="${result//[![:print:]]/}"
  case "${result,,}" in
    "${CLOCKSOURCE,,}" ) ;;
    "kvm-clock" ) info "Nested KVM virtualization detected.." ;;
    "hyperv_clocksource_tsc_page" ) info "Nested Hyper-V virtualization detected.." ;;
    "hpet" ) warn "unsupported clock source ﻿detected﻿: '$result'. Please﻿ ﻿set host clock source to '$CLOCKSOURCE'." ;;
    *) warn "unexpected clock source ﻿detected﻿: '$result'. Please﻿ ﻿set host clock source to '$CLOCKSOURCE'." ;;
  esac
fi

SM_BIOS=""
PS="/sys/class/dmi/id/product_serial"

if [ -s "$PS" ] && [ -r "$PS" ]; then

  BIOS_SERIAL=$(<"$PS")
  BIOS_SERIAL="${BIOS_SERIAL//[![:alnum:]]/}"

  if [ -n "$BIOS_SERIAL" ]; then
    SM_BIOS="-smbios type=1,serial=$BIOS_SERIAL"
  fi

fi

if [[ "$TPM" == [Yy1]* ]]; then

  rm -f /var/run/tpm.pid

  if ! swtpm socket -t -d --tpmstate "backend-uri=file://$STORAGE/${BOOT_MODE,,}.tpm" --ctrl type=unixio,path=/run/swtpm-sock --pid file=/var/run/tpm.pid --tpm2; then
    error "Failed to start TPM emulator, reason: $?"
  else

    for (( i = 1; i < 20; i++ )); do

      [ -S "/run/swtpm-sock" ] && break

      if (( i % 10 == 0 )); then
        echo "Waiting for TPM emulator to become available..."
      fi

      sleep 0.1

    done

    if [ ! -S "/run/swtpm-sock" ]; then
      error "TPM socket not found? Disabling TPM module..."
    else
      BOOT_OPTS+=" -chardev socket,id=chrtpm,path=/run/swtpm-sock"
      BOOT_OPTS+=" -tpmdev emulator,id=tpm0,chardev=chrtpm -device tpm-tis,tpmdev=tpm0"
    fi

  fi
fi

return 0

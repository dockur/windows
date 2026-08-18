#!/usr/bin/env bash
set -Eeuo pipefail

: "${SHUTDOWN:="Y"}"        # Graceful ACPI shutdown
: "${TIMEOUT:="105"}"       # QEMU termination timeout

# Configure QEMU for graceful shutdown

SHUTDOWN_SKIP=0
SHUTDOWN_SIGNAL=0

QEMU_PTY="$QEMU_DIR/qemu.pty"
QEMU_END="$QEMU_DIR/qemu.end"
ACPI_SOCKET="$QEMU_DIR/monitor.sock"
CONSOLE_PID="$QEMU_DIR/console.pid"
CONSOLE_SOCKET="$QEMU_DIR/console.sock"
QEMU_START_PID="$QEMU_DIR/qemu.start.pid"

UEFI_SHELL_MESSAGE='UEFI Interactive Shell'
LEGACY_BOOT_PATTERN='^Booting from (Hard Disk|DVD/CD)'
UEFI_BOOT_PATTERN='BdsDxe: starting Boot[[:xdigit:]]{4} '
UEFI_NO_BOOT_MESSAGE='BdsDxe: No bootable option or device was found.'
UEFI_DVD_BOOT_PATTERN='BdsDxe: starting Boot[[:xdigit:]]{4} "UEFI QEMU .*DVD-ROM'
UEFI_USB_BOOT_PATTERN='BdsDxe: starting Boot[[:xdigit:]]{4} "UEFI QEMU .*USB HARDDRIVE'
UEFI_WINDOWS_BOOT_PATTERN='BdsDxe: starting Boot[[:xdigit:]]{4} "Windows Boot Manager" from .*HD\('

bootStatus() {

  [ ! -s "$QEMU_PTY" ] && return 1

  if isLegacyBoot; then
    local line last recent

    # Only inspect output produced after the most recent BIOS boot attempt so
    # stale failures from an earlier device do not affect the current state.
    line=$(getBootMarker)
    [ -z "$line" ] && return 1

    last="${line#*:}"
    recent=$(tail -n +"${line%%:*}" "$QEMU_PTY")

    grep -Fq "Loading FreeLoader..." <<< "$recent" && return 0

    if grep -Fq \
      -e "No bootable device." \
      -e "BOOTMGR is missing" \
      -e "Replace the disk, and then press any key" \
      -e "The following file is missing or corrupted:" \
      -e "Type the name of the Windows loader" \
      <<< "$recent"; then
      return 2
    fi

    # These BIOS messages only describe the failed device attempt. QEMU may
    # immediately continue with another boot target, so clear pending success
    # instead of treating them as a terminal failure.
    if grep -Fq \
      -e "Boot failed: not a bootable disk" \
      -e "Boot failed: Could not read from CDROM" \
      -e "Boot failed: could not read the boot disk" \
      <<< "$recent"; then
      return 5
    fi

    if [[ "$last" == "Booting from Hard Disk"* ]]; then
      return 3
    fi

    if [[ "$last" == "Booting from DVD/CD"* ]]; then
      return 4
    fi

    return 1
  fi

  local line last recent

  # OVMF logs every boot option it tries. Track the newest attempt and only
  # evaluate messages emitted from that point onward.
  line=$(getBootMarker)
  [ -z "$line" ] && return 1

  last="${line#*:}"
  recent=$(tail -n +"${line%%:*}" "$QEMU_PTY")

  grep -Eq \
    'BdsDxe: failed to start Boot[[:xdigit:]]{4} "UEFI QEMU .*DVD-ROM.*: Time out' \
    <<< "$recent" && return 2

  grep -Fq "$UEFI_NO_BOOT_MESSAGE" <<< "$recent" && return 2
  grep -Fq "$UEFI_SHELL_MESSAGE" <<< "$recent" && return 2

  # A failed device attempt is transitional because OVMF may immediately try
  # another boot target. Clear pending success and wait for the next attempt.
  grep -Eq \
    'BdsDxe: failed to start Boot[[:xdigit:]]{4} ' \
    <<< "$recent" && return 5

  grep -Eq "$UEFI_WINDOWS_BOOT_PATTERN" <<< "$last" && return 3

  grep -Eq \
    -e '"UEFI QEMU .*DVD-ROM' \
    -e 'CDROM\(' \
    -e 'USB\(' \
    <<< "$last" && return 4

  return 1
}

waitForBoot() {

  local pid="$1"
  local timeout="${2:-30}"
  local keySent=0
  local keyWait=0
  local pendingType=0
  local pendingLine=""
  local pendingDeadline=0
  local status marker
  local deadline=$((SECONDS + timeout))
  local screen="visit http://127.0.0.1:$WEB_PORT/ to view the screen..."

  while isAlive "$pid"; do

    # The boot prompt is only an opportunistic early trigger because some
    # Windows versions do not expose it on the PTY until much later.
    if (( ! keySent )) && needsBootKey; then

      if [ -s "$QEMU_PTY" ] && grep -Fq "Press any key to boot from" "$QEMU_PTY"; then
        if sendKey ret 0 500; then
          keySent=1
        fi
      elif bootKeyReady; then
        (( keyWait += 1 ))

        if isLegacyBoot; then
          # Keep the legacy fallback at about one second after the DVD marker.
          if (( keyWait >= 5 )); then
            if sendKey ret 0 100 6 0.25; then
              keySent=1
            fi
          fi
        elif (( keyWait >= 1 )); then
          # Modern Windows usually needs blind timing, so start earlier.
          if sendKey ret 0 100 6 0.25; then
            keySent=1
          fi
        fi
      else
        keyWait=0
      fi

    fi

    if bootStatus; then
      status=0
    else
      status=$?
    fi

    case "$status" in

      0) echo

        if [[ "${DISPLAY,,}" == "web" ]] && ! disabled "${WEB:-Y}"; then
          info "$(app) started successfully, $screen"
        else
          info "$(app) started successfully."
        fi

        echo && return 0 ;;

      2) echo

        error "$(app) could not boot, terminating..."
        terminateQemu
        return 0 ;;

      3 | 4)

        marker=$(getBootMarker)

        # A firmware boot line alone is not proof that the guest started. Wait
        # briefly for a more definitive success or failure message, restarting
        # the grace period whenever firmware begins a different boot attempt.
        if [[ "$marker" != "$pendingLine" ]] || (( status != pendingType )); then
          pendingLine="$marker"
          pendingType=$status

          pendingDeadline=$((SECONDS + 6))
        fi

        if (( pendingDeadline > 0 && SECONDS >= pendingDeadline )); then
          echo

          if [[ "${DISPLAY,,}" == "web" ]] && ! disabled "${WEB:-Y}"; then
            info "$(app) started successfully, $screen"
          else
            info "$(app) started successfully."
          fi

          echo && return 0
        fi
        ;;

      5)

        # A failed device attempt is transitional because firmware may continue
        # with another target. Discard any pending success decision.
        pendingType=0
        pendingLine=""
        pendingDeadline=0
        ;;

      *)

        pendingType=0
        pendingLine=""
        pendingDeadline=0
        ;;

    esac

    (( SECONDS >= deadline )) && break

    sleep 0.25
  done

  isAlive "$pid" || return 0
  [ -f "$QEMU_END" ] && return 0

  error "Timeout while waiting for QEMU to boot the machine, terminating..."
  terminateQemu

  return 0
}

legacyBootReady() {

  local line last recent
  local hard="Booting from Hard"
  local cdrom="Booting from DVD/CD"

  line=$(grep -n "^Booting.*" "$QEMU_PTY" | tail -1)
  [ -z "$line" ] && return 1

  last="${line#*:}"
  recent=$(tail -n +"${line%%:*}" "$QEMU_PTY")

  # ACPI shutdown is safe once BIOS has handed control to the hard disk, unless
  # the same attempt already produced a known boot failure.
  [[ "${last,,}" != "${hard,,}"* ]] && return 1

  grep -Fq "Loading FreeLoader..." <<< "$recent" && return 0
  grep -Fq "No bootable device." <<< "$recent" && return 1
  grep -Fq "BOOTMGR is missing" <<< "$recent" && return 1
  grep -Fq "Replace the disk, and then press any key" <<< "$recent" && return 1
  grep -Fq "Boot failed: not a bootable disk" <<< "$recent" && return 1
  grep -Fq "Boot failed: could not read the boot disk" <<< "$recent" && return 1
  grep -Fq "The following file is missing or corrupted:" <<< "$recent" && return 1
  grep -Fq "Type the name of the Windows loader" <<< "$recent" && return 1

  return 0
}

ready() {

  # The marker means installation completed previously, so shutdown
  # no longer needs to infer guest readiness from firmware output.
  hasBootMarker && return 0

  [ ! -s "$QEMU_PTY" ] && return 1

  if isLegacyBoot; then
    legacyBootReady && return 0
    return 1
  fi

  local line last recent

  line=$(getBootMarker)
  [ -z "$line" ] && return 1

  last="${line#*:}"
  recent=$(tail -n +"${line%%:*}" "$QEMU_PTY")

  # Only a Windows Boot Manager entry loaded from a hard disk proves that setup
  # has progressed far enough for an ACPI shutdown request to be appropriate.
  grep -Eq "$UEFI_WINDOWS_BOOT_PATTERN" <<< "$last" || return 1

  # Reject failures emitted after this exact boot attempt. Without these checks,
  # a failed Windows Boot Manager entry remains classified as ready indefinitely.
  grep -Eq \
    'BdsDxe: failed to start Boot[[:xdigit:]]{4} "Windows Boot Manager"' \
    <<< "$recent" && return 1

  grep -Fq "$UEFI_NO_BOOT_MESSAGE" <<< "$recent" && return 1
  grep -Fq "$UEFI_SHELL_MESSAGE" <<< "$recent" && return 1

  return 0
}

sendKey() {

  local key="$1"
  local delay="${2:-0}"
  local hold="${3:-100}"
  local repeat="${4:-1}"
  local interval="${5:-0}"
  local i output

  [ ! -S "$ACPI_SOCKET" ] && return 1
  [[ "$delay" != "0" ]] && sleep "$delay"

  # Send all repeats through one monitor connection so timing remains stable
  # and QEMU receives the sequence as one operation.
  if ! output=$(
    {
      for ((i = 1; i <= repeat; i++)); do
        printf 'sendkey %s %s\n' "$key" "$hold"

        if (( i < repeat )); then
          sleep "$interval"
        fi
      done
    } | nc -q 1 -w 1 -U "$ACPI_SOCKET" 2>&1
  ); then
    return 1
  fi

  # The human monitor may return success at the transport level while reporting
  # a command error in its text response, so inspect that output explicitly.
  if grep -Eqi \
    -e 'unknown command' \
    -e 'unknown key' \
    -e 'invalid parameter' \
    -e 'invalid key' \
    -e '^error:' \
    <<< "$output"; then

    warn "failed to send boot key through QEMU monitor!"

    if enabled "${DEBUG:-}"; then
      echo "$output"
    fi

    return 1
  fi

  return 0
}

needsBootKey() {

  hasImage "$BOOT" || return 1

  hasCompletedInstall && return 1
  supportsBootKey "$DETECTED" || return 1

  return 0
}

bootKeyReady() {

  [ ! -s "$QEMU_PTY" ] && return 1

  if isLegacyBoot; then
    grep -Fq "Booting from DVD/CD" "$QEMU_PTY"
    return $?
  fi

  if isPlatform "arm64"; then
    grep -Eq "$UEFI_USB_BOOT_PATTERN" "$QEMU_PTY"
  else
    grep -Eq "$UEFI_DVD_BOOT_PATTERN" "$QEMU_PTY"
  fi
}

getBootMarker() {

  if isLegacyBoot; then
    grep -nE "$LEGACY_BOOT_PATTERN" "$QEMU_PTY" | tail -1
    return 0
  fi

  grep -nE "$UEFI_BOOT_PATTERN" "$QEMU_PTY" | tail -1

  return 0
}

markWindowsBooted() {

  if hasBootMarker || [ ! -f "$BOOT" ]; then
    return 0
  fi

  # Do not remove installation media until firmware output confirms Windows is
  # now booting from the installed disk rather than from setup media.
  ready || return 0

  createMarker "windows.boot" || return 0

  if ! disabled "$REMOVE"; then
    case "${BOOT,,}" in
      *.img | *.raw | *.qcow2 ) ;;
      * ) removeImage "$BOOT" || : ;;
    esac
  fi

  rm -f "$STORAGE/setup.img" 2>/dev/null || :

  return 0
}

finish() {

  local reason=$1 failed=0

  # A nonzero exit is unexpected only when QEMU_END is missing.
  if [ ! -f "$QEMU_END" ] && (( reason != 0 )); then
    failed=1
  fi

  touch "$QEMU_END" || :

  forceKillQemu "$reason"

  if ! hasBootMarker; then
    markWindowsBooted
  fi

  cleanupHelpers "${SMB_PID:-}" "${NMB_PID:-}" "${DDN_PID:-}"

  if ! waitQemuExit 10; then
    warn "Timed out while waiting for $(app) to exit!"
  fi

  stopConsole
  echo

  if (( failed == 0 )); then
    echo "❯ Shutdown completed!"
  else
    error "QEMU exited unexpectedly!"
  fi

  exit "$reason"
}

gracefulShutdown() {

  local sig="$1"
  local pid code

  # Traps can run in subshells created by pipelines or command substitutions;
  # only the original shell may coordinate QEMU shutdown.
  [[ $BASHPID != "$TRAP_PID" ]] && return

  code=$(signalCode "$sig")

  if (( SHUTDOWN_SIGNAL != 0 )); then

    # A second Ctrl-C during an active shutdown skips the remaining grace period
    # and lets the shutdown loop force QEMU down immediately.
    if (( code == 130 && SHUTDOWN_SIGNAL == code )); then
      SHUTDOWN_SKIP=1
      echo && info "Received SIGINT again, forcing shutdown..."
      return
    fi

    echo && info "Received $sig signal while already shutting down..."
    return
  fi

  SHUTDOWN_SIGNAL=$code

  # Signal handlers must complete their own error handling and cleanup without
  # errexit terminating the shell partway through the shutdown sequence.
  set +e
  touch "$QEMU_END"

  echo && info "Received $sig signal, sending ACPI shutdown signal..."

  # Interactive startup may receive a signal before the PID file appears, so
  # briefly wait for it there; non-interactive operation fails immediately.
  if ! readQemuPid pid; then
    if ! interactive || ! waitQemuPid pid; then
      warn "QEMU PID file does not exist?"
      finish "$code"
    fi
  fi

  if [ -z "$pid" ] || ! isAlive "$pid"; then
    warn "QEMU process with PID $pid does not exist?"
    finish "$code"
  fi

  if ! supportsACPI "$DETECTED"; then

    if [[ "${DETECTED,,}" == "win95" ]]; then
      info "Windows 95 does not support ACPI shutdown, decreasing timeout to 1 second..."
    elif [[ "${DETECTED,,}" == "reactos" ]]; then
      info "ReactOS LiveCD does not support ACPI shutdown, decreasing timeout to 1 second..."
    else
      info "This $(app) version does not support ACPI shutdown, decreasing timeout to 1 second..."
    fi

    TIMEOUT=7

  elif hasSystemImage && ! hasBootMarker; then

    info "$(app) will ignore ACPI signals during setup, decreasing timeout to 10 seconds..."
    TIMEOUT=13

  elif ! ready; then

    info "$(app) will ignore ACPI signals during setup, decreasing timeout to 10 seconds..."
    TIMEOUT=13

  fi

  normalizeTimeout 105
  waitForShutdown "$pid"

  finish "$code"
}

enableTrap() {

  enabled "$SHUTDOWN" || return 0

  # Keep Ctrl-C available to interactive users without installing an unnecessary
  # SIGINT handler for background/container execution.
  if interactive; then
    _trap gracefulShutdown SIGINT
  fi

  _trap gracefulShutdown SIGTERM SIGHUP SIGABRT SIGQUIT

  return 0
}

[ -n "${QEMU_TIMEOUT:-}" ] && TIMEOUT="$QEMU_TIMEOUT"

return 0

#!/usr/bin/env bash
set -Eeuo pipefail

: "${SHUTDOWN:="Y"}"        # Graceful ACPI shutdown
: "${TIMEOUT:="105"}"       # QEMU termination timeout

# Configure QEMU for graceful shutdown

SHUTDOWN_SKIP=0
SHUTDOWN_SIGNAL=0

QEMU_PTY="$QEMU_DIR/qemu.pty"
QEMU_END="$QEMU_DIR/qemu.end"
ACPI_SOCKET="$QEMU_DIR/acpi.sock"
CONSOLE_PID="$QEMU_DIR/console.pid"
CONSOLE_SOCKET="$QEMU_DIR/console.sock"
QEMU_START_PID="$QEMU_DIR/qemu.start.pid"

bootStatus() {

  [ ! -s "$QEMU_PTY" ] && return 1

  if [[ "${BOOT_MODE,,}" == "windows_legacy" ]]; then
    local line last recent

    line=$(grep -nE '^Booting from (Hard Disk|DVD/CD)' "$QEMU_PTY" | tail -1)
    [ -z "$line" ] && return 1

    last="${line#*:}"
    recent=$(tail -n +"${line%%:*}" "$QEMU_PTY")

    if [[ "$last" == "Booting from DVD/CD"* ]]; then
      return 0
    fi

    grep -Fq "Loading FreeLoader..." <<< "$recent" && return 0

    grep -Fq \
      -e "No bootable device." \
      -e "BOOTMGR is missing" \
      -e "Boot failed: not a bootable disk" \
      -e "Boot failed: could not read the boot disk" \
      <<< "$recent" && return 1

    return 3
  fi

  local line last recent

  line=$(grep -nE \
    'BdsDxe: starting Boot[[:xdigit:]]{4} ' \
    "$QEMU_PTY" | tail -1)

  [ -z "$line" ] && return 1

  last="${line#*:}"
  recent=$(tail -n +"${line%%:*}" "$QEMU_PTY")

  if [[ "$last" == *'"Windows Boot Manager"'* ]]; then
    return 0
  fi

  grep -Eq \
    'BdsDxe: failed to start Boot[[:xdigit:]]{4} "UEFI QEMU .*DVD-ROM.*: Time out' \
    <<< "$recent" && return 2

  grep -Fq "UEFI Interactive Shell" <<< "$recent" && return 2

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
  local pendingType=0
  local pendingLine=""
  local pendingDeadline=0
  local keyDelay status marker
  local deadline=$((SECONDS + timeout))
  local screen="visit http://127.0.0.1:$WEB_PORT/ to view the screen..."

  while isAlive "$pid"; do

    if (( ! keySent )) && needsBootKey; then

      if keyDelay=$(bootKeyDelay); then
        if sendKey f11 "$keyDelay" 500; then
          keySent=1
        fi
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

        error "$(app) could not boot, aborting..."
        terminateQemu
        return 0 ;;

      3 | 4)

        marker=$(getBootMarker)

        if [[ "$marker" != "$pendingLine" ]] || (( status != pendingType )); then
          pendingLine="$marker"
          pendingType=$status

          if (( status == 3 )); then
            pendingDeadline=$((SECONDS + 1))
          else
            pendingDeadline=$((SECONDS + 6))
          fi
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

  error "Timeout while waiting for QEMU to boot the machine, aborting..."
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

  [[ "${last,,}" != "${hard,,}"* ]] && return 1

  grep -Fq "Loading FreeLoader..." <<< "$recent" && return 0
  grep -Fq "No bootable device." <<< "$recent" && return 1
  grep -Fq "BOOTMGR is missing" <<< "$recent" && return 1
  grep -Fq "Boot failed: not a bootable disk" <<< "$recent" && return 1
  grep -Fq "Boot failed: could not read the boot disk" <<< "$recent" && return 1

  return 0
}

ready() {

  [ -f "$STORAGE/windows.boot" ] && return 0
  [ ! -s "$QEMU_PTY" ] && return 1

  if [[ "${BOOT_MODE,,}" == "windows_legacy" ]]; then
    legacyBootReady && return 0
    return 1
  fi

  local last
  last=$(grep -E \
    'BdsDxe: starting Boot[[:xdigit:]]{4} ' \
    "$QEMU_PTY" | tail -1)

  grep -Eq \
    'BdsDxe: starting Boot[[:xdigit:]]{4} "Windows Boot Manager" from HD\(' \
    <<< "$last" && return 0

  return 1
}

sendKey() {

  local key="$1"
  local delay="${2:-0}"
  local hold="${3:-100}"
  local output

  [ ! -S "$ACPI_SOCKET" ] && return 1
  [[ "$delay" != "0" ]] && sleep "$delay"

  if ! output=$(
    printf 'sendkey %s %s\n' "$key" "$hold" |
      nc -q 1 -w 1 -U "$ACPI_SOCKET" 2>&1
  ); then
    return 1
  fi

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

  [ ! -s "$BOOT" ] && return 1
  [[ "${BOOT,,}" != *".iso" ]] && return 1
  [ -f "$STORAGE/windows.boot" ] && return 1

  return 0
}

bootKeyDelay() {

  [ ! -s "$QEMU_PTY" ] && return 1

  if grep -Fq "Press any key to" "$QEMU_PTY"; then
    echo 0
    return 0
  fi

  if [[ "${BOOT_MODE,,}" == "windows_legacy" ]]; then
    grep -Fq "Booting from DVD/CD" "$QEMU_PTY" || return 1
  else
    grep -Eq \
      'BdsDxe: starting Boot[[:xdigit:]]{4} "UEFI QEMU .*DVD-ROM' \
      "$QEMU_PTY" || return 1
  fi

  echo 0.5
  return 0
}

getBootMarker() {

  if [[ "${BOOT_MODE,,}" == "windows_legacy" ]]; then
    grep -nE '^Booting from (Hard Disk|DVD/CD)' "$QEMU_PTY" | tail -1
    return 0
  fi

  grep -nE \
    'BdsDxe: starting Boot[[:xdigit:]]{4} ' \
    "$QEMU_PTY" | tail -1

  return 0
}

markWindowsBooted() {

  local file="$STORAGE/windows.boot"

  if [ -f "$file" ] || [ ! -f "$BOOT" ]; then
    return 0
  fi

  # Remove CD-ROM ISO after install
  ready || return 0

  if ! touch "$file"; then
    warn "failed to create Windows installation marker!"
    return 0
  fi

  if ! setOwner "$file"; then
    rm -f "$file"
    warn "failed to set the owner for \"$file\" !"
    return 0
  fi

  if ! disabled "$REMOVE"; then
    rm -f "$BOOT" 2>/dev/null || true
  fi

  return 0
}

finish() {

  local reason=$1 failed=0

  if [ ! -f "$QEMU_END" ] && (( reason != 0 )); then
    failed=1
  fi

  touch "$QEMU_END"

  forceKillQemu "$reason"

  if [ ! -f "$STORAGE/windows.boot" ]; then
    markWindowsBooted
  fi

  cleanupHelpers \
    "${SMB_PID:-}" \
    "${NMB_PID:-}" \
    "${DDN_PID:-}"

  if ! waitQemuExit 10; then
    warn "Timed out while waiting for $(app) to exit!"
  fi

  echo

  if (( failed == 0 )); then
    echo "❯ Shutdown completed!"
  else
    error "QEMU exited unexpectedly!"
  fi

  exit "$reason"
}

abortDuringSetup() {

  local code="$1"

  if [[ "${DETECTED,,}" != "reactos" ]] || [ -n "${CUSTOM:-}" ]; then
    info "Cannot send ACPI signal during $(app) setup, aborting..."
  else
    info "ReactOS LiveCD does not support ACPI shutdown, terminating..."
  fi

  terminateQemu

  if ! waitQemuExit 10; then
    warn "Timed out while waiting for $(app) to exit!"
  fi

  finish "$code"
}

gracefulShutdown() {

  local sig="$1"
  local pid code

  [[ $BASHPID != "$TRAP_PID" ]] && return

  code=$(signalCode "$sig")

  if [ -f "$QEMU_END" ]; then

    if (( code == 130 && SHUTDOWN_SIGNAL == code )); then
      SHUTDOWN_SKIP=1
      echo && info "Received SIGINT again, forcing shutdown..."
      return
    fi

    echo && info "Received $sig signal while already shutting down..."
    return
  fi

  set +e
  SHUTDOWN_SIGNAL=$code

  touch "$QEMU_END"
  echo && info "Received $sig signal, sending ACPI shutdown signal..."

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

  if ! ready; then
    abortDuringSetup "$code"
  fi

  normalizeTimeout 105
  waitForShutdown "$pid"

  finish "$code"
}

enabled "$SHUTDOWN" || return 0
[ -n "${QEMU_TIMEOUT:-}" ] && TIMEOUT="$QEMU_TIMEOUT"

if interactive; then
  _trap gracefulShutdown SIGINT
fi

_trap gracefulShutdown SIGTERM SIGHUP SIGABRT SIGQUIT

return 0

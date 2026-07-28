#!/usr/bin/env bash
set -Eeuo pipefail

: "${SHUTDOWN:="Y"}"        # Graceful ACPI shutdown
: "${TIMEOUT:="105"}"       # QEMU termination timeout

# Configure QEMU for graceful shutdown

SHUTDOWN_SKIP=0
SHUTDOWN_SIGNAL=0

QEMU_PTY="$QEMU_DIR/qemu.pty"
QEMU_END="$QEMU_DIR/qemu.end"
CONSOLE_PID="$QEMU_DIR/console.pid"
CONSOLE_SOCKET="$QEMU_DIR/console.sock"
QEMU_START_PID="$QEMU_DIR/qemu.start.pid"

bootStatus() {

  [ ! -s "$QEMU_PTY" ] && return 1

  if [[ "${BOOT_MODE,,}" == "windows_legacy" ]]; then
    grep -Fq \
      -e "No bootable device." \
      -e "BOOTMGR is missing" \
      -e "Boot failed: not a bootable disk" \
      -e "Boot failed: could not read the boot disk" \
      "$QEMU_PTY" && return 2

    grep -Eq '^Booting from (Hard|DVD/CD)' "$QEMU_PTY"
    return $?
  fi

  grep -Fq "UEFI Interactive Shell" "$QEMU_PTY" && return 2

  local last
  last=$(grep -E \
    'BdsDxe: starting Boot[[:xdigit:]]{4} ' \
    "$QEMU_PTY" | tail -1)

  [ -z "$last" ] && return 1

  grep -Eq \
    -e '"Windows Boot Manager"' \
    -e '"UEFI QEMU .*DVD-ROM' \
    -e 'CDROM\(' \
    -e 'USB\(' \
    <<< "$last"
}

waitForBoot() {

  local pid="$1"
  local timeout="${2:-30}"
  local deadline=$((SECONDS + timeout))
  local screen="visit http://127.0.0.1:$WEB_PORT/ to view the screen..."

  while isAlive "$pid"; do

    if bootStatus; then
      local status=0
    else
      local status=$?
    fi

    case "$status" in
      0) echo

        if [[ "${DISPLAY,,}" == "web" ]] && ! disabled "${WEB:-Y}"; then
          info "$(app) started successfully, $screen"
        else
          info "$(app) started successfully."
        fi

        echo && return 0 ;;

      2) error "$(app) could not boot, aborting..."
         terminateQemu
         return 0 ;;

    esac

    (( SECONDS >= deadline )) && break

    sleep 0.25
  done

  ! isAlive "$pid" && return 0
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

markWindowsBooted() {

  local file="$STORAGE/windows.boot"

  if [ -f "$file" ] || [ ! -f "$BOOT" ]; then
    return 0
  fi

  # Remove CD-ROM ISO after install
  ! ready && return 0

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

! enabled "$SHUTDOWN" && return 0
[ -n "${QEMU_TIMEOUT:-}" ] && TIMEOUT="$QEMU_TIMEOUT"

if interactive; then
  _trap gracefulShutdown SIGINT
fi

_trap gracefulShutdown SIGTERM SIGHUP SIGABRT SIGQUIT

return 0

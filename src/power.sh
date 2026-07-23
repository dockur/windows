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

bootFailed() {

  local fail=""

  if [[ "${BOOT_MODE,,}" == "windows_legacy" ]]; then
    grep -Fq "No bootable device." "$QEMU_PTY" && fail="y"
    grep -Fq "BOOTMGR is missing" "$QEMU_PTY" && fail="y"
  fi

  [ -n "$fail" ]
}

boot() {

  [ -f "$QEMU_END" ] && return 0

  if [ -s "$QEMU_PTY" ]; then
    if [ "$(stat -c%s "$QEMU_PTY")" -gt 7 ]; then
      if ! bootFailed; then

        if [[ "${DISPLAY,,}" == "web" ]] && ! disabled "${WEB:-Y}"; then
          info "$(app) started successfully, visit http://127.0.0.1:$WEB_PORT/ to view the screen..."
        else
          info "$(app) started successfully."
        fi

        return 0
      fi
    fi
  fi

  error "Timeout while waiting for QEMU to boot the machine, aborting..."
  terminateQemu

  return 0
}

legacyBootReady() {

  local last
  local bios="Booting from Hard"

  last=$(grep "^Booting.*" "$QEMU_PTY" | tail -1)
  [[ "${last,,}" != "${bios,,}"* ]] && return 1
  grep -Fq "No bootable device." "$QEMU_PTY" && return 1
  grep -Fq "BOOTMGR is missing" "$QEMU_PTY" && return 1

  return 0
}

ready() {

  [ -f "$STORAGE/windows.boot" ] && return 0
  [ ! -s "$QEMU_PTY" ] && return 1

  if [[ "${BOOT_MODE,,}" == "windows_legacy" ]]; then
    legacyBootReady && return 0
    return 1
  fi

  local line="\"Windows Boot Manager\""
  grep -Fq "$line" "$QEMU_PTY" && return 0

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

  info "Cannot send ACPI signal during $(app) setup, aborting..."

  terminateQemu

  if ! waitQemuExit 10; then
    warn "Timed out while waiting for $(app) to exit!"
  fi

  finish "$code"
}

gracefulShutdown() {

  local sig="$1"
  local pid="" code=0

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

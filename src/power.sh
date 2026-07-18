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

_trap() {

  local func="$1"; shift
  local sig

  TRAP_PID=$BASHPID

  for sig; do
    trap "$func $sig" "$sig"
  done

  return 0
}

signalCode() {

  local sig="$1"

  case "$sig" in
    SIGHUP)  echo 129 ;;
    SIGINT)  echo 130 ;;
    SIGQUIT) echo 131 ;;
    SIGABRT) echo 134 ;;
    SIGTERM) echo 143 ;;
    *)       echo 0 ;;
  esac

  return 0
}

displayReason() {

  local reason="$1"

  case "$reason" in
    129 ) echo "SIGHUP" ;;
    130 ) echo "SIGINT" ;;
    131 ) echo "SIGQUIT" ;;
    134 ) echo "SIGABRT" ;;
    143 ) echo "SIGTERM" ;;
    * )   echo "$reason" ;;
  esac

  return 0
}

readQemuPid() {

  local -n _pid="$1"

  if [ ! -s "$QEMU_PID" ] || ! read -r _pid <"$QEMU_PID"; then
    return 1
  fi

  return 0
}

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
        info "$(app) started successfully, visit http://127.0.0.1:8006/ to view the screen..."
        return 0
      fi
    fi
  fi

  error "Timeout while waiting for QEMU to boot the machine, aborting..."
  sKill "$QEMU_PID"

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

forceKillQemu() {

  local reason="$1"
  local pid=""
  local display

  ! readQemuPid pid && return 0
  ! isAlive "$pid" && return 0

  display=$(displayReason "$reason")
  error "Forcefully terminating $(app), reason: $display..."
  { disown "$pid" || :; kill -9 -- "$pid" || :; } 2>/dev/null

  return 0
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

cleanupHelpers() {

  local pids=( "${SMB_PID:-}" "${NMB_PID:-}" "${DDN_PID:-}" \
               "${TPM_PID:-}" "${WSD_PID:-}" "${WEB_PID:-}" \
               "${AUX_PID:-}" "${AUDIO_PID:-}" "${CONSOLE_PID:-}" \
               "${PASST_PID:-}" "${DNSMASQ_PID:-}" "${BALLOONING_PID:-}" )

  mKill "${pids[@]}"

  closeNetwork
  return 0
}

startConsole() {

  local cnt=0
  local pid=""
  local output="${1:-/dev/tty}"

  rm -f -- "$CONSOLE_SOCKET" "$CONSOLE_PID"

  if ! stty -icanon -echo isig -ixon min 1 time 0 </dev/tty; then
    error "Failed to configure serial console terminal!"
    return 1
  fi

  (
    trap '' INT QUIT
    exec nc -lU "$CONSOLE_SOCKET" </dev/tty >"$output"
  ) &

  pid=$!
  echo "$pid" > "$CONSOLE_PID"

  while [ ! -S "$CONSOLE_SOCKET" ]; do

    if ! isAlive "$pid"; then
      rm -f -- "$CONSOLE_PID"
      error "Serial console relay exited unexpectedly!"
      return 1
    fi

    sleep 0.02
    cnt=$((cnt + 1))

    if (( cnt > 100 )); then
      error "Failed to start serial console relay!"
      return 1
    fi

  done

  return 0
}

stopConsole() {

  mKill "$CONSOLE_PID"

  return 0
}

finish() {

  local reason=$1
  local failed=0

  if [ ! -f "$QEMU_END" ] && (( reason != 0 )); then
    failed=1
  fi

  touch "$QEMU_END"

  forceKillQemu "$reason"

  if [ ! -f "$STORAGE/windows.boot" ]; then
    markWindowsBooted
  fi

  cleanupHelpers

  if ! waitPidFile "$QEMU_PID" 10; then
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

normalizeTimeout() {

  local term_grace=3      # seconds before loop ends to send SIGTERM
  local cleanup_grace=3   # seconds reserved after the loop for cleanup
  local min

  TIMEOUT=$(strip "$TIMEOUT")
  if [[ ! "$TIMEOUT" =~ ^[0-9]+$ ]]; then
    TIMEOUT=115
  fi

  if (( TIMEOUT >= 30 )); then
    term_grace=5
    cleanup_grace=5
  elif (( TIMEOUT >= 15 )); then
    term_grace=4
    cleanup_grace=4
  fi

  min=$((term_grace + cleanup_grace + 1))
  (( TIMEOUT < min )) && (( TIMEOUT = min ))

  wait_until=$((TIMEOUT - cleanup_grace))
  sigterm_at=$((wait_until - term_grace))

  return 0
}

sendAcpiShutdown() {

  [ ! -S "$QEMU_DIR/monitor.sock" ] && return 0

  # Send ACPI shutdown signal
  nc -q 1 -w 1 -U "$QEMU_DIR/monitor.sock" &> /dev/null <<<'system_powerdown' || :

  return 0
}

abortDuringSetup() {

  local code="$1"
  info "Cannot send ACPI signal during $(app) setup, aborting..."

  sKill "$QEMU_PID"

  if ! waitPidFile "$QEMU_PID" 5; then
    warn "Timed out while waiting for $(app) to exit!"
  fi

  finish "$code"
}

waitForShutdown() {

  local cnt=0
  local pid="$1"
  local name="$APP"
  local slp

  while (( cnt <= wait_until && SHUTDOWN_SKIP == 0 )); do

    sleep 1 &
    slp=$!

    # Stop waiting if the process has exited
    ! isAlive "$pid" && break

    # Workaround for stale/zombie QEMU pid file
    [ ! -s "$QEMU_PID" ] && break

    if (( cnt == sigterm_at )); then
      info "${name^} is still running, sending SIGTERM... ($cnt/$wait_until)"
      kill -15 -- "$pid" 2>/dev/null || :
    elif (( cnt > 0 )); then
      info "Waiting for $name to shut down... ($cnt/$wait_until)"
    fi

    sendAcpiShutdown

    wait "$slp" || :
    (( cnt++ ))

  done

  return 0
}

graceful_shutdown() {

  local sig="$1"
  local pid=""
  local code=0

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
    warn "QEMU PID file ($QEMU_PID) does not exist?"
    finish "$code"
  fi

  if [ -z "$pid" ] || ! isAlive "$pid"; then
    warn "QEMU process with PID $pid does not exist?"
    finish "$code"
  fi

  if ! ready; then
    abortDuringSetup "$code"
  fi

  normalizeTimeout
  waitForShutdown "$pid"

  finish "$code"
}

! enabled "$SHUTDOWN" && return 0
[ -n "${QEMU_TIMEOUT:-}" ] && TIMEOUT="$QEMU_TIMEOUT"

if interactive; then
  _trap graceful_shutdown SIGINT
fi

_trap graceful_shutdown SIGTERM SIGHUP SIGABRT SIGQUIT

return 0

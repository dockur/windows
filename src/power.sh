#!/usr/bin/env bash
set -Eeuo pipefail

: "${SHUTDOWN:="Y"}"        # Graceful ACPI shutdown
: "${TIMEOUT:="115"}"       # QEMU termination timeout

# Configure QEMU for graceful shutdown

QEMU_PTY="$QEMU_DIR/qemu.pty"
QEMU_END="$QEMU_DIR/qemu.end"

_trap() {
  local func="$1"; shift
  local sig
  TRAP_PID=$BASHPID

  for sig; do
    trap "$func $sig" "$sig"
  done
}

app() {
  echo "$APP" && return 0
}

boot() {

  [ -f "$QEMU_END" ] && return 0

  if [ -s "$QEMU_PTY" ]; then
    if [ "$(stat -c%s "$QEMU_PTY")" -gt 7 ]; then
      local fail=""
      if [[ "${BOOT_MODE,,}" == "windows_legacy" ]]; then
        grep -Fq "No bootable device." "$QEMU_PTY" && fail="y"
        grep -Fq "BOOTMGR is missing" "$QEMU_PTY" && fail="y"
      fi
      if [ -z "$fail" ]; then
        info "$(app) started successfully, visit http://127.0.0.1:8006/ to view the screen..."
        return 0
      fi
    fi
  fi

  error "Timeout while waiting for QEMU to boot the machine, aborting..."
  sKill "$QEMU_PID"

  return 0
}

ready() {

  [ -f "$STORAGE/windows.boot" ] && return 0
  [ ! -s "$QEMU_PTY" ] && return 1

  if [[ "${BOOT_MODE,,}" == "windows_legacy" ]]; then
    local last
    local bios="Booting from Hard"
    last=$(grep "^Booting.*" "$QEMU_PTY" | tail -1)
    [[ "${last,,}" != "${bios,,}"* ]] && return 1
    grep -Fq "No bootable device." "$QEMU_PTY" && return 1
    grep -Fq "BOOTMGR is missing" "$QEMU_PTY" && return 1
    return 0
  fi

  local line="\"Windows Boot Manager\""
  grep -Fq "$line" "$QEMU_PTY" && return 0

  return 1
}

finish() {

  local i=0
  local pid=""
  local reason=$1
  local pids=( "${SMB_PID:-}" "${NMB_PID:-}" "${DDN_PID:-}" "${TPM_PID:-}" "${WSD_PID:-}" \
               "${WEB_PID:-}" "${PASST_PID:-}" "${DNSMASQ_PID:-}" "${BALLOONING_PID:-}" )

  touch "$QEMU_END"

  if [ -s "$QEMU_PID" ]; then
    if read -r pid <"$QEMU_PID"; then
      if [ -n "$pid" ] && isAlive "$pid"; then
        local display="$reason"
        case "$reason" in
          129 ) display="SIGHUP" ;;
          130 ) display="SIGINT" ;;
          131 ) display="SIGQUIT" ;;
          134 ) display="SIGABRT" ;;
          143 ) display="SIGTERM" ;;
        esac
        error "Forcefully terminating $(app), reason: $display..."
        { disown "$pid" || :; kill -9 -- "$pid" || :; } 2>/dev/null
      fi
    fi
  fi

  if [ ! -f "$STORAGE/windows.boot" ] && [ -f "$BOOT" ]; then
    # Remove CD-ROM ISO after install
    if ready; then
      local file="$STORAGE/windows.boot"
      touch "$file"
      ! setOwner "$file" && error "Failed to set the owner for \"$file\" !"
      if [[ "$REMOVE" != [Nn]* ]]; then
        rm -f "$BOOT" 2>/dev/null || true
      fi
    fi
  fi

  mKill "${pids[@]}"
  closeNetwork

  if ! waitPidFile "$QEMU_PID" 10; then
    warn "Timed out while waiting for $(app) to exit!"
  fi

  (( reason != 1 )) && echo && echo "❯ Shutdown completed!"
  exit "$reason"
}

graceful_shutdown() {

  local sig="$1"
  local pid=""
  local code=0

  [[ $BASHPID != "$TRAP_PID" ]] && return

  case "$sig" in
    SIGHUP)  code=129 ;;
    SIGINT)  code=130 ;;
    SIGQUIT) code=131 ;;
    SIGABRT) code=134 ;;
    SIGTERM) code=143 ;;
  esac

  if [ -f "$QEMU_END" ]; then
    echo && info "Received $1 signal while already shutting down..."
    return
  fi

  set +e
  touch "$QEMU_END"
  echo && info "Received $1 signal, sending ACPI shutdown signal..."

  if [ ! -s "$QEMU_PID" ] || ! read -r pid <"$QEMU_PID"; then
    warn "QEMU PID file ($QEMU_PID) does not exist?"
    finish "$code"
  fi

  if [ -z "$pid" ] || ! isAlive "$pid"; then
    warn "QEMU process with PID $pid does not exist?"
    finish "$code"
  fi

  if ! ready; then
    info "Cannot send ACPI signal during $(app) setup, aborting..."
    sKill "$QEMU_PID"
    if ! waitPidFile "$QEMU_PID" 5; then
      warn "Timed out while waiting for $(app) to exit!"
    fi
    finish "$code"
  fi

  local name
  name="$(app)"

  local term_grace=3      # seconds before loop ends to send SIGTERM
  local cleanup_grace=3   # seconds reserved after the loop for cleanup

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

  local cnt=0 sigterm_at=0 min wait_until

  min=$((term_grace + cleanup_grace + 1))
  (( TIMEOUT < min )) && (( TIMEOUT = min ))

  wait_until=$((TIMEOUT - cleanup_grace))
  sigterm_at=$((wait_until - term_grace))

  while (( cnt <= wait_until )); do

    sleep 1 &
    local slp=$!

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

    # Send ACPI shutdown signal
    if [ -S "$QEMU_DIR/monitor.sock" ]; then
      nc -q 1 -w 1 -U "$QEMU_DIR/monitor.sock" &> /dev/null <<<'system_powerdown' || :
    fi

    wait "$slp"
    (( cnt++ ))

  done

  finish "$code"
}

[[ "$SHUTDOWN" != [Yy1]* ]] && return 0
[ -n "${QEMU_TIMEOUT:-}" ] && TIMEOUT="$QEMU_TIMEOUT"

_trap graceful_shutdown SIGTERM SIGHUP SIGABRT SIGQUIT

return 0

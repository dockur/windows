#!/usr/bin/env bash
set -Eeuo pipefail

: "${SHUTDOWN:="Y"}"        # Graceful ACPI shutdown
: "${TIMEOUT:="110"}"       # QEMU termination timeout

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
  local pids=( "$SMB_PID" "$NMB_PID" "$DDN_PID" "$TPM_PID" "$WSD_PID" \
               "$WEB_PID" "$PASST_PID" "$DNSMASQ_PID" "${BALLOONING_PID:-}" )

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
    echo && info "Received $1 while already shutting down..."
    return
  fi

  set +e
  touch "$QEMU_END"
  echo && info "Received $1, sending ACPI shutdown signal..."

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

  local cnt=0 abort=0 factor=3 offset=3 min max name

  [[ "$TIMEOUT" =~ ^[0-9]+$ ]] || TIMEOUT=110
  [ "$TIMEOUT" -ge 15 ] && factor=4 && offset=4
  [ "$TIMEOUT" -ge 30 ] && factor=5 && offset=5
  min=$((factor + offset + 1))
  [ "$TIMEOUT" -lt "$min" ] && TIMEOUT="$min"
  max=$(( TIMEOUT - offset ))
  abort=$(( max - factor ))
  name="$(app)"

  while [ "$cnt" -le "$max" ]; do

    sleep 1 &
    local slp=$!

    ! isAlive "$pid" && break
    # Workaround for zombie pid
    [ ! -s "$QEMU_PID" ] && break

    if [ "$cnt" -ne "$abort" ]; then
      if [ "$cnt" -gt 0 ]; then
        info "Waiting for $name to shut down... ($cnt/$max)"
      fi
    else
      info "${name^} is still running, sending SIGTERM... ($cnt/$max)"
      { kill -15 -- "$pid" || :; } 2>/dev/null
    fi

    # Send ACPI shutdown signal
    if [ -S "$QEMU_DIR/monitor.sock" ]; then
      nc -q 1 -w 1 -U "$QEMU_DIR/monitor.sock" &> /dev/null <<<'system_powerdown' || :
    fi

    wait $slp
    (( cnt++ ))

  done

  finish "$code"
}

[[ "$SHUTDOWN" != [Yy1]* ]] && return 0
[ -n "${QEMU_TIMEOUT:-}" ] && TIMEOUT="$QEMU_TIMEOUT"

_trap graceful_shutdown SIGTERM SIGHUP SIGABRT SIGQUIT

return 0

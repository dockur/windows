#!/usr/bin/env bash
set -Eeuo pipefail

# Configure QEMU for graceful shutdown

QEMU_TERM=""
QEMU_PORT=7100
QEMU_TIMEOUT=110
QEMU_DIR="/run/shm"
QEMU_PID="$QEMU_DIR/qemu.pid"
QEMU_PTY="$QEMU_DIR/qemu.pty"
QEMU_LOG="$QEMU_DIR/qemu.log"
QEMU_OUT="$QEMU_DIR/qemu.out"
QEMU_END="$QEMU_DIR/qemu.end"

rm -f "$QEMU_DIR/qemu.*"
touch "$QEMU_LOG"

_trap() {
  func="$1" ; shift
  for sig ; do
    trap "$func $sig" "$sig"
  done
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
        info "Windows started succesfully, visit http://127.0.0.1:8006/ to view the screen..."
        return 0
      fi
    fi
  fi

  error "Timeout while waiting for QEMU to boot the machine!"

  local pid
  pid=$(<"$QEMU_PID")
  { kill -15 "$pid" || true; } 2>/dev/null

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

  local pid
  local reason=$1

  touch "$QEMU_END"

  if [ -s "$QEMU_PID" ]; then

    pid=$(<"$QEMU_PID")
    error "Forcefully terminating Windows, reason: $reason..."
    { kill -15 "$pid" || true; } 2>/dev/null

    while isAlive "$pid"; do
      sleep 1
      # Workaround for zombie pid
      [ ! -s "$QEMU_PID" ] && break
    done
  fi

  if [ ! -f "$STORAGE/windows.boot" ] && [ -f "$BOOT" ]; then
    # Remove CD-ROM ISO after install
    if ready; then
      touch "$STORAGE/windows.boot"
      if [[ "$REMOVE" != [Nn]* ]]; then
        rm -f "$BOOT" 2>/dev/null || true
      fi
    fi
  fi

  pid="/var/run/tpm.pid"
  [ -s "$pid" ] && pKill "$(<"$pid")"

  pid="/var/run/wsdd.pid"
  [ -s "$pid" ] && pKill "$(<"$pid")"

  fKill "smbd"

  closeNetwork

  sleep 0.5
  echo "❯ Shutdown completed!"

  exit "$reason"
}

terminal() {

  local dev=""

  if [ -s "$QEMU_OUT" ]; then

    local msg
    msg=$(<"$QEMU_OUT")

    if [ -n "$msg" ]; then

      if [[ "${msg,,}" != "char"* ||  "$msg" != *"serial0)" ]]; then
        echo "$msg"
      fi

      dev="${msg#*/dev/p}"
      dev="/dev/p${dev%% *}"

    fi
  fi

  if [ ! -c "$dev" ]; then
    dev=$(echo 'info chardev' | nc -q 1 -w 1 localhost "$QEMU_PORT" | tr -d '\000')
    dev="${dev#*serial0}"
    dev="${dev#*pty:}"
    dev="${dev%%$'\n'*}"
    dev="${dev%%$'\r'*}"
  fi

  if [ ! -c "$dev" ]; then
    error "Device '$dev' not found!"
    finish 34 && return 34
  fi

  QEMU_TERM="$dev"
  return 0
}

_graceful_shutdown() {

  local code=$?

  set +e

  if [ -f "$QEMU_END" ]; then
    info "Received $1 while already shutting down..."
    return
  fi

  touch "$QEMU_END"
  info "Received $1, sending ACPI shutdown signal..."

  if [ ! -s "$QEMU_PID" ]; then
    error "QEMU PID file does not exist?"
    finish "$code" && return "$code"
  fi

  local pid=""
  pid=$(<"$QEMU_PID")

  if ! isAlive "$pid"; then
    error "QEMU process does not exist?"
    finish "$code" && return "$code"
  fi

  if ! ready; then
    info "Cannot send ACPI signal during Windows setup, aborting..."
    finish "$code" && return "$code"
  fi

  # Send ACPI shutdown signal
  echo 'system_powerdown' | nc -q 1 -w 1 localhost "${QEMU_PORT}" > /dev/null

  local cnt=0
  while [ "$cnt" -lt "$QEMU_TIMEOUT" ]; do

    sleep 1
    cnt=$((cnt+1))

    ! isAlive "$pid" && break
    # Workaround for zombie pid
    [ ! -s "$QEMU_PID" ] && break

    info "Waiting for Windows to shutdown... ($cnt/$QEMU_TIMEOUT)"

    # Send ACPI shutdown signal
    echo 'system_powerdown' | nc -q 1 -w 1 localhost "${QEMU_PORT}" > /dev/null

  done

  if [ "$cnt" -ge "$QEMU_TIMEOUT" ]; then
    error "Shutdown timeout reached, aborting..."
  fi

  finish "$code" && return "$code"
}

SERIAL="pty"
MONITOR="telnet:localhost:$QEMU_PORT,server,nowait,nodelay"
MONITOR+=" -daemonize -D $QEMU_LOG -pidfile $QEMU_PID"

_trap _graceful_shutdown SIGTERM SIGHUP SIGINT SIGABRT SIGQUIT

return 0

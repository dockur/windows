#!/usr/bin/env bash
set -Eeuo pipefail

# Configure QEMU for graceful shutdown

QEMU_TERM=""
QEMU_PORT=7100
QEMU_TIMEOUT=50
QEMU_PID="/run/shm/qemu.pid"
QEMU_LOG="/run/shm/qemu.log"
QEMU_OUT="/run/shm/qemu.out"
QEMU_END="/run/shm/qemu.end"

touch "$QEMU_LOG"

_trap() {
  func="$1" ; shift
  for sig ; do
    trap "$func $sig" "$sig"
  done
}

finish() {

  local pid
  local reason=$1

  if [ -f "$QEMU_PID" ]; then

    pid=$(<"$QEMU_PID")
    echo && error "Forcefully terminating QEMU process, reason: $reason..."
    { kill -15 "$pid" || true; } 2>/dev/null

    while isAlive "$pid"; do
      sleep 1
      # Workaround for zombie pid
      [ ! -f "$QEMU_PID" ] && break
    done
  fi

  closeNetwork

  sleep 1
  echo && echo "❯ Shutdown completed!"

  exit "$reason"
}

terminal() {

  local dev=""

  if [ -f "$QEMU_OUT" ]; then

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
  local pid url response

  set +e

  if [ -f "$QEMU_END" ]; then
    echo && info "Received $1 signal while already shutting down..."
    return
  fi

  touch "$QEMU_END"
  echo && info "Received $1 signal, sending ACPI shutdown signal..."

  if [ ! -f "$QEMU_PID" ]; then
    echo && error "QEMU PID file does not exist?"
    finish "$code" && return "$code"
  fi

  pid=$(<"$QEMU_PID")

  if ! isAlive "$pid"; then
    echo && error "QEMU process does not exist?"
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
    [ ! -f "$QEMU_PID" ] && break

    info "Waiting for Windows shutdown... ($cnt/$QEMU_TIMEOUT)"

    # Send ACPI shutdown signal
    echo 'system_powerdown' | nc -q 1 -w 1 localhost "${QEMU_PORT}" > /dev/null

  done

  if [ "$cnt" -ge "$QEMU_TIMEOUT" ]; then
    echo && error "Shutdown timeout reached, aborting..."
  fi

  finish "$code" && return "$code"
}

MON_OPTS="\
        -pidfile $QEMU_PID \
        -monitor telnet:localhost:$QEMU_PORT,server,nowait,nodelay"

if [[ "$CONSOLE" != [Yy]* ]]; then

  MON_OPTS="$MON_OPTS -daemonize -D $QEMU_LOG"

  _trap _graceful_shutdown SIGTERM SIGHUP SIGINT SIGABRT SIGQUIT

fi

return 0

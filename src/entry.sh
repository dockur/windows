#!/usr/bin/env bash
set -Eeuo pipefail

: "${BOOT_MODE:="windows"}"

APP="Windows"
SUPPORT="https://github.com/dockur/windows"

cd /run

. reset.sh      # Initialize system
. define.sh     # Define versions
. install.sh    # Run installation
. disk.sh       # Initialize disks
. display.sh    # Initialize graphics
. network.sh    # Initialize network
. samba.sh      # Configure samba
. boot.sh       # Configure boot
. proc.sh       # Initialize processor
. power.sh      # Configure shutdown
. config.sh     # Configure arguments

trap - ERR

info "Booting ${APP}${BOOT_DESC}..."
[[ "$DEBUG" == [Yy1]* ]] && echo "Arguments: $ARGS" && echo

{ qemu-system-x86_64 ${ARGS:+ $ARGS} >"$QEMU_OUT" 2>"$QEMU_LOG"; rc=$?; } || :
(( rc != 0 )) && error "$(<"$QEMU_LOG")" && exit 15

terminal
( sleep 10; boot ) &
tail -fn +0 "$QEMU_LOG" 2>/dev/null &
cat "$QEMU_TERM" 2> /dev/null | tee "$QEMU_PTY" &
wait $! || :

sleep 1 & wait $!
finish 0

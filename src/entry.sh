#!/usr/bin/env bash
set -Eeuo pipefail

: "${APP:="Windows"}"
: "${PLATFORM:="x64"}"
: "${BOOT_MODE:="windows"}"
: "${SUPPORT:="https://github.com/dockur/windows"}"

cd /run

. start.sh      # Startup hook
. utils.sh      # Load functions
. reset.sh      # Initialize system
. server.sh     # Start webserver
. define.sh     # Define versions
. mido.sh       # Download Windows
. install.sh    # Run installation
. disk.sh       # Initialize disks
. display.sh    # Initialize graphics
. network.sh    # Initialize network
. samba.sh      # Configure samba
. boot.sh       # Configure boot
. proc.sh       # Initialize processor
. power.sh      # Configure shutdown
. memory.sh     # Check available memory
. balloon.sh    # Initialize ballooning
. config.sh     # Configure arguments
. finish.sh     # Finish initialization

trap - ERR

cmd=(qemu-system-x86_64)
version=$("${cmd[@]}" --version | awk 'NR==1 { print $4 }')
info "Booting ${APP}${BOOT_DESC} using QEMU v$version..." && echo

pipe="$QEMU_DIR/qemu.pipe"
rm -f "$pipe" && mkfifo "$pipe"

tee "$QEMU_PTY" <"$pipe" |
sed -u \
  -e 's/\x1B\[[=0-9;]*[a-z]//gi' \
  -e 's/\x1B\x63//g' \
  -e 's/\x1B\[[=?]7l//g' \
  -e '/^$/d' \
  -e 's/\x44\x53\x73//g' \
  -e 's/failed to load Boot/skipped Boot/g' \
  -e 's/0): Not Found/0)/g' &

if ! enabled "$SHUTDOWN"; then
  exec "${cmd[@]}" ${ARGS:+ $ARGS} >"$pipe"
fi

"${cmd[@]}" ${ARGS:+ $ARGS} >"$pipe" &

pid=$!
( sleep 30; boot ) &

rc=0
wait "$pid" || rc=$?
[ -f "$QEMU_END" ] && exit "$rc"

sleep 1 & wait $!
finish "$rc"

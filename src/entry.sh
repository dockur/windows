#!/usr/bin/env bash
set -Eeuo pipefail

: "${APP:="Windows"}"
: "${PLATFORM:="x64"}"
: "${BOOT_MODE:="windows"}"
: "${SUPPORT:="https://github.com/dockur/windows"}"

cd /run

. start.sh      # Startup hook
. utils.sh      # Load functions
. init.sh       # Initialize system
. memory.sh     # Check memory
. server.sh     # Start webserver
. download.sh   # Load functions
. define.sh     # Define versions
. mido.sh       # Download Windows
. answer.sh     # Setup answer files
. legacy.sh     # Legacy installation
. image.sh      # Detect image files
. install.sh    # Run installation
. disk.sh       # Initialize disks
. display.sh    # Initialize graphics
. audio.sh      # Initialize audio
. network.sh    # Initialize network
. samba.sh      # Configure samba
. boot.sh       # Configure boot
. proc.sh       # Initialize processor
. power.sh      # Configure shutdown
. balloon.sh    # Initialize ballooning
. config.sh     # Configure arguments

# Windows Me hardware-detection diagnostic: config.sh from the QEMU base adds a
# VirtIO RNG device unconditionally. Strip just that inherited device from the
# completed argument list instead of overriding the base config implementation.
if enabled "${WINME_MINIMAL_HW:-N}"; then
  ARGS=$(printf '%s\n' "$ARGS" | sed -E \
    -e 's/(^| )-object rng-random,id=objrng0,filename=\/dev\/urandom( |$)/ /' \
    -e 's/(^| )-device virtio-rng-pci,rng=objrng0,id=rng0,bus=[^ ]+( |$)/ /' \
    -e 's/[[:space:]]+/ /g' \
    -e 's/^ //;s/ $//')
fi

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

output=$!

if ! enabled "$SHUTDOWN"; then
  exec "${cmd[@]}" ${ARGS:+ $ARGS} >"$pipe" 2>&1
fi

if ! interactive; then
  "${cmd[@]}" ${ARGS:+ $ARGS} >"$pipe" 2>&1 &
else
  startConsole "$pipe"
  startQemu "${cmd[@]}" ${ARGS:+ $ARGS} >"$pipe" 2>&1
fi

pid=$!
waitForBoot "$pid" 30 &

rc=0
wait "$pid" || rc=$?
interactive && stopConsole
wait "$output" || :

[ -f "$QEMU_END" ] && exit "$rc"

sleep 1 & wait $!
finish "$rc"

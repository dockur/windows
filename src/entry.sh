#!/usr/bin/env bash
set -Eeuox pipefail

: "${APP:="Windows"}"
: "${PLATFORM:="x64"}"
: "${BOOT_MODE:="windows"}"
: "${SUPPORT:="https://github.com/dockur/windows"}"

cd /run

. utils.sh      # Load functions
. reset.sh      # Initialize system
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
. config.sh     # Configure arguments

trap - ERR

version=$(qemu-system-x86_64 --version | head -n 1 | cut -d '(' -f 1 | awk '{ print $NF }')
info "Booting ${APP}${BOOT_DESC} using QEMU v$version..."

{
    qemu-system-x86_64 ${ARGS:+ $ARGS} >"$QEMU_OUT" 2>"$QEMU_LOG"
    rc=$?
} || :
((rc != 0)) && error "$(<"$QEMU_LOG")" && exit 15

terminal
(
    sleep 30
    boot

    if ! configure_guest_network_interface; then
        error "Failed to configure guest network interfaces"
        exit 666
    fi

    if [[ -n "${EXTRA_SCRIPT:-}" ]]; then
        info "Executing extra script: $EXTRA_SCRIPT"
        if ! "$EXTRA_SCRIPT"; then
            error "Extra script failed"
            exit 555
        fi
    fi

    info "Windows started successfully, you can now connect using RDP or visit http://localhost:8006/ to view the screen..."
    touch "$STORAGE/ready"
) &
bg_pid=$!

tail -fn +0 "$QEMU_LOG" 2>/dev/null &
cat "$QEMU_TERM" 2>/dev/null | tee "$QEMU_PTY" |
    sed -u -e 's/\x1B\[[=0-9;]*[a-z]//gi' \
        -e 's/failed to load Boot/skipped Boot/g' \
        -e 's/0): Not Found/0)/g' &
term_pd=$!

wait $bg_pid
exit_code=$?

if [[ $exit_code -ne 0 ]]; then
    error "A critical process failed, exiting container..."
    exit $exit_code
fi

wait $term_pd || :

sleep 1 &
wait $!
[ ! -f "$QEMU_END" ] && finish 0

#!/usr/bin/env bash
set -Eeuo pipefail

echo "❯ Starting Windows for Docker v$(</run/version)..."
echo "❯ For support visit https://github.com/dockur/windows"

export DISPLAY=web
export BOOT_MODE=windows

cd /run

. reset.sh      # Initialize system
. install.sh    # Get bootdisk
. disk.sh       # Initialize disks
. display.sh    # Initialize graphics
. network.sh    # Initialize network
. boot.sh       # Configure boot
. proc.sh       # Initialize processor
. config.sh     # Configure arguments

trap - ERR

if [[ "${DISPLAY,,}" == "web" ]]; then
  websockify -D --web /usr/share/novnc/ 8006 localhost:5900 2>/dev/null
fi

info "Booting Windows using $VERS..."

[[ "$DEBUG" == [Yy1]* ]] && set -x
exec qemu-system-x86_64 ${ARGS:+ $ARGS}

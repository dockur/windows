#!/usr/bin/env bash
set -Eeuo pipefail

[[ "$DHCP" == [Yy1]* ]] && return 0

SHARE="$STORAGE/shared"
mkdir -p "$SHARE"
chmod -R 777 "$SHARE"

{      echo "[global]"
        echo "    server string = Dockur"
        echo "    netbios name = dockur"
        echo "    workgroup = WORKGROUP"
        echo "    interfaces = dockerbridge"
        echo "    bind interfaces only = yes"
        echo "    security = user"
        echo "    guest account = nobody"
        echo "    map to guest = Bad User"
        echo "    #server min protocol = SMB2"
        echo ""
        echo "    # disable printing services"
        echo "    load printers = no"
        echo "    printing = bsd"
        echo "    printcap name = /dev/null"
        echo "    disable spoolss = yes"
        echo ""
        echo "[Shared]"
        echo "    path = $SHARE"
        echo "    comment = Shared"
        echo "    writable = yes"
        echo "    guest ok = yes"
        echo "    guest only = yes"
        echo "    force user = root"
        echo "    force group = root"
} > "/etc/samba/smb.conf"

smbd -D
wsdd -i dockerbridge -p -n "host.local" &

return 0

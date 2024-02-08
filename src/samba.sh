#!/usr/bin/env bash
set -Eeuo pipefail

[[ "$DHCP" == [Yy1]* ]] && return 0

SHARE="$STORAGE/shared"

mkdir -p "$SHARE"
chmod -R 777 "$SHARE"

SAMBA="/etc/samba/smb.conf"

{      echo "[global]"
        echo "    server string = Dockur"
        echo "    netbios name = dockur"
        echo "    workgroup = WORKGROUP"
        echo "    interfaces = dockerbridge"
        echo "    bind interfaces only = yes"
        echo "    security = user"
        echo "    guest account = nobody"
        echo "    map to guest = Bad User"
        echo "    server min protocol = SMB2"
        echo ""
        echo "    # disable printing services"
        echo "    load printers = no"
        echo "    printing = bsd"
        echo "    printcap name = /dev/null"
        echo "    disable spoolss = yes"
        echo ""
        echo "[Data]"
        echo "    path = $SHARE"
        echo "    comment = Shared"
        echo "    writable = yes"
        echo "    guest ok = yes"
        echo "    guest only = yes"
        echo "    force user = root"
        echo "    force group = root"
} > "$SAMBA"

{      echo "--------------------------------------------------------" 
        echo " $APP for Docker v$(</run/version)..."
        echo " For support visit $SUPPORT"
        echo "--------------------------------------------------------"
        echo ""
        echo "Using this folder you can share files with the host machine."
        echo ""
        echo "To change the storage location, include the following bind mount in your compose file:"
        echo ""
        echo "  volumes:"
        echo "    - \"/home/user/example:/storage/shared\""
        echo ""
        echo "Or in your run command:"
        echo ""
        echo "  -v \"/home/user/example:/storage/shared\""
        echo ""
        echo "Replace the example path /home/user/example with the desired storage folder."
        echo ""
} | unix2dos > "$SHARE/readme.txt"

smbd -D
wsdd -i dockerbridge -p -n "host.lan" &

return 0

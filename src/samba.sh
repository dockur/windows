#!/usr/bin/env bash
set -Eeuo pipefail

: "${SAMBA:="Y"}"

[[ "$DHCP" == [Yy1]* ]] && return 0
[[ "$SAMBA" != [Yy1]* ]] && return 0
[[ "$NETWORK" != [Yy1]* ]] && return 0

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
        echo "    server min protocol = NT1"
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

! smbd && smbd --debug-stdout

isXP="N"

if [ -f "$STORAGE/windows.old" ]; then
  MT=$(<"$STORAGE/windows.old")
  if [[ "${MT,,}" == "pc-q35-2"* ]]; then
    isXP="Y"
  fi
fi

if [[ "$isXP" == [Yy1]* ]]; then
  # Enable NetBIOS on Windows XP
  ! nmbd && nmbd --debug-stdout
else
  # Enable Web Service Discovery
  wsdd -i dockerbridge -p -n "host.lan" &
fi

return 0

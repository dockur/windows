#!/usr/bin/env bash
set -Eeuo pipefail

: "${SAMBA:="Y"}"

[[ "$SAMBA" == [Nn]* ]] && return 0
[[ "$NETWORK" == [Nn]* ]] && return 0

hostname="host.lan"
interface="dockerbridge"

if [[ "$DHCP" == [Yy1]* ]]; then
  hostname="$IP"
  interface="$VM_NET_DEV"
fi

share="/shared"

if [ ! -d "$share" ] && [ -d "$STORAGE/shared" ]; then
  share="$STORAGE/shared"
fi

mkdir -p "$share"

if [ -z "$(ls -A "$share")" ]; then

  chmod 777 "$share"

  {      echo "--------------------------------------------------------"
          echo " $APP for Docker v$(</run/version)..."
          echo " For support visit $SUPPORT"
          echo "--------------------------------------------------------"
          echo ""
          echo "Using this folder you can share files with the host machine."
          echo ""
          echo "To change its location, include the following bind mount in your compose file:"
          echo ""
          echo "  volumes:"
          echo "    - \"/home/user/example:/shared\""
          echo ""
          echo "Or in your run command:"
          echo ""
          echo "  -v \"/home/user/example:/shared\""
          echo ""
          echo "Replace the example path /home/user/example with the desired shared folder."
          echo ""
  } | unix2dos > "$share/readme.txt"

fi

{      echo "[global]"
        echo "    server string = Dockur"
        echo "    netbios name = $hostname"
        echo "    workgroup = WORKGROUP"
        echo "    interfaces = $interface"
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
        echo "    path = $share"
        echo "    comment = Shared"
        echo "    writable = yes"
        echo "    guest ok = yes"
        echo "    guest only = yes"
        echo "    force user = root"
        echo "    force group = root"
} > "/etc/samba/smb.conf"

if ! smbd; then
  error "Samba daemon failed to start!"
  smbd -i --debug-stdout || true
fi

legacy=""

if [ -f "$STORAGE/windows.old" ]; then
  MT=$(<"$STORAGE/windows.old")
  [[ "${MT,,}" == "pc-q35-2"* ]] && legacy="y"
  [[ "${MT,,}" == "pc-i440fx-2"* ]] && legacy="y"
fi

if [ -n "$legacy" ]; then
  # Enable NetBIOS on Windows XP and lower
  if ! nmbd; then
    error "NetBIOS daemon failed to start!"
    nmbd -i --debug-stdout || true
  fi
else
  # Enable Web Service Discovery on Vista and up
  wsdd -i "$interface" -p -n "$hostname" &
  echo "$!" > /var/run/wsdd.pid
fi

return 0

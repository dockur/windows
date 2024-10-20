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

addShare() {
  local dir="$1"
  local name="$2"
  local comment="$3"

  mkdir -p "$dir" || return 1

  if [ -z "$(ls -A "$dir")" ]; then

    chmod 777 "$dir"

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
            echo "    - \"/home/example:/${name,,}\""
            echo ""
            echo "Or in your run command:"
            echo ""
            echo "  -v \"/home/example:/${name,,}\""
            echo ""
            echo "Replace the example path /home/example with the desired shared folder."
            echo ""
    } | unix2dos > "$dir/readme.txt"

  fi

  {      echo ""
          echo "[$name]"
          echo "    path = $dir"
          echo "    comment = $comment"
          echo "    writable = yes"
          echo "    guest ok = yes"
          echo "    guest only = yes"
          echo "    force user = root"
          echo "    force group = root"
  } >> "/etc/samba/smb.conf"

  return 0
}

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
} > "/etc/samba/smb.conf"

share="/data"
[ ! -d "$share" ] && [ -d "$STORAGE/data" ] && share="$STORAGE/data"
[ ! -d "$share" ] && [ -d "/shared" ] && share="/shared"
[ ! -d "$share" ] && [ -d "$STORAGE/shared" ] && share="$STORAGE/shared"

addShare "$share" "Data" "Shared" || error "Failed to create shared folder!"

[ -d "/data2" ] && addShare "/data2" "Data2" "Shared"
[ -d "/data3" ] && addShare "/data3" "Data3" "Shared"

if ! smbd; then
  error "Samba daemon failed to start!"
  smbd -i --debug-stdout || true
fi

if [[ "${BOOT_MODE:-}" == "windows_legacy" ]]; then
  # Enable NetBIOS on Windows 7 and lower
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

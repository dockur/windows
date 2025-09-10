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

if [[ "${NETWORK,,}" == "user"* ]]; then
  interface="127.0.0.1"
fi

addShare() {
  local dir="$1"
  local name="$2"
  local comment="$3"

  mkdir -p "$dir" || return 1
  ls -A "$dir" >/dev/null 2>&1 || return 1

  if [ -z "$(ls -A "$dir")" ]; then

    chmod 777 "$dir" || return 1

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
        echo "    follow symlinks = yes"
        echo "    wide links = yes"
        echo "    unix extensions = no"
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

if ! addShare "$share" "Data" "Shared"; then
  error "Failed to add shared folder '$share'. Please check its permissions." && return 0
fi

if [ -d "/data2" ]; then
  addShare "/data2" "Data2" "Shared" || error "Failed to add shared folder '/data2'. Please check its permissions."
fi

if [ -d "/data3" ]; then
  addShare "/data3" "Data3" "Shared" || error "Failed to add shared folder '/data3'. Please check its permissions."
fi

IFS=',' read -r -a dirs <<< "${SHARES:-}"
for dir in "${dirs[@]}"; do
  [ ! -d "$dir" ] && continue
  dir_name=$(basename "$dir")
  addShare "$dir" "$dir_name" "Shared $dir_name" || error "Failed to create shared folder for $dir!"
done

# Fix Samba permissions
[ -d /run/samba/msg.lock ] && chmod -R 0755 /run/samba/msg.lock
[ -d /var/log/samba/cores ] && chmod -R 0700 /var/log/samba/cores
[ -d /var/cache/samba/msg.lock ] && chmod -R 0755 /var/cache/samba/msg.lock

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

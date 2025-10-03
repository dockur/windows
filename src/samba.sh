#!/usr/bin/env bash
set -Eeuo pipefail

: "${SAMBA:="Y"}"        # Enable Samba
: "${SAMBA_DEBUG:="N"}"  # Disable debug
: "${SAMBA_LEVEL:="1"}"  # Debug log level

tmp="/tmp/smb"
rm -rf "$tmp"
rm -rf /var/run/wsdd.pid

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

html "Initializing shared folder..."
[[ "$DEBUG" == [Yy1]* ]] && echo "Starting Samba daemon..."

addShare() {
  local dir="$1"
  local ref="$2"
  local name="$3" 
  local comment="$4"

  mkdir -p "$dir" || return 1
  ls -A "$dir" >/dev/null 2>&1 || return 1

  if [ -z "$(ls -A "$dir")" ]; then
    chmod 777 "$dir" || return 1
  fi

  if [[ "$dir" == "$tmp" ]]; then

    {      echo "--------------------------------------------------------"
            echo " $APP for Docker v$(</run/version)..."
            echo " For support visit $SUPPORT"
            echo "--------------------------------------------------------"
            echo ""
            echo "Using this folder you can exchange files with the host machine."
            echo ""
            echo "To select a folder on the host for this purpose, include the following bind mount in your compose file:"
            echo ""
            echo "  volumes:"
            echo "    - \"./example:${ref}\""
            echo ""
            echo "Or in your run command:"
            echo ""
            echo "  -v \"\${PWD:-.}/example:${ref}\""
            echo ""
            echo "Replace the example path ./example with your desired shared folder, which then will become visible here."
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

share="/shared"
[ ! -d "$share" ] && [ -d "$STORAGE/shared" ] && share="$STORAGE/shared"
[ ! -d "$share" ] && [ -d "/data" ] && share="/data"
[ ! -d "$share" ] && [ -d "$STORAGE/data" ] && share="$STORAGE/data"
[ ! -d "$share" ] && share="$tmp"

m1="Failed to add shared folder"
m2="Please check its permissions."

if ! addShare "$share" "/shared" "Data" "Shared"; then
  error "$m1 '$share'. $m2" && return 0
fi

if [ -d "/shared2" ]; then
  addShare "/shared2" "/shared2" "Data2" "Shared" || error "$m1 '/shared2'. $m2"
else
  if [ -d "/data2" ]; then
    addShare "/data2" "/shared2" "Data2" "Shared" || error "$m1 '/data2'. $m2."
  fi
fi

if [ -d "/shared3" ]; then
  addShare "/shared3" "/shared3" "Data3" "Shared" || error "$m1 '/shared3'. $m2"
else
  if [ -d "/data3" ]; then
    addShare "/data3" "/shared3" "Data3" "Shared" || error "$m1 '/data3'. $m2"
  fi
fi

IFS=',' read -r -a dirs <<< "${SHARES:-}"
for dir in "${dirs[@]}"; do
  [ ! -d "$dir" ] && continue
  dir_name=$(basename "$dir")
  addShare "$dir" "/shared" "$dir_name" "Shared $dir_name" || error "Failed to create shared folder for $dir!"
done

# Try to repair Samba permissions
[ -d /run/samba/msg.lock ] && chmod -R 0755 /run/samba/msg.lock 2>/dev/null || :
[ -d /var/log/samba/cores ] && chmod -R 0700 /var/log/samba/cores 2>/dev/null || :
[ -d /var/cache/samba/msg.lock ] && chmod -R 0755 /var/cache/samba/msg.lock 2>/dev/null || :

rm -f /var/log/samba/log.smbd

if ! smbd -l /var/log/samba; then
  SAMBA_DEBUG="Y"
  error "Failed to start Samba daemon!"
fi

if [[ "$SAMBA_DEBUG" == [Yy1]* ]]; then
  tail -fn +0 /var/log/samba/log.smbd &
fi

if [[ "${BOOT_MODE:-}" == "windows_legacy" ]]; then

  # Enable NetBIOS on Windows 7 and lower
  [[ "$DEBUG" == [Yy1]* ]] && echo "Starting NetBIOS daemon..."

  rm -f /var/log/samba/log.nmbd

  if ! nmbd -l /var/log/samba; then
    SAMBA_DEBUG="Y"
    error "Failed to start NetBIOS daemon!"
  fi

  if [[ "$SAMBA_DEBUG" == [Yy1]* ]]; then
    tail -fn +0 /var/log/samba/log.nmbd &
  fi

else

  # Enable Web Service Discovery on Vista and up
  [[ "$DEBUG" == [Yy1]* ]] && echo "Starting Web Service Discovery daemon..."

  rm -f /var/log/wsddn.log

  if ! wsddn -i "$interface" -H "$hostname" --unixd --log-file=/var/log/wsddn.log --pid-file=/var/run/wsdd.pid; then
    SAMBA_DEBUG="Y"
    error "Failed to start WSDDN daemon!"
  fi

  if [[ "$SAMBA_DEBUG" == [Yy1]* ]]; then
    tail -fn +0 /var/log/wsddn.log &
  fi

fi

return 0

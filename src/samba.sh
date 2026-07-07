#!/usr/bin/env bash
set -Eeuo pipefail

: "${SAMBA:="Y"}"         # Enable Samba
: "${SAMBA_DEBUG:="N"}"   # Disable debug

tmp="/tmp/smb"
rm -rf "$tmp"

DDN_PID="/var/run/wsdd.pid"
NMB_PID="/var/run/samba/nmbd.pid"
SMB_PID="/var/run/samba/smbd.pid"

rm -f "$SMB_PID" "$NMB_PID" "$DDN_PID"

disabled "$SAMBA" && return 0
disabled "$NETWORK" && return 0

configureNetwork() {

  if enabled "$DHCP"; then
    socket="$UPLINK"
    hostname="$UPLINK"
    interfaces="$DEV"
  else
    hostname="host.lan"
    case "${NETWORK,,}" in
      "passt" | "slirp" )
        interfaces="lo"
        socket="127.0.0.1" ;;
      *)
        socket="$IP"
        interfaces="$BRIDGE" ;;
    esac
    if [ -n "${SAMBA_INTERFACE:-}" ]; then
      interfaces+=",$SAMBA_INTERFACE"
    fi
  fi

  return 0
}

writeReadme() {

  local dir="$1"
  local ref="$2"

  {   echo "--------------------------------------------------------"
      echo " $APP for $ENGINE v$(</etc/version)..."
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

  return 0
}

addShare() {

  local dir="$1"
  local ref="$2"
  local name="$3"
  local comment="$4"
  local cfg="$5"
  local owner=""

  if [ ! -d "$dir" ]; then
    if ! mkdir -p "$dir"; then
      error "Failed to create shared folder ($dir)." && return 1
    fi
  fi

  if ! ls -A "$dir" >/dev/null 2>&1; then
    msg="No permission to access shared folder ($dir)."
    msg+=" If SELinux is active, you need to add the \":Z\" flag to the bind mount."
    error "$msg" && return 1
  fi

  if [ ! -w "$dir" ]; then
    msg="shared folder ($dir) is not writeable!"
    warn "$msg"
  fi

  if [ -z "$(ls -A "$dir")" ]; then
  
    if ! chmod 2777 "$dir"; then
      error "Failed to set permissions for directory $dir" && return 1
    fi
  
    if ! owner=$(stat -c %u "$dir"); then
      error "Failed to determine ownership for directory $dir"
      return 1
    fi

    if [[ "$owner" == "0" ]]; then
      if ! chown "1000:1000" "$dir"; then
        error "Failed to set ownership for directory $dir" && return 1
      fi
    fi
  
  fi

  if [[ "$dir" == "$tmp" ]]; then
    writeReadme "$dir" "$ref"
  fi

  if ! {
    echo ""
    echo "[$name]"
    echo "    path = $dir"
    echo "    comment = $comment"
    echo "    writable = yes"
    echo "    guest ok = yes"
    echo "    guest only = yes"
  } >> "$cfg"; then
    error "Failed to update Samba config \"$cfg\" !"
    return 1
  fi

  return 0
}

writeConfig() {

  {   echo "[global]"
      echo "    server string = Dockur"
      echo "    netbios name = $hostname"
      echo "    workgroup = WORKGROUP"
      echo "    interfaces = $interfaces"
      echo "    bind interfaces only = yes"
      echo "    socket address = $socket"
      echo "    security = user"
      echo "    guest account = nobody"
      echo "    map to guest = Bad User"
      echo "    server min protocol = NT1"
      echo "    follow symlinks = yes"
      echo "    wide links = yes"
      echo "    unix extensions = no"
      echo "    inherit owner = yes"
      echo "    create mask = 0666"
      echo "    directory mask = 02777"
      echo "    force user = root"
      echo "    force group = root"
      echo "    force create mode = 0666"
      echo "    force directory mode = 02777"
      echo ""
      echo "    # Disable printing services"
      echo "    load printers = no"
      echo "    printing = bsd"
      echo "    printcap name = /dev/null"
      echo "    disable spoolss = yes"
  } > "$SAMBA_CONFIG"

  return 0
}

selectPrimaryShare() {

  share="/shared"
  [ ! -d "$share" ] && [ -d "$STORAGE/shared" ] && share="$STORAGE/shared"
  [ ! -d "$share" ] && [ -d "/data" ] && share="/data"
  [ ! -d "$share" ] && [ -d "$STORAGE/data" ] && share="$STORAGE/data"
  [ ! -d "$share" ] && share="$tmp"

  return 0
}

addOptionalShare() {

  local index="$1"
  local ref="/shared$index"
  local name="Data$index"

  if [ -d "$ref" ]; then
    addShare "$ref" "$ref" "$name" "Shared" "$SAMBA_CONFIG" || :
  elif [ -d "/data$index" ]; then
    addShare "/data$index" "$ref" "$name" "Shared" "$SAMBA_CONFIG" || :
  fi

  return 0
}

prepareSambaDirs() {

  # Create directories if missing
  mkdir -p /var/lib/samba/sysvol
  mkdir -p /var/lib/samba/private
  mkdir -p /var/lib/samba/bind-dns

  # Try to repair Samba permissions
  [ -d /run/samba/msg.lock ] && chmod -R 0755 /run/samba/msg.lock 2>/dev/null || :
  [ -d /var/log/samba/cores ] && chmod -R 0700 /var/log/samba/cores 2>/dev/null || :
  [ -d /var/cache/samba/msg.lock ] && chmod -R 0755 /var/cache/samba/msg.lock 2>/dev/null || :

  return 0
}

debugLog() {

  local file="$1"

  if enabled "$SAMBA_DEBUG"; then
    tail -fn +0 "$file" --pid=$$ &
  fi

  return 0
}

startSamba() {

  rm -f /var/log/samba/log.smbd

  if ! smbd -l /var/log/samba; then
    SAMBA_DEBUG="Y"
    error "Failed to start Samba daemon!"
  fi

  debugLog /var/log/samba/log.smbd
  return 0
}

startNetbios() {

  # Enable NetBIOS on Windows 7 and lower
  enabled "$DEBUG" && echo "Starting NetBIOS daemon..."

  rm -f /var/log/samba/log.nmbd

  if ! nmbd -l /var/log/samba; then
    SAMBA_DEBUG="Y"
    error "Failed to start NetBIOS daemon!"
  fi

  debugLog /var/log/samba/log.nmbd
  return 0
}

startWsddn() {

  # Enable Web Service Discovery on Vista and up
  enabled "$DEBUG" && echo "Starting wsddn daemon..."
  rm -f /var/log/wsddn.log

  if ! wsddn -i "${interfaces%%,*}" -H "$hostname" --unixd --log-file=/var/log/wsddn.log --pid-file="$DDN_PID"; then
    SAMBA_DEBUG="Y"
    error "Failed to start wsddn daemon!"
  fi

  debugLog /var/log/wsddn.log
  return 0
}

configureNetwork

html "Initializing shared folder..."
SAMBA_CONFIG="/etc/samba/smb.conf"
enabled "$DEBUG" && echo "Starting Samba daemon..."

writeConfig

# Add shared folders
selectPrimaryShare
! addShare "$share" "/shared" "Data" "Shared" "$SAMBA_CONFIG" && return 0

addOptionalShare "2"
addOptionalShare "3"

prepareSambaDirs
startSamba

case "${NETWORK,,}" in
  "passt" | "slirp" )
    return 0 ;;
esac

if [[ "${BOOT_MODE:-}" == "windows_legacy" ]]; then
  startNetbios
else
  startWsddn
fi

return 0

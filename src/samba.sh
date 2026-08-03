#!/usr/bin/env bash
set -Eeuo pipefail

: "${SAMBA:="Y"}"            # Enable Samba
: "${SAMBA_DEBUG:="N"}"      # Disable debug
: "${SAMBA_READONLY:="N"}"   # Disable writes
: "${SAMBA_CONFIG:="/etc/samba/smb.conf"}"

DDN_PID="/var/run/wsdd.pid"
NMB_PID="/var/run/samba/nmbd.pid"
SMB_PID="/var/run/samba/smbd.pid"

if ! rm -f "$SMB_PID" "$NMB_PID" "$DDN_PID"; then
  error "Failed to clean Samba PID files!"
  return 0
fi

disabled "$SAMBA" && return 0
disabled "$NETWORK" && return 0

configureNetwork() {

  if enabled "$DHCP"; then

    hostname="$UPLINK"
    interfaces="$DEV"

  else

    hostname="host.lan"

    # User-mode networking has no host bridge to bind to, so expose Samba only
    # through loopback and let QEMU's forwarding provide guest access.
    if isUserMode; then
      interfaces="lo"
    else
      interfaces="$BRIDGE"
    fi

    if [ -n "${SAMBA_INTERFACE:-}" ]; then
      interfaces+=",$SAMBA_INTERFACE"
    fi

  fi

  # NetBIOS names are limited to 15 visible characters.
  netbios="${hostname%%.*}"
  netbios="${netbios:0:15}"

  [ -z "$netbios" ] && netbios="host"

  return 0
}

writeReadme() {

  local dir="$1"
  local ref="$2"

  if ! {
    echo "--------------------------------------------------------"
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
  } | unix2dos > "$dir/readme.txt"; then
    error "Failed to write shared folder readme!"
    return 1
  fi

  return 0
}

addShare() {

  local dir="$1"
  local ref="$2"
  local name="$3"
  local comment="$4"
  local cfg="$5"
  local owner probe
  local empty="N"
  local writable="N"
  local readonly="N"
  local tmp="/tmp/smb"

  if [ ! -d "$dir" ]; then
    if ! mkdir -p "$dir"; then
      error "Failed to create shared folder ($dir)." && return 1
    fi
  fi

  if ! ls -A "$dir" >/dev/null 2>&1; then
    local msg="No permission to access shared folder ($dir)."
    msg+=" If SELinux is active, you need to add the \":Z\" flag to the bind mount."
    error "$msg" && return 1
  fi

  if [ -z "$(ls -A "$dir")" ]; then
    empty="Y"
  fi

  # The generated fallback share contains only instructions and must never be
  # writable from the guest.
  if [[ "$dir" == "$tmp" ]]; then

    readonly="Y"

  elif enabled "$SAMBA_READONLY"; then

    readonly="Y"

  # Test actual write access instead of relying on mount flags or mode bits,
  # which may not reflect bind-mount and host filesystem restrictions.
  elif probe=$(mktemp "$dir/.samba-write-test.XXXXXX" 2>/dev/null); then

    writable="Y"

    if ! rm -f "$probe"; then
      error "Failed to remove write test file ($probe)."
      return 1
    fi

  # Empty bind mounts are safe to initialize with shared-directory permissions.
  # Retry the write probe afterward because the original mode may have blocked it.
  elif [[ "$empty" == "Y" ]] && chmod 2777 "$dir" 2>/dev/null; then

    if probe=$(mktemp "$dir/.samba-write-test.XXXXXX" 2>/dev/null); then

      writable="Y"

      if ! rm -f "$probe"; then
        error "Failed to remove write test file ($probe)."
        return 1
      fi

    fi

  fi

  if [[ "$writable" == "Y" ]]; then

    if [[ "$empty" == "Y" ]]; then

      # Keep newly created content in the shared group through the setgid bit.
      if ! chmod 2777 "$dir"; then
        error "Failed to set permissions for directory $dir" && return 1
      fi

      if ! owner=$(stat -c %u "$dir"); then
        error "Failed to determine ownership for directory $dir"
        return 1
      fi

      # Docker commonly creates a missing bind source as root. Transfer an empty
      # directory to the default non-root owner used for shared content.
      if [[ "$owner" == "0" ]]; then
        if ! chown "1000:1000" "$dir"; then
          error "Failed to set ownership for directory $dir" && return 1
        fi
      fi

    fi

  elif [[ "$readonly" != "Y" ]]; then

    # Preserve access to non-writable mounts by exporting them read-only.
    readonly="Y"

  fi

  if [[ "$dir" == "$tmp" ]]; then
    writeReadme "$dir" "$ref" || return 1
  fi

  if ! {
    echo ""
    echo "[$name]"
    echo "    path = $dir"
    echo "    comment = $comment"

    if [[ "$readonly" == "Y" ]]; then
      echo "    read only = yes"
    else
      echo "    read only = no"
    fi

    echo "    guest ok = yes"
    echo "    guest only = yes"
  } >> "$cfg"; then
    error "Failed to update Samba config \"$cfg\" !"
    return 1
  fi

  return 0
}

writeConfig() {

  if ! {
    echo "[global]"
    echo "    server string = Dockur"
    echo "    netbios name = $netbios"
    echo "    workgroup = WORKGROUP"
    echo "    interfaces = $interfaces"
    echo "    bind interfaces only = yes"
    echo "    security = user"
    echo "    guest account = nobody"
    echo "    map to guest = Bad User"

    # Retain SMB1 negotiation for legacy Windows guests.
    echo "    server min protocol = NT1"

    # Allow bind-mounted shares to follow symlinks outside their share root.
    echo "    follow symlinks = yes"
    echo "    wide links = yes"
    echo "    unix extensions = no"
    echo "    inherit owner = yes"
    echo "    create mask = 0666"
    echo "    directory mask = 02777"

    # Perform guest filesystem access as root so bind mounts with differing host
    # ownership remain usable; share-level read-only checks still apply.
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
  } > "$SAMBA_CONFIG"; then
    error "Failed to write Samba config \"$SAMBA_CONFIG\" !"
    return 1
  fi

  return 0
}

selectPrimaryShare() {

  local tmp="/tmp/smb"

  if ! rm -rf "$tmp"; then
    error "Failed to clean temporary Samba folder!"
    return 1
  fi

  # Prefer explicit root-level bind mounts, then storage-local compatibility
  # paths. When none exist, publish an instructional read-only share.
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

  # Optional shares are best-effort and must not prevent the primary share or
  # Samba service from starting.
  if [ -d "$ref" ]; then
    addShare "$ref" "$ref" "$name" "Shared" "$SAMBA_CONFIG" || :
  elif [ -d "/data$index" ]; then
    addShare "/data$index" "$ref" "$name" "Shared" "$SAMBA_CONFIG" || :
  fi

  return 0
}

prepareSambaDirs() {

  mkdir -p \
    /var/lib/samba/sysvol \
    /var/lib/samba/private \
    /var/lib/samba/bind-dns || return 1

  # Runtime directories may retain restrictive modes from earlier daemon runs
  # or package defaults, so repair only the known Samba lock and core paths.
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

startDaemon() {

  local name="$1"
  local log="$2"
  shift 2

  rm -f "$log" || :

  # Keep initialization alive after a daemon startup failure so its log can be
  # streamed and the actual Samba error remains visible to the user.
  if ! "$@"; then
    SAMBA_DEBUG="Y"
    error "Failed to start $name daemon!"
  fi

  debugLog "$log"
  return 0
}

startSamba() {

  startDaemon "Samba" "/var/log/samba/log.smbd" \
    smbd -l /var/log/samba

  return 0
}

startNetbios() {

  enabled "$DEBUG" && echo "Starting NetBIOS daemon..."

  startDaemon "NetBIOS" "/var/log/samba/log.nmbd" \
    nmbd -l /var/log/samba

  return 0
}

startWsddn() {

  enabled "$DEBUG" && echo "Starting wsddn daemon..."

  # wsddn accepts one interface, while Samba may bind to an additional
  # user-supplied interface as well.
  startDaemon "wsddn" "/var/log/wsddn.log" \
    wsddn -i "${interfaces%%,*}" -H "$hostname" \
      --unixd --log-file=/var/log/wsddn.log --pid-file="$DDN_PID"

  return 0
}

configureNetwork || return 0

html "Initializing shared folder..."
enabled "$DEBUG" && echo "Starting Samba daemon..."

writeConfig || return 0

selectPrimaryShare || return 0

addShare "$share" "/shared" "Data" "Shared" "$SAMBA_CONFIG" || return 0
addOptionalShare "2" || :
addOptionalShare "3" || :

prepareSambaDirs || return 0

startSamba || return 0

# User-mode networking does not expose a LAN interface where discovery
# broadcasts would be useful.
isUserMode && return 0

# Older Windows versions discover shares through NetBIOS, while modern Windows
# uses Web Services Discovery.
if [[ "${BOOT_MODE:-}" == "windows_legacy" ]]; then
  startNetbios || :
else
  startWsddn || :
fi

return 0

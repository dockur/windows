#!/usr/bin/env bash
set -Eeuo pipefail

[[ "$DHCP" == [Yy1]* ]] && return 0

{      echo "[global]"
        echo "    netbios name = dockur"
        echo "    workgroup = WORKGROUP"
        echo "    server string = Dockur"
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
        echo "[data]"
        echo "    path = /storage"
        echo "    comment = Storage"
        echo "    writable = yes"
        echo "    guest ok = yes"
        echo "    guest only = yes"
        echo "    create mode = 0777"
        echo "    directory mode = 0777"
  } > "/etc/samba/smb.conf"

  smbd -D
  wsdd -i dockerbridge -n Host -p

  return 0

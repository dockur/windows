#!/usr/bin/env bash
set -Eeuox pipefail

# Docker environment variables

: "${MAC:=""}"
: "${DHCP:="N"}"
: "${NETWORK:="bridge"}"
: "${USER_PORTS:=""}"
: "${HOST_PORTS:=""}"
: "${ADAPTER:="virtio-net-pci"}"

: "${VM_NET_DEV:=""}"
: "${VM_NET_TAP:="qemu"}"
: "${VM_NET_MAC:="$MAC"}"
: "${VM_NET_HOST:="QEMU"}"
: "${VM_NET_IP:="20.20.20.21"}"

: "${DNSMASQ_OPTS:=""}"
: "${DNSMASQ:="/usr/sbin/dnsmasq"}"
: "${DNSMASQ_CONF_DIR:="/etc/dnsmasq.d"}"

ETH_COUNT=$(ls /sys/class/net | grep -E '^eth[0-9]+$' | wc -l)
ADD_ERR="Please add the following setting to your container:"

# ######################################
#  Functions
# ######################################
find_free_ip() {
  local current_ip="$1"
  local mask="$2"

  # Get network prefix
  IFS='.' read -r i1 i2 i3 i4 <<<"$current_ip"
  IFS='.' read -r m1 m2 m3 m4 <<<"$(ip -o -f inet addr show | awk '/scope global/ {print $4}' | cut -d'/' -f2)"

  network_ip=$((i1 & m1)).$((i2 & m2)).$((i3 & m3)).0
  base_ip="$i1.$i2.$i3"

  # Iterate over available IPs
  for i in {2..254}; do
    new_ip="$base_ip.$i"
    if [[ "$new_ip" != "$current_ip" ]] && ! ping -c 1 -W 1 "$new_ip" &>/dev/null; then
      echo "$new_ip"
      return
    fi
  done

  echo "No free IP found"
}

configure_guest_network_interface() {
  if [[ "${NETWORK,,}" == "bridge"* ]]; then
    for ((i = 0; i < ETH_COUNT; i++)); do
      HOST_INTERFACE="dockerbridge$i"
      CURRENT_IP=$(ip addr show $HOST_INTERFACE | grep -oP 'inet \K[\d.]+')
      MASK="$(ip -4 addr show $HOST_INTERFACE | awk '/inet / {print $2}' | cut -d'/' -f2)"

      if [ -z "$CURRENT_IP" ]; then
        echo "Error: Unable to retrieve the current IP address of $HOST_INTERFACE."
        return 1
      fi

      echo "Current Host IP: $CURRENT_IP"

      IFS='.' read -r -a ip_parts <<<"$CURRENT_IP"
      NEW_HOST_IP=$(find_free_ip "$CURRENT_IP" "$MASK")
      GW="${ip_parts[0]}.${ip_parts[1]}.${ip_parts[2]}.1"

      echo "New Host IP: $NEW_HOST_IP"

      ip addr del $CURRENT_IP/$MASK dev $HOST_INTERFACE
      ip addr add $NEW_HOST_IP/$MASK dev $HOST_INTERFACE

      ip link set $HOST_INTERFACE down
      ip link set $HOST_INTERFACE up

      route add default gw $GW

      if [ $i -eq 0 ]; then
        INTERFACE_NAME="Ethernet"
      else
        IDX=$((1 + i))
        INTERFACE_NAME="Ethernet $IDX"
      fi

      RETRIES=10
      for j in $(seq 1 $RETRIES); do
        OUTPUT=$(python3 /run/qga.py powershell -Command "(\$(Get-NetAdapter -Name '$INTERFACE_NAME').Status)")
        STATUS=$(echo "$OUTPUT" | grep -A1 'STDOUT:' | tail -n1 | tr -d '\r' | xargs)

        echo "Status: '$STATUS'"
        if [[ "$STATUS" == "Up" ]]; then
          echo "Interface '$INTERFACE_NAME' is up!"
          break
        else
          echo "Waiting for interface '$INTERFACE_NAME' to be up... ($j/$RETRIES)"
          sleep 1
        fi
      done

      exit_code=0
      python3 /run/qga.py powershell -Command "Set-NetIPInterface -InterfaceAlias '$INTERFACE_NAME' -Dhcp Disabled" || exit_code=$?
      if [[ $exit_code -ne 0 ]]; then
        echo "Failed to disable dhcp using qga.py" >&2
        return 2
      fi

      if [[ -f "$STORAGE/interfaces_configured" ]]; then
        python3 /run/qga.py powershell -Command "Remove-NetIPAddress -IPAddress '$CURRENT_IP' -Confirm:\$false" || true
        python3 /run/qga.py powershell -Command "Remove-NetRoute -InterfaceAlias '$INTERFACE_NAME' -DestinationPrefix '0.0.0.0/0' -Confirm:\$false" || true
      fi

      python3 /run/qga.py powershell -Command "New-NetIPAddress -InterfaceAlias '$INTERFACE_NAME' -IPAddress '$CURRENT_IP' -PrefixLength 24 -DefaultGateway '$GW'" || exit_code=$?
      if [[ $exit_code -ne 0 ]]; then
        echo "Failed to set ip address using qga.py" >&2
        return 3
      fi

      python3 /run/qga.py powershell -Command "Set-DnsClientServerAddress -InterfaceAlias '$INTERFACE_NAME' -ServerAddresses 1.1.1.1" || exit_code=$?
      if [[ $exit_code -ne 0 ]]; then
        echo "Failed to set dns server using qga.py" >&2
        return 4
      fi

    done

    touch "$STORAGE/interfaces_configured"
  fi

  return 0
}

configureDHCP() {

  # Create the necessary file structure for /dev/vhost-net
  if [ ! -c /dev/vhost-net ]; then
    if mknod /dev/vhost-net c 10 238; then
      chmod 660 /dev/vhost-net
    fi
  fi

  # Create a macvtap network for the VM guest
  {
    msg=$(ip link add link "$VM_NET_DEV" name "$VM_NET_TAP" address "$VM_NET_MAC" type macvtap mode bridge 2>&1)
    rc=$?
  } || :

  case "$msg" in
  "RTNETLINK answers: File exists"*)
    while ! ip link add link "$VM_NET_DEV" name "$VM_NET_TAP" address "$VM_NET_MAC" type macvtap mode bridge; do
      info "Waiting for macvtap interface to become available.."
      sleep 5
    done
    ;;
  "RTNETLINK answers: Invalid argument"*)
    error "Cannot create macvtap interface. Please make sure that the network type of the container is 'macvlan' and not 'ipvlan'."
    return 1
    ;;
  "RTNETLINK answers: Operation not permitted"*)
    error "No permission to create macvtap interface. Please make sure that your host kernel supports it and that the NET_ADMIN capability is set."
    return 1
    ;;
  *)
    [ -n "$msg" ] && echo "$msg" >&2
    if ((rc != 0)); then
      error "Cannot create macvtap interface."
      return 1
    fi
    ;;
  esac

  while ! ip link set "$VM_NET_TAP" up; do
    info "Waiting for MAC address $VM_NET_MAC to become available..."
    sleep 2
  done

  local TAP_NR TAP_PATH MAJOR MINOR
  TAP_NR=$(</sys/class/net/"$VM_NET_TAP"/ifindex)
  TAP_PATH="/dev/tap${TAP_NR}"

  # Create dev file (there is no udev in container: need to be done manually)
  IFS=: read -r MAJOR MINOR < <(cat /sys/devices/virtual/net/"$VM_NET_TAP"/tap*/dev)
  ((MAJOR < 1)) && error "Cannot find: sys/devices/virtual/net/$VM_NET_TAP" && return 1

  [[ ! -e "$TAP_PATH" ]] && [[ -e "/dev0/${TAP_PATH##*/}" ]] && ln -s "/dev0/${TAP_PATH##*/}" "$TAP_PATH"

  if [[ ! -e "$TAP_PATH" ]]; then
    {
      mknod "$TAP_PATH" c "$MAJOR" "$MINOR"
      rc=$?
    } || :
    ((rc != 0)) && error "Cannot mknod: $TAP_PATH ($rc)" && return 1
  fi

  {
    exec 30>>"$TAP_PATH"
    rc=$?
  } 2>/dev/null || :

  if ((rc != 0)); then
    error "Cannot create TAP interface ($rc). $ADD_ERR --device-cgroup-rule='c *:* rwm'" && return 1
  fi

  {
    exec 40>>/dev/vhost-net
    rc=$?
  } 2>/dev/null || :

  if ((rc != 0)); then
    error "VHOST can not be found ($rc). $ADD_ERR --device=/dev/vhost-net" && return 1
  fi

  NET_OPTS="-netdev tap,id=hostnet0,vhost=on,vhostfd=40,fd=30"

  return 0
}

configureDNS() {

  # dnsmasq configuration:
  DNSMASQ_OPTS+=" --dhcp-range=$VM_NET_IP,$VM_NET_IP --dhcp-host=$VM_NET_MAC,,$VM_NET_IP,$VM_NET_HOST,infinite --dhcp-option=option:netmask,255.255.255.0"

  # Create lease file for faster resolve
  echo "0 $VM_NET_MAC $VM_NET_IP $VM_NET_HOST 01:$VM_NET_MAC" >/var/lib/misc/dnsmasq.leases
  chmod 644 /var/lib/misc/dnsmasq.leases

  # Set DNS server and gateway
  DNSMASQ_OPTS+=" --dhcp-option=option:dns-server,${VM_NET_IP%.*}.1 --dhcp-option=option:router,${VM_NET_IP%.*}.1"

  # Add DNS entry for container
  DNSMASQ_OPTS+=" --address=/host.lan/${VM_NET_IP%.*}.1"

  DNSMASQ_OPTS=$(echo "$DNSMASQ_OPTS" | sed 's/\t/ /g' | tr -s ' ' | sed 's/^ *//')

  if ! $DNSMASQ ${DNSMASQ_OPTS:+ $DNSMASQ_OPTS}; then
    error "Failed to start dnsmasq, reason: $?" && return 1
  fi

  return 0
}

getUserPorts() {

  local args=""
  local list=$1
  local ssh="22"
  local rdp="3389"

  [ -z "$list" ] && list="$ssh,$rdp" || list+=",$ssh,$rdp"

  list="${list//,/ }"
  list="${list## }"
  list="${list%% }"

  for port in $list; do
    args+="hostfwd=tcp::$port-$VM_NET_IP:$port,"
  done

  echo "${args%?}"
  return 0
}

getHostPorts() {

  local list=$1
  local vnc="5900"
  local web="8006"

  [ -z "$list" ] && list="$web" || list+=",$web"

  if [[ "${DISPLAY,,}" == "vnc" ]] || [[ "${DISPLAY,,}" == "web" ]]; then
    [ -z "$list" ] && list="$vnc" || list+=",$vnc"
  fi

  [ -z "$list" ] && echo "" && return 0

  if [[ "$list" != *","* ]]; then
    echo " ! --dport $list"
  else
    echo " -m multiport ! --dports $list"
  fi

  return 0
}

configureUser() {

  NET_OPTS="-netdev user,id=hostnet0,host=${VM_NET_IP%.*}.1,net=${VM_NET_IP%.*}.0/24,dhcpstart=$VM_NET_IP,hostname=$VM_NET_HOST"

  local forward
  forward=$(getUserPorts "$USER_PORTS")
  [ -n "$forward" ] && NET_OPTS+=",$forward"

  return 0
}

configureNAT() {

  local tuntap="TUN device is missing. $ADD_ERR --device /dev/net/tun"
  local tables="The 'ip_tables' kernel module is not loaded. Try this command: sudo modprobe ip_tables iptable_nat"

  # Create the necessary file structure for /dev/net/tun
  if [ ! -c /dev/net/tun ]; then
    [ ! -d /dev/net ] && mkdir -m 755 /dev/net
    if mknod /dev/net/tun c 10 200; then
      chmod 666 /dev/net/tun
    fi
  fi

  if [ ! -c /dev/net/tun ]; then
    error "$tuntap" && return 1
  fi

  # Check port forwarding flag
  if [[ $(</proc/sys/net/ipv4/ip_forward) -eq 0 ]]; then
    {
      sysctl -w net.ipv4.ip_forward=1 >/dev/null
      rc=$?
    } || :
    if ((rc != 0)) || [[ $(</proc/sys/net/ipv4/ip_forward) -eq 0 ]]; then
      error "IP forwarding is disabled. $ADD_ERR --sysctl net.ipv4.ip_forward=1" && return 1
    fi
  fi

  # Create a bridge with a static IP for the VM guest

  {
    ip link add dev dockerbridge type bridge
    rc=$?
  } || :

  if ((rc != 0)); then
    error "Failed to create bridge. $ADD_ERR --cap-add NET_ADMIN" && return 1
  fi

  if ! ip address add "${VM_NET_IP%.*}.1/24" broadcast "${VM_NET_IP%.*}.255" dev dockerbridge; then
    error "Failed to add IP address!" && return 1
  fi

  while ! ip link set dockerbridge up; do
    info "Waiting for IP address to become available..."
    sleep 2
  done

  # QEMU Works with taps, set tap to the bridge created
  if ! ip tuntap add dev "$VM_NET_TAP" mode tap; then
    error "$tuntap" && return 1
  fi

  while ! ip link set "$VM_NET_TAP" up promisc on; do
    info "Waiting for TAP to become available..."
    sleep 2
  done

  if ! ip link set dev "$VM_NET_TAP" master dockerbridge; then
    error "Failed to set IP link!" && return 1
  fi

  # Add internet connection to the VM
  update-alternatives --set iptables /usr/sbin/iptables-legacy >/dev/null
  update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy >/dev/null

  exclude=$(getHostPorts "$HOST_PORTS")

  if ! iptables -t nat -A POSTROUTING -o "$VM_NET_DEV" -j MASQUERADE; then
    error "$tables" && return 1
  fi

  # shellcheck disable=SC2086
  if ! iptables -t nat -A PREROUTING -i "$VM_NET_DEV" -d "$IP" -p tcp${exclude} -j DNAT --to "$VM_NET_IP"; then
    error "Failed to configure IP tables!" && return 1
  fi

  if ! iptables -t nat -A PREROUTING -i "$VM_NET_DEV" -d "$IP" -p udp -j DNAT --to "$VM_NET_IP"; then
    error "Failed to configure IP tables!" && return 1
  fi

  if ((KERNEL > 4)); then
    # Hack for guest VMs complaining about "bad udp checksums in 5 packets"
    iptables -A POSTROUTING -t mangle -p udp --dport bootpc -j CHECKSUM --checksum-fill >/dev/null 2>&1 || true
  fi

  NET_OPTS="-netdev tap,id=hostnet0,ifname=$VM_NET_TAP"

  if [ -c /dev/vhost-net ]; then
    {
      exec 40>>/dev/vhost-net
      rc=$?
    } 2>/dev/null || :
    ((rc == 0)) && NET_OPTS+=",vhost=on,vhostfd=40"
  fi

  NET_OPTS+=",script=no,downscript=no"

  configureDNS || return 1

  return 0
}

configureBridge() {

  local tuntap="TUN device is missing. $ADD_ERR --device /dev/net/tun"
  local tables="The 'ip_tables' kernel module is not loaded. Try this command: sudo modprobe ip_tables iptable_nat"

  # Create the necessary file structure for /dev/net/tun
  if [ ! -c /dev/net/tun ]; then
    [ ! -d /dev/net ] && mkdir -m 755 /dev/net
    if mknod /dev/net/tun c 10 200; then
      chmod 666 /dev/net/tun
    fi
  fi

  if [ ! -c /dev/net/tun ]; then
    error "$tuntap" && return 1
  fi

  # Check port forwarding flag
  if [[ $(</proc/sys/net/ipv4/ip_forward) -eq 0 ]]; then
    {
      sysctl -w net.ipv4.ip_forward=1 >/dev/null
      rc=$?
    } || :
    if ((rc != 0)) || [[ $(</proc/sys/net/ipv4/ip_forward) -eq 0 ]]; then
      error "IP forwarding is disabled. $ADD_ERR --sysctl net.ipv4.ip_forward=1" && return 1
    fi
  fi

  for ((i = 0; i < ETH_COUNT; i++)); do
    DOCKER_BRIDGE="dockerbridge$i"
    NET_DEV="eth$i"
    NET_TAP="qemu$i"
    {
      ip link add dev $DOCKER_BRIDGE type bridge
      rc=$?
    } || :

    if ((rc != 0)); then
      error "Failed to create bridge. $ADD_ERR --cap-add NET_ADMIN" && return 1
    fi

    # We need freshly created bridge to have IP address of the container
    # For this reason we need to migrate IP from eth0 to dockerbridge.
    for addr in $(ip --json addr show dev $NET_DEV | jq -c '.[0].addr_info[] | select(.family == "inet")'); do
      cidr_addr=$(echo $addr | jq -r '[ .local, .prefixlen|tostring] | join("/")')
      if ! ip addr add dev $DOCKER_BRIDGE $cidr_addr; then
        error "Failed to add address for $DOCKER_BRIDGE interface"
        exit 30
      fi
    done

    if ! ip addr flush dev $NET_DEV; then
      error "Failed to clear $NET_DEV interface addresses"
      exit 30
    fi

    while ! ip link set $DOCKER_BRIDGE up; do
      info "Waiting for IP address to become available..."
      sleep 2
    done

    # QEMU Works with taps, set tap to the bridge created
    if ! ip tuntap add dev "$NET_TAP" mode tap; then
      error "$tuntap" && return 1
    fi

    while ! ip link set "$NET_TAP" up promisc on; do
      info "Waiting for TAP to become available..."
      sleep 2
    done

    if ! ip link set dev "$NET_TAP" master $DOCKER_BRIDGE; then
      error "Failed to set IP link!" && return 1
    fi

    if ! ip link set dev "$NET_DEV" master $DOCKER_BRIDGE; then
      error "Failed to attach docker interface to bridge"
    fi

    NET_OPTS+=" -netdev tap,id=hostnet$i,ifname=$NET_TAP"
    if [ -c /dev/vhost-net ]; then
      fd=$((40 + i))
      eval "exec $fd>>/dev/vhost-net"
      rc=$?
      if ((rc == 0)); then
        NET_OPTS+=",vhost=on,vhostfd=$fd"
      fi
    fi

    NET_OPTS+=",script=no,downscript=no "

  done

  return 0
}

closeNetwork() {

  # Shutdown nginx
  nginx -s stop 2>/dev/null
  fWait "nginx"

  [[ "$NETWORK" == [Nn]* ]] && return 0

  exec 30<&- || true
  for ((i = 0; i < ETH_COUNT; i++)); do
    fd=$((40 + i))
    eval "exec $fd<&-" || true
  done

  if [[ "$DHCP" == [Yy1]* ]]; then

    ip link set "$VM_NET_TAP" down || true
    ip link delete "$VM_NET_TAP" || true

  else

    local pid="/var/run/dnsmasq.pid"
    [ -s "$pid" ] && pKill "$(<"$pid")"

    [[ "${NETWORK,,}" == "user"* ]] && return 0

    if [[ "${NETWORK,,}" == "bridge"* ]]; then
      for ((i = 0; i < ETH_COUNT; i++)); do
        ip link set "qemu$i" down promisc off || true
        ip link delete "qemu$i" || true

        ip link set dockerbridge$i down || true
        ip link delete dockerbridge$i || true
      done
    else
      ip link set "$VM_NET_TAP" down promisc off || true
      ip link delete "$VM_NET_TAP" || true

      ip link set dockerbridge down || true
      ip link delete dockerbridge || true
    fi

  fi

  return 0
}

checkOS() {

  local name
  local os=""
  local if="macvlan"
  name=$(uname -a)

  [[ "${name,,}" == *"darwin"* ]] && os="Docker Desktop for macOS"
  [[ "${name,,}" == *"microsoft"* ]] && os="Docker Desktop for Windows"

  if [[ "$DHCP" == [Yy1]* ]]; then
    if="macvtap"
    [[ "${name,,}" == *"synology"* ]] && os="Synology Container Manager"
  fi

  if [ -n "$os" ]; then
    warn "you are using $os which does not support $if, please revert to bridge networking!"
  fi

  return 0
}

getInfo() {

  if [ -z "$VM_NET_DEV" ]; then
    # Give Kubernetes priority over the default interface
    [ -d "/sys/class/net/net0" ] && VM_NET_DEV="net0"
    [ -d "/sys/class/net/net1" ] && VM_NET_DEV="net1"
    [ -d "/sys/class/net/net2" ] && VM_NET_DEV="net2"
    [ -d "/sys/class/net/net3" ] && VM_NET_DEV="net3"
    # Automaticly detect the default network interface
    [ -z "$VM_NET_DEV" ] && VM_NET_DEV=$(awk '$2 == 00000000 { print $1 }' /proc/net/route)
    [ -z "$VM_NET_DEV" ] && VM_NET_DEV="eth0"
  fi

  if [ ! -d "/sys/class/net/$VM_NET_DEV" ]; then
    error "Network interface '$VM_NET_DEV' does not exist inside the container!"
    error "$ADD_ERR -e \"VM_NET_DEV=NAME\" to specify another interface name." && exit 27
  fi

  if [ -z "$MAC" ]; then
    local file="$STORAGE/$PROCESS.mac"
    [ -s "$file" ] && MAC=$(<"$file")
    if [ -z "$MAC" ]; then
      # Generate MAC address based on Docker container ID in hostname
      MAC=$(echo "$HOST" | md5sum | sed 's/^\(..\)\(..\)\(..\)\(..\)\(..\).*$/02:\1:\2:\3:\4:\5/')
      echo "${MAC^^}" >"$file"
    fi
  fi

  VM_NET_MAC="${MAC^^}"
  VM_NET_MAC="${VM_NET_MAC//-/:}"

  if [[ ${#VM_NET_MAC} == 12 ]]; then
    m="$VM_NET_MAC"
    VM_NET_MAC="${m:0:2}:${m:2:2}:${m:4:2}:${m:6:2}:${m:8:2}:${m:10:2}"
  fi

  if [[ ${#VM_NET_MAC} != 17 ]]; then
    error "Invalid MAC address: '$VM_NET_MAC', should be 12 or 17 digits long!" && exit 28
  fi

  GATEWAY=$(ip route list dev "$VM_NET_DEV" | awk ' /^default/ {print $3}')
  IP=$(ip address show dev "$VM_NET_DEV" | grep inet | awk '/inet / { print $2 }' | cut -f1 -d/)

  return 0
}

# ######################################
#  Configure Network
# ######################################

if [[ "$NETWORK" == [Nn]* ]]; then
  NET_OPTS=""
  return 0
fi

getInfo
html "Initializing network..."

if [[ "$DEBUG" == [Yy1]* ]]; then
  info "Host: $HOST  IP: $IP  Gateway: $GATEWAY  Interface: $VM_NET_DEV  MAC: $VM_NET_MAC"
  [ -f /etc/resolv.conf ] && grep '^nameserver*' /etc/resolv.conf
  echo
fi

if [[ "$DHCP" == [Yy1]* ]]; then

  checkOS

  if [[ "$IP" == "172."* ]]; then
    warn "container IP starts with 172.* which is often a sign that you are not on a macvlan network (required for DHCP)!"
  fi

  # Configure for macvtap interface
  configureDHCP || exit 20

else

  if [[ "$IP" != "172."* ]] && [[ "$IP" != "10.8"* ]] && [[ "$IP" != "10.9"* ]]; then
    checkOS
  fi

  if [[ "${NETWORK,,}" == [Yy1]* ]]; then

    # Configure for tap interface
    if ! configureNAT; then

      NETWORK="user"
      warn "falling back to usermode networking! Performance will be bad and port mapping will not work."

      ip link set "$VM_NET_TAP" down promisc off &>null || true
      ip link delete "$VM_NET_TAP" &>null || true

      ip link set dockerbridge down &>null || true
      ip link delete dockerbridge &>null || true

    fi

  fi

  if [[ "${NETWORK,,}" == "user"* ]]; then

    # Configure for usermode networking (slirp)
    configureUser || exit 24

  fi

  if [[ "${NETWORK,,}" == "bridge"* ]]; then

    # Configure for usermode networking (slirp)
    # CONFIGURE Bridge
    html "Configuring bridged network"

    if ! configureBridge; then

      error "Failed to setup bridge networking"
      for ((i = 0; i < ETH_COUNT; i++)); do
        ip link set "$VM_NET_TAP$i" down promisc off &>null || true
        ip link delete "$VM_NET_TAP$i" &>null || true

        ip link set dockerbridge$i down &>null || true
        ip link delete dockerbridge$i &>null || true
      done

      exit 25
    fi

  fi

fi

NET_OPTS+=" -device $ADAPTER,romfile=,netdev=hostnet0,mac=$VM_NET_MAC,id=net0"

if [[ "${NETWORK,,}" == "bridge"* ]]; then
  for ((i = 1; i < ETH_COUNT; i++)); do
    MAC=$(printf "52:54:00:%02X:%02X:%02X" $((RANDOM % 256)) $((RANDOM % 256)) $((RANDOM % 256)))
    NET_OPTS+=" -device $ADAPTER,romfile=,netdev=hostnet$i,mac=$MAC,id=net$i"
  done
fi

NET_OPTS+=" -device virtio-serial-pci,id=virtserial0,bus=pcie.0,addr=0x6"
NET_OPTS+=" -chardev socket,id=qga0,path=/tmp/qga.sock,server=on,wait=off"
NET_OPTS+=" -device virtio-serial"
NET_OPTS+=" -device virtserialport,chardev=qga0,name=org.qemu.guest_agent.0"

html "Initialized network successfully..."
return 0

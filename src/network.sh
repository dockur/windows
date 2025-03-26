#!/usr/bin/env bash
set -Eeuo pipefail

# Docker environment variables

: "${MAC:=""}"
: "${MAC_2:=""}"
: "${DHCP:="N"}"
: "${NETWORK:="bridge"}"
: "${USER_PORTS:=""}"
: "${HOST_PORTS:=""}"
: "${ADAPTER:="virtio-net-pci"}"
: "${ADAPTER_2:="virtio-net-pci"}"

: "${VM_NET_DEV:="eth0"}"
: "${VM_NET_DEV_2:="eth1"}"
: "${VM_NET_TAP:="qemu"}"
: "${VM_NET_TAP_2:="qemu_2"}"
: "${VM_NET_MAC:="$MAC"}"
: "${VM_NET_MAC_2:="$MAC_2"}"
: "${VM_NET_HOST:="QEMU"}"
: "${VM_NET_HOST_2:="QEMU_2"}"
: "${VM_NET_IP:="192.168.0.101"}"
: "${VM_NET_IP_2:="192.168.1.101"}"

: "${DNSMASQ_OPTS:=""}"
: "${DNSMASQ:="/usr/sbin/dnsmasq"}"
: "${DNSMASQ_CONF_DIR:="/etc/dnsmasq.d"}"

ADD_ERR="Please add the following setting to your container:"

# ######################################
#  Functions
# ######################################

configureDNS() {
  # Create lease file for faster resolve
  echo "0 $VM_NET_MAC $VM_NET_IP $VM_NET_HOST 01:$VM_NET_MAC" >/var/lib/misc/dnsmasq.leases
  echo "0 $VM_NET_MAC_2 $VM_NET_IP_2 $VM_NET_HOST_2 01:$VM_NET_MAC_2" >>/var/lib/misc/dnsmasq.leases
  chmod 644 /var/lib/misc/dnsmasq.leases

  # dnsmasq configuration:
  # eth0 - Provides both DNS and Default Gateway
  DNSMASQ_OPTS+=" --dhcp-range=$VM_NET_IP,$VM_NET_IP"
  DNSMASQ_OPTS+=" --dhcp-host=$VM_NET_MAC,,$VM_NET_IP,$VM_NET_HOST,infinite"
  DNSMASQ_OPTS+=" --dhcp-option=option:netmask,255.255.255.0"
  DNSMASQ_OPTS+=" --dhcp-option=option:dns-server,${VM_NET_IP%.*}.1"
  DNSMASQ_OPTS+=" --address=/host.lan/${VM_NET_IP%.*}.1"

  # eth1 - Provides only DNS, no default gateway
  DNSMASQ_OPTS+=" --dhcp-range=$VM_NET_IP_2,$VM_NET_IP_2"
  DNSMASQ_OPTS+=" --dhcp-host=$VM_NET_MAC_2,,$VM_NET_IP_2,$VM_NET_HOST_2,infinite"
  DNSMASQ_OPTS+=" --dhcp-option=option:netmask,255.255.255.0"
  DNSMASQ_OPTS+=" --dhcp-option=option:dns-server,${VM_NET_IP_2%.*}.1"
  DNSMASQ_OPTS+=" --address=/host.lan/${VM_NET_IP_2%.*}.1"

  # Cleanup and start dnsmasq
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

  NET_OPTS+=" -netdev user,id=hostnet1,host=${VM_NET_IP_2%.*}.1,net=${VM_NET_IP_2%.*}.0/24,dhcpstart=$VM_NET_IP_2,hostname=$VM_NET_HOST_2"
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

  {
    ip link add dev dockerbridge_2 type bridge
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

  if ! ip address add "${VM_NET_IP_2%.*}.1/24" broadcast "${VM_NET_IP_2%.*}.255" dev dockerbridge_2; then
    error "Failed to add IP address!" && return 1
  fi

  while ! ip link set dockerbridge_2 up; do
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

  if ! ip tuntap add dev "$VM_NET_TAP_2" mode tap; then
    error "$tuntap" && return 1
  fi

  while ! ip link set "$VM_NET_TAP_2" up promisc on; do
    info "Waiting for TAP to become available..."
    sleep 2
  done

  if ! ip link set dev "$VM_NET_TAP_2" master dockerbridge_2; then
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

  if ! iptables -t nat -A POSTROUTING -o "$VM_NET_DEV_2" -j MASQUERADE; then
    error "$tables" && return 1
  fi

  # shellcheck disable=SC2086
  if ! iptables -t nat -A PREROUTING -i "$VM_NET_DEV_2" -d "$IP_2" -p tcp${exclude} -j DNAT --to "$VM_NET_IP_2"; then
    error "Failed to configure IP tables!" && return 1
  fi

  if ! iptables -t nat -A PREROUTING -i "$VM_NET_DEV_2" -d "$IP_2" -p udp -j DNAT --to "$VM_NET_IP_2"; then
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

  NET_OPTS+=" -netdev tap,id=hostnet1,ifname=$VM_NET_TAP_2"

  if [ -c /dev/vhost-net ]; then
    {
      exec 41>>/dev/vhost-net
      rc=$?
    } 2>/dev/null || :
    ((rc == 0)) && NET_OPTS+=",vhost=on,vhostfd=41"
  fi

  NET_OPTS+=",script=no,downscript=no"

  configureDNS || return 1

  return 0/
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

  # Create a bridge with a static IP for the VM guest

  {
    ip link add dev dockerbridge type bridge
    rc=$?
  } || :

  if ((rc != 0)); then
    error "Failed to create bridge. $ADD_ERR --cap-add NET_ADMIN" && return 1
  fi

  {
    ip link add dev dockerbridge_2 type bridge
    rc=$?
  } || :
  if ((rc != 0)); then
    error "Failed to create bridge. $ADD_ERR --cap-add NET_ADMIN" && return 1
  fi

  # We need freshly created bridge to have IP address of the container
  # For this reason we need to migrate IP from eth0 to dockerbridge.
  for addr in $(ip --json addr show dev $VM_NET_DEV | jq -c '.[0].addr_info[] | select(.family == "inet")'); do
    cidr_addr=$(echo $addr | jq -r '[ .local, .prefixlen|tostring] | join("/")');
    if ! ip addr add dev dockerbridge $cidr_addr; then
        error "Failed to add address for dockerbridge interface"
        exit 30
    fi
  done
  if ! ip addr flush dev $VM_NET_DEV; then
    error "Failed to clear $VM_NET_DEV interface addresses"
    exit 30
  fi

  while ! ip link set dockerbridge up; do
    info "Waiting for IP address to become available..."
    sleep 2
  done

  # We need freshly created bridge to have IP address of the container
  # For this reason we need to migrate IP from eth0 to dockerbridge.
  for addr in $(ip --json addr show dev $VM_NET_DEV_2 | jq -c '.[0].addr_info[] | select(.family == "inet")'); do
    cidr_addr=$(echo $addr | jq -r '[ .local, .prefixlen|tostring] | join("/")');
    if ! ip addr add dev dockerbridge_2 $cidr_addr; then
        error "Failed to add address for dockerbridge_2 interface"
        exit 30
    fi
  done
  if ! ip addr flush dev $VM_NET_DEV_2; then
    error "Failed to clear $VM_NET_DEV_2 interface addresses"
    exit 30
  fi

  while ! ip link set dockerbridge_2 up; do
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

  if ! ip link set dev "$VM_NET_DEV" master dockerbridge; then
    error "Failed to attach docker interface to bridge"
  fi

  if ! ip tuntap add dev "$VM_NET_TAP_2" mode tap; then
    error "$tuntap" && return 1
  fi

  while ! ip link set "$VM_NET_TAP_2" up promisc on; do
    info "Waiting for TAP to become available..."
    sleep 2
  done

  if ! ip link set dev "$VM_NET_TAP_2" master dockerbridge_2; then
    error "Failed to set IP link!" && return 1
  fi

  # add initial default route as well
  if ! ip route add default dev dockerbridge via ${VM_NET_IP%.*}.1; then
    error "Failed to setup default route" && return 10
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

  NET_OPTS+=" -netdev tap,id=hostnet1,ifname=$VM_NET_TAP_2"

  if [ -c /dev/vhost-net ]; then
    {
      exec 41>>/dev/vhost-net
      rc=$?
    } 2>/dev/null || :
    ((rc == 0)) && NET_OPTS+=",vhost=on,vhostfd=41"
  fi

  NET_OPTS+=",script=no,downscript=no"

  return 0

}

closeNetwork() {

  # Shutdown nginx
  nginx -s stop 2>/dev/null
  fWait "nginx"

  [[ "$NETWORK" == [Nn]* ]] && return 0

  exec 40<&- || true
  exec 41<&- || true

  if [[ "$DHCP" == [Yy1]* ]]; then

    ip link set "$VM_NET_TAP" down || true
    ip link delete "$VM_NET_TAP" || true
    ip link set "$VM_NET_TAP_2" down || true
    ip link delete "$VM_NET_TAP_2" || true

  else

    local pid="/var/run/dnsmasq.pid"
    [ -s "$pid" ] && pKill "$(<"$pid")"

    [[ "${NETWORK,,}" == "user"* ]] && return 0

    ip link set "$VM_NET_TAP" down promisc off || true
    ip link delete "$VM_NET_TAP" || true
    ip link set "$VM_NET_TAP_2" down promisc off || true
    ip link delete "$VM_NET_TAP_2" || true

    ip link set dockerbridge down || true
    ip link delete dockerbridge || true
    ip link set dockerbridge_2 down || true
    ip link delete dockerbridge_2 || true

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

  if [ ! -d "/sys/class/net/$VM_NET_DEV" ]; then
    error "Network interface '$VM_NET_DEV' does not exist inside the container!"
    error "$ADD_ERR -e \"VM_NET_DEV=NAME\" to specify another interface name." && exit 27
  fi

  if [ ! -d "/sys/class/net/$VM_NET_DEV_2" ]; then
    error "Network interface '$VM_NET_DEV_2' does not exist inside the container!"
    error "$ADD_ERR -e \"VM_NET_DEV_2=NAME\" to specify another interface name." && exit 27
  fi

  if [ -z "$MAC" ]; then
    local file="$STORAGE/$PROCESS.mac"
    if [ -z "$MAC" ]; then
      # Generate MAC address based on Docker container ID in hostname
      MAC=$(printf '02:%02x:%02x:%02x:%02x:%02x\n' \
        $((RANDOM % 256)) $((RANDOM % 256)) $((RANDOM % 256)) $((RANDOM % 256)) $((RANDOM % 256)))
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

  if [ -z "$MAC_2" ]; then
    local file="$STORAGE/$PROCESS.mac"
    if [ -z "$MAC_2" ]; then
      # Generate MAC address based on Docker container ID in hostname
      MAC_2=$(printf '02:%02x:%02x:%02x:%02x:%02x\n' \
        $((RANDOM % 256)) $((RANDOM % 256)) $((RANDOM % 256)) $((RANDOM % 256)) $((RANDOM % 256)))
      echo "${MAC_2^^}" >>"$file"
    fi
  fi

  VM_NET_MAC_2="${MAC_2^^}"
  VM_NET_MAC_2="${VM_NET_MAC_2//-/:}"

  if [[ ${#VM_NET_MAC_2} == 12 ]]; then
    m="$VM_NET_MAC_2"
    VM_NET_MAC_2="${m:0:2}:${m:2:2}:${m:4:2}:${m:6:2}:${m:8:2}:${m:10:2}"
  fi

  if [[ ${#VM_NET_MAC_2} != 17 ]]; then
    error "Invalid MAC address: '$VM_NET_MAC_2', should be 12 or 17 digits long!" && exit 28
  fi

  GATEWAY=$(ip route list dev "$VM_NET_DEV" | awk ' /^default/ {print $3}')
  IP=$(ip address show dev "$VM_NET_DEV" | grep inet | awk '/inet / { print $2 }' | cut -f1 -d/)

  GATEWAY_2=$(ip route list dev "$VM_NET_DEV_2" | awk ' /^default/ {print $3}')
  IP_2=$(ip address show dev "$VM_NET_DEV_2" | grep inet | awk '/inet / { print $2 }' | cut -f1 -d/)

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
if [[ "$DEBUG" == [Yy1]* ]]; then
  info "Host: $HOST  IP: $IP_2  Gateway: $GATEWAY_2  Interface: $VM_NET_DEV_2  MAC: $VM_NET_MAC_2"
  [ -f /etc/resolv.conf ] && grep '^nameserver*' /etc/resolv.conf
  echo
fi

if [[ "$IP" != "172."* ]] && [[ "$IP" != "10.8"* ]] && [[ "$IP" != "10.9"* ]]; then
  checkOS
fi

if [[ "${NETWORK,,}" == "user"* ]]; then

  # Configure for usermode networking (slirp)
  configureUser || exit 24

elif [[ "${NETWORK,,}" == "bridge"* ]]; then
  # CONFIGURE Bridge
  html "Configuring bridged network"

  if ! configureBridge; then

    error "Failed to setup bridge networking"

    ip link set "$VM_NET_TAP" down promisc off &>null || true
    ip link delete "$VM_NET_TAP" &>null || true
    ip link set "$VM_NET_TAP_2" down promisc off &>null || true
    ip link delete "$VM_NET_TAP_2" &>null || true

    ip link set dockerbridge down &>null || true
    ip link delete dockerbridge &>null || true
    ip link set dockerbridge_2 down &>null || true
    ip link delete dockerbridge_2 &>null || true

    exit 25
  fi

else

  # Configure for tap interface
  if ! configureNAT; then

    error "Failed to setup NAT networking"

    ip link set "$VM_NET_TAP" down promisc off &>null || true
    ip link delete "$VM_NET_TAP" &>null || true
    ip link set "$VM_NET_TAP_2" down promisc off &>null || true
    ip link delete "$VM_NET_TAP_2" &>null || true

    ip link set dockerbridge down &>null || true
    ip link delete dockerbridge &>null || true
    ip link set dockerbridge_2 down &>null || true
    ip link delete dockerbridge_2 &>null || true

    exit 25

  fi

fi

NET_OPTS+=" -device $ADAPTER,romfile=,netdev=hostnet0,mac=$VM_NET_MAC,id=net0"
NET_OPTS+=" -device $ADAPTER_2,romfile=,netdev=hostnet1,mac=$VM_NET_MAC_2,id=net1"

html "Initialized network successfully..."
return 0

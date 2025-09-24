Before doing the docker compose up always use the command  

1) Create a macvlan network for the containers

Pick a tiny slice of your LAN that you won’t use for normal devices; we’ll use .200–.206.

# stop your current containers first
docker compose down

# create the macvlan network (parent is your NIC that’s on 192.168.10.0/24)
# \\ here remember that you have to set the subnet gateway ip-range and the parent with your network configuration 
docker network create -d macvlan \  
  --subnet=192.168.10.0/24 \
  --gateway=192.168.10.1 \
  --ip-range=192.168.10.200/29 \
  -o parent=enp6s0 \
  ad_vlan
Why: macvlan lets each container appear as its own L2 host on your 192.168.10.0/24.

2) Allow the host to talk to macvlan endpoints (host-access workaround)

macvlan blocks host↔︎container by design. Create a macvlan sub-interface on the host so Arch can reach them:

# create a host-side macvlan interface that shares the same parent
sudo ip link add adhost link enp6s0 type macvlan mode bridge
sudo ip addr add 192.168.10.9/24 dev adhost
sudo ip link set adhost up

# route the small pool via this host-side macvlan interface
sudo ip route add 192.168.10.200/29 dev adhost

Now your Arch host (192.168.10.10) can reach the macvlan IPs through adhost (192.168.10.9).


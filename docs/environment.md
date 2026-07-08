# Environment Variables

This page lists all the environment variables that can be used to configure the container.

## Windows

| Variable | Default | Description |
|---|---|---|
| `VERSION` | `11` | Windows version to install, for example `11`, `10`,  etc. |
| `EDITION` |  | Windows edition to install, for example `core` for Windows Server. |
| `LANGUAGE` | `en-US` | Windows display language, for example `en`, `fr`, `nl`, etc. |
| `REGION` | `en-US` | Windows regional format, for example `en-US`. |
| `KEYBOARD` | `en-US` | Keyboard layout used during installation, for example `en-US`. |
| `USERNAME` | `Dockur` | Username for the Windows account. |
| `PASSWORD` | `admin` | Password for the Windows account. |
| `KEY` |  | Windows product key used during installation. |
| `WIDTH` | `1920` | Display width configured for Windows. |
| `HEIGHT` | `1080` | Display height configured for Windows. |
| `MANUAL` | `N` | Enables manual installation instead of automatic. |
| `VERIFY` | `N` | Enables checksum verification of downloaded images. |
| `REMOVE` | `Y` | If disabled, skips removal of the Windows .iso. |
| `DETECTED` |  | Overrides the detected Windows image identifier. |

## System

| Variable | Default | Description |
|---|---|---|
| `MACHINE` | `q35` | QEMU machine type. |
| `KVM` | `Y` | Enables KVM acceleration. Set to `N` to disable. |
| `VMX` | `N` | Controls whether VMX virtualization is exposed to Windows. |
| `HV` | `Y` | Enables Hyper-V enlightenments for Windows guests. |
| `UUID` |  | QEMU VM UUID override. |
| `HPET` | `off` | QEMU HPET setting. |
| `VMPORT` | `off` | QEMU vmport setting. |
| `SM_BIOS` |  | Extra SMBIOS arguments passed to QEMU. |
| `CPU_MODEL` | `host` | Overrides the QEMU CPU model. |
| `CPU_FLAGS` |  | Adds extra QEMU CPU flags. |
| `CPU_CORES` | `2` | Number of CPU cores assigned to the VM. Can also be set to `max` or `half`. |
| `RAM_SIZE` | `4G` | Amount of RAM assigned to the VM, for example `4G`, `8G`, `max`, or `half`. |
| `RAM_CHECK` | `Y` | Checks whether enough host memory is available before starting the VM. |
| `ARGUMENTS` |  | Extra raw QEMU arguments appended to the generated command line. |

## Boot

| Variable | Default | Description |
|---|---|---|
| `BOOT_MODE` | `windows` | Boot mode, for example `windows`, `windows_secure`, or `windows_legacy`. |
| `BOOT_INDEX` | `9` | Boot priority index for the installation media. |
| `BIOS` |  | Custom BIOS/firmware file. Setting this enables custom boot mode. |
| `TPM` | `N` | Enables TPM support. |
| `SMM` | `N` | Enables SMM/secure-machine support. |
| `LOGO` | `Y` | Enables custom boot logo. |
| `CLEAR` | `N` | If enabled the firmware/NVRAM variables will be cleared during the next boot. |
| `USB` | `qemu-xhci,id=xhci,p2=7,p3=7` | QEMU USB controller setting. Set to a `no*` value to disable. |

## Shutdown

| Variable | Default | Description |
|---|---|---|
| `SHUTDOWN` | `Y` | Enables graceful ACPI shutdown handling. |
| `TIMEOUT` | `115` | Timeout used while waiting for the VM to shut down. |

## Storage

| Variable | Default | Description |
|---|---|---|
| `DISK_SIZE` | `64G` | Size of the main data disk. |
| `DISK_FMT` | `raw` | Disk image format, usually `raw` or `qcow2`. |
| `DISK_TYPE` | `scsi` | Disk controller/device type, such as `sata`, `scsi`, `nvme`, or `blk`. |
| `DISK_CACHE` | `none` | QEMU disk cache mode, for example `none` or `writeback`. |
| `DISK_IO` | `native` | QEMU disk I/O mode, for example `native`, `threads`, or `io_uring`. |
| `DISK_DISCARD` | `unmap` | Controls TRIM/unmap support. |
| `DISK_ROTATION` | `1` | Rotation rate exposed to the guest. Use `1` for SSD-like storage. |
| `DISK_FLAGS` |  | Extra options used when creating qcow2 disks. |
| `ALLOCATE` | `N` | Controls whether disk space is preallocated. |
| `STORAGE` | `/storage` | Storage directory used for the data files. |

## Networking

| Variable | Default | Description |
|---|---|---|
| `NETWORK` | `Y` | Network mode. Common values are `Y` for NAT, `passt`, `slirp`, or `N`. |
| `DHCP` | `N` | Enables DHCP/macvtap mode, where the VM receives an address from the external LAN. |
| `IP` |  | Guest IP address override. |
| `MAC` |  | Guest network adapter MAC address. |
| `HOST` | `Windows` | Hostname for the VM. |
| `DEV` | `eth0` | Network interface to use. |
| `MTU` |  | Network MTU override. |
| `MASK` | `255.255.255.0` | IPv4 netmask. |
| `TAP` | `qemu` | TAP/macvtap interface name. |
| `BRIDGE` | `docker` | Bridge name used for NAT networking. |
| `ADAPTER` | `virtio-net-pci` | QEMU network adapter model. |
| `HOST_PORTS` |  | Ports reserved for services running on the host/container side. |
| `USER_PORTS` |  | Ports forwarded to the VM when using user-mode networking. |
| `WEB` | `Y` | Enables or disables the web interface. |
| `WEB_PORT` | `8006` | Port for the web interface. |
| `VNC_PORT` | `5900` | Port for the VNC server. |
| `WSS_PORT` | `5700` | WebSocket port used by QEMU/noVNC. |
| `WSD_PORT` | `8004` | Internal websocketd port. |
| `PROTECT` | `N` | Enables password protection for the web interface. |
| `DNSMASQ_OPTS` |  | Extra dnsmasq options. |
| `DNSMASQ_DEBUG` | `N` | Enables dnsmasq log tailing. |
| `DNSMASQ_DISABLE` | `N` | Disables dnsmasq setup. |
| `PASST_OPTS` |  | Extra passt options. |
| `PASST_DEBUG` | `N` | Enables passt debug/log output. |

## Samba

| Variable | Default | Description |
|---|---|---|
| `SAMBA` | `Y` | Enables or disables the Samba shared folder service. |
| `SAMBA_DEBUG` | `N` | Enables Samba debug output. |

## Display

| Variable | Default | Description |
|---|---|---|
| `DISPLAY` | `web` | Display backend. Common values are `web`, `vnc`, `disabled`, or `none`. |
| `VGA` | `virtio` | QEMU video adapter model. |
| `GPU` | `N` | Enables GPU acceleration for Intel integrated graphics (WIP). |
| `RENDERNODE` | `/dev/dri/renderD128` | Render node used for GPU acceleration. |

## Memory Ballooning

| Variable | Default | Description |
|---|---|---|
| `BALLOONING` | `N` | Enables dynamic memory ballooning. |
| `BALLOONING_DEBUG` | `N` | Enables debug output for the ballooning monitor. |
| `BALLOONING_MIN_MEM` | `33%` | Minimum memory target for the balloon device. |
| `BALLOONING_RAM_THRESHOLD` | `80.0` | Host RAM usage target for ballooning decisions. |
| `BALLOONING_RAM_THRESHOLD_HARD` | `90.0` | Hard host RAM pressure threshold. |
| `BALLOONING_PSI_PRESSURE` | `10.0` | PSI memory pressure level where ballooning starts reacting more aggressively. |
| `BALLOONING_PSI_PRESSURE_MAX` | `50.0` | PSI memory pressure level where ballooning reaches its strongest response. |
| `BALLOONING_HYSTERESIS` | `128M` | Minimum memory change before the balloon target is updated. |
| `BALLOONING_KP` | `0.5` | Proportional gain for the ballooning controller. |
| `BALLOONING_KI` | `0.05` | Integral gain for the ballooning controller. |
| `BALLOONING_INTERVAL` | `5` | Polling interval for the ballooning monitor. |

## Debugging

| Variable | Default | Description |
|---|---|---|
| `DEBUG` | `N` | Enables verbose debug output. |
| `TRACE` | `N` | Enables shell command tracing. |
| `SERIAL` | `mon:stdio` | QEMU serial device setting. |
| `MONITOR` | `unix:$QEMU_DIR/monitor.sock,server,wait=off,nodelay` | QEMU monitor socket/device setting. |

# Environment Variables

This page lists all the environment variables that can be used to configure the container.

## 🪟 Windows

| Variable | Default | Description |
|---|---|---|
| `VERSION` | `11` | Windows version to install, for example `10` or `11`. |
| `EDITION` |  | Windows edition to install, for example `core` for Windows Server Core. |
| `LANGUAGE` | `en-US` | Windows display language, for example `en`, `fr`, `nl`, etc. |
| `REGION` | `en-US` | Windows regional format, for example `en-US`. |
| `KEYBOARD` | `en-US` | Keyboard layout used during installation, for example `en-US`. |
| `USERNAME` | `Dockur` | Username for the Windows account. |
| `PASSWORD` | `admin` | Password for the Windows account. |
| `KEY` |  | Windows product key used during installation. |
| `MANUAL` | `N` | Enables manual installation instead of unattended installation. |
| `VERIFY` | `N` | Verifies checksums of downloaded images. |
| `REMOVE` | `Y` | Removes the Windows ISO after installation. Set to `N` to keep it. |

## 🧠 CPU and Memory

| Variable | Default | Description |
|---|---|---|
| `CPU_CORES` | `2` | Number of CPU cores assigned to the VM. Can also be set to `max` or `half`. |
| `CPU_MODEL` | `host` | QEMU CPU model to use. |
| `CPU_FLAGS` |  | Additional QEMU CPU flags. |
| `KVM` | `Y` | Enables KVM hardware acceleration. Set to `N` to disable. |
| `VMX` | `N` | Exposes Intel VMX virtualization extensions to Windows. |
| `HV` | `Y` | Enables Hyper-V enlightenments for Windows. |
| `RAM_SIZE` | `4G` | Amount of RAM assigned to the VM, for example `4G`, `8G`, `max`, or `half`. |
| `RAM_CHECK` | `Y` | Checks whether enough host memory is available before starting the VM. |

## ⚙️ System

| Variable | Default | Description |
|---|---|---|
| `MACHINE` | `q35` | QEMU machine type. |
| `UUID` |  | QEMU VM UUID. |
| `HPET` | `off` | Enables or disables the QEMU HPET timer. |
| `VMPORT` | `off` | Enables or disables the QEMU VMware port. |
| `SM_BIOS` |  | Additional SMBIOS arguments passed to QEMU. |
| `ARGUMENTS` |  | Additional raw QEMU arguments appended to the generated command line. |

## 🚀 Boot

| Variable | Default | Description |
|---|---|---|
| `BOOT_MODE` | `windows` | Boot mode, for example `windows`, `windows_secure`, or `windows_legacy`. |
| `BOOT_INDEX` | `9` | Boot priority index for the installation media. |
| `BIOS` |  | Custom BIOS/firmware file. Setting this enables custom boot mode. |
| `TPM` | `N` | Enables TPM support. |
| `SMM` | `N` | Enables SMM/secure-machine support. |
| `LOGO` | `Y` | Enables the custom boot logo. |
| `CLEAR` | `N` | Clears the firmware/NVRAM variables on the next boot. |
| `USB` | `qemu-xhci,id=xhci,p2=7,p3=7` | QEMU USB controller setting. Set to a `no*` value to disable. |

## 💾 Storage

| Variable | Default | Description |
|---|---|---|
| `DISK_SIZE` | `64G` | Size of the main data disk. |
| `DISK_FMT` | `raw` | Disk image format, usually `raw` or `qcow2`. |
| `DISK_TYPE` | `scsi` | Disk controller/device type, such as `sata`, `scsi`, `nvme`, or `blk`. |
| `DISK_CACHE` | `none` | QEMU disk cache mode, for example `none` or `writeback`. |
| `DISK_IO` | `native` | QEMU disk I/O mode, for example `native`, `threads`, or `io_uring`. |
| `DISK_DISCARD` | `unmap` | Enables TRIM/unmap support for the data disk. |
| `DISK_ROTATION` | `1` | Rotation rate reported to the guest. Use `1` for SSD-like storage. |
| `DISK_FLAGS` |  | Additional options used when creating qcow2 disks. |
| `ALLOCATE` | `N` | Preallocates disk space when creating the data disk. |
| `STORAGE` | `/storage` | Storage directory used for disks, firmware variables, and generated files. |

## 🌐 Networking

| Variable | Default | Description |
|---|---|---|
| `NETWORK` | `Y` | Network mode. Common values are `Y` for NAT, `passt`, `slirp`, or `N` to disable networking. |
| `DHCP` | `N` | Enables DHCP/macvtap mode so the VM receives an address from the external LAN. |
| `IP` |  | Guest IP address override. |
| `MAC` |  | Guest network adapter MAC address. |
| `HOST` | `Windows` | Hostname assigned to the VM. |
| `DEV` | `eth0` | Host/container network interface to use. |
| `MTU` |  | Network MTU to use for the guest interface. |
| `MASK` | `255.255.255.0` | IPv4 netmask. |
| `TAP` | `qemu` | TAP/macvtap interface name. |
| `BRIDGE` | `docker` | Bridge name used for NAT networking. |
| `ADAPTER` | `virtio-net-pci` | QEMU network adapter model. |
| `HOST_PORTS` |  | Ports reserved for services running on the host/container side. |
| `USER_PORTS` |  | Additional ports to forward to the VM when using user-mode networking. |
| `DNSMASQ_OPTS` |  | Additional dnsmasq options. |
| `DNSMASQ_DEBUG` | `N` | Enables dnsmasq log tailing. |
| `DNSMASQ_DISABLE` | `N` | Disables the internal dnsmasq resolver. |
| `PASST_OPTS` |  | Additional passt options. |
| `PASST_DEBUG` | `N` | Enables passt debug output. |

## 📁 File Sharing

| Variable | Default | Description |
|---|---|---|
| `SAMBA` | `Y` | Enables or disables the Samba shared folder. |
| `SAMBA_DEBUG` | `N` | Enables Samba debug output. |

## 🖥️ Display

| Variable | Default | Description |
|---|---|---|
| `WIDTH` | `1920` | Display width configured for Windows. |
| `HEIGHT` | `1080` | Display height configured for Windows. |
| `DISPLAY` | `web` | Display backend. Common values are `web`, `vnc`, `disabled`, or `none`. |
| `VGA` | `virtio` | QEMU video adapter model. |
| `GPU` | `N` | Enables Intel iGPU acceleration. Experimental. |
| `RENDERNODE` | `/dev/dri/renderD128` | Render node used for GPU acceleration. |

## 🌍 Web UI

| Variable | Default | Description |
|---|---|---|
| `WEB` | `Y` | Enables or disables the web interface. |
| `WEB_PORT` | `8006` | Port for the web interface. |
| `VNC_PORT` | `5900` | Port for the VNC server. |
| `WSS_PORT` | `5700` | WebSocket port used by noVNC. |
| `WSD_PORT` | `8004` | Internal websocketd port. |
| `AUDIO` | `N` | Streams guest audio to the web viewer. |
| `SOUND` | `intel-hda` | QEMU audio device used for browser audio. |
| `AUX_PORT` | `8003` | Internal WebSocket port used for browser audio. |
| `PROTECT` | `N` | Enables password protection for the web interface. |

## 🎈 Memory Ballooning

Also see [Dynamic memory allocation](https://github.com/qemus/qemu/blob/master/docs/ballooning.md) for usage notes and important caveats.

| Variable | Default | Description |
|---|---|---|
| `BALLOONING` | `N` | Enables dynamic memory ballooning. |
| `BALLOONING_DEBUG` | `N` | Enables debug output for the ballooning monitor. |
| `BALLOONING_MIN_MEM` | `33%` | Minimum memory target for the balloon device. |
| `BALLOONING_RAM_THRESHOLD` | `80.0` | Target host RAM usage percentage. |
| `BALLOONING_RAM_THRESHOLD_HARD` | `90.0` | Host RAM usage percentage where ballooning becomes more aggressive. |
| `BALLOONING_PSI_PRESSURE` | `10.0` | PSI memory pressure level where ballooning starts reacting more aggressively. |
| `BALLOONING_PSI_PRESSURE_MAX` | `50.0` | PSI memory pressure level where ballooning reaches its strongest response. |
| `BALLOONING_HYSTERESIS` | `128M` | Minimum memory change before the balloon target is updated. |
| `BALLOONING_KP` | `0.5` | Proportional gain for the ballooning controller. |
| `BALLOONING_KI` | `0.05` | Integral gain for the ballooning controller. |
| `BALLOONING_INTERVAL` | `5` | Polling interval in seconds. |

## 🔌 Shutdown

| Variable | Default | Description |
|---|---|---|
| `SHUTDOWN` | `Y` | Enables graceful ACPI shutdown. |
| `TIMEOUT` | `115` | Timeout used while waiting for the VM to shut down. |

## 🐞 Debugging

| Variable | Default | Description |
|---|---|---|
| `DEBUG` | `N` | Enables verbose debug output. |
| `TRACE` | `N` | Enables shell command tracing. |
| `DETECTED` |  | Overrides the detected Windows image identifier. |
| `SERIAL` | `mon:stdio` | QEMU serial device setting. |
| `MONITOR` | `unix:$QEMU_DIR/monitor.sock,server,wait=off,nodelay` | QEMU monitor device setting. |

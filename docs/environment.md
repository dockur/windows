# Environment Variables

This page lists all the environment variables that can be used to configure the container.

An empty default means the variable is unset and its value is determined automatically when applicable.

## 🪟 Windows

| Variable | Default | Description |
|---|---|---|
| `VERSION` | `11` | Windows version to install, such as `10` or `11`. |
| `EDITION` |  | Windows edition to install, such as `core` for Windows Server Core. |
| `LANGUAGE` | `en-US` | Windows display language, such as `English`, `en-US`, or `en`. |
| `REGION` |  | Windows regional format. Uses `LANGUAGE` when unset. |
| `KEYBOARD` |  | Keyboard layout. Uses `LANGUAGE` when unset. |
| `USERNAME` | `Docker` | Name of the Windows user account. |
| `PASSWORD` | `admin` | Password for the Windows account. |
| `DOMAIN` |  | Active Directory domain to join during installation. |
| `KEY` |  | Windows product key used to install and activate Windows. |

## 🧠 CPU and Memory

| Variable | Default | Description |
|---|---|---|
| `CPU_CORES` | `2` | Number of virtual CPU cores, such as `4`, `half`, or `max`. |
| `CPU_MODEL` | `host` | QEMU CPU model. |
| `CPU_FLAGS` |  | Additional QEMU CPU flags. |
| `SMP` |  | Custom CPU topology. Determined from `CPU_CORES` when unset. |
| `KVM` | `Y` | Enables KVM hardware acceleration. |
| `VMX` | `N` | Exposes Intel VMX virtualization extensions to the guest. |
| `HV` | `Y` | Enables Hyper-V enlightenments for Windows guests. |
| `RAM_SIZE` | `4G` | Amount of RAM assigned to Windows, such as `8G`, `half`, or `max`. |
| `RAM_CHECK` | `Y` | Checks whether enough host memory is available before starting Windows. |

## 💾 Storage

| Variable | Default | Description |
|---|---|---|
| `DISK_SIZE` | `64G` | Size of the primary disk. |
| `DISK_FMT` | `raw` | Disk image format: `raw` or `qcow2`. |
| `DISK_TYPE` | `scsi` | Disk device type, such as `sata`, `scsi`, `nvme`, or `blk`. |
| `DISK_CACHE` | `none` | Disk cache mode, such as `none` or `writeback`. |
| `DISK_IO` | `native` | Disk I/O mode, such as `native`, `threads`, or `io_uring`. |
| `DISK_DISCARD` | `unmap` | Discard/TRIM mode for the primary disk. |
| `DISK_ROTATION` | `1` | Rotation rate reported to the guest. Use `1` to identify the disk as an SSD. |
| `DISK_FLAGS` |  | Additional options used when creating `qcow2` disks. |
| `ALLOCATE` | `N` | Preallocates space for the primary disk. |
| `STORAGE` | `/storage` | Storage directory used for disks, firmware variables, and downloads. |

## 🌐 Networking

| Variable | Default | Description |
|---|---|---|
| `NETWORK` |  | Network mode, such as `nat`, `user`, or `N` to disable networking. |
| `DHCP` | `N` | Enables macvtap networking so Windows receives an address from the external LAN through DHCP. |
| `HOST` | `Windows` | Hostname assigned to Windows. |
| `IP` |  | Overrides the automatically selected guest IPv4 address. |
| `MAC` |  | Guest network adapter MAC address. |
| `ADAPTER` | `virtio-net-pci` | QEMU network adapter model. |
| `DEV` | `eth0` | Container network interface used as the uplink. |
| `MTU` |  | MTU assigned to the guest network interface. |
| `MASK` | `255.255.255.0` | IPv4 netmask. |
| `TAP` | `qemu` | TAP or macvtap interface name. |
| `BRIDGE` | `docker` | Bridge name used for NAT networking. |
| `HOST_PORTS` |  | Ports excluded from guest forwarding. |
| `USER_PORTS` |  | Additional ports to forward to Windows when using user-mode networking. |
| `DNSMASQ_OPTS` |  | Additional options passed to dnsmasq. |
| `DNSMASQ_DEBUG` | `N` | Enables dnsmasq debug output. |
| `DNSMASQ_DISABLE` | `N` | Disables the internal dnsmasq resolver. |
| `PASST_OPTS` |  | Additional options passed to passt. |
| `PASST_DEBUG` | `N` | Enables passt debug output. |

## 🖥️ Display

| Variable | Default | Description |
|---|---|---|
| `DISPLAY` | `web` | Display backend, such as `web`, `vnc`, `disabled`, or `none`. |
| `LOSSY` | `N` | Enables lossy VNC compression to reduce bandwidth usage. |
| `VGA` | `virtio` | QEMU video adapter model. |
| `WIDTH` | `1920` | Display width configured in Windows. |
| `HEIGHT` | `1080` | Display height configured in Windows. |
| `GPU` | `N` | Enables experimental Intel iGPU acceleration. |
| `RENDERNODE` | `/dev/dri/renderD128` | Render node used for GPU acceleration. |

## 🌍 Web UI

| Variable | Default | Description |
|---|---|---|
| `WEB` | `Y` | Enables the web interface. |
| `WEB_PORT` | `8006` | Port for the web interface. |
| `VNC_PORT` | `5900` | Port for the VNC server. |
| `WSS_PORT` | `5700` | WebSocket port used by noVNC. |
| `WSD_PORT` | `8004` | Internal websocketd port used for the display stream. |
| `AUDIO` | `N` | Streams guest audio to the web viewer. |
| `SOUND` | `intel-hda` | QEMU audio device used by the web viewer. |
| `AUX_PORT` | `8003` | Internal WebSocket port used for the audio stream. |
| `PROTECT` | `N` | Enables password protection for the web interface. |

## 📁 File Sharing

| Variable | Default | Description |
|---|---|---|
| `SAMBA` | `Y` | Enables the Samba shared folder. |
| `SAMBA_DEBUG` | `N` | Enables Samba debug output. |

## ⚙️ System

| Variable | Default | Description |
|---|---|---|
| `MACHINE` | `q35` | QEMU machine type. |
| `UUID` |  | UUID assigned to Windows. |
| `HPET` | `off` | QEMU HPET timer setting. |
| `VMPORT` | `off` | QEMU VMware port setting. |
| `SM_BIOS` |  | Additional arguments passed to QEMU’s `-smbios` option. |
| `ARGUMENTS` |  | Additional raw arguments appended to the QEMU command line. |

## 🚀 Boot

| Variable | Default | Description |
|---|---|---|
| `BOOT_MODE` | `windows` | Boot configuration, such as `windows`, `windows_secure`, or `windows_legacy`. |
| `BOOT_INDEX` | `9` | Boot priority index for the installation media. |
| `MEDIA_TYPE` |  | Device type used for installation media. |
| `BIOS` |  | Custom firmware file. |
| `TPM` | `N` | Enables the TPM emulator, usually set by `BOOT_MODE`. |
| `SMM` | `N` | Enables System Management Mode, usually set by `BOOT_MODE`. |
| `LOGO` | `Y` | Enables the custom boot logo. |
| `CLEAR` | `N` | Resets the NVRAM variables on the next boot. |
| `USB` | `qemu-xhci,id=xhci` | QEMU USB controller configuration. |

## 🎈 Memory Ballooning

Also see [Dynamic memory allocation](https://github.com/qemus/qemu/blob/master/docs/ballooning.md) for usage instructions and important caveats.

| Variable | Default | Description |
|---|---|---|
| `BALLOONING` | `N` | Enables dynamic memory ballooning. |
| `BALLOONING_MIN_MEM` | `33%` | Minimum amount of memory retained by the VM. |
| `BALLOONING_RAM_THRESHOLD` | `80.0` | Host RAM usage percentage at which ballooning begins adjusting memory. |
| `BALLOONING_RAM_THRESHOLD_HARD` | `90.0` | Host RAM usage percentage at which ballooning becomes more aggressive. |
| `BALLOONING_PSI_PRESSURE` | `10.0` | PSI memory pressure level at which ballooning becomes more aggressive. |
| `BALLOONING_PSI_PRESSURE_MAX` | `50.0` | PSI memory pressure level at which ballooning reaches its strongest response. |
| `BALLOONING_HYSTERESIS` | `128M` | Minimum memory change before the balloon target is updated. |
| `BALLOONING_KP` | `0.5` | Proportional gain used by the ballooning controller. |
| `BALLOONING_KI` | `0.05` | Integral gain used by the ballooning controller. |
| `BALLOONING_INTERVAL` | `5` | Polling interval in seconds. |
| `BALLOONING_DEBUG` | `N` | Enables debug output for the ballooning monitor. |

## 💿 Installation

| Variable | Default | Description |
|---|---|---|
| `MIDO` | `Y` | Enables downloading Windows ISO files directly from Microsoft. |
| `ESD` | `Y` | Enables downloading Windows through the ESD-based installation method. |
| `VERIFY` | `N` | Verifies downloaded installation media against predefined checksums. |
| `REMOVE` | `Y` | Deletes the downloaded Windows ISO after installation to save space. |
| `MANUAL` | `N` | Enables manual installation instead of unattended installation. |
| `COMMAND` |  | Command to be executed during the final step of automatic installation. |

## 🔌 Shutdown

| Variable | Default | Description |
|---|---|---|
| `SHUTDOWN` | `Y` | Enables graceful ACPI shutdown. |
| `TIMEOUT` | `115` | Maximum time, in seconds, to wait before forcing Windows to stop. |

## 🐞 Debugging

| Variable | Default | Description |
|---|---|---|
| `DEBUG` | `N` | Enables verbose debug output. |
| `TRACE` | `N` | Enables shell command tracing. |
| `DETECTED` |  | Overrides the automatically detected Windows image identifier. |
| `SERIAL` | `mon:stdio` | QEMU serial device configuration. |
| `MONITOR` | `unix:$QEMU_DIR/monitor.sock,server,wait=off,nodelay` | QEMU monitor configuration. |

<h1 align="center">Windows<br />
<div align="center">
<a href="https://github.com/dockur/windows"><img src="https://github.com/dockur/windows/raw/master/.github/logo.png" title="Logo" style="max-width:100%;" width="96" /></a>
</div>
<div align="center">

[![Build]][build_url]
[![Version]][tag_url]
[![Size]][tag_url]
[![Package]][pkg_url]
[![Pulls]][hub_url]

</div></h1>

Windows inside a Docker container.

## Features ✨

- Runs Windows inside a Docker container
- Automatic download and hands-free installation
- Supports modern and legacy Windows releases
- Near-native performance with KVM acceleration
- Customizable CPU, memory, and storage allocation
- Dynamic memory allocation with memory ballooning
- USB passthrough and host folder sharing
- Supports NAT, user-mode, macvlan, and macvtap networking

## Video 📺

[![YouTube](https://img.youtube.com/vi/xhGYobuG508/maxresdefault.jpg)](https://www.youtube.com/watch?v=xhGYobuG508)

## Usage 🐳

##### Docker Compose:

```yaml
services:
  windows:
    image: dockurr/windows
    container_name: windows
    environment:
      VERSION: "11"
    devices:
      - /dev/kvm
      - /dev/net/tun
    cap_add:
      - NET_ADMIN
    ports:
      - 8006:8006
      - 3389:3389/tcp
      - 3389:3389/udp
    volumes:
      - ./windows:/storage
    restart: always
    stop_grace_period: 2m
```

##### Docker CLI:

```bash
docker run -it --rm --name windows -e "VERSION=11" -p 8006:8006 --device=/dev/kvm --device=/dev/net/tun --cap-add NET_ADMIN -v "${PWD:-.}/windows:/storage" --stop-timeout 120 docker.io/dockurr/windows
```

##### Kubernetes:

```shell
kubectl apply -f https://raw.githubusercontent.com/dockur/windows/refs/heads/master/kubernetes.yml
```

##### GitHub Codespaces:

[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/dockur/windows)

##### Graphical installer:

[![Download WinBoat](https://github.com/dockur/windows/raw/master/.github/winboat.png)](https://winboat.app)

## Requirements ⚙️

- Docker or Podman on a Linux host with KVM support.
- Docker Desktop or Podman (Desktop) on Windows 11 with nested virtualization enabled.
- At least 4 GB of available RAM.
- At least 64 GB of free disk space.

> [!NOTE]
> Docker Desktop on Linux, macOS, and Windows 10 does not currently provide KVM access to containers and is therefore not supported.

## FAQ 💬

### How do I use it?

  Very simple! These are the steps:
  
  - Start the container and connect to [port 8006](http://127.0.0.1:8006/) using your web browser.

  - Sit back and relax while the magic happens, the whole installation will be performed fully automatically.

  - Once you see the desktop, your Windows installation is ready for use.
  
  Enjoy your brand new machine, and don't forget to star this repo!

### How do I select the Windows version?

  By default, Windows 11 Pro will be installed. But you can add the `VERSION` environment variable to your compose file, in order to specify an alternative Windows version to be downloaded:

  ```yaml
  environment:
    VERSION: "10"
  ```

  Select from the values below:
  
  | **Value** | **Version**            | **Size** |
  |---|---|---|
  | `11`   | Windows 11 Pro            | 7.9 GB   |
  | `11l`  | Windows 11 LTSC           | 4.7 GB   |
  | `11e`  | Windows 11 Enterprise     | 6.6 GB   |
  ||||
  | `10`   | Windows 10 Pro            | 5.7 GB   |
  | `10l`  | Windows 10 LTSC           | 4.6 GB   |
  | `10e`  | Windows 10 Enterprise     | 5.2 GB   |
  ||||
  | `8e`   | Windows 8.1 Enterprise    | 3.7 GB   |
  | `7u`   | Windows 7 Ultimate        | 3.1 GB   |
  | `vu`   | Windows Vista Ultimate    | 3.0 GB   |
  | `xp`   | Windows XP Professional   | 0.6 GB   |
  | `2k`   | Windows 2000 Professional | 0.4 GB   | 
  ||||  
  | `2025` | Windows Server 2025       | 7.6 GB   |
  | `2022` | Windows Server 2022       | 6.0 GB   |
  | `2019` | Windows Server 2019       | 5.3 GB   |
  | `2016` | Windows Server 2016       | 6.5 GB   |
  | `2012` | Windows Server 2012       | 4.3 GB   |
  | `2008` | Windows Server 2008       | 3.0 GB   |
  | `2003` | Windows Server 2003       | 0.6 GB   |

> [!TIP]
> To install ARM64 versions of Windows use [dockur/windows-arm](https://github.com/dockur/windows-arm/).

### How do I change the storage location?

  To change the storage location, include the following bind mount in your compose file:

  ```yaml
  volumes:
    - ./windows:/storage
  ```

  Replace the example path `./windows` with the desired storage folder or named volume.

### How do I change the size of the disk?

  To expand the default size of 64 GB, add the `DISK_SIZE` setting to your compose file and set it to your preferred capacity:

  ```yaml
  environment:
    DISK_SIZE: "256G"
  ```
  
> [!TIP]
> This can also be used to resize an existing disk to a larger capacity without any data loss. However, you will need to [manually extend the disk partition](https://learn.microsoft.com/en-us/windows-server/storage/disk-management/extend-a-basic-volume?tabs=disk-management) afterwards, since the added disk space will appear as unallocated.

### How do I share files with the host?

  After installation there will be a folder called `Shared` on your desktop, which can be used to exchange files with the host machine.
  
  To select a folder on the host for this purpose, include the following bind mount in your compose file:

  ```yaml
  volumes:
    -  ./example:/shared
  ```

  Replace the example path `./example` with your desired shared folder, which then will become visible as `Shared`.

### How do I change the amount of CPU or RAM?

  By default, Windows will be allowed to use 2 CPU cores and 4 GB of RAM.

  If you want to adjust this, you can specify the desired amount using the following environment variables:

  ```yaml
  environment:
    RAM_SIZE: "8G"
    CPU_CORES: "4"
  ```

### How do I configure the username and password?

  By default, a user called `Docker` is created and its password is `admin`.

  If you want to set up different credentials during installation, you can configure them in your compose file:

  ```yaml
  environment:
    USERNAME: "bill"
    PASSWORD: "gates"
  ```

### How do I select the Windows language?

  By default, the English version of Windows will be downloaded.
  
  But you can add the `LANGUAGE` environment variable to your compose file, in order to specify an alternative language to be downloaded:

  ```yaml
  environment:
    LANGUAGE: "French"
  ```
  
  You can choose between: 🇦🇪 Arabic, 🇧🇬 Bulgarian, 🇨🇳 Chinese, 🇭🇷 Croatian, 🇨🇿 Czech, 🇩🇰 Danish, 🇳🇱 Dutch, 🇬🇧 English, 🇪🇪 Estonian, 🇫🇮 Finnish, 🇫🇷 French, 🇩🇪 German, 🇬🇷 Greek, 🇮🇱 Hebrew, 🇭🇺 Hungarian, 🇮🇹 Italian, 🇯🇵 Japanese, 🇰🇷 Korean, 🇱🇻 Latvian, 🇱🇹 Lithuanian, 🇳🇴 Norwegian, 🇵🇱 Polish, 🇵🇹 Portuguese, 🇷🇴 Romanian, 🇷🇺 Russian, 🇷🇸 Serbian, 🇸🇰 Slovak, 🇸🇮 Slovenian, 🇪🇸 Spanish, 🇸🇪 Swedish, 🇹🇭 Thai, 🇹🇷 Turkish and 🇺🇦 Ukrainian.

### How do I select the keyboard layout?

  If you want to set up a keyboard layout or locale that is not the default for your selected language, you can add `KEYBOARD` and `REGION` variables like this:

  ```yaml
  environment:
    REGION: "en-US"
    KEYBOARD: "en-US"
  ```

### How do I install a custom image?

  In order to download an unsupported ISO image, specify its URL in the `VERSION` environment variable:
  
  ```yaml
  environment:
    VERSION: "https://example.com/win.iso"
  ```

  Alternatively, you can also skip the download and use a local file instead, by binding it in your compose file in this way:
  
  ```yaml
  volumes:
    - ./example.iso:/custom.iso
  ```

  Replace the example path `./example.iso` with the filename of your desired ISO file. The value of `VERSION` will be ignored in this case.

### How do I run a script after installation?

  To run your own script after installation, you can create a file called `install.bat` and place it in a folder together with any additional files it needs (software to be installed for example).
  
  Then bind that folder in your compose file like this:

  ```yaml
  volumes:
    -  ./example:/oem
  ```

  The example folder `./example` will be copied to `C:\OEM` and the `install.bat` file inside that folder will be executed during the last step of the automatic installation.

### How do I perform a manual installation?

  It's recommended to stick to the automatic installation, as it adjusts various settings to prevent common issues when running Windows inside a virtual environment.

  However, if you insist on performing the installation manually (at your own risk), add the following environment variable to your compose file:

  ```yaml
  environment:
    MANUAL: "Y"
  ```

### How do I connect using RDP?

  The web viewer is mainly intended for use during installation, since it is less responsive than RDP and does not support features such as clipboard sharing.

  So for a better experience you can connect using any Microsoft Remote Desktop client to the IP of the container, using the username `Docker` and password `admin`.

  There is an RDP client for [Android](https://play.google.com/store/apps/details?id=com.microsoft.rdc.androidx) available from the Play Store and one for [iOS](https://apps.apple.com/nl/app/microsoft-remote-desktop/id714464092?l=en-GB) in the Apple Store. For Linux you can use [FreeRDP](https://www.freerdp.com/) and on Windows just type `mstsc` in the search box.

### How do I enable audio?

    Audio is disabled by default unless you are using RDP. To stream it to the browser, add the following environment variable:

  ```yaml
  environment:
    AUDIO: "Y"
  ```

  Then enable **Audio** under **Settings → Advanced** in the web viewer. The stream is only active while this option is enabled, so it uses no extra bandwidth otherwise.

### How do I assign an individual IP address to the container?

  By default, the container uses bridge networking, which shares the IP address with the host. 

  If you want to assign an individual IP address to the container, you can create a macvlan network as follows:

  ```bash
  docker network create -d macvlan \
      --subnet=192.168.0.0/24 \
      --gateway=192.168.0.1 \
      --ip-range=192.168.0.100/28 \
      -o parent=eth0 vlan
  ```
  
  Be sure to modify these values to match your local subnet. 

  Once you have created the network, change your compose file to look as follows:

  ```yaml
  services:
    windows:
      container_name: windows
      ..<snip>..
      networks:
        vlan:
          ipv4_address: 192.168.0.100

  networks:
    vlan:
      external: true
  ```
 
  An added benefit of this approach is that you won't have to perform any port mapping anymore, since all ports will be exposed by default.

> [!IMPORTANT]  
> This IP address won't be accessible from the Docker host due to the design of macvlan, which doesn't permit communication between the two. If this is a concern, you need to create a [second macvlan](https://blog.oddbit.com/post/2018-03-12-using-docker-macvlan-networks/#host-access) as a workaround.

### How can Windows acquire an IP address from my router?

  After configuring the container for [macvlan](#how-do-i-assign-an-individual-ip-address-to-the-container), it is possible for Windows to become part of your home network by requesting an IP from your router, just like a real PC.

  To enable this mode, in which the container and Windows will have separate IP addresses, add the following lines to your compose file:

  ```yaml
  environment:
    DHCP: "Y"
  devices:
    - /dev/vhost-net
  device_cgroup_rules:
    - 'c *:* rwm'
  ```

### How do I add multiple disks?

  To create additional disks, modify your compose file like this:
  
  ```yaml
  environment:
    DISK2_SIZE: "32G"
    DISK3_SIZE: "64G"
  volumes:
    - ./example2:/storage2
    - ./example3:/storage3
  ```

### How do I pass through a disk?

  You can pass through disk devices or partitions directly by adding them to your compose file in this way:

  ```yaml
  devices:
    - /dev/sdb:/disk1
    - /dev/sdc1:/disk2
  ```

  Use `/disk1` if you want it to become your main drive (which will be formatted during installation), and use `/disk2` and higher to add them as secondary drives (which will stay untouched).

### How do I pass through a USB device?

  To pass through a USB device, first look up its vendor and product IDs via the `lsusb` command, then add them to your compose file like this:

  ```yaml
  environment:
    ARGUMENTS: "-device usb-host,vendorid=0x1234,productid=0x1234"
  devices:
    - /dev/bus/usb
  ```

> [!WARNING]  
> Adding a USB mass storage device before Windows Setup has finished may cause it to fail. Or worse: the drive can get formatted as the system disk, and all your data will be lost! So always keep them disconnected when launching the container for the first time.

### Are these all available options?

  No. For a complete overview of all supported settings, see the [environment variables](docs/environment.md) page.

### How do I verify that KVM is available?

  First, make sure your platform and container runtime meet the [requirements](#requirements-️) listed above.

  On a Linux host, install `cpu-checker` and run:

  ```bash
  sudo apt install cpu-checker
  sudo kvm-ok
  ```

  A working configuration should report:

  ```text
  KVM acceleration can be used
  ```

  You can also verify that the KVM device exists:

  ```bash
  ls -l /dev/kvm
  ```

  If KVM is unavailable, check whether:

  - Hardware virtualization (`Intel VT-x` or `AMD-V`) is enabled in your BIOS or UEFI.
  - Nested virtualization is enabled when the host itself is a virtual machine.
  - Your VPS or cloud provider supports nested virtualization.

  If `kvm-ok` succeeds but the container still reports that KVM is unavailable, you can temporarily add `privileged: true` to your Compose file to rule out a permission or device-access issue.

### How do I run macOS in a container?

  You can use [dockur/macos](https://github.com/dockur/macos) for that. It shares many of the same features, except for the automatic installation.

### How do I run a Linux desktop in a container?

  You can use [qemus/qemu](https://github.com/qemus/qemu) in that case.

### Is this project legal?

  Yes, this project contains only open-source code and does not distribute Windows itself. Any product keys found in the code are generic installation keys published by Microsoft for trial purposes and are not valid activation licenses.

  You are responsible for ensuring that you have a valid Windows license and that your use complies with Microsoft's licensing terms.

## Stars 🌟
[![Stargazers](https://raw.githubusercontent.com/star-stats/stars/refs/heads/data/charts/dockur-windows.svg)](https://github.com/dockur/windows/stargazers)

## Disclaimer ⚖️

*The product names, logos, brands, and other trademarks referred to within this project are the property of their respective trademark holders. This project is not affiliated, sponsored, or endorsed by Microsoft Corporation.*

[build_url]: https://github.com/dockur/windows/
[hub_url]: https://hub.docker.com/r/dockurr/windows/
[tag_url]: https://hub.docker.com/r/dockurr/windows/tags
[pkg_url]: https://github.com/dockur/windows/pkgs/container/windows

[Build]: https://github.com/dockur/windows/actions/workflows/build.yml/badge.svg
[Size]: https://img.shields.io/docker/image-size/dockurr/windows/latest?color=066da5&label=size
[Pulls]: https://img.shields.io/docker/pulls/dockurr/windows.svg?style=flat&label=pulls&logo=docker
[Version]: https://img.shields.io/docker/v/dockurr/windows/latest?arch=amd64&sort=semver&color=066da5
[Package]: https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fipitio.github.io%2Fbackage%2Fdockur%2Fwindows%2Fwindows.json&query=%24.downloads&logo=github&style=flat&color=066da5&label=pulls

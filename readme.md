<h1 align="center">Windows<br />
<div align="center">
<a href="https://github.com/dockur/windows"><img src="https://github.com/dockur/windows/raw/master/.github/logo.png" title="Logo" style="max-width:100%;" width="128" /></a>
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

 - ISO downloader
 - KVM acceleration
 - Web-based viewer

## Video 📺

[![Youtube](https://img.youtube.com/vi/xhGYobuG508/0.jpg)](https://www.youtube.com/watch?v=xhGYobuG508)

## Usage 🐳

##### Via Docker Compose:

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

##### Via Docker CLI:

```bash
docker run -it --rm --name windows -p 8006:8006 --device=/dev/kvm --device=/dev/net/tun --cap-add NET_ADMIN -v ${PWD:-.}/windows:/storage --stop-timeout 120 dockurr/windows
```

##### Via Kubernetes:

```shell
kubectl apply -f https://raw.githubusercontent.com/dockur/windows/refs/heads/master/kubernetes.yml
```

##### Via Github Codespaces:

[`Click here to launch this container in the cloud!`](https://github.com/codespaces/new?skip_quickstart=true&machine=basicLinux32gb&repo=743140652&ref=master&devcontainer_path=.devcontainer.json)

## Compatibility ⚙️

| **Product**  | **Platform**   | |
|---|---|---|
| Docker Engine     | Linux| ✅ |
| Docker Desktop    | Linux | ❌ |
| Docker Desktop    | macOS | ❌ |
| Docker Desktop    | Windows 11 | ✅ |
| Docker Desktop    | Windows 10 | ❌ |
| Github Codespaces | Cloud      | ✅ |

## FAQ 💬

### How do I use it?

  Very simple! These are the steps:
  
  - Start the container and connect to [port 8006](http://127.0.0.1:8006/) using your web browser.

  - Sit back and relax while the magic happens, the whole installation will be performed fully automatic.

  - Once you see the desktop, your Windows installation is ready for use.
  
  Enjoy your brand new machine, and don't forget to star this repo!

### How do I select the Windows version?

  By default, Windows 11 Pro will be installed. But you can add the `VERSION` environment variable to your compose file, in order to specify an alternative Windows version to be downloaded:

  ```yaml
  environment:
    VERSION: "11"
  ```

  Select from the values below:
  
  | **Value** | **Version**           | **Size** |
  |---|---|---|
  | `11`   | Windows 11 Pro           | 5.4 GB   |
  | `11l`  | Windows 11 LTSC          | 4.7 GB   |
  | `11e`  | Windows 11 Enterprise    | 4.0 GB   |
  ||||
  | `10`   | Windows 10 Pro           | 5.7 GB   |
  | `10l`  | Windows 10 LTSC          | 4.6 GB   |
  | `10e`  | Windows 10 Enterprise    | 5.2 GB   |
  ||||
  | `8e`   | Windows 8.1 Enterprise   | 3.7 GB   |
  | `7e`   | Windows 7 Enterprise     | 3.0 GB   |
  | `ve`   | Windows Vista Enterprise | 3.0 GB   |
  | `xp`   | Windows XP Professional  | 0.6 GB   |
  ||||
  | `2025` | Windows Server 2025      | 5.6 GB   |
  | `2022` | Windows Server 2022      | 4.7 GB   |
  | `2019` | Windows Server 2019      | 5.3 GB   |
  | `2016` | Windows Server 2016      | 6.5 GB   |
  | `2012` | Windows Server 2012      | 4.3 GB   |
  | `2008` | Windows Server 2008      | 3.0 GB   |
  | `2003` | Windows Server 2003      | 0.6 GB   |

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
> This can also be used to resize the existing disk to a larger capacity without any data loss.

### How do I share files with the host?

  Open 'File Explorer' and click on the 'Network' section, you will see a computer called `host.lan`.
  
  Double-click it and it will show a folder called `Data`, which can be bound to any folder on your host via the compose file:

  ```yaml
  volumes:
    -  ./example:/data
  ```

  The example folder `./example` will be available as ` \\host.lan\Data`.
  
> [!TIP]
> You can map this path to a drive letter in Windows, for easier access.

### How do I change the amount of CPU or RAM?

  By default, the container will be allowed to use a maximum of 2 CPU cores and 4 GB of RAM.

  If you want to adjust this, you can specify the desired amount using the following environment variables:

  ```yaml
  environment:
    RAM_SIZE: "8G"
    CPU_CORES: "4"
  ```

### How do I configure the username and password?

  By default, a user called `Docker` (with an empty password) is created during installation.

  If you want to use different credentials, you can configure them in your compose file (only before installation):

  ```yaml
  environment:
    USERNAME: "bill"
    PASSWORD: "gates"
  ```

### How do I select the Windows language?

  By default, the English version of Windows will be downloaded.
  
  But before installation you can add the `LANGUAGE` environment variable to your compose file, in order to specify an alternative language:

  ```yaml
  environment:
    LANGUAGE: "French"
  ```
  
  You can choose between: 🇦🇪 Arabic, 🇧🇬 Bulgarian, 🇨🇳 Chinese, 🇭🇷 Croatian, 🇨🇿 Czech, 🇩🇰 Danish, 🇳🇱 Dutch, 🇬🇧 English, 🇪🇪 Estonian, 🇫🇮 Finnish, 🇫🇷 French, 🇩🇪 German, 🇬🇷 Greek, 🇮🇱 Hebrew, 🇭🇺 Hungarian, 🇮🇹 Italian, 🇯🇵 Japanese, 🇰🇷 Korean, 🇱🇻 Latvian, 🇱🇹 Lithuanian, 🇳🇴 Norwegian, 🇵🇱 Polish, 🇵🇹 Portuguese, 🇷🇴 Romanian, 🇷🇺 Russian, 🇷🇸 Serbian, 🇸🇰 Slovak, 🇸🇮 Slovenian, 🇪🇸 Spanish, 🇸🇪 Swedish, 🇹🇭 Thai, 🇹🇷 Turkish and 🇺🇦 Ukrainian.

### How do I select the keyboard layout?

  If you want to use a keyboard layout or locale that is not the default for your selected language, you can add  `KEYBOARD` and `REGION` variables like this (before installation):

  ```yaml
  environment:
    REGION: "en-US"
    KEYBOARD: "en-US"
  ```

### How do I set the product key?

  By default, an evaluation version of Windows will be installed, but if you have a product key you can add a `KEY` variable like this (before installation):

  ```yaml
  environment:
    KEY: "xxxxx-xxxxx-xxxxx-xxxxx-xxxxx"
  ```

### How do I select the edition?

  Windows Server offers a minimalistic Core edition without a GUI. To select those non-standard editions, you can add a `EDITION` variable like this (before installation):

  ```yaml
  environment:
    EDITION: "core"
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

  The example folder `./example` will be copied to `C:\OEM` and the containing `install.bat` will be executed during the last step of the automatic installation.

### How do I perform a manual installation?

  It's recommended to stick to the automatic installation, as it adjusts various settings to prevent common issues when running Windows inside a virtual environment.

  However, if you insist on performing the installation manually on your own risk, add the following environment variable to your compose file:

  ```yaml
  environment:
    MANUAL: "Y"
  ```

### How do I connect using RDP?

  The web-viewer is mainly meant to be used during installation, as its picture quality is low, and it has no audio or clipboard for example.

  So for a better experience you can connect using any Microsoft Remote Desktop client to the IP of the container, using the username `Docker` and by leaving the password empty.

  There is a RDP client for [Android](https://play.google.com/store/apps/details?id=com.microsoft.rdc.androidx) available from the Play Store and one for [iOS](https://apps.apple.com/nl/app/microsoft-remote-desktop/id714464092?l=en-GB) in the Apple Store. For Linux you can use [FreeRDP](https://www.freerdp.com/) and on Windows just type `mstsc` in the search box.

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

### How do I pass-through a disk?

  It is possible to pass-through disk devices directly by adding them to your compose file in this way:

  ```yaml
  devices:
    - /dev/sdb:/disk1
    - /dev/sdc:/disk2
  ```

  Use `/disk1` if you want it to become your main drive (which will be formatted during installation), and use `/disk2` and higher to add them as secondary drives (which will stay untouched).

### How do I pass-through a USB device?

  To pass-through a USB device, first lookup its vendor and product id via the `lsusb` command, then add them to your compose file like this:

  ```yaml
  environment:
    ARGUMENTS: "-device usb-host,vendorid=0x1234,productid=0x1234"
  devices:
    - /dev/bus/usb
  ```

  If the device is a USB disk drive, please wait until after the installation is fully completed before connecting it. Otherwise the installation may fail, as the order of the disks can get rearranged.

### How do I verify if my system supports KVM?

  Only Linux and Windows 11 support KVM virtualization, macOS and Windows 10 do not unfortunately.
  
  You can run the following commands in Linux to check your system:

  ```bash
  sudo apt install cpu-checker
  sudo kvm-ok
  ```

  If you receive an error from `kvm-ok` indicating that KVM cannot be used, please check whether:

  - the virtualization extensions (`Intel VT-x` or `AMD SVM`) are enabled in your BIOS.

  - you enabled "nested virtualization" if you are running the container inside a virtual machine.

  - you are not using a cloud provider, as most of them do not allow nested virtualization for their VPS's.

  If you do not receive any error from `kvm-ok` but the container still complains about KVM, please check whether:

  - you are not using "Docker Desktop for Linux" as it does not support KVM, instead make use of Docker Engine directly.
 
  - it could help to add `privileged: true` to your compose file (or `sudo` to your `docker run` command), to rule out any permission issue.

### How do I run macOS in a container?

  You can use [dockur/macos](https://github.com/dockur/macos) for that. It shares many of the same features, except for the automatic installation.

### How do I run a Linux desktop in a container?

  You can use [qemus/qemu](https://github.com/qemus/qemu) in that case.

### Is this project legal?

  Yes, this project contains only open-source code and does not distribute any copyrighted material. Any product keys found in the code are just generic placeholders provided by Microsoft for trial purposes. So under all applicable laws, this project will be considered legal.

## Stars 🌟
[![Stars](https://starchart.cc/dockur/windows.svg?variant=adaptive)](https://starchart.cc/dockur/windows)

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

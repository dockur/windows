<h1 align="center">Windows<br />
<div align="center">
<a href="https://github.com/dockur/windows"><img src="https://github.com/dockur/windows/raw/master/.github/logo.png" title="Logo" style="max-width:100%;" width="128" /></a>
</div>
<div align="center">

[![Build]][build_url]
[![Version]][tag_url]
[![Size]][tag_url]
[![Pulls]][hub_url]

</div></h1>

Windows in a docker container.

## Features

 - ISO downloader
 - KVM acceleration
 - Web-based viewer

## Usage

Via `docker-compose.yml`

```yaml
version: "3"
services:
  windows:
    image: dockurr/windows
    container_name: windows
    devices:
      - /dev/kvm
    cap_add:
      - NET_ADMIN
    ports:
      - 8006:8006
      - 3389:3389/tcp
      - 3389:3389/udp
    stop_grace_period: 2m
    restart: on-failure
```

Via `docker run`

```bash
docker run -it --rm -p 8006:8006 --device=/dev/kvm --cap-add NET_ADMIN --stop-timeout 120 dockurr/windows
```

## FAQ

* ### How do I use it?

  Very simple! These are the steps:
  
  - Start the container and connect to [port 8006](http://localhost:8006) using your web browser.

  - Sit back and relax while the magic happens, the whole installation will be performed fully automatic.

  - Once you see the desktop, your Windows installation is ready for use.
  
  Enjoy your brand new machine, and don't forget to star this repo!

* ### How do I select the Windows version?

  By default, Windows 11 will be installed. But you can add the `VERSION` environment variable to your compose file, in order to specify an alternative Windows version to be downloaded:

  ```yaml
  environment:
    VERSION: "win11"
  ```

  Select from the values below:
  
  | **Value**  | **Description**  | **Source**  | **Transfer**  | **Size**  |
  |---|---|---|---|---|
  | `win11`   | Windows 11 Pro         | Microsoft    | Fast    | 6.4 GB    |
  | `win10`   | Windows 10 Pro         | Microsoft    | Fast    | 5.8 GB    |
  | `ltsc10`  | Windows 10 LTSC        | Microsoft    | Fast    | 4.6 GB    |
  | `win81`   | Windows 8.1 Pro        | Microsoft    | Fast    | 4.2 GB    |
  | `win7`    | Windows 7 SP1          | Bob Pony     | Medium  | 3.0 GB    |
  | `vista`   | Windows Vista SP2      | Bob Pony     | Medium  | 3.6 GB    |
  | `winxp`   | Windows XP SP3         | Bob Pony     | Medium  | 0.6 GB    |
  ||||||
  | `2022`    | Windows Server 2022    | Microsoft    | Fast    | 4.7 GB    |
  | `2019`    | Windows Server 2019    | Microsoft    | Fast    | 5.3 GB    |
  | `2016`    | Windows Server 2016    | Microsoft    | Fast    | 6.5 GB    |
  | `2012`    | Windows Server 2012 R2 | Microsoft    | Fast    | 4.3 GB    |
  | `2008`    | Windows Server 2008 R2 | Microsoft    | Fast    | 3.0 GB    |
  ||||||
  | `core11`  | Tiny 11 Core           | Archive.org  | Slow    | 2.1 GB    |
  | `tiny11`  | Tiny 11                | Archive.org  | Slow    | 3.8 GB    |
  | `tiny10`  | Tiny 10                | Archive.org  | Slow    | 3.6 GB    |

  To install ARM64 versions of Windows use [dockur/windows-arm](https://github.com/dockur/windows-arm/).

* ### How do I increase the amount of CPU or RAM?

  By default, 2 CPU cores and 4 GB of RAM are allocated to the container, as those are the minimum requirements of Windows 11.

  To increase this, add the following environment variables:

  ```yaml
  environment:
    RAM_SIZE: "8G"
    CPU_CORES: "4"
  ```

* ### How do I change the size of the disk?

  To expand the default size of 64 GB, add the `DISK_SIZE` setting to your compose file and set it to your preferred capacity:

  ```yaml
  environment:
    DISK_SIZE: "256G"
  ```
  
  This can also be used to resize the existing disk to a larger capacity without any data loss.
  
* ### How do I change the storage location?

  To change the storage location, include the following bind mount in your compose file:

  ```yaml
  volumes:
    - /var/win:/storage
  ```

  Replace the example path `/var/win` with the desired storage folder.

* ### How do I share files with the host?

  Open File Explorer and click on the Network section, you will see a computer called `host.lan`, double-click it and it will show a folder called `Data`.

  Inside this folder you can access any files that are placed in `/storage/shared` (see above) on the host.

* ### How do I install a custom image?

  In order to download a custom ISO image, start a clean container with the URL specified in the `VERSION` environment variable:
  
  ```yaml
  environment:
    VERSION: "https://example.com/win.iso"
  ```

  Alternatively, you can also rename a local file to `custom.iso` and place it in an empty `/storage` folder to skip the download.

* ### How do I perform a manual installation?

  It's best to use the automatic installation, as it optimizes various settings for use with this container.

  However, if you insist on performing the installation manually, start a clean container with the following environment variable:

  ```yaml
  environment:
    MANUAL: "Y"
  ```

  Then follow these steps:

  - Start the container and connect to [port 8006](http://localhost:8006) of the container in your web browser. After the download is finished, you will see the Windows installation screen.

  - Start the installation by clicking `Install now`. On the next screen, press 'OK' when prompted to `Load driver` and select the `VirtIO SCSI` driver from the list that matches your Windows version. So for Windows 11, select `D:\amd64\w11\vioscsi.inf` and click 'Next'.

  - Accept the license agreement and select your preferred Windows edition, like Home or Pro.

  - Choose `Custom: Install Windows only (advanced)`, and click `Load driver` on the next screen. Select 'Browse' and navigate to the `D:\NetKVM\w11\amd64` folder, and click 'OK'. Select the `VirtIO Ethernet Adapter` from the list and click 'Next'.

  - Select `Drive 0` and click 'Next'.

  - Wait until Windows finishes copying files and completes the installation.

  - Once you see the desktop, open File Explorer and navigate to the CD-ROM drive (E:). Double-click on `virtio-win-gt-x64.msi` and proceed to install the VirtIO drivers.

  Enjoy your brand new machine, and don't forget to star this repo!

* ### How do I assign an individual IP address to the container?

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

  Please note that this IP address won't be accessible from the Docker host due to the design of macvlan, which doesn't permit communication between the two. If this is a concern, you need to create a [second macvlan](https://blog.oddbit.com/post/2018-03-12-using-docker-macvlan-networks/#host-access) as a workaround.

* ### How can Windows acquire an IP address from my router?

  After configuring the container for macvlan (see above), it is possible for Windows to become part of your home network by requesting an IP from your router, just like a real PC.

  To enable this mode, add the following lines to your compose file:

  ```yaml
  environment:
    DHCP: "Y"
  device_cgroup_rules:
    - 'c *:* rwm'
  ```

  Please note that in this mode, the container and Windows will each have their own separate IPs. The container will keep the macvlan IP, and Windows will use the DHCP IP.
  
* ### How do I pass-through a disk?

  It is possible to pass-through disk devices directly by adding them to your compose file in this way:

  ```yaml
  environment:
    DEVICE: "/dev/sda"
    DEVICE2: "/dev/sdb"
  devices:
    - /dev/sda
    - /dev/sdb
  ```

  Use `DEVICE` if you want it to become your main drive, and use `DEVICE2` and higher to add them as secondary drives.

* ### How do I pass-through a USB device?

  To pass-through a USB device, first lookup its vendor and product id via the `lsusb` command, then add them to your compose file like this:

  ```yaml
  environment:
    ARGUMENTS: "-device usb-host,vendorid=0x1234,productid=0x1234"
  devices:
    - /dev/bus/usb
  ```
  
* ### How do I verify if my system supports KVM?

  To verify if your system supports KVM, run the following commands:

  ```bash
  sudo apt install cpu-checker
  sudo kvm-ok
  ```

  If you receive an error from `kvm-ok` indicating that KVM acceleration can't be used, check the virtualization settings in the BIOS.

* ### Is this project legal?

  Yes, this project contains only open-source code and does not distribute any copyrighted material. Neither does it try to circumvent any copyright protection measures. So under all applicable laws, this project would be considered legal.

## Stars
[![Stars](https://starchart.cc/dockur/windows.svg?variant=adaptive)](https://starchart.cc/dockur/windows)

## Disclaimer

The product names, logos, brands, and other trademarks referred to within this project are the property of their respective trademark holders. This project is not affiliated, sponsored, or endorsed by Microsoft Corporation.

[build_url]: https://github.com/dockur/windows/
[hub_url]: https://hub.docker.com/r/dockurr/windows/
[tag_url]: https://hub.docker.com/r/dockurr/windows/tags

[Build]: https://github.com/dockur/windows/actions/workflows/build.yml/badge.svg
[Size]: https://img.shields.io/docker/image-size/dockurr/windows/latest?color=066da5&label=size
[Pulls]: https://img.shields.io/docker/pulls/dockurr/windows.svg?style=flat&label=pulls&logo=docker
[Version]: https://img.shields.io/docker/v/dockurr/windows/latest?arch=amd64&sort=semver&color=066da5

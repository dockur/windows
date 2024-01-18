<h1 align="center">Windows<br />
<div align="center">
<img src="https://github.com/dockur/windows/raw/master/.github/logo.png" title="Logo" style="max-width:100%;" width="128" />
</div>
<div align="center">

[![Build]][build_url]
[![Version]][tag_url]
[![Size]][tag_url]
[![Pulls]][hub_url]

</div></h1>

Windows in a docker container.

## Features

 - Multi-platform
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
    restart: unless-stopped
```

Via `docker run`

```bash
docker run -it --rm -p 8006:8006 --device=/dev/kvm --cap-add NET_ADMIN dockurr/windows
```

## FAQ

  * ### How do I use it?

    Very simple! These are the steps:
    
    - Start the container and get some coffee.

    - Connect to port 8006 of the container in your web browser.

    - Sit back and relax while the magic happens, the whole installation will be performed fully automatic.

    - Once you see the desktop, your Windows installation is ready for use. Enjoy it, and don't forget to star this repo!

  * ### How do I select the Windows version?

    By default, Windows 11 will be installed. But you can add the `VERSION` environment variable to your compose file, in order to specify an alternative Windows version to download:

    ```yaml
    environment:
      VERSION: "win11"
    ```
    
    Select from the values below:
    
    - ```win11``` = Windows 11
    - ```win10``` = Windows 10
    - ```win81``` = Windows 8.1
    - ```win22``` = Windows Server 2022
    - ```win19``` = Windows Server 2019
    - ```win16``` = Windows Server 2016
    - ```tiny11``` = Tiny11 (Slow download)
    - ```tiny10``` = Tiny10 (Slow download)
 
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

  * ### How do I perform a manual installation?

    If you prefer to perform the installation manually in order to customize some options, such as selecting another edition, add the following environment variable:

    ```yaml
    environment:
      MANUAL: "Y"
    ```

    Then follow these steps:

    - Start the container and connect to port 8006 of the container in your web browser. After the download is finished, you will see the Windows installation screen.

    - Start the installation by clicking ```Install now```. On the next screen, press 'OK' when prompted to ```Load driver``` and select the ```VirtIO SCSI``` driver from the list that matches your Windows version. So for Windows 11, select ```D:\amd64\w11\vioscsi.inf``` and click 'Next'.

    - Accept the license agreement and select your preferred Windows edition, like Home or Pro.

    - Choose ```Custom: Install Windows only (advanced)```, and click ```Load driver``` on the next screen. Select 'Browse' and navigate  to the ```D:\NetKVM\w11\amd64``` folder, and click 'OK'. Select the ```VirtIO Ethernet Adapter``` from the list and click 'Next'.

    - Select 'Drive 0' and click 'Next'.

    - Wait until Windows finishes copying files and completes the installation.

    - Once you see the desktop, open File Explorer and navigate to the CD-ROM drive (E:). Double-click on ```virtio-win-gt-x64.msi``` and proceed to install the VirtIO drivers.

    - Now your Windows installation is ready for use. Enjoy it, and don't forget to star this repo!

  * ### How do I install an unsupported version?

    You can specify an URL in the `VERSION` environment variable, in order to download a custom ISO image:
    
    ```yaml
    environment:
      VERSION: "https://example.com/win.iso"
    ```
    
    During the installation you may need to add some drivers as described in [manual installation](https://github.com/dockur/windows/tree/master?tab=readme-ov-file#how-do-i-perform-a-manual-installation) above.

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

    Use ```DEVICE``` if you want it to become your main drive, and use ```DEVICE2``` and higher to add them as secondary drives.
    
  * ### How do I verify if my system supports KVM?

    To verify if your system supports KVM, run the following commands:

    ```bash
    sudo apt install cpu-checker
    sudo kvm-ok
    ```

    If you receive an error from `kvm-ok` indicating that KVM acceleration can't be used, check the virtualization settings in the BIOS.

  * ### Is this project legal?

    Yes, this project contains only open-source code and does not distribute any copyrighted material. Neither does it try to circumvent any copyright protection measures. So under all applicable laws, this project would be considered legal. 

## Disclaimer

The product names, logos, brands, and other trademarks referred to within this project are the property of their respective trademark holders. This project is not affiliated, sponsored, or endorsed by Microsoft Corporation.

[build_url]: https://github.com/dockur/windows/
[hub_url]: https://hub.docker.com/r/dockurr/windows/
[tag_url]: https://hub.docker.com/r/dockurr/windows/tags

[Build]: https://github.com/dockur/windows/actions/workflows/build.yml/badge.svg
[Size]: https://img.shields.io/docker/image-size/dockurr/windows/latest?color=066da5&label=size
[Pulls]: https://img.shields.io/docker/pulls/dockurr/windows.svg?style=flat&label=pulls&logo=docker
[Version]: https://img.shields.io/docker/v/dockurr/windows/latest?arch=amd64&sort=semver&color=066da5

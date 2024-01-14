<h1 align="center">Windows for Docker<br />
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
 - KVM acceleration

## Usage

Via `docker-compose.yml`

```yaml
version: "3"
services:
  windows:
    container_name: windows
    image: dockurr/windows:latest
    environment:
      VERSION: "win11x64"
    devices:
      - /dev/kvm
    cap_add:
      - NET_ADMIN
    ports:
      - 8006:8006
    stop_grace_period: 2m
    restart: unless-stopped
```

Via `docker run`

```bash
docker run -it --rm -e "VERSION=win11x64" -p 8006:8006 --device=/dev/kvm --cap-add NET_ADMIN dockurr/windows:latest
```

## FAQ

  * ### How do I specify the Windows version?

    You can modify the `VERSION` environment variable to specify the version you want:

    ```yaml
    environment:
      VERSION: "win11x64"
    ```
    
    Select from the values below:
    
    - ```win11x64``` (Windows 11)
    - ```win10x64``` (Windows 10)
    - ```win81x64``` (Windows 8.1)
    - ```win7x64-ultimate``` (Windows 7 )
    - ```win2016-eval``` (Windows Server 2016)
    - ```win2019-eval``` (Windows Server 2019)
    - ```win2022-eval``` (Windows Server 2022)
    
  * ### How do I see the screen?

    The container includes a web-based viewer, so you can visit [http://localhost:8006/](http://localhost:8006/) using any webbrowser to view the screen and interact with Windows via the keyboard/mouse.

    Alternatively it is also possible to connect to port 5900 using a VNC client like RealVNC or many others.
    
  * ### How do I increase the amount of CPU or RAM?

    By default, a single core and 4 GB of RAM are allocated to the container.

    To increase this, add the following environment variables:

    ```yaml
    environment:
      RAM_SIZE: "8G"
      CPU_CORES: "4"
    ```

  * ### How do I change the size of the data disk?

    To expand the default size of 64 GB, add the `DISK_SIZE` setting to your compose file and set it to your preferred capacity:

    ```yaml
    environment:
      DISK_SIZE: "128G"
    ```
    
    This can also be used to resize the existing disk to a larger capacity without any data loss.
    
  * ### How do I change the location of the data disk?

    To change the location of the data disk, include the following bind mount in your compose file:

    ```yaml
    volumes:
      - /var/win:/storage
    ```

    Replace the example path `/var/win` with the desired storage folder.

  * ### How do I verify if my system supports KVM?

    To verify if your system supports KVM, run the following commands:

    ```bash
    sudo apt install cpu-checker
    sudo kvm-ok
    ```

    If you receive an error from `kvm-ok` indicating that KVM acceleration can't be used, check the virtualization settings in the BIOS.

[build_url]: https://github.com/dockur/windows/
[hub_url]: https://hub.docker.com/r/dockurr/windows/
[tag_url]: https://hub.docker.com/r/dockurr/windows/tags

[Build]: https://github.com/dockur/windows/actions/workflows/build.yml/badge.svg
[Size]: https://img.shields.io/docker/image-size/dockurr/windows/latest?color=066da5&label=size
[Pulls]: https://img.shields.io/docker/pulls/dockurr/windows.svg?style=flat&label=pulls&logo=docker
[Version]: https://img.shields.io/docker/v/dockurr/windows/latest?arch=amd64&sort=semver&color=066da5

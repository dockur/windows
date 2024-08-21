Here's a rewritten version of the GitHub README with improved formatting and readability:

# Windows
================

<div align="center">
  <a href="https://github.com/dockur/windows">
    <img src="https://github.com/tj5miniop/windows-docker/raw/master/.github/logo.png" title="Logo" style="max-width:100%;" width="128" />
  </a>
</div>

**Windows inside a Docker container. A fork of Dockur's Windows project**

## Features

✨ **Multi-language**: Support for multiple languages
✨ **ISO downloader**: Download and install Windows ISOs
✨ **KVM acceleration**: Accelerate Windows installation with KVM
✨ **Web-based viewer**: Access Windows via web browser
✨ **Easy to configure**: Simplified configuration process

## Video

[![Youtube](https://img.youtube.com/vi/xhGYobuG508/0.jpg)](https://www.youtube.com/watch?v=xhGYobuG508)

## Usage

### Docker Compose

To use this project, create a `docker-compose.yml` file with the following contents:
```yaml
version: '3'
services:
  windows:
    container_name: windows
    image: dockurr/windows
    ports:
      - "8006:8006"
    volumes:
      - /var/win:/storage
    environment:
      - VERSION=win11
      - LANGUAGE=English
      - USERNAME=bill
      - PASSWORD=gates
```
Then, run `docker-compose up -d` to start the container.

## FAQ

### Why do Microsoft Store, Windows Activation, and some program installations not work?

Microsoft blocks access to the Microsoft Store and some of its services, including Windows Activation and Smart Screen, from Data Center IPs.

### How do I use it?

1. Start the container and connect to `http://localhost:8006` using your web browser.
2. Wait for the installation to complete.
3. Once you see the desktop, your Windows installation is ready for use.

### How do I select the Windows version?

By default, Windows 11 will be installed. To select a different version, add the `VERSION` environment variable to your `docker-compose.yml` file:
```yaml
environment:
  VERSION: "win10"
```
Available versions:

| Value | Version | Size |
| --- | --- | --- |
| `win11` | Windows 11 Pro | 6.4 GB |
| `win11e` | Windows 11 Enterprise | 5.8 GB |
| `win10` | Windows 10 Pro | 5.7 GB |
|... |... |... |

### How do I select the Windows language?

By default, the English version of Windows will be downloaded. To select a different language, add the `LANGUAGE` environment variable to your `docker-compose.yml` file:
```yaml
environment:
  LANGUAGE: "French"
```
Available languages:

🇦🇪 Arabic, 🇧🇬 Bulgarian, 🇨🇳 Chinese, 🇭🇷 Croatian, 🇨🇿 Czech, 🇩🇰 Danish, 🇳🇱 Dutch, 🇬🇧 English, 🇪🇪 Estionian, 🇫🇮 Finnish, 🇫🇷 French, 🇩🇪 German, 🇬🇷 Greek, 🇮🇱 Hebrew, 🇭🇺 Hungarian, 🇮🇹 Italian, 🇯🇵 Japanese, 🇰🇷 Korean, 🇱🇻 Latvian, 🇱🇹 Lithuanian, 🇳🇴 Norwegian, 🇵🇱 Polish, 🇵🇹 Portuguese, 🇷🇴 Romanian, 🇷🇺 Russian, 🇷🇸 Serbian, 🇸🇰 Slovak, 🇸🇮 Slovenian, 🇪🇸 Spanish, 🇸🇪 Swedish, 🇹🇭 Thai, 🇹🇷 Turkish, and 🇺🇦 Ukrainian.

### How do I connect using RDP?

The web-viewer is mainly meant to be used during installation. For a better experience, connect using any Microsoft Remote Desktop client to the IP of the container, using the username `Docker` and leaving the password empty.

### How do I assign an individual IP address to the container?

Create a macvlan network and assign an IP address to the container:
```bash
docker network create -d macvlan \
  --subnet=192.168.0.0/24 \
  --gateway=192.168.0.1 \
  --ip-range=192.168.0.100/28 \
  -o parent

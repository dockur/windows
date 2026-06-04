# winctl.sh User Guide

A comprehensive guide to managing Windows Docker containers with `winctl.sh`.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Commands Reference](#commands-reference)
- [Snapshots & Restore](#snapshots--restore)
- [Multi-Instance Support](#multi-instance-support)
- [ISO Cache](#iso-cache)
- [Configuration](#configuration)
- [ARM64 Setup](#arm64-setup)
- [Interactive Menus](#interactive-menus)
- [Common Scenarios](#common-scenarios)
- [Troubleshooting](#troubleshooting)
- [Tips & Tricks](#tips--tricks)

---

## Overview

`winctl.sh` is a management script for running Windows virtual machines inside Docker containers. It provides:

- **22 Windows versions** from Windows 2000 to Windows 11
- **Simple commands** to start, stop, and manage containers
- **Interactive menus** when you don't specify a version
- **Snapshot & restore** for backing up and restoring VM data
- **LAN IP detection** with remote access URLs shown automatically
- **Port conflict detection** before starting containers
- **Disk usage monitoring** with per-VM and snapshot breakdowns
- **Status caching** for fast performance
- **Resource profiles** optimized for modern and legacy systems
- **ARM64 auto-detection** with architecture-aware image selection and version filtering

### Supported Windows Versions

| Category | Versions |
|----------|----------|
| **Desktop** | win11, win11e, win11l, win10, win10e, win10l, win81, win81e, win7, win7e |
| **Legacy** | vista, winxp, win2k |
| **Server** | win2025, win2022, win2019, win2016, win2012, win2008, win2003 |
| **Tiny** | tiny11, tiny10 |

### ARM64 Support

The script auto-detects your CPU architecture. On ARM64 systems (e.g., Apple Silicon, Ampere), only the following versions are supported:

| Version | Name |
|---------|------|
| win11 | Windows 11 Pro |
| win11e | Windows 11 Enterprise |
| win11l | Windows 11 LTSC |
| win10 | Windows 10 Pro |
| win10e | Windows 10 Enterprise |
| win10l | Windows 10 LTSC |

To run on ARM64, set the Docker image in your `.env.modern` file:

```bash
WINDOWS_IMAGE=dockurr/windows-arm
```

The `winctl.sh list` command shows `[x86 only]` tags on ARM64 for unsupported versions, and `winctl.sh start` blocks unsupported versions with a clear error message.

### Port Mappings

Each version has unique ports to avoid conflicts:

| Version | Web UI | RDP | Version | Web UI | RDP |
|---------|--------|-----|---------|--------|-----|
| win11 | 8011 | 3311 | win2025 | 8025 | 3325 |
| win10 | 8010 | 3310 | win2022 | 8022 | 3322 |
| win81 | 8008 | 3308 | win2019 | 8019 | 3319 |
| win7 | 8007 | 3307 | win2016 | 8016 | 3316 |
| vista | 8006 | 3306 | win2012 | 8112 | 3212 |
| winxp | 8005 | 3305 | win2008 | 8108 | 3208 |
| win2k | 8000 | 3300 | win2003 | 8003 | 3303 |
| tiny11 | 8111 | 3111 | tiny10 | 8110 | 3110 |

---

## Prerequisites

### Required

1. **Docker** - Container runtime
2. **Docker Compose** - Container orchestration (plugin or standalone)
3. **KVM** - Hardware virtualization for near-native performance

### Check Prerequisites

Run the built-in check:

```bash
./winctl.sh check
```

Example output:
```
Prerequisites Check
────────────────────────────────────────────────────────────
[OK] Docker is available
[OK] Docker Compose plugin is available
[OK] KVM is available
[OK] TUN device is available
[OK] Memory OK: 16GB available (8GB needed)
[OK] Disk space OK: 500GB available (128GB needed)

[OK] All critical prerequisites passed!
  Architecture: amd64
  LAN IP:       192.168.1.100
```

On ARM64, the output also shows:
```
  Architecture: arm64
  ARM64 image:  dockurr/windows-arm
  Supported:    win11 win11e win11l win10 win10e win10l
  LAN IP:       192.168.1.100
```

### Fix Common Issues

**KVM not accessible:**
```bash
sudo usermod -aG kvm $USER
newgrp kvm  # or log out and back in
```

**Docker not running:**
```bash
sudo systemctl start docker
```

---

## Quick Start

### 1. Start a Windows VM

```bash
# Start Windows 11
./winctl.sh start win11

# Or use interactive menu
./winctl.sh start
```

### 2. Access the VM

After starting, you'll see connection details:

```
Connection Details:
  → Web Viewer: http://localhost:8011
  → RDP:        localhost:3311
  → LAN Web:    http://192.168.1.100:8011
  → LAN RDP:    192.168.1.100:3311
```

- **Web Viewer**: Open in browser for quick access
- **RDP**: Use any RDP client for better performance
- **LAN URLs**: Shown automatically when a LAN IP is detected — use these to access from other devices on your network

### 3. Check Status

```bash
./winctl.sh status
```

### 4. Stop the VM

```bash
./winctl.sh stop win11
```

---

## Commands Reference

### start

Start one or more containers.

```bash
# Start single version
./winctl.sh start win11

# Start multiple versions
./winctl.sh start win11 win10 winxp

# Interactive menu (no version specified)
./winctl.sh start
```

**What it does:**
1. Checks prerequisites (Docker, KVM)
2. Detects architecture and blocks unsupported versions on ARM64
3. Verifies ports are not already in use
4. Creates data directory if missing
5. Checks available resources
6. Starts the container
7. Shows connection details (including LAN URLs)

---

### stop

Stop containers with a 2-minute grace period for clean shutdown.

```bash
# Stop single version
./winctl.sh stop win11

# Stop multiple versions
./winctl.sh stop win11 win10

# Stop all running containers
./winctl.sh stop all

# Interactive menu
./winctl.sh stop
```

**Note:** You'll be asked to confirm before stopping.

---

### restart

Restart containers.

```bash
./winctl.sh restart win11
```

---

### status

Show status of containers.

```bash
# All containers
./winctl.sh status

# Specific versions
./winctl.sh status win11 win10
```

Example output:
```
  VERSION      NAME                       STATUS     WEB      RDP
  ──────────────────────────────────────────────────────────────────
  win11        Windows 11 Pro             running    8011     3311
  win10        Windows 10 Pro             stopped    8010     3310
  winxp        Windows XP Professional    not created 8005    3305

  LAN IP: 192.168.1.100 — use http://192.168.1.100:<web-port> for remote access
```

---

### logs

View container logs.

```bash
# View logs
./winctl.sh logs win11

# Follow logs in real-time
./winctl.sh logs win11 -f
```

Press `Ctrl+C` to stop following logs.

---

### shell

Open an interactive bash shell inside the container.

```bash
./winctl.sh shell win11
```

Useful for debugging or accessing container internals.

---

### stats

Show real-time resource usage (CPU, memory, network).

```bash
# All running containers
./winctl.sh stats

# Specific containers
./winctl.sh stats win11 win10
```

Press `Ctrl+C` to exit.

---

### build

Build the Docker image locally from source.

```bash
./winctl.sh build
```

---

### rebuild

Destroy and recreate containers. Data in `/storage` is preserved.

```bash
./winctl.sh rebuild win11
```

**Warning:** You must type `yes` to confirm (destructive operation).

---

### list

List available Windows versions.

```bash
# All versions
./winctl.sh list

# By category
./winctl.sh list desktop
./winctl.sh list legacy
./winctl.sh list server
./winctl.sh list tiny
```

Example output:
```
Available Windows Versions
────────────────────────────────────────────────────────────

  DESKTOP
  ──────────────────────────────────────────────────
    win11      Windows 11 Pro               (8G RAM)
    win10      Windows 10 Pro               (8G RAM) [running]
    win7       Windows 7 Ultimate           (2G RAM)
```

On ARM64, unsupported versions show an `[x86 only]` tag:
```
    win7       Windows 7 Ultimate           (2G RAM) [x86 only]
```

---

### inspect

Show detailed information about a version.

```bash
./winctl.sh inspect win11
```

Example output:
```
Container Details: win11
────────────────────────────────────────────────────────────

  Version:      win11
  Name:         Windows 11 Pro
  Category:     desktop
  Status:       running
  Web Port:     8011
  RDP Port:     3311
  Resources:    modern
  Compose:      compose/desktop/win11.yml
  Web URL:      http://localhost:8011
  RDP:          localhost:3311
  LAN Web:      http://192.168.1.100:8011
  LAN RDP:      192.168.1.100:3311
```

---

### monitor

Real-time dashboard showing all containers.

```bash
# Default 5-second refresh
./winctl.sh monitor

# Custom refresh interval (10 seconds)
./winctl.sh monitor 10
```

Press `Ctrl+C` to exit.

---

### check

Run prerequisites check.

```bash
./winctl.sh check
```

---

### refresh

Force refresh the status cache.

```bash
./winctl.sh refresh
```

The cache is stored at `~/.cache/winctl/status.json` and auto-refreshes when:
- Cache is older than 7 days
- Cached data becomes stale
- After start/stop/restart/rebuild operations

---

### open

Open the web viewer in your default browser.

```bash
./winctl.sh open win11
```

If the container is not running, you'll be prompted to start it first.

---

### pull

Pull the latest Docker image.

```bash
./winctl.sh pull
```

Automatically selects `dockurr/windows` or `dockurr/windows-arm` based on detected architecture. Shows whether the image was updated or already up to date.

---

### disk

Show disk usage per VM data directory.

```bash
# All VMs
./winctl.sh disk

# Specific versions
./winctl.sh disk win11 win10
```

Example output:
```
Disk Usage
────────────────────────────────────────────────────────────

  VERSION      SIZE         STATUS
  ────────────────────────────────────
  win11        45.2G        running
  win10        32.1G        stopped
  ────────────────────────────────────
  Total:       77.3G

  Snapshots:   12.5G (2 snapshots)
    win11      12.5G (2 snapshots)
```

---

### snapshot

Back up a VM's data directory.

```bash
# Auto-named with timestamp
./winctl.sh snapshot win11

# Custom name
./winctl.sh snapshot win11 before-update
```

The snapshot is saved to `snapshots/<version>/<name>/`. The container is stopped during the copy and restarted automatically.

---

### restore

Restore a VM's data directory from a snapshot.

```bash
# Interactive snapshot selection
./winctl.sh restore win11

# Restore specific snapshot
./winctl.sh restore win11 before-update
```

If no snapshot name is given, a list of available snapshots is shown for selection. Requires typing `yes` to confirm (destructive: replaces current data).

---

### clean

Remove stopped containers and optionally purge their data directories.

```bash
# Remove stopped containers only
./winctl.sh clean

# Also delete data directories for stopped containers
./winctl.sh clean --data
```

Requires typing `yes` to confirm. Shows freed disk space on completion. Stopped instances are automatically unregistered and their compose files removed.

---

## Snapshots & Restore

`winctl.sh` supports snapshot and restore for VM data directories, stored under `snapshots/`.

### Creating a Snapshot

```bash
# Snapshot with auto-generated timestamp name
./winctl.sh snapshot win11

# Snapshot with custom name
./winctl.sh snapshot win11 before-update
```

The container is stopped during the copy to ensure data consistency, then restarted automatically.

### Listing Snapshots

```bash
# Via disk command
./winctl.sh disk

# Or browse directly
ls snapshots/win11/
```

### Restoring a Snapshot

```bash
# Interactive selection
./winctl.sh restore win11

# Direct restore
./winctl.sh restore win11 before-update
```

**Warning:** Restore replaces all current data for the version. The container is stopped during restore and restarted automatically.

### Snapshot Directory Structure

```
snapshots/
├── win11/
│   ├── 20260129-143022/    # Auto-named
│   └── before-update/      # Custom-named
└── win10/
    └── 20260128-091500/
```

---

## Multi-Instance Support

Run multiple instances of the same Windows version with auto-managed ports and a JSON registry.

### Creating an Instance

```bash
# Create winxp-1 with auto-allocated ports
./winctl.sh start winxp --new

# Create winxp-lab with a custom name
./winctl.sh start winxp --new lab

# Create winxp-lab and clone data from base winxp
./winctl.sh start winxp --new lab --clone
```

The `--new` flag:
1. Allocates unique ports (web: 9000+, RDP: 4000+)
2. Generates a compose file in `instances/<name>.yml`
3. Creates a data directory at `data/<name>/`
4. Registers the instance in `instances/registry.json`
5. Starts the container

### Managing Instances

Instances work transparently with all existing commands:

```bash
# Stop an instance
./winctl.sh stop winxp-lab

# Restart an instance
./winctl.sh restart winxp-lab

# View logs
./winctl.sh logs winxp-lab -f

# Open shell
./winctl.sh shell winxp-lab

# Inspect details
./winctl.sh inspect winxp-lab

# Open web viewer
./winctl.sh open winxp-lab

# Snapshot and restore
./winctl.sh snapshot winxp-lab before-update
./winctl.sh restore winxp-lab before-update
```

### Listing Instances

```bash
# List all instances
./winctl.sh instances

# Filter by base version
./winctl.sh instances winxp
```

Example output:
```
Instances
────────────────────────────────────────────────────────────

  INSTANCE             BASE       STATUS     WEB      RDP      CREATED
  ──────────────────────────────────────────────────────────────────────────────
  winxp-1              winxp      running    9000     4000     2026-01-30
  winxp-lab            winxp      stopped    9001     4001     2026-01-30
```

### Destroying an Instance

```bash
./winctl.sh destroy winxp-lab
```

This will:
1. Stop and remove the container
2. Delete the compose file
3. Prompt to delete the data directory
4. Remove the instance from the registry

### How It Works

- **Port allocation**: Web ports start at 9000, RDP at 4000, auto-incrementing to avoid conflicts
- **Naming**: Instances are named `<version>-<suffix>` (e.g., `winxp-1`, `winxp-lab`)
- **Registry**: All instances are tracked in `instances/registry.json`
- **Compose files**: Generated in `instances/<name>.yml` with relative paths to env files and data
- **No collisions**: Base versions never contain hyphens; instances always do

### Instance Directory Structure

```
instances/
├── registry.json          # Instance registry
├── winxp-1.yml           # Generated compose file
└── winxp-lab.yml         # Generated compose file

data/
├── winxp/                # Base version data
├── winxp-1/              # Instance data
└── winxp-lab/            # Instance data (cloned from base)
```

---

## ISO Cache

Windows ISOs are large (3-6 GB) and re-downloaded every time a new container is created for the same version. The ISO cache saves downloaded ISOs so new instances can skip the download.

### How It Works

1. Download the original ISO: `./winctl.sh cache download winxp`
2. Create new instances — cached ISOs are auto-restored: `./winctl.sh start winxp --new`

When creating a new instance with `--new`, winctl checks `cache/<version>/` for ISOs and copies them into the new instance's data directory before starting the container. The container finds the ISO locally and processes it (extracts, injects drivers, builds answer file) without needing to re-download.

### Downloading an ISO

```bash
# Download original ISOs to the cache
./winctl.sh cache download winxp
./winctl.sh cache download win11
```

This uses the container's download logic to fetch the original, unprocessed ISO directly to the cache. This is the recommended way to populate the cache.

### Saving from an Existing VM

```bash
# Cache unprocessed ISOs from a VM's data directory
./winctl.sh cache save winxp
```

> **Note:** After a VM completes its first boot, the container rebuilds the ISO with injected drivers. These rebuilt ISOs are automatically skipped by `cache save` because they cannot be re-processed. Use `cache download` instead.

### Listing Cached ISOs

```bash
./winctl.sh cache list
```

Shows all cached ISOs grouped by version with file sizes and a total.

### Removing Cached ISOs

```bash
# Remove cached ISOs for a specific version
./winctl.sh cache rm winxp

# Remove all cached ISOs
./winctl.sh cache flush
```

Both commands require typing `yes` to confirm.

### Auto-Restore

When creating a new instance with `--new` (without `--clone`), winctl automatically checks the cache:

```bash
# If cache/winxp/ has an ISO, it is copied to data/winxp-1/ before start
./winctl.sh start winxp --new
```

The original ISO is copied as-is. The container processes it locally (extract, inject drivers, build answer file) without needing to re-download. This is skipped when using `--clone`, since cloning copies all data from the base version including any ISOs.

### Auto-Cache on Stop

To automatically cache ISOs whenever a container is stopped, add `AUTO_CACHE=Y` to your `.env` file:

```bash
# .env
AUTO_CACHE=Y
```

When enabled, `winctl.sh stop` will silently cache any unprocessed ISOs found in the stopped container's data directory. Rebuilt ISOs (from the container's install pipeline) and already-cached ISOs are skipped.

### Cache Directory Structure

```
cache/
├── winxp/
│   └── winxpx86.iso
├── win11/
│   └── win11x64.iso
└── win10/
    └── win10x64.iso
```

> **Note:** The cache must contain original (unprocessed) ISOs. Use `cache download` to populate it. Rebuilt ISOs from `data/` directories are skipped by `cache save` because the container cannot re-extract them.

---

## Configuration

### Environment Files

Two pre-configured environment files control VM resources:

| File | RAM | CPU | Disk | Used By |
|------|-----|-----|------|---------|
| `.env.modern` | 8G | 4 | 128G | Win 10/11, Server 2016+ |
| `.env.legacy` | 2G | 2 | 32G | Win 7/8, Vista, XP, 2000, Server 2003-2012, Tiny |

### Customizing Resources

Edit `.env.modern` or `.env.legacy`:

```bash
# Resources
RAM_SIZE=8G
CPU_CORES=4
DISK_SIZE=128G

# Credentials
USERNAME=docker
PASSWORD=admin

# Display
WIDTH=1280
HEIGHT=720

# Other
LANGUAGE=en
REGION=en-US
KEYBOARD=en-US
DHCP=N
SAMBA=Y
RESTART_POLICY=on-failure
DEBUG=N
```

### Available Settings

| Setting | Description | Default |
|---------|-------------|---------|
| `RAM_SIZE` | Memory allocation | 8G/2G |
| `CPU_CORES` | CPU cores | 4/2 |
| `DISK_SIZE` | Virtual disk size | 128G/32G |
| `USERNAME` | Windows username | docker |
| `PASSWORD` | Windows password | admin |
| `LANGUAGE` | Installation language | en |
| `REGION` | Region setting | en-US |
| `KEYBOARD` | Keyboard layout | en-US |
| `WIDTH` | Display width | 1280 |
| `HEIGHT` | Display height | 720 |
| `DHCP` | Use DHCP networking | N |
| `SAMBA` | Enable file sharing | Y |
| `RESTART_POLICY` | Container restart policy | on-failure |
| `DEBUG` | Debug mode | N |
| `WINDOWS_IMAGE` | Docker image | dockurr/windows |
| `AUTO_CACHE` | Auto-cache ISOs on stop (in `.env`) | N |

### Restart Policy Options

| Value | Description |
|-------|-------------|
| `no` | Never restart automatically |
| `on-failure` | Restart only if container exits with error (default) |
| `always` | Always restart regardless of exit status |
| `unless-stopped` | Always restart unless manually stopped |

**Note:** With `on-failure` (default), shutting down Windows from inside will stop the container. With `unless-stopped` or `always`, the container will restart after Windows shutdown.

---

## ARM64 Setup

If you're running on an ARM64 system (e.g., Apple Silicon Mac, Ampere server), follow these steps:

### 1. Set the Docker image

Edit `.env.modern` (and `.env.legacy` if needed):

```bash
WINDOWS_IMAGE=dockurr/windows-arm
```

### 2. Check your setup

```bash
./winctl.sh check
```

Verify the output shows `Architecture: arm64` and lists supported versions.

### 3. Start a supported version

Only Windows 10 and 11 variants work on ARM64:

```bash
./winctl.sh start win11    # Works
./winctl.sh start win10    # Works
./winctl.sh start winxp    # Blocked with error
```

### 4. View compatible versions

```bash
./winctl.sh list
```

Unsupported versions are tagged `[x86 only]` on ARM64 systems.

### Supported ARM64 Versions

| Version | Name |
|---------|------|
| win11 | Windows 11 Pro |
| win11e | Windows 11 Enterprise |
| win11l | Windows 11 LTSC |
| win10 | Windows 10 Pro |
| win10e | Windows 10 Enterprise |
| win10l | Windows 10 LTSC |

All other versions (Win 8.1, 7, Vista, XP, 2000, all Server editions, Tiny) are x86 only.

---

## Interactive Menus

When you don't specify a version, `winctl.sh` shows interactive menus.

### Category Selection

```
Select Category
────────────────────────────────────────────────────────────

  1) Desktop (Win 11, 10, 8.1, 7)
  2) Legacy (Vista, XP, 2000)
  3) Server (2025, 2022, 2019, 2016, 2012, 2008, 2003)
  4) Tiny (Tiny11, Tiny10)
  5) All versions
  6) Select individual versions

  Select [1-6]:
```

### Version Selection

```
Select Version(s)
────────────────────────────────────────────────────────────

   1) win11      Windows 11 Pro               [running]
   2) win11e     Windows 11 Enterprise
   3) win11l     Windows 11 LTSC
   4) win10      Windows 10 Pro               [stopped]

   a) Select all
   q) Cancel

  Select (numbers separated by spaces, or 'a' for all):
```

- Enter numbers separated by spaces: `1 3 4`
- Enter `a` for all versions
- Enter `q` to cancel

---

## Common Scenarios

### Scenario 1: Set Up a Development Environment

```bash
# Start Windows 10 for development
./winctl.sh start win10

# Access via web browser
# Open http://localhost:8010

# Or connect via RDP for better performance
# Use RDP client to connect to localhost:3310
```

### Scenario 2: Test Software on Multiple Windows Versions

```bash
# Start multiple versions
./winctl.sh start win11 win10 win7

# Check they're all running
./winctl.sh status

# Access each via their ports:
# - Win11: http://localhost:8011
# - Win10: http://localhost:8010
# - Win7:  http://localhost:8007

# Stop all when done
./winctl.sh stop win11 win10 win7
```

### Scenario 3: Run Legacy Software on Windows XP

```bash
# Start Windows XP
./winctl.sh start winxp

# Access via http://localhost:8005
# Login: docker / admin

# Transfer files via the Shared folder on desktop
```

### Scenario 4: Monitor Resource Usage

```bash
# See real-time stats for all running VMs
./winctl.sh stats

# Or use the dashboard
./winctl.sh monitor
```

### Scenario 5: Increase Resources for a VM

1. Stop the container:
   ```bash
   ./winctl.sh stop win11
   ```

2. Edit `.env.modern`:
   ```bash
   RAM_SIZE=16G
   CPU_CORES=8
   ```

3. Start again:
   ```bash
   ./winctl.sh start win11
   ```

### Scenario 6: Running on ARM64

```bash
# Set the ARM64 image (one-time setup)
# Edit .env.modern and set: WINDOWS_IMAGE=dockurr/windows-arm

# Check architecture is detected
./winctl.sh check

# List versions to see what's available
./winctl.sh list

# Start a supported version
./winctl.sh start win11
```

### Scenario 7: Fresh Start (Reset VM)

```bash
# This destroys the container but keeps data
./winctl.sh rebuild win11

# For a complete reset, also delete the data:
rm -rf data/win11/*
./winctl.sh start win11
```

### Scenario 8: Snapshot Before a Risky Change

```bash
# Create a snapshot before installing something
./winctl.sh snapshot win11 before-update

# Do your work...
# If something goes wrong, restore:
./winctl.sh restore win11 before-update
```

### Scenario 9: Clean Up Disk Space

```bash
# Check disk usage
./winctl.sh disk

# Remove stopped containers
./winctl.sh clean

# Remove stopped containers AND their data
./winctl.sh clean --data
```

### Scenario 10: Quick Access from Browser

```bash
# Open web viewer directly in your browser
./winctl.sh open win11

# Or pull latest image before starting
./winctl.sh pull
./winctl.sh start win11
```

### Scenario 11: Access from Another Device on LAN

```bash
# Check your LAN IP
./winctl.sh check

# Start a VM — LAN URLs are shown automatically
./winctl.sh start win11
# → LAN Web: http://192.168.1.100:8011
# → LAN RDP: 192.168.1.100:3311

# Use the LAN URL from any device on the same network
```

---

## Troubleshooting

### Container Won't Start

**Check prerequisites:**
```bash
./winctl.sh check
```

**Check logs:**
```bash
./winctl.sh logs win11
```

**Common issues:**
- KVM not accessible → Add user to kvm group
- Port already in use → `start` auto-detects port conflicts; stop the conflicting service or container
- Not enough disk space → Run `./winctl.sh disk` to check usage, or free up space

### Slow Performance

- Ensure KVM is working (hardware virtualization)
- Increase RAM_SIZE and CPU_CORES in env file
- Use RDP instead of web viewer for better performance

### Can't Connect via RDP

1. Wait for Windows to fully boot (check web viewer first)
2. RDP might be disabled in Windows → Enable via web viewer
3. Check firewall settings in Windows

### Web Viewer Not Loading

```bash
# Check if container is running
./winctl.sh status win11

# Check container logs
./winctl.sh logs win11

# Restart the container
./winctl.sh restart win11
```

### Cache Issues

Force refresh the status cache:
```bash
./winctl.sh refresh
```

---

## Tips & Tricks

### 1. Use Aliases

Add to your `~/.bashrc`:
```bash
alias wctl='./winctl.sh'
alias wstart='./winctl.sh start'
alias wstop='./winctl.sh stop'
alias wstatus='./winctl.sh status'
```

### 2. Quick Access Bookmarks

Bookmark your commonly used VMs:
- Windows 11: http://localhost:8011
- Windows 10: http://localhost:8010

### 3. File Sharing

Each VM has a "Shared" folder on the desktop that maps to the host. Use this to transfer files.

### 4. Snapshots

Use the built-in snapshot and restore commands:
```bash
./winctl.sh snapshot win11 my-backup
./winctl.sh restore win11 my-backup
```

Snapshots are stored in `snapshots/<version>/<name>/`.

### 5. Running Multiple VMs

Check your available resources before starting multiple VMs:
```bash
# Each modern VM needs 8GB RAM
# Each legacy VM needs 2GB RAM

# Example: Running win11 + win10 + winxp = 8+8+2 = 18GB RAM needed
```

### 6. Headless Operation

For servers, you can start VMs and access only via RDP:
```bash
./winctl.sh start win2022
# Connect via RDP to localhost:3322
```

---

## File Structure

```
.
├── winctl.sh              # Management script
├── .env.modern            # Modern systems config (8G RAM)
├── .env.legacy            # Legacy systems config (2G RAM)
├── compose/
│   ├── desktop/           # Win 11, 10, 8.1, 7
│   ├── legacy/            # Vista, XP, 2000
│   ├── server/            # Server 2003-2025
│   └── tiny/              # Tiny10, Tiny11
├── instances/
│   ├── registry.json      # Instance registry
│   ├── winxp-1.yml        # Generated compose files
│   └── winxp-lab.yml
├── data/
│   ├── win11/             # Win11 VM storage
│   ├── win10/             # Win10 VM storage
│   ├── winxp-1/           # Instance VM storage
│   ├── winxp-lab/         # Instance VM storage
│   └── ...                # Other VM storage
├── snapshots/
│   ├── win11/             # Win11 snapshots
│   │   ├── 20260129-143022/
│   │   └── before-update/
│   └── ...                # Other version snapshots
├── cache/
│   ├── winxp/             # Cached winxp ISOs
│   ├── win11/             # Cached win11 ISOs
│   └── ...                # Other cached ISOs
└── ~/.cache/winctl/
    └── status.json        # Status cache
```

---

## Getting Help

```bash
# Show commands + interactive topic menu
./winctl.sh help

# Jump to a specific topic
./winctl.sh help commands       # Full command reference
./winctl.sh help instances      # Multi-instance support
./winctl.sh help cache          # ISO cache management
./winctl.sh help examples       # Usage examples
./winctl.sh help config         # Environment settings
./winctl.sh help all            # Show everything

# Check system requirements
./winctl.sh check

# List all versions
./winctl.sh list
```

When run interactively, `help` shows a numbered menu to browse topics. When piped or run in a script, it prints the command summary only.

For issues, visit: https://github.com/dockur/windows/issues

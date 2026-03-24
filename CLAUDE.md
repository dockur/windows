# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is **dockur/windows** - a Docker container that runs Windows inside QEMU with KVM acceleration. It provides automatic Windows installation with ISO downloading, VirtIO driver injection, and unattended setup via answer files.

## Architecture

### Entry Point & Script Chain

The container starts via `/run/entry.sh` which sources scripts in sequence:
1. `start.sh` → `utils.sh` → `reset.sh` → `server.sh` → `define.sh` → `mido.sh` → `install.sh`
2. Then: `disk.sh` → `display.sh` → `network.sh` → `samba.sh` → `boot.sh` → `proc.sh` → `power.sh` → `memory.sh` → `config.sh` → `finish.sh`
3. Finally launches `qemu-system-x86_64` with constructed arguments

### Key Components

- **src/define.sh**: Version parsing, language mapping, and Windows edition detection. Maps user-friendly version strings (e.g., "11", "10l", "2022") to internal identifiers
- **src/mido.sh**: Microsoft ISO downloader - scrapes Microsoft's download portal to get direct ISO links
- **src/install.sh**: ISO extraction, image detection, driver injection, answer file customization, and ISO rebuilding using `wimlib-imagex` and `genisoimage`
- **src/samba.sh**: Configures Samba for host-guest file sharing (appears as "Shared" folder on desktop)
- **assets/*.xml**: Unattended answer files for different Windows versions

### Build System

- Base image: `qemux/qemu` (QEMU with web-based VNC viewer)
- VirtIO drivers downloaded at build time from `qemus/virtiso-whql`
- Multi-arch support: amd64 native, arm64 via `dockur/windows-arm`

### GitHub Codespaces

The `.devcontainer/` directory provides GitHub Codespaces configurations — separate from the `compose/` files used by `winctl.sh`.

- `devcontainer.json` (root): Default config, launches Windows 11 Pro
- Numbered subfolders (010–210): Alternative configs for each Windows version
- `codespaces.yml`: Shared compose file using `ghcr.io/dockur/windows`
- Runs a single VM at a time on ports 8006/3389 (no unique port mapping needed)
- Do not sync ports with `compose/` files — they serve different use cases

## Commands

### Linting & Validation

```bash
# ShellCheck for all shell scripts
shellcheck -x --source-path=src src/*.sh

# Dockerfile linting
hadolint Dockerfile

# XML validation (answer files)
# Uses action-pack/valid-xml in CI
```

### Building

```bash
# Build Docker image locally
docker build -t windows .

# Build with version argument
docker build --build-arg VERSION_ARG=1.0 -t windows .
```

### Testing Locally

```bash
# Run container (requires KVM)
docker run -it --rm -e "VERSION=11" -p 8006:8006 --device=/dev/kvm --device=/dev/net/tun --cap-add NET_ADMIN -v "${PWD}/storage:/storage" windows

# Access web viewer at http://localhost:8006
```

## CI/CD

- **check.yml**: Runs on PRs - ShellCheck, Hadolint, XML/JSON/YAML validation
- **build.yml**: Manual trigger - builds multi-arch image, pushes to Docker Hub and GHCR
- **test.yml**: Runs check.yml on PRs

ShellCheck exclusions (from CI): SC1091, SC2001, SC2002, SC2034, SC2064, SC2153, SC2317, SC2028

## Key Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| VERSION | "11" | Windows version (11, 10, 10l, 2022, etc.) or ISO URL |
| LANGUAGE | "en" | Installation language |
| USERNAME | "Docker" | Windows username |
| PASSWORD | "admin" | Windows password |
| DISK_SIZE | "64G" | Virtual disk size |
| RAM_SIZE | "4G" | RAM allocation |
| CPU_CORES | "2" | CPU cores |
| MANUAL | "" | Set to "Y" for manual installation |

## Git Remotes & Pull Requests

### Remotes

| Remote | Repository | Purpose |
|--------|-----------|---------|
| `origin` | `michelabboud/windows` | Personal repo, push directly to `master` |
| `fork` | `michelabboud/windows-1` | Fork of `dockur/windows`, used for PRs to upstream |

### Creating a PR to upstream

1. Push changes to a feature branch on the fork:
   ```bash
   git push fork master:<branch-name>
   ```
2. Create the PR:
   ```bash
   gh pr create --repo dockur/windows --head michelabboud:<branch-name> --base master --title "..." --body "..."
   ```
3. Create a matching issue:
   ```bash
   gh issue create --repo dockur/windows --title "..." --body "..."
   ```

### Updating an existing PR

Push new commits to the same branch on the fork:
```bash
git push fork master:<branch-name>
```
The PR updates automatically. Update the PR description if needed:
```bash
gh pr edit <pr-number> --repo dockur/windows --body "..."
```

### Updating the GitHub release

```bash
gh release edit <tag> --notes "..."
```

### Active PRs

| PR | Branch | Issue | Description |
|----|--------|-------|-------------|
| [#1637](https://github.com/dockur/windows/pull/1637) | `feat/winctl-management-script` | [#1639](https://github.com/dockur/windows/issues/1639) | winctl.sh management script with ARM64 support |
| [#1638](https://github.com/dockur/windows/pull/1638) | `fix/reviewdog-fail-level` | [#1640](https://github.com/dockur/windows/issues/1640) | Replace deprecated fail_on_error with fail_level in reviewdog actions |

## Adding New Windows Versions

1. Add version aliases in `src/define.sh` `parseVersion()` function
2. Create answer file in `assets/` named `{version}.xml`
3. Add driver folder mapping in `src/install.sh` `addDriver()` function

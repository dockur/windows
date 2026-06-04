# Changelog

All notable changes to this project will be documented in this file.

## [1.0.0] - 2026-01-30

### Added
- **winctl.sh**: Management script for Windows Docker containers
  - 20+ commands: start, stop, restart, status, logs, shell, stats, build, rebuild, list, inspect, monitor, check, refresh, open, pull, disk, snapshot, restore, clean, destroy, instances, cache, help
  - Interactive menus for version selection
  - Prerequisites checking (Docker, Compose, KVM, TUN, memory, disk)
  - Color-coded output with professional table formatting
  - Safety confirmations for destructive operations
  - Support for all 22 Windows versions across 4 categories
  - JSON status cache (`~/.cache/winctl/status.json`) with auto-refresh
- **Multi-instance support**: run multiple instances of the same version
  - `start <version> --new` creates auto-numbered instances with allocated ports
  - `start <version> --new <name>` creates named instances
  - `--clone` copies data from the base version
  - JSON registry (`instances/registry.json`) tracks all instances
  - `instances` lists all registered instances; `destroy` removes them
- **ISO cache**: skip re-downloading ISOs for new instances
  - `cache download <version>` downloads original ISOs using the container's download logic
  - `cache save <version>` caches from data directory (skips rebuilt ISOs)
  - Auto-restore on `start --new` copies cached ISOs before container starts
  - `cache list` / `cache rm` / `cache flush` for cache management
  - Rebuilt ISOs (genisoimage output) detected and skipped automatically
- **Auto-cache on stop**: `AUTO_CACHE=Y` in `.env` caches unprocessed ISOs when stopping
- **Snapshot & restore**: back up and restore VM data directories
- **Topic-based help system**: `help [commands|instances|cache|examples|config|all]`
  - Interactive numbered menu in terminal mode
  - Auto-disabled in pipes, CI, and batch environments
  - Aligned columns using `_help_row()` with ANSI-safe formatting
- **ARM64 auto-detection**: blocks unsupported versions, shows `[x86 only]` tags
- **LAN IP detection** with remote access URLs shown on start
- **Port conflict detection** before starting containers
- **Disk usage monitoring** with per-VM and snapshot breakdowns
- Multi-version compose structure with organized folders (`compose/`)
- Environment file configuration (`.env` / `.env.example`)
- Two resource profiles: modern (8G RAM, 4 CPU) and legacy (2G RAM, 2 CPU)
- Per-version data folders under `data/`
- Pre-configured compose files for all Windows versions:
  - Desktop: Win 11, 10, 8.1, 7 (with Enterprise variants)
  - Legacy: Vista, XP, 2000
  - Server: 2003, 2008, 2012, 2016, 2019, 2022, 2025
  - Tiny: Tiny11, Tiny10
- Unique port mappings for each version (no conflicts)
- CLAUDE.md for Claude Code guidance
- WINCTL_GUIDE.md comprehensive user guide

### Changed
- Default storage location changed from `./windows` to `./data/`
- Compose files now use `env_file` for centralized configuration
- Restart policy changed from `always` to `on-failure`
- `clean --data` now unregisters instances and removes compose files

### Resource Profiles

| Profile | RAM | CPU | Disk | Used By |
|---------|-----|-----|------|---------|
| Modern | 8G | 4 | 128G | Win 10/11, Server 2016+ |
| Legacy | 2G | 2 | 32G | Win 7/8, Vista, XP, 2000, Server 2003-2012, Tiny |

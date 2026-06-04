#!/usr/bin/env bash
#
# winctl.sh - Windows Docker Container Management Script
# Manage Windows Docker containers with ease
#
# Usage: ./winctl.sh <command> [options]
#
set -Eeuo pipefail

# ==============================================================================
# METADATA
# ==============================================================================

readonly SCRIPT_VERSION="1.0.0"
readonly SCRIPT_NAME="winctl"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

# Cache settings
readonly CACHE_DIR="${HOME}/.cache/winctl"
readonly CACHE_FILE="${CACHE_DIR}/status.json"
readonly CACHE_MAX_AGE=$((7 * 24 * 60 * 60))  # 7 days in seconds

# ==============================================================================
# COLORS & TERMINAL DETECTION
# ==============================================================================

if [[ -t 1 ]] && [[ "${TERM:-}" != "dumb" ]]; then
    readonly RED=$'\033[0;31m'
    readonly GREEN=$'\033[0;32m'
    readonly YELLOW=$'\033[0;33m'
    readonly BLUE=$'\033[0;34m'
    readonly MAGENTA=$'\033[0;35m'
    readonly CYAN=$'\033[0;36m'
    readonly WHITE=$'\033[0;37m'
    readonly BOLD=$'\033[1m'
    readonly DIM=$'\033[2m'
    readonly RESET=$'\033[0m'
else
    readonly RED=''
    readonly GREEN=''
    readonly YELLOW=''
    readonly BLUE=''
    readonly MAGENTA=''
    readonly CYAN=''
    readonly WHITE=''
    readonly BOLD=''
    readonly DIM=''
    readonly RESET=''
fi

# ==============================================================================
# VERSION DATA
# ==============================================================================

# All supported versions
readonly ALL_VERSIONS=(
    win11 win11e win11l win10 win10e win10l
    win81 win81e win7 win7e
    vista winxp win2k
    win2025 win2022 win2019 win2016 win2012 win2008 win2003
    tiny11 tiny10
)

# Versions supported on ARM64
readonly ARM_VERSIONS=(
    win11 win11e win11l win10 win10e win10l
)

# Port mappings (web)
declare -A VERSION_PORTS_WEB=(
    ["win11"]=8011 ["win11e"]=8012 ["win11l"]=8013
    ["win10"]=8010 ["win10e"]=8014 ["win10l"]=8015
    ["win81"]=8008 ["win81e"]=8081
    ["win7"]=8007 ["win7e"]=8071
    ["vista"]=8006 ["winxp"]=8005 ["win2k"]=8000
    ["win2025"]=8025 ["win2022"]=8022 ["win2019"]=8019 ["win2016"]=8016
    ["win2012"]=8112 ["win2008"]=8108 ["win2003"]=8003
    ["tiny11"]=8111 ["tiny10"]=8110
)

# Port mappings (RDP)
declare -A VERSION_PORTS_RDP=(
    ["win11"]=3311 ["win11e"]=3312 ["win11l"]=3313
    ["win10"]=3310 ["win10e"]=3314 ["win10l"]=3315
    ["win81"]=3308 ["win81e"]=3381
    ["win7"]=3307 ["win7e"]=3371
    ["vista"]=3306 ["winxp"]=3305 ["win2k"]=3300
    ["win2025"]=3325 ["win2022"]=3322 ["win2019"]=3319 ["win2016"]=3316
    ["win2012"]=3212 ["win2008"]=3208 ["win2003"]=3303
    ["tiny11"]=3111 ["tiny10"]=3110
)

# Categories
declare -A VERSION_CATEGORIES=(
    ["win11"]="desktop" ["win11e"]="desktop" ["win11l"]="desktop"
    ["win10"]="desktop" ["win10e"]="desktop" ["win10l"]="desktop"
    ["win81"]="desktop" ["win81e"]="desktop"
    ["win7"]="desktop" ["win7e"]="desktop"
    ["vista"]="legacy" ["winxp"]="legacy" ["win2k"]="legacy"
    ["win2025"]="server" ["win2022"]="server" ["win2019"]="server" ["win2016"]="server"
    ["win2012"]="server" ["win2008"]="server" ["win2003"]="server"
    ["tiny11"]="tiny" ["tiny10"]="tiny"
)

# Compose files
declare -A VERSION_COMPOSE_FILES=(
    ["win11"]="compose/desktop/win11.yml" ["win11e"]="compose/desktop/win11.yml" ["win11l"]="compose/desktop/win11.yml"
    ["win10"]="compose/desktop/win10.yml" ["win10e"]="compose/desktop/win10.yml" ["win10l"]="compose/desktop/win10.yml"
    ["win81"]="compose/desktop/win8.yml" ["win81e"]="compose/desktop/win8.yml"
    ["win7"]="compose/desktop/win7.yml" ["win7e"]="compose/desktop/win7.yml"
    ["vista"]="compose/legacy/vista.yml" ["winxp"]="compose/legacy/winxp.yml" ["win2k"]="compose/legacy/win2k.yml"
    ["win2025"]="compose/server/win2025.yml" ["win2022"]="compose/server/win2022.yml"
    ["win2019"]="compose/server/win2019.yml" ["win2016"]="compose/server/win2016.yml"
    ["win2012"]="compose/server/win2012.yml" ["win2008"]="compose/server/win2008.yml" ["win2003"]="compose/server/win2003.yml"
    ["tiny11"]="compose/tiny/tiny11.yml" ["tiny10"]="compose/tiny/tiny10.yml"
)

# Display names
declare -A VERSION_DISPLAY_NAMES=(
    ["win11"]="Windows 11 Pro" ["win11e"]="Windows 11 Enterprise" ["win11l"]="Windows 11 LTSC"
    ["win10"]="Windows 10 Pro" ["win10e"]="Windows 10 Enterprise" ["win10l"]="Windows 10 LTSC"
    ["win81"]="Windows 8.1 Pro" ["win81e"]="Windows 8.1 Enterprise"
    ["win7"]="Windows 7 Ultimate" ["win7e"]="Windows 7 Enterprise"
    ["vista"]="Windows Vista Ultimate" ["winxp"]="Windows XP Professional" ["win2k"]="Windows 2000 Professional"
    ["win2025"]="Windows Server 2025" ["win2022"]="Windows Server 2022"
    ["win2019"]="Windows Server 2019" ["win2016"]="Windows Server 2016"
    ["win2012"]="Windows Server 2012 R2" ["win2008"]="Windows Server 2008 R2" ["win2003"]="Windows Server 2003"
    ["tiny11"]="Tiny11" ["tiny10"]="Tiny10"
)

# Resource type (modern = high resources, legacy = low resources)
declare -A VERSION_RESOURCE_TYPE=(
    ["win11"]="modern" ["win11e"]="modern" ["win11l"]="modern"
    ["win10"]="modern" ["win10e"]="modern" ["win10l"]="modern"
    ["win81"]="legacy" ["win81e"]="legacy"
    ["win7"]="legacy" ["win7e"]="legacy"
    ["vista"]="legacy" ["winxp"]="legacy" ["win2k"]="legacy"
    ["win2025"]="modern" ["win2022"]="modern" ["win2019"]="modern" ["win2016"]="modern"
    ["win2012"]="legacy" ["win2008"]="legacy" ["win2003"]="legacy"
    ["tiny11"]="legacy" ["tiny10"]="legacy"
)

# VERSION env values (maps base version to compose VERSION environment variable)
declare -A VERSION_ENV_VALUES=(
    ["win11"]="11"     ["win11e"]="11e"   ["win11l"]="11l"
    ["win10"]="10"     ["win10e"]="10e"   ["win10l"]="10l"
    ["win81"]="8"      ["win81e"]="8e"
    ["win7"]="7u"      ["win7e"]="7e"
    ["vista"]="vu"     ["winxp"]="xp"     ["win2k"]="2k"
    ["win2025"]="2025" ["win2022"]="2022" ["win2019"]="2019" ["win2016"]="2016"
    ["win2012"]="2012" ["win2008"]="2008" ["win2003"]="2003"
    ["tiny11"]="tiny11" ["tiny10"]="tiny10"
)

# VERSION env files (maps base version to env file path)
declare -A VERSION_ENV_FILES=(
    ["win11"]=".env.modern"   ["win11e"]=".env.modern"  ["win11l"]=".env.modern"
    ["win10"]=".env.modern"   ["win10e"]=".env.modern"  ["win10l"]=".env.modern"
    ["win81"]=".env.legacy"   ["win81e"]=".env.legacy"
    ["win7"]=".env.legacy"    ["win7e"]=".env.legacy"
    ["vista"]=".env.legacy"   ["winxp"]=".env.legacy"   ["win2k"]=".env.legacy"
    ["win2025"]=".env.modern" ["win2022"]=".env.modern"
    ["win2019"]=".env.modern" ["win2016"]=".env.modern"
    ["win2012"]=".env.legacy" ["win2008"]=".env.legacy" ["win2003"]=".env.legacy"
    ["tiny11"]=".env.legacy"  ["tiny10"]=".env.legacy"
)

# Instance constants
readonly INSTANCE_DIR="${SCRIPT_DIR}/instances"

# ISO cache directory
readonly ISO_CACHE_DIR="${SCRIPT_DIR}/cache"
readonly INSTANCE_REGISTRY="${INSTANCE_DIR}/registry.json"
readonly INSTANCE_WEB_PORT_BASE=9000
readonly INSTANCE_RDP_PORT_BASE=4000
readonly INSTANCE_PORT_RANGE=999

# Resource requirements
readonly MODERN_RAM_GB=8
readonly MODERN_DISK_GB=128
readonly LEGACY_RAM_GB=2
readonly LEGACY_DISK_GB=32

# Winctl settings (loaded from .env)
AUTO_CACHE="N"
if [[ -f "$SCRIPT_DIR/.env" ]]; then
    _val=$(grep -E '^AUTO_CACHE=' "$SCRIPT_DIR/.env" 2>/dev/null | tail -1 | cut -d'=' -f2- || true)
    [[ -n "$_val" ]] && AUTO_CACHE="$_val"
    unset _val
fi

# ==============================================================================
# OUTPUT HELPERS
# ==============================================================================

info() {
    printf '%s\n' "${BLUE}[INFO]${RESET} $*"
}

success() {
    printf '%s\n' "${GREEN}[OK]${RESET} $*"
}

warn() {
    printf '%s\n' "${YELLOW}[WARN]${RESET} $*"
}

error() {
    printf '%s\n' "${RED}[ERROR]${RESET} $*" >&2
}

die() {
    error "$@"
    exit 1
}

header() {
    printf '\n'
    printf '%s\n' "${BOLD}${CYAN}$*${RESET}"
    printf '%s\n' "${DIM}$(printf '─%.0s' {1..60})${RESET}"
}

# Print a formatted table row
table_row() {
    local version="$1"
    local name="$2"
    local status="$3"
    local web="$4"
    local rdp="$5"

    local status_color
    case "$status" in
        running) status_color="${GREEN}" ;;
        stopped|exited) status_color="${RED}" ;;
        *) status_color="${YELLOW}" ;;
    esac

    printf "  %s%-12s%s %-26s %s%-10s%s %-8s %-8s\n" \
        "${BOLD}" "$version" "${RESET}" "$name" "$status_color" "$status" "${RESET}" "$web" "$rdp"
}

table_header() {
    printf '\n'
    printf "  %s%-12s %-26s %-10s %-8s %-8s%s\n" \
        "${BOLD}${DIM}" "VERSION" "NAME" "STATUS" "WEB" "RDP" "${RESET}"
    printf '%s\n' "  ${DIM}$(printf '─%.0s' {1..66})${RESET}"
}

# ==============================================================================
# ARCHITECTURE DETECTION
# ==============================================================================

DETECTED_ARCH=""

detect_arch() {
    if [[ -n "$DETECTED_ARCH" ]]; then
        return
    fi
    local machine
    machine=$(uname -m)
    case "$machine" in
        x86_64|amd64)   DETECTED_ARCH="amd64" ;;
        aarch64|arm64)  DETECTED_ARCH="arm64" ;;
        *)              DETECTED_ARCH="amd64" ;;
    esac
}

is_arm_supported() {
    local version="$1"
    local v
    for v in "${ARM_VERSIONS[@]}"; do
        if [[ "$v" == "$version" ]]; then
            return 0
        fi
    done
    return 1
}

# ==============================================================================
# LAN IP DETECTION
# ==============================================================================

LAN_IP=""

detect_lan_ip() {
    if [[ -n "$LAN_IP" ]]; then return; fi
    # Try hostname -I first (Linux), then ipconfig getifaddr (macOS)
    LAN_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
    if [[ -z "$LAN_IP" ]]; then
        LAN_IP=$(ipconfig getifaddr en0 2>/dev/null || true)
    fi
}

# ==============================================================================
# PREREQUISITES CHECKS
# ==============================================================================

check_docker() {
    if ! command -v docker &>/dev/null; then
        error "Docker is not installed"
        printf '%s\n' "  Install Docker: https://docs.docker.com/get-docker/"
        return 1
    fi

    if ! docker info &>/dev/null; then
        error "Docker daemon is not running"
        printf '%s\n' "  Start Docker: sudo systemctl start docker"
        return 1
    fi

    success "Docker is available"
    return 0
}

check_compose() {
    if docker compose version &>/dev/null; then
        success "Docker Compose plugin is available"
        return 0
    elif command -v docker-compose &>/dev/null; then
        success "Docker Compose standalone is available"
        return 0
    else
        error "Docker Compose is not installed"
        printf '%s\n' "  Install: https://docs.docker.com/compose/install/"
        return 1
    fi
}

check_kvm() {
    if [[ ! -e /dev/kvm ]]; then
        error "KVM device not found (/dev/kvm)"
        printf '%s\n' "  Enable virtualization in BIOS or check nested virtualization"
        return 1
    fi

    if [[ ! -r /dev/kvm ]] || [[ ! -w /dev/kvm ]]; then
        error "KVM device not accessible"
        printf '%s\n' "  Fix: sudo usermod -aG kvm \$USER && newgrp kvm"
        return 1
    fi

    success "KVM is available"
    return 0
}

check_tun() {
    if [[ ! -e /dev/net/tun ]]; then
        warn "TUN device not found (/dev/net/tun) - networking may be limited"
        return 1
    fi

    success "TUN device is available"
    return 0
}

check_memory() {
    local required_gb="${1:-$MODERN_RAM_GB}"
    local available_kb
    available_kb=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
    local available_gb=$((available_kb / 1024 / 1024))

    if ((available_gb < required_gb)); then
        warn "Low memory: ${available_gb}GB available (${required_gb}GB recommended)"
        return 1
    fi

    success "Memory OK: ${available_gb}GB available (${required_gb}GB needed)"
    return 0
}

check_disk() {
    local required_gb="${1:-$MODERN_DISK_GB}"
    local available_kb
    available_kb=$(df "$SCRIPT_DIR" | tail -1 | awk '{print $4}')
    local available_gb=$((available_kb / 1024 / 1024))

    if ((available_gb < required_gb)); then
        warn "Low disk space: ${available_gb}GB available (${required_gb}GB recommended)"
        return 1
    fi

    success "Disk space OK: ${available_gb}GB available (${required_gb}GB needed)"
    return 0
}

run_all_checks() {
    header "Prerequisites Check"

    local failed=0

    check_docker || ((failed++))
    check_compose || ((failed++))
    check_kvm || ((failed++))
    check_tun || true  # Warning only
    check_memory || true  # Warning only
    check_disk || true  # Warning only

    printf '\n'
    if ((failed > 0)); then
        error "Some critical checks failed. Please fix the issues above."
        return 1
    else
        success "All critical prerequisites passed!"
        return 0
    fi
}

# ==============================================================================
# DOCKER HELPERS
# ==============================================================================

# Get the compose command (plugin vs standalone)
compose_cmd() {
    if docker compose version &>/dev/null; then
        echo "docker compose"
    else
        echo "docker-compose"
    fi
}

# ==============================================================================
# STATUS CACHE (JSON file-based with auto-refresh)
# ==============================================================================

# In-memory cache (loaded from JSON)
declare -A _STATUS_CACHE=()
_STATUS_CACHE_VALID=false
_STATUS_CACHE_TIMESTAMP=0

# Ensure cache directory exists
ensure_cache_dir() {
    [[ -d "$CACHE_DIR" ]] || mkdir -p "$CACHE_DIR"
}

# Get cache file age in seconds (returns large number if file doesn't exist)
get_cache_age() {
    if [[ -f "$CACHE_FILE" ]]; then
        local file_time current_time
        file_time=$(stat -c %Y "$CACHE_FILE" 2>/dev/null || stat -f %m "$CACHE_FILE" 2>/dev/null || echo 0)
        current_time=$(date +%s)
        echo $((current_time - file_time))
    else
        echo 999999999
    fi
}

# Check if cache needs refresh (age > max age)
cache_needs_refresh() {
    local age
    age=$(get_cache_age)
    ((age > CACHE_MAX_AGE))
}

# Write status cache to JSON file
write_cache_file() {
    ensure_cache_dir
    local timestamp
    timestamp=$(date +%s)

    # Build JSON manually (no jq dependency)
    {
        echo "{"
        echo "  \"timestamp\": $timestamp,"
        echo "  \"containers\": {"
        local first=true
        for name in "${!_STATUS_CACHE[@]}"; do
            if [[ "$first" == "true" ]]; then
                first=false
            else
                echo ","
            fi
            printf '    "%s": "%s"' "$name" "${_STATUS_CACHE[$name]}"
        done
        echo ""
        echo "  }"
        echo "}"
    } > "$CACHE_FILE"
}

# Read status cache from JSON file
read_cache_file() {
    if [[ ! -f "$CACHE_FILE" ]]; then
        return 1
    fi

    _STATUS_CACHE=()
    _STATUS_CACHE_TIMESTAMP=0

    # Parse JSON manually (no jq dependency)
    local in_containers=false
    while IFS= read -r line; do
        # Extract timestamp
        if [[ "$line" =~ \"timestamp\":[[:space:]]*([0-9]+) ]]; then
            _STATUS_CACHE_TIMESTAMP="${BASH_REMATCH[1]}"
        fi
        # Track when we're in containers section
        if [[ "$line" =~ \"containers\" ]]; then
            in_containers=true
            continue
        fi
        # Parse container entries
        if [[ "$in_containers" == "true" && "$line" =~ \"([^\"]+)\":[[:space:]]*\"([^\"]+)\" ]]; then
            local name="${BASH_REMATCH[1]}"
            local state="${BASH_REMATCH[2]}"
            _STATUS_CACHE["$name"]="$state"
        fi
    done < "$CACHE_FILE"

    return 0
}

# Validate cache by spot-checking a running container still exists
validate_cache() {
    # If cache shows a container as running, verify it still exists
    for name in "${!_STATUS_CACHE[@]}"; do
        if [[ "${_STATUS_CACHE[$name]}" == "running" ]]; then
            # Quick check if this container exists
            if ! docker ps -q --filter "name=^${name}$" 2>/dev/null | grep -q .; then
                return 1  # Cache is stale
            fi
            return 0  # Found a valid running container
        fi
    done
    return 0  # No running containers to validate
}

# Refresh the status cache from Docker and save to file
refresh_status_cache() {
    local force="${1:-false}"

    # Try to load from file cache first (unless forced)
    if [[ "$force" != "true" && "$_STATUS_CACHE_VALID" != "true" ]]; then
        if read_cache_file; then
            # Check if cache is still valid (not too old)
            if ! cache_needs_refresh; then
                # Validate cache data
                if validate_cache; then
                    _STATUS_CACHE_VALID=true
                    return 0
                fi
            fi
        fi
    fi

    # Fetch fresh data from Docker
    _STATUS_CACHE=()
    local line
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            local name state
            name="${line%%:*}"
            state="${line#*:}"
            _STATUS_CACHE["$name"]="$state"
        fi
    done < <(docker ps -a --format '{{.Names}}:{{.State}}' 2>/dev/null)
    _STATUS_CACHE_VALID=true

    # Save to file
    write_cache_file
}

# Force refresh the cache (called after start/stop/restart operations)
invalidate_cache() {
    _STATUS_CACHE_VALID=false
    refresh_status_cache true
}

# Check if a container is running
is_running() {
    local version="$1"
    if [[ "$_STATUS_CACHE_VALID" == "true" ]]; then
        [[ "${_STATUS_CACHE[$version]:-}" == "running" ]]
    else
        docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${version}$"
    fi
}

# Check if a container exists (running or stopped)
container_exists() {
    local version="$1"
    if [[ "$_STATUS_CACHE_VALID" == "true" ]]; then
        [[ -n "${_STATUS_CACHE[$version]:-}" ]]
    else
        docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${version}$"
    fi
}

# Get container status
get_status() {
    local version="$1"
    if [[ "$_STATUS_CACHE_VALID" == "true" ]]; then
        echo "${_STATUS_CACHE[$version]:-not created}"
    else
        local status
        status=$(docker ps -a --filter "name=^${version}$" --format '{{.State}}' 2>/dev/null)
        echo "${status:-not created}"
    fi
}

# ==============================================================================
# INSTANCE REGISTRY (JSON file-based)
# ==============================================================================

# In-memory registry: _REGISTRY_INSTANCES["name"]="base|suffix|web_port|rdp_port|created"
declare -A _REGISTRY_INSTANCES=()
_REGISTRY_LOADED=false

# Ensure instance directory exists
ensure_instance_dir() {
    [[ -d "$INSTANCE_DIR" ]] || mkdir -p "$INSTANCE_DIR"
}

# Load registry from JSON file into memory
load_registry() {
    if [[ "$_REGISTRY_LOADED" == "true" ]]; then
        return 0
    fi

    _REGISTRY_INSTANCES=()

    if [[ ! -f "$INSTANCE_REGISTRY" ]]; then
        _REGISTRY_LOADED=true
        return 0
    fi

    local current_name="" current_base="" current_suffix=""
    local current_web="" current_rdp="" current_created=""
    local in_instances=false in_entry=false

    while IFS= read -r line; do
        if [[ "$line" =~ \"instances\" ]]; then
            in_instances=true
            continue
        fi
        if [[ "$in_instances" == "true" && "$in_entry" == "false" ]]; then
            # Look for entry key like "winxp-lab": {
            if [[ "$line" =~ \"([^\"]+)\":[[:space:]]*\{ ]]; then
                current_name="${BASH_REMATCH[1]}"
                in_entry=true
                current_base="" current_suffix="" current_web="" current_rdp="" current_created=""
                continue
            fi
        fi
        if [[ "$in_entry" == "true" ]]; then
            if [[ "$line" =~ \"base\":[[:space:]]*\"([^\"]+)\" ]]; then
                current_base="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ \"suffix\":[[:space:]]*\"([^\"]+)\" ]]; then
                current_suffix="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ \"web_port\":[[:space:]]*([0-9]+) ]]; then
                current_web="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ \"rdp_port\":[[:space:]]*([0-9]+) ]]; then
                current_rdp="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ \"created\":[[:space:]]*\"([^\"]+)\" ]]; then
                current_created="${BASH_REMATCH[1]}"
            fi
            # End of entry
            if [[ "$line" =~ \} ]]; then
                if [[ -n "$current_name" ]]; then
                    _REGISTRY_INSTANCES["$current_name"]="${current_base}|${current_suffix}|${current_web}|${current_rdp}|${current_created}"
                fi
                in_entry=false
                current_name=""
            fi
        fi
    done < "$INSTANCE_REGISTRY"

    _REGISTRY_LOADED=true
}

# Write in-memory registry to JSON file (atomic: write to .tmp then mv)
write_registry() {
    ensure_instance_dir

    local tmp_file="${INSTANCE_REGISTRY}.tmp"
    {
        echo "{"
        echo "  \"version\": 1,"
        echo "  \"instances\": {"
        local first=true
        for name in "${!_REGISTRY_INSTANCES[@]}"; do
            local entry="${_REGISTRY_INSTANCES[$name]}"
            local base suffix web_port rdp_port created
            IFS='|' read -r base suffix web_port rdp_port created <<< "$entry"

            if [[ "$first" == "true" ]]; then
                first=false
            else
                echo ","
            fi
            printf '    "%s": {\n' "$name"
            printf '      "base": "%s",\n' "$base"
            printf '      "suffix": "%s",\n' "$suffix"
            printf '      "web_port": %s,\n' "$web_port"
            printf '      "rdp_port": %s,\n' "$rdp_port"
            printf '      "created": "%s"\n' "$created"
            printf '    }'
        done
        echo ""
        echo "  }"
        echo "}"
    } > "$tmp_file"
    mv "$tmp_file" "$INSTANCE_REGISTRY"
}

# Register a new instance
register_instance() {
    local name="$1" base="$2" suffix="$3" web_port="$4" rdp_port="$5"
    local created
    created=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    _REGISTRY_INSTANCES["$name"]="${base}|${suffix}|${web_port}|${rdp_port}|${created}"
    write_registry
}

# Unregister an instance
unregister_instance() {
    local name="$1"
    unset '_REGISTRY_INSTANCES['"$name"']'
    write_registry
}

# Get a field from a registry entry
# Fields: 1=base, 2=suffix, 3=web_port, 4=rdp_port, 5=created
registry_get_field() {
    local name="$1" field="$2"
    local entry="${_REGISTRY_INSTANCES[$name]:-}"
    if [[ -z "$entry" ]]; then
        return 1
    fi
    local idx
    case "$field" in
        base)     idx=1 ;;
        suffix)   idx=2 ;;
        web_port) idx=3 ;;
        rdp_port) idx=4 ;;
        created)  idx=5 ;;
        *) return 1 ;;
    esac
    echo "$entry" | cut -d'|' -f"$idx"
}

# Check if a name is a registered instance
is_instance() {
    local name="$1"
    load_registry
    [[ -n "${_REGISTRY_INSTANCES[$name]:-}" ]]
}

# ==============================================================================
# DOCKER HELPERS (continued)
# ==============================================================================

# Get compose file path for version or instance
get_compose_file() {
    local target="$1"

    # Check if it's an instance first
    if is_instance "$target"; then
        echo "$INSTANCE_DIR/${target}.yml"
        return 0
    fi

    local file="${VERSION_COMPOSE_FILES[$target]:-}"
    if [[ -z "$file" ]]; then
        die "Unknown version or instance: $target"
    fi
    echo "$SCRIPT_DIR/$file"
}

# ==============================================================================
# RESOLUTION LAYER
# ==============================================================================

# Resolved target globals (set by resolve_target)
RESOLVED_TYPE=""         # "base" or "instance"
RESOLVED_NAME=""         # e.g. "win11" or "winxp-lab"
RESOLVED_BASE=""         # base version, e.g. "winxp"
RESOLVED_WEB_PORT=""
RESOLVED_RDP_PORT=""
RESOLVED_DISPLAY_NAME=""
RESOLVED_COMPOSE=""

# Resolve a target name to its type, ports, display name, and compose file
resolve_target() {
    local target="$1"

    # Reset globals
    RESOLVED_TYPE="" RESOLVED_NAME="" RESOLVED_BASE=""
    RESOLVED_WEB_PORT="" RESOLVED_RDP_PORT=""
    RESOLVED_DISPLAY_NAME="" RESOLVED_COMPOSE=""

    # Check if it's a base version
    if [[ -n "${VERSION_COMPOSE_FILES[$target]:-}" ]]; then
        RESOLVED_TYPE="base"
        RESOLVED_NAME="$target"
        RESOLVED_BASE="$target"
        RESOLVED_WEB_PORT="${VERSION_PORTS_WEB[$target]}"
        RESOLVED_RDP_PORT="${VERSION_PORTS_RDP[$target]}"
        RESOLVED_DISPLAY_NAME="${VERSION_DISPLAY_NAMES[$target]}"
        RESOLVED_COMPOSE=$(get_compose_file "$target")
        return 0
    fi

    # Check if it's a registered instance
    load_registry
    if [[ -n "${_REGISTRY_INSTANCES[$target]:-}" ]]; then
        local base
        base=$(registry_get_field "$target" "base")
        RESOLVED_TYPE="instance"
        RESOLVED_NAME="$target"
        RESOLVED_BASE="$base"
        RESOLVED_WEB_PORT=$(registry_get_field "$target" "web_port")
        RESOLVED_RDP_PORT=$(registry_get_field "$target" "rdp_port")
        RESOLVED_DISPLAY_NAME="${VERSION_DISPLAY_NAMES[$base]} ($target)"
        RESOLVED_COMPOSE="$INSTANCE_DIR/${target}.yml"
        return 0
    fi

    return 1
}

# Validate a target (base version or instance)
validate_target() {
    local target="$1"
    if ! resolve_target "$target"; then
        error "Unknown version or instance: $target"
        echo "  Run '${SCRIPT_NAME} list' to see available versions"
        echo "  Run '${SCRIPT_NAME} instances' to see instances"
        return 1
    fi
    return 0
}

# Validate base version only (backward compat wrapper)
validate_version() {
    local version="$1"
    if [[ -z "${VERSION_COMPOSE_FILES[$version]:-}" ]]; then
        error "Unknown version: $version"
        echo "  Run '${SCRIPT_NAME} list' to see available versions"
        return 1
    fi
    return 0
}

# Run compose command for a version or instance
run_compose() {
    local target="$1"
    shift
    local compose_file
    compose_file=$(get_compose_file "$target")

    cd "$SCRIPT_DIR"
    if is_instance "$target"; then
        $(compose_cmd) -p "$target" -f "$compose_file" "$@"
    else
        $(compose_cmd) -f "$compose_file" "$@"
    fi
}

# ==============================================================================
# INTERACTIVE MENU
# ==============================================================================

# Get versions by category
get_versions_by_category() {
    local category="$1"
    local versions=()
    for v in "${ALL_VERSIONS[@]}"; do
        if [[ "${VERSION_CATEGORIES[$v]}" == "$category" ]]; then
            versions+=("$v")
        fi
    done
    echo "${versions[*]}"
}

# Show category menu (prompts to stderr, result to stdout)
select_category() {
    {
        header "Select Category"
        printf '\n'
        printf '  %b) Desktop (Win 11, 10, 8.1, 7)\n' "${BOLD}1${RESET}"
        printf '  %b) Legacy (Vista, XP, 2000)\n' "${BOLD}2${RESET}"
        printf '  %b) Server (2025, 2022, 2019, 2016, 2012, 2008, 2003)\n' "${BOLD}3${RESET}"
        printf '  %b) Tiny (Tiny11, Tiny10)\n' "${BOLD}4${RESET}"
        printf '  %b) All versions\n' "${BOLD}5${RESET}"
        printf '  %b) Select individual versions\n' "${BOLD}6${RESET}"
        printf '\n'
        printf '  Select [1-6]: '
    } >&2

    local choice
    read -r choice </dev/tty

    case "$choice" in
        1) echo "desktop" ;;
        2) echo "legacy" ;;
        3) echo "server" ;;
        4) echo "tiny" ;;
        5) echo "all" ;;
        6) echo "individual" ;;
        *) echo "" ;;
    esac
}

# Show version selection menu (prompts to stderr, result to stdout)
select_versions() {
    local category="$1"
    local versions=()

    if [[ "$category" == "all" ]]; then
        versions=("${ALL_VERSIONS[@]}")
    elif [[ "$category" == "individual" ]]; then
        versions=("${ALL_VERSIONS[@]}")
    else
        IFS=' ' read -ra versions <<< "$(get_versions_by_category "$category")"
    fi

    if [[ ${#versions[@]} -eq 0 ]]; then
        error "No versions found for category: $category"
        return 1
    fi

    # Fetch all container statuses in one call
    refresh_status_cache

    {
        header "Select Version(s)"
        printf '\n'

        local i=1
        for v in "${versions[@]}"; do
            local status=""
            if is_running "$v"; then
                status="${GREEN}[running]${RESET}"
            elif container_exists "$v"; then
                status="${YELLOW}[stopped]${RESET}"
            fi
            printf '  %b) %-10s %-28s %b\n' "${BOLD}$(printf '%2d' "$i")${RESET}" "$v" "${VERSION_DISPLAY_NAMES[$v]}" "$status"
            ((i++))
        done

        printf '\n'
        printf '  %b) Select all\n' "${BOLD} a${RESET}"
        printf '  %b) Cancel\n' "${BOLD} q${RESET}"
        printf '\n'
        printf '  Select (numbers separated by spaces, or '\''a'\'' for all): '
    } >&2

    local input
    read -r input </dev/tty

    if [[ "$input" == "q" ]] || [[ -z "$input" ]]; then
        return 1
    fi

    if [[ "$input" == "a" ]]; then
        echo "${versions[*]}"
        return 0
    fi

    local selected=()
    for num in $input; do
        if [[ "$num" =~ ^[0-9]+$ ]] && ((num >= 1 && num <= ${#versions[@]})); then
            selected+=("${versions[$((num-1))]}")
        fi
    done

    if [[ ${#selected[@]} -eq 0 ]]; then
        return 1
    fi

    echo "${selected[*]}"
}

# Interactive version selection
interactive_select() {
    local category
    category=$(select_category)

    if [[ -z "$category" ]]; then
        error "Invalid selection"
        return 1
    fi

    local selected
    if ! selected=$(select_versions "$category"); then
        error "No versions selected"
        return 1
    fi

    echo "$selected"
}

# ==============================================================================
# COMMANDS
# ==============================================================================

cmd_start() {
    local args=("$@")
    local versions=()
    local new_flag=false
    local clone_flag=false
    local instance_name=""

    # Parse flags
    local i=0
    while ((i < ${#args[@]})); do
        case "${args[$i]}" in
            --new)
                new_flag=true
                # Next non-flag arg is optional instance name
                if ((i + 1 < ${#args[@]})) && [[ "${args[$((i+1))]}" != --* ]]; then
                    ((i++)) || true
                    instance_name="${args[$i]}"
                fi
                ;;
            --clone)
                clone_flag=true
                ;;
            *)
                versions+=("${args[$i]}")
                ;;
        esac
        ((i++)) || true
    done

    # Route to cmd_new if --new flag is set
    if [[ "$new_flag" == "true" ]]; then
        if [[ ${#versions[@]} -ne 1 ]]; then
            die "Usage: ${SCRIPT_NAME} start <version> --new [name] [--clone]"
        fi
        cmd_new "${versions[0]}" "$instance_name" "$clone_flag"
        return
    fi

    # Interactive selection if no versions specified
    if [[ ${#versions[@]} -eq 0 ]]; then
        local selected
        if ! selected=$(interactive_select); then
            exit 1
        fi
        IFS=' ' read -ra versions <<< "$selected"
    fi

    # Validate all targets first
    for v in "${versions[@]}"; do
        validate_target "$v" || exit 1
    done

    # Check ARM compatibility (only for base versions)
    detect_arch
    if [[ "$DETECTED_ARCH" == "arm64" ]]; then
        for v in "${versions[@]}"; do
            resolve_target "$v"
            if ! is_arm_supported "$RESOLVED_BASE"; then
                die "${RESOLVED_DISPLAY_NAME} is not supported on ARM64. Supported: ${ARM_VERSIONS[*]}"
            fi
        done
    fi

    # Run prerequisite checks
    check_docker || exit 1
    check_kvm || exit 1

    for v in "${versions[@]}"; do
        resolve_target "$v"
        header "Starting ${RESOLVED_DISPLAY_NAME} ($v)"

        # Check resources
        local resource_type="${VERSION_RESOURCE_TYPE[$RESOLVED_BASE]}"
        if [[ "$resource_type" == "modern" ]]; then
            check_memory "$MODERN_RAM_GB" || true
            check_disk "$MODERN_DISK_GB" || true
        else
            check_memory "$LEGACY_RAM_GB" || true
            check_disk "$LEGACY_DISK_GB" || true
        fi

        # Ensure data directory exists
        local data_dir="$SCRIPT_DIR/data/$v"
        if [[ ! -d "$data_dir" ]]; then
            info "Creating data directory: data/$v"
            mkdir -p "$data_dir"
        fi

        # Pre-populate from ISO cache if no ISO exists in data dir
        local existing_isos
        existing_isos=$(find "$data_dir" -maxdepth 1 -name '*.iso' -type f 2>/dev/null || true)
        if [[ -z "$existing_isos" ]]; then
            local cache_src="$ISO_CACHE_DIR/$RESOLVED_BASE"
            if [[ -d "$cache_src" ]]; then
                local cached_iso
                cached_iso=$(find "$cache_src" -maxdepth 1 -name '*.iso' -type f -print -quit 2>/dev/null || true)
                if [[ -n "$cached_iso" ]]; then
                    local iso_name
                    iso_name=$(basename "$cached_iso")
                    info "Restoring cached ISO: $iso_name..."
                    cp "$cached_iso" "$data_dir/$iso_name"
                    success "ISO restored from cache (skipping download)"
                fi
            fi
        fi

        # Check ports are available
        if ! check_port "$RESOLVED_WEB_PORT"; then
            error "Web port $RESOLVED_WEB_PORT is already in use"
            continue
        fi
        if ! check_port "$RESOLVED_RDP_PORT"; then
            error "RDP port $RESOLVED_RDP_PORT is already in use"
            continue
        fi

        if is_running "$v"; then
            info "$v is already running"
        else
            info "Starting $v..."
            if run_compose "$v" up -d "$v"; then
                success "$v started successfully"
            else
                error "Failed to start $v"
                continue
            fi
        fi

        # Show connection info
        detect_lan_ip
        printf '\n'
        printf '%s\n' "  ${BOLD}Connection Details:${RESET}"
        printf '%s\n' "    → Web Viewer: ${CYAN}http://localhost:${RESOLVED_WEB_PORT}${RESET}"
        printf '%s\n' "    → RDP:        ${CYAN}localhost:${RESOLVED_RDP_PORT}${RESET}"
        if [[ -n "$LAN_IP" ]]; then
            printf '%s\n' "    → LAN Web:    ${CYAN}http://${LAN_IP}:${RESOLVED_WEB_PORT}${RESET}"
            printf '%s\n' "    → LAN RDP:    ${CYAN}${LAN_IP}:${RESOLVED_RDP_PORT}${RESET}"
        fi
        printf '\n'
    done

    # Refresh cache after state changes
    invalidate_cache
}

cmd_stop() {
    local versions=("$@")

    # Stop all running containers (base + instances)
    if [[ ${#versions[@]} -eq 1 && "${versions[0]}" == "all" ]]; then
        versions=()
        refresh_status_cache
        for v in "${ALL_VERSIONS[@]}"; do
            local status
            status=$(get_status "$v")
            if [[ "$status" == "running" ]]; then
                versions+=("$v")
            fi
        done
        # Also check instances
        load_registry
        for name in "${!_REGISTRY_INSTANCES[@]}"; do
            local status
            status=$(get_status "$name")
            if [[ "$status" == "running" ]]; then
                versions+=("$name")
            fi
        done
        if [[ ${#versions[@]} -eq 0 ]]; then
            info "No running containers found"
            return 0
        fi
    fi

    # Interactive selection if no versions specified
    if [[ ${#versions[@]} -eq 0 ]]; then
        local selected
        if ! selected=$(interactive_select); then
            exit 1
        fi
        IFS=' ' read -ra versions <<< "$selected"
    fi

    # Validate all targets first
    for v in "${versions[@]}"; do
        validate_target "$v" || exit 1
    done

    # Show confirmation
    header "Stopping Containers"
    printf '\n'
    printf '%s\n' "  The following containers will be stopped:"
    for v in "${versions[@]}"; do
        resolve_target "$v"
        local status
        if is_running "$v"; then
            status="${GREEN}running${RESET}"
        else
            status="${YELLOW}not running${RESET}"
        fi
        printf '%s\n' "    • $v (${RESOLVED_DISPLAY_NAME}) - $status"
    done
    printf '\n'
    printf '%s' "  Continue? [y/N]: "

    local confirm
    read -r confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        info "Canceled"
        return 0
    fi

    for v in "${versions[@]}"; do
        if ! is_running "$v" && ! container_exists "$v"; then
            info "$v is not running"
            continue
        fi

        info "Stopping $v (grace period: 2 minutes)..."
        if run_compose "$v" stop "$v"; then
            success "$v stopped"
        else
            error "Failed to stop $v"
        fi
    done

    # Auto-cache ISOs if enabled
    if [[ "${AUTO_CACHE^^}" == "Y" ]]; then
        for v in "${versions[@]}"; do
            auto_cache_save "$v"
        done
    fi

    # Refresh cache after state changes
    invalidate_cache
}

cmd_restart() {
    local versions=("$@")

    # Interactive selection if no versions specified
    if [[ ${#versions[@]} -eq 0 ]]; then
        local selected
        if ! selected=$(interactive_select); then
            exit 1
        fi
        IFS=' ' read -ra versions <<< "$selected"
    fi

    # Validate all targets first
    for v in "${versions[@]}"; do
        validate_target "$v" || exit 1
    done

    for v in "${versions[@]}"; do
        resolve_target "$v"
        header "Restarting ${RESOLVED_DISPLAY_NAME} ($v)"

        info "Restarting $v..."
        if run_compose "$v" restart "$v"; then
            success "$v restarted"
            detect_lan_ip
            printf '\n'
            printf '%s\n' "  ${BOLD}Connection Details:${RESET}"
            printf '%s\n' "    → Web Viewer: ${CYAN}http://localhost:${RESOLVED_WEB_PORT}${RESET}"
            printf '%s\n' "    → RDP:        ${CYAN}localhost:${RESOLVED_RDP_PORT}${RESET}"
            if [[ -n "$LAN_IP" ]]; then
                printf '%s\n' "    → LAN Web:    ${CYAN}http://${LAN_IP}:${RESOLVED_WEB_PORT}${RESET}"
                printf '%s\n' "    → LAN RDP:    ${CYAN}${LAN_IP}:${RESOLVED_RDP_PORT}${RESET}"
            fi
            printf '\n'
        else
            error "Failed to restart $v"
        fi
    done

    # Refresh cache after state changes
    invalidate_cache
}

cmd_status() {
    local versions=("$@")

    # Show all if no versions specified
    if [[ ${#versions[@]} -eq 0 ]]; then
        versions=("${ALL_VERSIONS[@]}")
    fi

    table_header

    for v in "${versions[@]}"; do
        if validate_version "$v" 2>/dev/null; then
            local status
            status=$(get_status "$v")
            table_row "$v" "${VERSION_DISPLAY_NAMES[$v]}" "$status" "${VERSION_PORTS_WEB[$v]}" "${VERSION_PORTS_RDP[$v]}"
        elif validate_target "$v" 2>/dev/null; then
            resolve_target "$v"
            local status
            status=$(get_status "$v")
            table_row "$v" "$RESOLVED_DISPLAY_NAME" "$status" "$RESOLVED_WEB_PORT" "$RESOLVED_RDP_PORT"
        fi
    done

    # Show instances section if showing all
    load_registry
    if [[ ${#_REGISTRY_INSTANCES[@]} -gt 0 && ${#versions[@]} -eq ${#ALL_VERSIONS[@]} ]]; then
        printf '\n'
        printf "  %s%-12s %-26s %-10s %-8s %-8s%s\n" \
            "${BOLD}${DIM}" "INSTANCE" "NAME" "STATUS" "WEB" "RDP" "${RESET}"
        printf '%s\n' "  ${DIM}$(printf '─%.0s' {1..66})${RESET}"

        for name in "${!_REGISTRY_INSTANCES[@]}"; do
            resolve_target "$name"
            local status
            status=$(get_status "$name")
            table_row "$name" "$RESOLVED_DISPLAY_NAME" "$status" "$RESOLVED_WEB_PORT" "$RESOLVED_RDP_PORT"
        done
    fi
    printf '\n'

    detect_lan_ip
    if [[ -n "$LAN_IP" ]]; then
        printf '%s\n' "  ${DIM}LAN IP: ${LAN_IP} — use http://${LAN_IP}:<web-port> for remote access${RESET}"
        printf '\n'
    fi
}

cmd_logs() {
    local version="${1:-}"
    local follow="${2:-}"

    if [[ -z "$version" ]]; then
        die "Usage: ${SCRIPT_NAME} logs <version|instance> [-f]"
    fi

    validate_target "$version" || exit 1

    local args=()
    if [[ "$follow" == "-f" ]]; then
        args+=("--follow")
    fi

    info "Showing logs for $version..."
    run_compose "$version" logs "${args[@]}" "$version"
}

cmd_shell() {
    local version="${1:-}"

    if [[ -z "$version" ]]; then
        die "Usage: ${SCRIPT_NAME} shell <version|instance>"
    fi

    validate_target "$version" || exit 1

    if ! is_running "$version"; then
        die "$version is not running"
    fi

    info "Opening shell in $version..."
    docker exec -it "$version" /bin/bash
}

cmd_stats() {
    local versions=("$@")

    # Get running containers if no versions specified
    if [[ ${#versions[@]} -eq 0 ]]; then
        local running=()
        for v in "${ALL_VERSIONS[@]}"; do
            if is_running "$v"; then
                running+=("$v")
            fi
        done
        # Also check instances
        load_registry
        for name in "${!_REGISTRY_INSTANCES[@]}"; do
            if is_running "$name"; then
                running+=("$name")
            fi
        done
        if [[ ${#running[@]} -eq 0 ]]; then
            die "No containers are running"
        fi
        versions=("${running[@]}")
    fi

    # Validate targets
    local valid_running=()
    for v in "${versions[@]}"; do
        if validate_target "$v" 2>/dev/null && is_running "$v"; then
            valid_running+=("$v")
        fi
    done

    if [[ ${#valid_running[@]} -eq 0 ]]; then
        die "None of the specified containers are running"
    fi

    info "Showing stats for: ${valid_running[*]}"
    docker stats "${valid_running[@]}"
}

cmd_build() {
    header "Building Docker Image"

    check_docker || exit 1

    info "Building dockurr/windows image locally..."
    cd "$SCRIPT_DIR"

    if docker build -t dockurr/windows .; then
        success "Image built successfully"
    else
        die "Build failed"
    fi
}

cmd_rebuild() {
    local versions=("$@")

    # Interactive selection if no versions specified
    if [[ ${#versions[@]} -eq 0 ]]; then
        local selected
        if ! selected=$(interactive_select); then
            exit 1
        fi
        IFS=' ' read -ra versions <<< "$selected"
    fi

    # Validate all targets first
    for v in "${versions[@]}"; do
        validate_target "$v" || exit 1
    done

    # Show warning
    header "Rebuild Containers"
    printf '\n'
    printf '%s\n' "  ${RED}${BOLD}WARNING: This will destroy and recreate the following containers.${RESET}"
    printf '%s\n' "  ${RED}Data in /storage volumes will be preserved.${RESET}"
    printf '\n'
    for v in "${versions[@]}"; do
        resolve_target "$v"
        printf '%s\n' "    • $v (${RESOLVED_DISPLAY_NAME})"
    done
    printf '\n'
    printf '%s' "  Type 'yes' to confirm: "

    local confirm
    read -r confirm
    if [[ "$confirm" != "yes" ]]; then
        info "Canceled"
        return 0
    fi

    for v in "${versions[@]}"; do
        resolve_target "$v"
        header "Rebuilding $v"

        # Ensure data directory exists
        local data_dir="$SCRIPT_DIR/data/$v"
        if [[ ! -d "$data_dir" ]]; then
            info "Creating data directory: data/$v"
            mkdir -p "$data_dir"
        fi

        info "Stopping and removing $v..."
        run_compose "$v" down "$v" 2>/dev/null || true

        info "Recreating $v..."
        if run_compose "$v" up -d "$v"; then
            success "$v rebuilt successfully"
            detect_lan_ip
            printf '\n'
            printf '%s\n' "  ${BOLD}Connection Details:${RESET}"
            printf '%s\n' "    → Web Viewer: ${CYAN}http://localhost:${RESOLVED_WEB_PORT}${RESET}"
            printf '%s\n' "    → RDP:        ${CYAN}localhost:${RESOLVED_RDP_PORT}${RESET}"
            if [[ -n "$LAN_IP" ]]; then
                printf '%s\n' "    → LAN Web:    ${CYAN}http://${LAN_IP}:${RESOLVED_WEB_PORT}${RESET}"
                printf '%s\n' "    → LAN RDP:    ${CYAN}${LAN_IP}:${RESOLVED_RDP_PORT}${RESET}"
            fi
            printf '\n'
        else
            error "Failed to rebuild $v"
        fi
    done

    # Refresh cache after state changes
    invalidate_cache
}

cmd_list() {
    local category="${1:-all}"

    detect_arch
    header "Available Windows Versions"

    local categories=()
    case "$category" in
        desktop) categories=("desktop") ;;
        legacy) categories=("legacy") ;;
        server) categories=("server") ;;
        tiny) categories=("tiny") ;;
        all) categories=("desktop" "legacy" "server" "tiny") ;;
        *)
            die "Unknown category: $category. Use: desktop, legacy, server, tiny, or all"
            ;;
    esac

    for cat in "${categories[@]}"; do
        printf '\n'
        local cat_upper
        cat_upper=$(echo "$cat" | tr '[:lower:]' '[:upper:]')
        printf '%s\n' "  ${BOLD}${cat_upper}${RESET}"
        printf '%s\n' "  ${DIM}$(printf '─%.0s' {1..50})${RESET}"

        for v in "${ALL_VERSIONS[@]}"; do
            if [[ "${VERSION_CATEGORIES[$v]}" == "$cat" ]]; then
                local status=""
                if is_running "$v"; then
                    status="${GREEN}[running]${RESET}"
                elif container_exists "$v"; then
                    status="${YELLOW}[stopped]${RESET}"
                fi
                local resource_tag
                if [[ "${VERSION_RESOURCE_TYPE[$v]}" == "modern" ]]; then
                    resource_tag="${CYAN}(8G RAM)${RESET}"
                else
                    resource_tag="${DIM}(2G RAM)${RESET}"
                fi
                local arch_tag=""
                if [[ "$DETECTED_ARCH" == "arm64" ]] && ! is_arm_supported "$v"; then
                    arch_tag="${RED}[x86 only]${RESET}"
                fi
                printf "    %-10s %-28s %s %s %s\n" "$v" "${VERSION_DISPLAY_NAMES[$v]}" "$resource_tag" "$arch_tag" "$status"
            fi
        done
    done

    # Show instances section
    load_registry
    if [[ ${#_REGISTRY_INSTANCES[@]} -gt 0 ]]; then
        printf '\n'
        printf '%s\n' "  ${BOLD}INSTANCES${RESET}"
        printf '%s\n' "  ${DIM}$(printf '─%.0s' {1..50})${RESET}"

        for name in "${!_REGISTRY_INSTANCES[@]}"; do
            local base status_tag
            base=$(registry_get_field "$name" "base")
            status_tag=""
            if is_running "$name"; then
                status_tag="${GREEN}[running]${RESET}"
            elif container_exists "$name"; then
                status_tag="${YELLOW}[stopped]${RESET}"
            fi
            local resource_tag
            if [[ "${VERSION_RESOURCE_TYPE[$base]}" == "modern" ]]; then
                resource_tag="${CYAN}(8G RAM)${RESET}"
            else
                resource_tag="${DIM}(2G RAM)${RESET}"
            fi
            printf "    %-20s %-18s %s %s\n" "$name" "${VERSION_DISPLAY_NAMES[$base]}" "$resource_tag" "$status_tag"
        done
    fi
    printf '\n'
}

cmd_inspect() {
    local version="${1:-}"

    if [[ -z "$version" ]]; then
        die "Usage: ${SCRIPT_NAME} inspect <version|instance>"
    fi

    validate_target "$version" || exit 1

    resolve_target "$version"

    header "Container Details: $version"
    printf '\n'
    printf '%s\n' "  ${BOLD}Version:${RESET}      $version"
    printf '%s\n' "  ${BOLD}Name:${RESET}         ${RESOLVED_DISPLAY_NAME}"
    printf '%s\n' "  ${BOLD}Type:${RESET}         ${RESOLVED_TYPE}"
    if [[ "$RESOLVED_TYPE" == "instance" ]]; then
        printf '%s\n' "  ${BOLD}Base:${RESET}         ${RESOLVED_BASE}"
        local suffix created
        suffix=$(registry_get_field "$version" "suffix")
        created=$(registry_get_field "$version" "created")
        printf '%s\n' "  ${BOLD}Suffix:${RESET}       ${suffix}"
        printf '%s\n' "  ${BOLD}Created:${RESET}      ${created}"
    fi
    printf '%s\n' "  ${BOLD}Category:${RESET}     ${VERSION_CATEGORIES[$RESOLVED_BASE]}"
    printf '%s\n' "  ${BOLD}Status:${RESET}       $(get_status "$version")"
    printf '%s\n' "  ${BOLD}Web Port:${RESET}     ${RESOLVED_WEB_PORT}"
    printf '%s\n' "  ${BOLD}RDP Port:${RESET}     ${RESOLVED_RDP_PORT}"
    printf '%s\n' "  ${BOLD}Resources:${RESET}    ${VERSION_RESOURCE_TYPE[$RESOLVED_BASE]}"
    if [[ "$RESOLVED_TYPE" == "base" ]]; then
        printf '%s\n' "  ${BOLD}Compose:${RESET}      ${VERSION_COMPOSE_FILES[$version]}"
    else
        printf '%s\n' "  ${BOLD}Compose:${RESET}      instances/${version}.yml"
    fi
    printf '%s\n' "  ${BOLD}Web URL:${RESET}      http://localhost:${RESOLVED_WEB_PORT}"
    printf '%s\n' "  ${BOLD}RDP:${RESET}          localhost:${RESOLVED_RDP_PORT}"
    detect_lan_ip
    if [[ -n "$LAN_IP" ]]; then
        printf '%s\n' "  ${BOLD}LAN Web:${RESET}      http://${LAN_IP}:${RESOLVED_WEB_PORT}"
        printf '%s\n' "  ${BOLD}LAN RDP:${RESET}      ${LAN_IP}:${RESOLVED_RDP_PORT}"
    fi
    printf '\n'

    if container_exists "$version"; then
        printf '%s\n' "  ${BOLD}Docker Info:${RESET}"
        docker inspect "$version" --format '
    Image:       {{.Config.Image}}
    Created:     {{.Created}}
    IP Address:  {{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}
    Mounts:      {{range .Mounts}}{{.Source}} -> {{.Destination}}
                 {{end}}' 2>/dev/null || true
    fi
    printf '\n'
}

cmd_monitor() {
    local interval="${1:-5}"

    if ! [[ "$interval" =~ ^[0-9]+$ ]]; then
        die "Interval must be a number (seconds)"
    fi

    header "Real-time Monitor (refresh: ${interval}s)"
    printf '%s\n' "  Press Ctrl+C to exit"
    printf '\n'

    while true; do
        # Refresh cache for accurate status
        invalidate_cache

        clear
        printf '%s\n' "${BOLD}${CYAN}Windows Container Monitor${RESET} - $(date '+%Y-%m-%d %H:%M:%S')"
        printf '%s\n' "${DIM}$(printf '─%.0s' {1..70})${RESET}"

        local running_count=0
        local stopped_count=0
        local total_count=0

        table_header

        for v in "${ALL_VERSIONS[@]}"; do
            local status
            status=$(get_status "$v")
            if [[ "$status" != "not created" ]]; then
                ((++total_count))
                if [[ "$status" == "running" ]]; then
                    ((++running_count))
                else
                    ((++stopped_count))
                fi
                table_row "$v" "${VERSION_DISPLAY_NAMES[$v]}" "$status" "${VERSION_PORTS_WEB[$v]}" "${VERSION_PORTS_RDP[$v]}"
            fi
        done

        # Also show instances
        load_registry
        for name in "${!_REGISTRY_INSTANCES[@]}"; do
            local status
            status=$(get_status "$name")
            if [[ "$status" != "not created" ]]; then
                resolve_target "$name"
                ((++total_count))
                if [[ "$status" == "running" ]]; then
                    ((++running_count))
                else
                    ((++stopped_count))
                fi
                table_row "$name" "$RESOLVED_DISPLAY_NAME" "$status" "$RESOLVED_WEB_PORT" "$RESOLVED_RDP_PORT"
            fi
        done

        if [[ $total_count -eq 0 ]]; then
            printf '%s\n' "  ${DIM}No containers found${RESET}"
        fi

        printf '\n'
        printf '%s\n' "  ${BOLD}Summary:${RESET} ${GREEN}$running_count running${RESET}, ${RED}$stopped_count stopped${RESET}, $total_count total"
        printf '\n'
        printf '%s\n' "  ${DIM}Refreshing in ${interval}s... (Ctrl+C to exit)${RESET}"

        sleep "$interval"
    done
}

cmd_check() {
    detect_arch
    run_all_checks
    printf '%s\n' "  ${BOLD}Architecture:${RESET} ${DETECTED_ARCH}"
    if [[ "$DETECTED_ARCH" == "arm64" ]]; then
        printf '%s\n' "  ${BOLD}ARM64 image:${RESET}  dockurr/windows-arm"
        printf '%s\n' "  ${BOLD}Supported:${RESET}    ${ARM_VERSIONS[*]}"
    fi
    detect_lan_ip
    if [[ -n "$LAN_IP" ]]; then
        printf '%s\n' "  ${BOLD}LAN IP:${RESET}       ${LAN_IP}"
    fi
    printf '\n'
}

cmd_refresh() {
    header "Refreshing Status Cache"

    info "Fetching container statuses from Docker..."
    refresh_status_cache true

    local count=${#_STATUS_CACHE[@]}
    success "Cache refreshed (${count} containers found)"

    # Show cache info
    local age
    age=$(get_cache_age)
    printf '\n'
    printf '%s\n' "  ${BOLD}Cache Info:${RESET}"
    printf '%s\n' "    → File:     ${CYAN}${CACHE_FILE}${RESET}"
    printf '%s\n' "    → Age:      ${age} seconds"
    printf '%s\n' "    → Max Age:  ${CACHE_MAX_AGE} seconds (7 days)"
    printf '\n'

    # Show summary
    local cnt_running=0 cnt_stopped=0 cnt_other=0
    for state in "${_STATUS_CACHE[@]}"; do
        case "$state" in
            running) ((cnt_running++)) || true ;;
            exited)  ((cnt_stopped++)) || true ;;
            *)       ((cnt_other++)) || true ;;
        esac
    done
    printf '%s\n' "  ${BOLD}Containers:${RESET} ${GREEN}${cnt_running} running${RESET}, ${RED}${cnt_stopped} stopped${RESET}, ${DIM}${cnt_other} other${RESET}"
    printf '\n'
}

# ==============================================================================
# PORT CHECK HELPER
# ==============================================================================

check_port() {
    local port="$1"
    if ss -tlnp 2>/dev/null | grep -q ":${port} "; then
        return 1  # port in use
    fi
    return 0
}

# ==============================================================================
# INSTANCE PORT ALLOCATION & COMPOSE GENERATION
# ==============================================================================

# Allocate ports for a new instance, echoes "web_port rdp_port"
allocate_instance_ports() {
    load_registry

    # Collect all used ports
    local -A used_ports=()
    for v in "${ALL_VERSIONS[@]}"; do
        used_ports["${VERSION_PORTS_WEB[$v]}"]=1
        used_ports["${VERSION_PORTS_RDP[$v]}"]=1
    done
    for name in "${!_REGISTRY_INSTANCES[@]}"; do
        local wp rp
        wp=$(registry_get_field "$name" "web_port")
        rp=$(registry_get_field "$name" "rdp_port")
        used_ports["$wp"]=1
        used_ports["$rp"]=1
    done

    # Find free web port
    local web_port=""
    local max_web=$((INSTANCE_WEB_PORT_BASE + INSTANCE_PORT_RANGE))
    local p
    for ((p=INSTANCE_WEB_PORT_BASE; p<=max_web; p++)); do
        if [[ -z "${used_ports[$p]:-}" ]] && check_port "$p"; then
            web_port=$p
            break
        fi
    done
    if [[ -z "$web_port" ]]; then
        die "No free web ports in range ${INSTANCE_WEB_PORT_BASE}-${max_web}"
    fi

    # Find free RDP port
    local rdp_port=""
    local max_rdp=$((INSTANCE_RDP_PORT_BASE + INSTANCE_PORT_RANGE))
    for ((p=INSTANCE_RDP_PORT_BASE; p<=max_rdp; p++)); do
        if [[ -z "${used_ports[$p]:-}" ]] && check_port "$p"; then
            rdp_port=$p
            break
        fi
    done
    if [[ -z "$rdp_port" ]]; then
        die "No free RDP ports in range ${INSTANCE_RDP_PORT_BASE}-${max_rdp}"
    fi

    echo "$web_port $rdp_port"
}

# Get the next numeric suffix for a base version
next_instance_suffix() {
    local base="$1"
    load_registry

    local max=0
    for name in "${!_REGISTRY_INSTANCES[@]}"; do
        local entry_base
        entry_base=$(registry_get_field "$name" "base")
        if [[ "$entry_base" == "$base" ]]; then
            local entry_suffix
            entry_suffix=$(registry_get_field "$name" "suffix")
            if [[ "$entry_suffix" =~ ^[0-9]+$ ]] && ((entry_suffix > max)); then
                max=$entry_suffix
            fi
        fi
    done
    echo $((max + 1))
}

# Generate a compose file for an instance
generate_instance_compose() {
    local name="$1" base="$2" web_port="$3" rdp_port="$4"

    ensure_instance_dir

    local env_file="${VERSION_ENV_FILES[$base]}"
    local version_val="${VERSION_ENV_VALUES[$base]}"
    local compose_file="$INSTANCE_DIR/${name}.yml"

    cat > "$compose_file" << YAML
---
services:
  ${name}:
    image: \${WINDOWS_IMAGE:-dockurr/windows}
    container_name: ${name}
    env_file: ../${env_file}
    environment:
      VERSION: "${version_val}"
    devices:
      - /dev/kvm
      - /dev/net/tun
    cap_add:
      - NET_ADMIN
    ports:
      - ${web_port}:8006
      - ${rdp_port}:3389/tcp
      - ${rdp_port}:3389/udp
    volumes:
      - ../data/${name}:/storage
    restart: \${RESTART_POLICY:-on-failure}
    stop_grace_period: 2m
YAML
}

# ==============================================================================
# SNAPSHOT COMMAND
# ==============================================================================

cmd_snapshot() {
    local version="${1:-}"
    local name="${2:-}"

    if [[ -z "$version" ]]; then
        die "Usage: ${SCRIPT_NAME} snapshot <version|instance> [name]"
    fi

    validate_target "$version" || exit 1
    resolve_target "$version"

    # Skip if container was never created
    refresh_status_cache
    if ! container_exists "$RESOLVED_NAME"; then
        die "$RESOLVED_NAME was never created — nothing to snapshot"
    fi

    local data_dir="$SCRIPT_DIR/data/$RESOLVED_NAME"
    if [[ ! -d "$data_dir" ]] || [[ -z "$(ls -A "$data_dir" 2>/dev/null)" ]]; then
        die "No data found for $RESOLVED_NAME (data/$RESOLVED_NAME/ is empty or missing)"
    fi

    # Default name: timestamp
    if [[ -z "$name" ]]; then
        name=$(date +%Y%m%d-%H%M%S)
    fi

    local snap_dir="$SCRIPT_DIR/snapshots/$RESOLVED_NAME/$name"
    if [[ -d "$snap_dir" ]]; then
        die "Snapshot already exists: snapshots/$RESOLVED_NAME/$name"
    fi

    header "Snapshot: ${RESOLVED_DISPLAY_NAME} ($RESOLVED_NAME)"

    # Stop container if running (remember to restart)
    local was_running=false
    if is_running "$RESOLVED_NAME"; then
        was_running=true
        info "Stopping $RESOLVED_NAME for snapshot..."
        run_compose "$RESOLVED_NAME" stop "$RESOLVED_NAME"
    fi

    info "Creating snapshot: snapshots/$RESOLVED_NAME/$name"
    mkdir -p "$snap_dir"
    if cp -a "$data_dir/." "$snap_dir/"; then
        local size
        size=$(du -sh "$snap_dir" | awk '{print $1}')
        success "Snapshot created successfully"
        printf '\n'
        printf '%s\n' "  ${BOLD}Path:${RESET} snapshots/$RESOLVED_NAME/$name"
        printf '%s\n' "  ${BOLD}Size:${RESET} $size"
        printf '\n'
    else
        error "Failed to create snapshot"
        # Clean up partial snapshot
        rm -rf "$snap_dir"
    fi

    # Restart if was running
    if [[ "$was_running" == "true" ]]; then
        info "Restarting $RESOLVED_NAME..."
        run_compose "$RESOLVED_NAME" up -d "$RESOLVED_NAME"
        invalidate_cache
    fi
}

# ==============================================================================
# RESTORE COMMAND
# ==============================================================================

cmd_restore() {
    local version="${1:-}"
    local name="${2:-}"

    if [[ -z "$version" ]]; then
        die "Usage: ${SCRIPT_NAME} restore <version|instance> [name]"
    fi

    validate_target "$version" || exit 1
    resolve_target "$version"

    # Skip if container was never created
    refresh_status_cache
    if ! container_exists "$RESOLVED_NAME"; then
        die "$RESOLVED_NAME was never created — nothing to restore"
    fi

    local snap_base="$SCRIPT_DIR/snapshots/$RESOLVED_NAME"
    if [[ ! -d "$snap_base" ]]; then
        die "No snapshots found for $RESOLVED_NAME"
    fi

    # If no name: list available snapshots and let user pick
    if [[ -z "$name" ]]; then
        local snapshots=()
        while IFS= read -r d; do
            snapshots+=("$(basename "$d")")
        done < <(find "$snap_base" -mindepth 1 -maxdepth 1 -type d | sort)

        if [[ ${#snapshots[@]} -eq 0 ]]; then
            die "No snapshots found for $RESOLVED_NAME"
        fi

        header "Available Snapshots for $RESOLVED_NAME"
        printf '\n'
        local i=1
        for s in "${snapshots[@]}"; do
            local size
            size=$(du -sh "$snap_base/$s" | awk '{print $1}')
            printf '  %s) %-24s %s\n' "$i" "$s" "${DIM}($size)${RESET}"
            ((i++))
        done
        printf '\n'
        printf '  Select snapshot [1-%d]: ' "${#snapshots[@]}"

        local choice
        read -r choice
        if [[ ! "$choice" =~ ^[0-9]+$ ]] || ((choice < 1 || choice > ${#snapshots[@]})); then
            die "Invalid selection"
        fi
        name="${snapshots[$((choice-1))]}"
    fi

    local snap_dir="$snap_base/$name"
    if [[ ! -d "$snap_dir" ]]; then
        die "Snapshot not found: snapshots/$RESOLVED_NAME/$name"
    fi

    header "Restore: ${RESOLVED_DISPLAY_NAME} ($RESOLVED_NAME)"
    printf '\n'
    printf '%s\n' "  ${RED}${BOLD}WARNING: This will replace current data for $RESOLVED_NAME.${RESET}"
    printf '%s\n' "  ${RED}Restoring from: snapshots/$RESOLVED_NAME/$name${RESET}"
    printf '\n'
    printf '%s' "  Type 'yes' to confirm: "

    local confirm
    read -r confirm
    if [[ "$confirm" != "yes" ]]; then
        info "Canceled"
        return 0
    fi

    # Stop container if running (remember to restart)
    local was_running=false
    if is_running "$RESOLVED_NAME"; then
        was_running=true
        info "Stopping $RESOLVED_NAME for restore..."
        run_compose "$RESOLVED_NAME" stop "$RESOLVED_NAME"
    fi

    local data_dir="$SCRIPT_DIR/data/$RESOLVED_NAME"
    info "Restoring data from snapshot..."
    mkdir -p "$data_dir"
    rm -rf "${data_dir:?}/"*
    if cp -a "$snap_dir/." "$data_dir/"; then
        success "Data restored successfully from snapshots/$RESOLVED_NAME/$name"
    else
        error "Failed to restore data"
    fi

    # Restart if was running
    if [[ "$was_running" == "true" ]]; then
        info "Restarting $RESOLVED_NAME..."
        run_compose "$RESOLVED_NAME" up -d "$RESOLVED_NAME"
        invalidate_cache
    fi
}

# ==============================================================================
# PULL COMMAND
# ==============================================================================

cmd_pull() {
    local versions=("$@")

    detect_arch
    local image="dockurr/windows"
    if [[ "$DETECTED_ARCH" == "arm64" ]]; then
        image="dockurr/windows-arm"
    fi

    header "Pull Docker Image"

    info "Image: $image"

    # Get current digest before pull
    local digest_before
    digest_before=$(docker inspect --format='{{index .RepoDigests 0}}' "$image" 2>/dev/null || echo "none")

    info "Pulling latest image..."
    if docker pull "$image"; then
        local digest_after
        digest_after=$(docker inspect --format='{{index .RepoDigests 0}}' "$image" 2>/dev/null || echo "none")
        if [[ "$digest_before" == "$digest_after" ]]; then
            success "Image is already up to date"
        else
            success "Image updated"
        fi
    else
        error "Failed to pull image"
    fi
    printf '\n'
}

# ==============================================================================
# DISK COMMAND
# ==============================================================================

cmd_disk() {
    local versions=("$@")

    header "Disk Usage"

    local data_base="$SCRIPT_DIR/data"
    if [[ ! -d "$data_base" ]]; then
        info "No data directory found"
        return 0
    fi

    # If no versions specified, scan all data directories
    if [[ ${#versions[@]} -eq 0 ]]; then
        for v in "${ALL_VERSIONS[@]}"; do
            if [[ -d "$data_base/$v" ]]; then
                versions+=("$v")
            fi
        done
        # Also include instance data dirs
        load_registry
        for name in "${!_REGISTRY_INSTANCES[@]}"; do
            if [[ -d "$data_base/$name" ]]; then
                versions+=("$name")
            fi
        done
    fi

    if [[ ${#versions[@]} -eq 0 ]]; then
        info "No VM data directories found"
        return 0
    fi

    # Refresh cache for status info
    refresh_status_cache

    printf '\n'
    printf "  %s%-20s %-12s %-10s%s\n" "${BOLD}${DIM}" "VERSION" "SIZE" "STATUS" "${RESET}"
    printf '%s\n' "  ${DIM}$(printf '─%.0s' {1..44})${RESET}"

    for v in "${versions[@]}"; do
        if [[ -d "$data_base/$v" ]]; then
            local size status
            size=$(du -sh "$data_base/$v" 2>/dev/null | awk '{print $1}')
            status=$(get_status "$v")
            local status_color
            case "$status" in
                running) status_color="${GREEN}" ;;
                stopped|exited) status_color="${RED}" ;;
                *) status_color="${YELLOW}" ;;
            esac
            printf "  %-20s %-12s %s%-10s%s\n" "$v" "$size" "$status_color" "$status" "${RESET}"
        fi
    done

    printf '%s\n' "  ${DIM}$(printf '─%.0s' {1..44})${RESET}"

    # Total data usage
    local total
    total=$(du -sh "$data_base" 2>/dev/null | awk '{print $1}')
    printf "  %-20s %s\n" "Total:" "$total"

    # Snapshots usage
    local snap_base="$SCRIPT_DIR/snapshots"
    if [[ -d "$snap_base" ]]; then
        local snap_total snap_count
        snap_total=$(du -sh "$snap_base" 2>/dev/null | awk '{print $1}')
        snap_count=$(find "$snap_base" -mindepth 2 -maxdepth 2 -type d 2>/dev/null | wc -l)
        printf '\n'
        printf "  Snapshots:   %s (%d snapshot%s)\n" "$snap_total" "$snap_count" "$( ((snap_count != 1)) && echo "s" )"

        # Per-version snapshot breakdown
        for v in "${ALL_VERSIONS[@]}"; do
            if [[ -d "$snap_base/$v" ]]; then
                local vsnap_size vsnap_count
                vsnap_size=$(du -sh "$snap_base/$v" 2>/dev/null | awk '{print $1}')
                vsnap_count=$(find "$snap_base/$v" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
                printf "    %-10s %s (%d snapshot%s)\n" "$v" "$vsnap_size" "$vsnap_count" "$( ((vsnap_count != 1)) && echo "s" )"
            fi
        done
        # Instance snapshot breakdown
        load_registry
        for name in "${!_REGISTRY_INSTANCES[@]}"; do
            if [[ -d "$snap_base/$name" ]]; then
                local vsnap_size vsnap_count
                vsnap_size=$(du -sh "$snap_base/$name" 2>/dev/null | awk '{print $1}')
                vsnap_count=$(find "$snap_base/$name" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
                printf "    %-18s %s (%d snapshot%s)\n" "$name" "$vsnap_size" "$vsnap_count" "$( ((vsnap_count != 1)) && echo "s" )"
            fi
        done
    fi
    printf '\n'
}

# ==============================================================================
# CLEAN COMMAND
# ==============================================================================

cmd_clean() {
    local purge_data=false
    if [[ "${1:-}" == "--data" ]]; then
        purge_data=true
    fi

    header "Clean Stopped Containers"

    refresh_status_cache

    # Find stopped containers (base + instances)
    local stopped=()
    for v in "${ALL_VERSIONS[@]}"; do
        local status
        status=$(get_status "$v")
        if [[ "$status" == "exited" || "$status" == "stopped" ]]; then
            stopped+=("$v")
        fi
    done
    load_registry
    for name in "${!_REGISTRY_INSTANCES[@]}"; do
        local status
        status=$(get_status "$name")
        if [[ "$status" == "exited" || "$status" == "stopped" ]]; then
            stopped+=("$name")
        fi
    done

    if [[ ${#stopped[@]} -eq 0 ]]; then
        info "No stopped containers found"
        return 0
    fi

    printf '\n'
    printf '%s\n' "  The following stopped containers will be removed:"
    for v in "${stopped[@]}"; do
        resolve_target "$v"
        printf '%s\n' "    • $v (${RESOLVED_DISPLAY_NAME})"
    done

    if [[ "$purge_data" == "true" ]]; then
        printf '\n'
        printf '%s\n' "  ${RED}${BOLD}Data directories will also be deleted:${RESET}"
        for v in "${stopped[@]}"; do
            if [[ -d "$SCRIPT_DIR/data/$v" ]]; then
                local size
                size=$(du -sh "$SCRIPT_DIR/data/$v" 2>/dev/null | awk '{print $1}')
                printf '%s\n' "    ${RED}• data/$v/ ($size)${RESET}"
            fi
        done
    fi

    printf '\n'
    printf '%s' "  Type 'yes' to confirm: "

    local confirm
    read -r confirm
    if [[ "$confirm" != "yes" ]]; then
        info "Canceled"
        return 0
    fi

    local freed_before
    freed_before=$(df "$SCRIPT_DIR" | tail -1 | awk '{print $4}')

    for v in "${stopped[@]}"; do
        info "Removing $v..."
        run_compose "$v" down "$v" 2>/dev/null || true
        if [[ "$purge_data" == "true" && -d "$SCRIPT_DIR/data/$v" ]]; then
            rm -rf "${SCRIPT_DIR:?}/data/$v"
            info "Deleted data/$v/"
        fi
        # Unregister instances and remove their compose files
        if is_instance "$v"; then
            rm -f "$INSTANCE_DIR/${v}.yml"
            unregister_instance "$v"
            info "Unregistered instance $v"
        fi
    done

    local freed_after
    freed_after=$(df "$SCRIPT_DIR" | tail -1 | awk '{print $4}')
    local freed_kb=$((freed_after - freed_before))
    local freed_mb=$((freed_kb / 1024))

    printf '\n'
    success "Cleaned ${#stopped[@]} container(s)"
    if ((freed_mb > 0)); then
        printf '%s\n' "  ${BOLD}Freed:${RESET} ${freed_mb}MB"
    fi
    printf '\n'

    invalidate_cache
}

# ==============================================================================
# OPEN COMMAND
# ==============================================================================

cmd_open() {
    local version="${1:-}"

    if [[ -z "$version" ]]; then
        die "Usage: ${SCRIPT_NAME} open <version|instance>"
    fi

    validate_target "$version" || exit 1
    resolve_target "$version"

    # Start container if not running
    if ! is_running "$version"; then
        printf '%s' "${YELLOW}[WARN]${RESET} $version is not running. Start it? [y/N]: "
        local confirm
        read -r confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            cmd_start "$version"
        else
            die "$version is not running"
        fi
    fi

    local url="http://localhost:${RESOLVED_WEB_PORT}"

    # Detect browser opener
    local opener=""
    if command -v xdg-open &>/dev/null; then
        opener="xdg-open"
    elif command -v open &>/dev/null; then
        opener="open"
    else
        info "Could not detect browser opener"
        info "Open manually: $url"
        return 0
    fi

    info "Opening $url ..."
    "$opener" "$url" &>/dev/null &

    detect_lan_ip
    if [[ -n "$LAN_IP" ]]; then
        printf '%s\n' "  ${DIM}LAN: http://${LAN_IP}:${RESOLVED_WEB_PORT}${RESET}"
    fi
}

# ==============================================================================
# INSTANCE COMMANDS
# ==============================================================================

cmd_new() {
    local version="$1"
    local suffix="${2:-}"
    local clone="${3:-false}"

    validate_version "$version" || exit 1

    # Determine instance name
    if [[ -z "$suffix" ]]; then
        suffix=$(next_instance_suffix "$version")
    fi
    local instance_name="${version}-${suffix}"

    # Check not already registered
    load_registry
    if [[ -n "${_REGISTRY_INSTANCES[$instance_name]:-}" ]]; then
        die "Instance '$instance_name' already exists"
    fi

    # Check ARM compatibility
    detect_arch
    if [[ "$DETECTED_ARCH" == "arm64" ]]; then
        if ! is_arm_supported "$version"; then
            die "${VERSION_DISPLAY_NAMES[$version]} ($version) is not supported on ARM64. Supported: ${ARM_VERSIONS[*]}"
        fi
    fi

    # Run prerequisite checks
    check_docker || exit 1
    check_kvm || exit 1

    header "Creating Instance: $instance_name"

    # Allocate ports
    local ports
    ports=$(allocate_instance_ports)
    local web_port rdp_port
    read -r web_port rdp_port <<< "$ports"

    info "Allocated ports — Web: $web_port, RDP: $rdp_port"

    # Generate compose file
    generate_instance_compose "$instance_name" "$version" "$web_port" "$rdp_port"
    info "Generated compose file: instances/${instance_name}.yml"

    # Create data directory
    local data_dir="$SCRIPT_DIR/data/$instance_name"
    mkdir -p "$data_dir"

    # Clone data from base if requested
    if [[ "$clone" == "true" ]]; then
        local base_data="$SCRIPT_DIR/data/$version"
        if [[ ! -d "$base_data" ]] || [[ -z "$(ls -A "$base_data" 2>/dev/null)" ]]; then
            warn "No data found for base $version to clone (data/$version/ is empty or missing)"
        else
            local was_running=false
            if is_running "$version"; then
                was_running=true
                info "Stopping base $version for cloning..."
                run_compose "$version" stop "$version"
            fi

            info "Cloning data from $version to $instance_name..."
            if cp -a "$base_data/." "$data_dir/"; then
                success "Data cloned successfully"
            else
                error "Failed to clone data"
            fi

            if [[ "$was_running" == "true" ]]; then
                info "Restarting base $version..."
                run_compose "$version" up -d "$version"
            fi
        fi
    else
        # Pre-populate from ISO cache if available (skip if cloning)
        local cache_src="$ISO_CACHE_DIR/$version"
        if [[ -d "$cache_src" ]]; then
            local cached_iso
            cached_iso=$(find "$cache_src" -maxdepth 1 -name '*.iso' -type f -print -quit 2>/dev/null || true)
            if [[ -n "$cached_iso" ]]; then
                local iso_name
                iso_name=$(basename "$cached_iso")
                info "Restoring cached ISO: $iso_name..."
                cp "$cached_iso" "$data_dir/$iso_name"
                success "ISO restored from cache (skipping download)"
            fi
        fi
    fi

    # Register instance
    register_instance "$instance_name" "$version" "$suffix" "$web_port" "$rdp_port"
    success "Instance registered"

    # Check resources
    local resource_type="${VERSION_RESOURCE_TYPE[$version]}"
    if [[ "$resource_type" == "modern" ]]; then
        check_memory "$MODERN_RAM_GB" || true
        check_disk "$MODERN_DISK_GB" || true
    else
        check_memory "$LEGACY_RAM_GB" || true
        check_disk "$LEGACY_DISK_GB" || true
    fi

    # Check ports are available
    if ! check_port "$web_port"; then
        error "Web port $web_port is already in use"
        return 1
    fi
    if ! check_port "$rdp_port"; then
        error "RDP port $rdp_port is already in use"
        return 1
    fi

    # Start the instance
    info "Starting $instance_name..."
    if run_compose "$instance_name" up -d "$instance_name"; then
        success "$instance_name started successfully"
    else
        error "Failed to start $instance_name"
        return 1
    fi

    # Show connection info
    detect_lan_ip
    printf '\n'
    printf '%s\n' "  ${BOLD}Instance:${RESET}     $instance_name"
    printf '%s\n' "  ${BOLD}Base:${RESET}         ${VERSION_DISPLAY_NAMES[$version]}"
    printf '\n'
    printf '%s\n' "  ${BOLD}Connection Details:${RESET}"
    printf '%s\n' "    → Web Viewer: ${CYAN}http://localhost:${web_port}${RESET}"
    printf '%s\n' "    → RDP:        ${CYAN}localhost:${rdp_port}${RESET}"
    if [[ -n "$LAN_IP" ]]; then
        printf '%s\n' "    → LAN Web:    ${CYAN}http://${LAN_IP}:${web_port}${RESET}"
        printf '%s\n' "    → LAN RDP:    ${CYAN}${LAN_IP}:${rdp_port}${RESET}"
    fi
    printf '\n'

    invalidate_cache
}

cmd_destroy() {
    local instance="${1:-}"

    if [[ -z "$instance" ]]; then
        die "Usage: ${SCRIPT_NAME} destroy <instance>"
    fi

    load_registry
    if [[ -z "${_REGISTRY_INSTANCES[$instance]:-}" ]]; then
        die "'$instance' is not a registered instance. Use '${SCRIPT_NAME} instances' to list instances."
    fi

    local base
    base=$(registry_get_field "$instance" "base")

    header "Destroy Instance: $instance"
    printf '\n'
    printf '%s\n' "  ${RED}${BOLD}WARNING: This will permanently remove instance '$instance'.${RESET}"
    printf '%s\n' "  ${RED}Base version: ${VERSION_DISPLAY_NAMES[$base]}${RESET}"
    printf '\n'
    printf '%s' "  Type 'yes' to confirm: "

    local confirm
    read -r confirm
    if [[ "$confirm" != "yes" ]]; then
        info "Canceled"
        return 0
    fi

    # Stop and remove container
    info "Stopping and removing $instance..."
    run_compose "$instance" down "$instance" 2>/dev/null || true

    # Delete compose file
    local compose_file="$INSTANCE_DIR/${instance}.yml"
    if [[ -f "$compose_file" ]]; then
        rm -f "$compose_file"
        info "Removed compose file"
    fi

    # Prompt to delete data directory
    local data_dir="$SCRIPT_DIR/data/$instance"
    if [[ -d "$data_dir" ]]; then
        local size
        size=$(du -sh "$data_dir" 2>/dev/null | awk '{print $1}')
        printf '\n'
        printf '%s' "  Delete data directory data/$instance/ ($size)? [y/N]: "
        local del_data
        read -r del_data
        if [[ "$del_data" =~ ^[Yy]$ ]]; then
            rm -rf "$data_dir"
            info "Deleted data/$instance/"
        else
            info "Data directory preserved at data/$instance/"
        fi
    fi

    # Unregister
    unregister_instance "$instance"
    success "Instance '$instance' destroyed"

    invalidate_cache
}

cmd_instances() {
    local filter_base="${1:-}"

    load_registry

    if [[ ${#_REGISTRY_INSTANCES[@]} -eq 0 ]]; then
        info "No instances registered"
        printf '%s\n' "  Create one with: ${SCRIPT_NAME} start <version> --new [name]"
        return 0
    fi

    header "Instances"

    # Refresh cache for status info
    refresh_status_cache

    printf '\n'
    printf "  %s%-20s %-10s %-10s %-8s %-8s %-20s%s\n" \
        "${BOLD}${DIM}" "INSTANCE" "BASE" "STATUS" "WEB" "RDP" "CREATED" "${RESET}"
    printf '%s\n' "  ${DIM}$(printf '─%.0s' {1..78})${RESET}"

    for name in "${!_REGISTRY_INSTANCES[@]}"; do
        local base web_port rdp_port created
        base=$(registry_get_field "$name" "base")
        web_port=$(registry_get_field "$name" "web_port")
        rdp_port=$(registry_get_field "$name" "rdp_port")
        created=$(registry_get_field "$name" "created")

        # Filter by base version if specified
        if [[ -n "$filter_base" && "$base" != "$filter_base" ]]; then
            continue
        fi

        local status
        status=$(get_status "$name")

        local status_color
        case "$status" in
            running) status_color="${GREEN}" ;;
            stopped|exited) status_color="${RED}" ;;
            *) status_color="${YELLOW}" ;;
        esac

        # Warn if compose file is missing
        local compose_file="$INSTANCE_DIR/${name}.yml"
        local orphan=""
        if [[ ! -f "$compose_file" ]]; then
            orphan=" ${RED}[orphaned]${RESET}"
        fi

        # Format created date (show date part only)
        local created_short="${created%%T*}"

        printf "  %-20s %-10s %s%-10s%s %-8s %-8s %-20s%b\n" \
            "$name" "$base" "$status_color" "$status" "${RESET}" "$web_port" "$rdp_port" "$created_short" "$orphan"
    done
    printf '\n'

    detect_lan_ip
    if [[ -n "$LAN_IP" ]]; then
        printf '%s\n' "  ${DIM}LAN IP: ${LAN_IP} — use http://${LAN_IP}:<web-port> for remote access${RESET}"
        printf '\n'
    fi
}

# ==============================================================================
# ISO CACHE
# ==============================================================================

# Check if an ISO has been rebuilt by the container (magic byte 0x16 at offset 0).
# Rebuilt ISOs cannot be re-processed by the container's install pipeline (7z
# fails on the duplicate boot catalog entry created by genisoimage).
_is_rebuilt_iso() {
    local iso="$1"
    local magic
    magic=$(dd if="$iso" bs=1 count=1 status=none 2>/dev/null | od -A n -t x1 -v | tr -d ' \n')
    [[ "$magic" == "16" ]]
}

# Non-interactive cache save — silently skips rebuilt ISOs and already-cached files.
# Used by cmd_stop() when AUTO_CACHE=Y.
auto_cache_save() {
    local target="$1"
    resolve_target "$target" || return 0

    local data_dir="$SCRIPT_DIR/data/$RESOLVED_NAME"
    local iso_files
    iso_files=$(find "$data_dir" -maxdepth 1 -name '*.iso' -type f 2>/dev/null || true)
    [[ -z "$iso_files" ]] && return 0

    local cache_dest="$ISO_CACHE_DIR/$RESOLVED_BASE"
    mkdir -p "$cache_dest"

    while IFS= read -r iso; do
        local filename
        filename=$(basename "$iso")
        # Skip rebuilt ISOs — they can't be re-processed by the container
        _is_rebuilt_iso "$iso" && continue
        if [[ ! -f "$cache_dest/$filename" ]]; then
            cp "$iso" "$cache_dest/$filename"
            info "Auto-cached ISO: $filename"
        fi
    done <<< "$iso_files"
}

cmd_cache() {
    local subcmd="${1:-}"
    shift || true

    case "$subcmd" in
        save)     cmd_cache_save "$@" ;;
        download) cmd_cache_download "$@" ;;
        list)     cmd_cache_list ;;
        rm)       cmd_cache_rm "$@" ;;
        flush)    cmd_cache_flush ;;
        "")
            error "Missing subcommand"
            printf '%s\n' "  Usage: ${SCRIPT_NAME} cache <save|download|list|rm|flush>"
            exit 1
            ;;
        *)
            error "Unknown cache subcommand: $subcmd"
            printf '%s\n' "  Usage: ${SCRIPT_NAME} cache <save|download|list|rm|flush>"
            exit 1
            ;;
    esac
}

cmd_cache_save() {
    local target="${1:-}"

    if [[ -z "$target" ]]; then
        die "Usage: ${SCRIPT_NAME} cache save <version|instance>"
    fi

    validate_target "$target" || exit 1
    resolve_target "$target"

    # Check container was created (same guard as snapshot)
    refresh_status_cache
    if ! container_exists "$RESOLVED_NAME"; then
        die "$RESOLVED_NAME was never created — nothing to cache"
    fi

    local data_dir="$SCRIPT_DIR/data/$RESOLVED_NAME"
    local iso_files
    iso_files=$(find "$data_dir" -maxdepth 1 -name '*.iso' -type f 2>/dev/null || true)

    if [[ -z "$iso_files" ]]; then
        die "No ISO files found in data/$RESOLVED_NAME/"
    fi

    local cache_dest="$ISO_CACHE_DIR/$RESOLVED_BASE"
    mkdir -p "$cache_dest"

    header "Cache Save: ${RESOLVED_DISPLAY_NAME}"

    local count=0
    local rebuilt=false
    while IFS= read -r iso; do
        local filename
        filename=$(basename "$iso")
        if _is_rebuilt_iso "$iso"; then
            warn "Skipping $filename — rebuilt ISO (cannot be re-processed)"
            rebuilt=true
            continue
        fi
        if [[ -f "$cache_dest/$filename" ]]; then
            info "Already cached: $filename"
        else
            info "Caching $filename..."
            cp "$iso" "$cache_dest/$filename"
            success "Cached $filename"
        fi
        local size
        size=$(du -h "$cache_dest/$filename" | awk '{print $1}')
        printf '%s\n' "    Size: $size"
        ((count++))
    done <<< "$iso_files"

    printf '\n'
    if (( count > 0 )); then
        success "Cached $count ISO file(s) to cache/$RESOLVED_BASE/"
    fi
    if [[ "$rebuilt" == true ]]; then
        warn "Some ISOs were skipped because they were rebuilt by the container."
        info "Use '${SCRIPT_NAME} cache download $RESOLVED_BASE' to download the original ISO."
    fi
    printf '\n'
}

cmd_cache_download() {
    local target="${1:-}"
    if [[ -z "$target" ]]; then
        error "Missing version"
        printf '%s\n' "  Usage: ${SCRIPT_NAME} cache download <version>"
        exit 1
    fi

    # Resolve the base version name
    local base="$target"
    if [[ -v VERSION_ENV_VALUES[$target] ]]; then
        base="$target"
    else
        # Try to find a matching version key
        local found=""
        for k in "${!VERSION_DISPLAY_NAMES[@]}"; do
            if [[ "$k" == "$target" ]]; then
                found="$k"
                break
            fi
        done
        [[ -n "$found" ]] && base="$found"
    fi

    # Use the container to resolve the download URL and filename
    local windows_image
    local resource_type="${VERSION_RESOURCE_TYPE[$base]:-modern}"
    if [[ "$resource_type" == "legacy" ]]; then
        windows_image=$(grep -E '^WINDOWS_IMAGE=' "$SCRIPT_DIR/.env.legacy" 2>/dev/null | tail -1 | cut -d'=' -f2- || true)
    else
        windows_image=$(grep -E '^WINDOWS_IMAGE=' "$SCRIPT_DIR/.env.modern" 2>/dev/null | tail -1 | cut -d'=' -f2- || true)
    fi
    windows_image="${windows_image:-dockurr/windows}"

    local version_env="${VERSION_ENV_VALUES[$base]:-$base}"

    header "Cache Download: ${VERSION_DISPLAY_NAMES[$base]:-$base}"

    info "Resolving download URL..."
    local iso_filename
    iso_filename=$(docker run --rm --entrypoint="" -e "VERSION=$version_env" "$windows_image" bash -c '
        set +eu
        APP="Windows"
        source /run/utils.sh 2>/dev/null
        source /run/define.sh 2>/dev/null
        parseVersion 2>/dev/null
        echo "${VERSION//\//}.iso"
    ' 2>/dev/null || true)

    if [[ -z "$iso_filename" ]]; then
        error "Could not resolve ISO filename for $base"
        exit 1
    fi

    local cache_dest="$ISO_CACHE_DIR/$base"
    mkdir -p "$cache_dest"

    if [[ -f "$cache_dest/$iso_filename" ]] && ! _is_rebuilt_iso "$cache_dest/$iso_filename"; then
        info "Already cached: $iso_filename"
        local size
        size=$(du -h "$cache_dest/$iso_filename" | awk '{print $1}')
        printf '%s\n' "    Size: $size"
        printf '\n'
        return 0
    fi

    # Run the container briefly to download the ISO, then copy from its tmp dir
    local tmp_dir
    tmp_dir=$(mktemp -d)

    info "Downloading original ISO (this may take a while)..."
    info "Using container to download ${VERSION_DISPLAY_NAMES[$base]:-$base}..."

    # Run container with storage mounted, let it download, then grab from tmp
    # The container downloads to /storage/tmp/<filename>.iso, so we watch for it
    local container_name="winctl-download-$$"
    docker run -d --rm --entrypoint="" \
        --name "$container_name" \
        -e "VERSION=$version_env" \
        -v "$tmp_dir:/storage" \
        "$windows_image" bash -c '
            set +eu
            APP="Windows"
            STORAGE="/storage"
            source /run/utils.sh 2>/dev/null
            source /run/define.sh 2>/dev/null
            source /run/mido.sh 2>/dev/null
            source /run/install.sh 2>/dev/null
            parseVersion 2>/dev/null
            BOOT="$STORAGE/${VERSION//\//}.iso"
            TMP="$STORAGE/tmp"
            mkdir -p "$TMP"
            ISO=$(basename "$BOOT")
            ISO="$TMP/$ISO"
            if [ -f "$BOOT" ] && [ -s "$BOOT" ]; then
                mv -f "$BOOT" "$ISO"
            fi
            if [ ! -s "$ISO" ] || [ ! -f "$ISO" ]; then
                downloadImage "$ISO" "$VERSION" "en" || exit 1
            fi
            # Signal completion — move ISO out of tmp to storage root
            cp "$ISO" "$BOOT"
        ' > /dev/null 2>&1

    # Wait for the download container to finish
    docker wait "$container_name" > /dev/null 2>&1

    # Check if the ISO was downloaded
    local downloaded_iso
    downloaded_iso=$(find "$tmp_dir" -maxdepth 1 -name '*.iso' -type f -print -quit 2>/dev/null || true)

    if [[ -z "$downloaded_iso" ]] || [[ ! -s "$downloaded_iso" ]]; then
        rm -rf "$tmp_dir"
        error "Failed to download ISO for $base"
        exit 1
    fi

    local dl_name
    dl_name=$(basename "$downloaded_iso")
    cp "$downloaded_iso" "$cache_dest/$dl_name"
    rm -rf "$tmp_dir"

    local size
    size=$(du -h "$cache_dest/$dl_name" | awk '{print $1}')

    printf '\n'
    success "Downloaded and cached: $dl_name ($size)"
    printf '\n'
}

cmd_cache_list() {
    if [[ ! -d "$ISO_CACHE_DIR" ]] || [[ -z "$(ls -A "$ISO_CACHE_DIR" 2>/dev/null)" ]]; then
        info "No cached ISOs"
        printf '%s\n' "  Cache ISOs with: ${SCRIPT_NAME} cache save <version>"
        return 0
    fi

    header "ISO Cache"

    local total_size=0
    local found=false

    for dir in "$ISO_CACHE_DIR"/*/; do
        [[ -d "$dir" ]] || continue
        local base
        base=$(basename "$dir")
        local display="${VERSION_DISPLAY_NAMES[$base]:-$base}"

        local iso_files
        iso_files=$(find "$dir" -maxdepth 1 -name '*.iso' -type f 2>/dev/null || true)
        if [[ -z "$iso_files" ]]; then
            continue
        fi

        found=true
        printf '\n'
        printf '  %s%s%s (%s)\n' "${BOLD}" "$base" "${RESET}" "$display"

        while IFS= read -r iso; do
            local filename size size_bytes
            filename=$(basename "$iso")
            size=$(du -h "$iso" | awk '{print $1}')
            size_bytes=$(du -b "$iso" | awk '{print $1}')
            total_size=$((total_size + size_bytes))
            printf '    %s  %s\n' "$size" "$filename"
        done <<< "$iso_files"
    done

    if [[ "$found" == "false" ]]; then
        info "No cached ISOs"
        return 0
    fi

    # Format total size
    local total_human
    if ((total_size >= 1073741824)); then
        total_human="$(awk "BEGIN {printf \"%.1fG\", $total_size / 1073741824}")"
    elif ((total_size >= 1048576)); then
        total_human="$(awk "BEGIN {printf \"%.1fM\", $total_size / 1048576}")"
    else
        total_human="${total_size}B"
    fi

    printf '\n'
    printf '  %s%s%s %s\n' "${DIM}" "$(printf '─%.0s' {1..40})" "${RESET}" ""
    printf '  %sTotal: %s%s\n' "${BOLD}" "$total_human" "${RESET}"
    printf '\n'
}

cmd_cache_rm() {
    local version="${1:-}"

    if [[ -z "$version" ]]; then
        die "Usage: ${SCRIPT_NAME} cache rm <version>"
    fi

    # Validate it's a known base version
    if [[ -z "${VERSION_COMPOSE_FILES[$version]:-}" ]]; then
        die "Unknown version: $version. Run '${SCRIPT_NAME} list' to see available versions."
    fi

    local cache_dir="$ISO_CACHE_DIR/$version"
    if [[ ! -d "$cache_dir" ]] || [[ -z "$(ls -A "$cache_dir" 2>/dev/null)" ]]; then
        die "No cached ISOs for $version"
    fi

    local display="${VERSION_DISPLAY_NAMES[$version]:-$version}"

    header "Remove Cached ISOs: $display"

    # Show what will be removed
    printf '\n'
    local iso_files
    iso_files=$(find "$cache_dir" -maxdepth 1 -name '*.iso' -type f 2>/dev/null || true)
    while IFS= read -r iso; do
        local filename size
        filename=$(basename "$iso")
        size=$(du -h "$iso" | awk '{print $1}')
        printf '  %s  %s\n' "$size" "$filename"
    done <<< "$iso_files"

    local dir_size
    dir_size=$(du -sh "$cache_dir" | awk '{print $1}')
    printf '\n'
    printf '%s\n' "  ${RED}${BOLD}This will remove $dir_size of cached ISOs for $version.${RESET}"
    printf '\n'
    printf '%s' "  Type 'yes' to confirm: "

    local confirm
    read -r confirm
    if [[ "$confirm" != "yes" ]]; then
        info "Canceled"
        return 0
    fi

    rm -rf "$cache_dir"
    success "Removed cached ISOs for $version"
}

cmd_cache_flush() {
    if [[ ! -d "$ISO_CACHE_DIR" ]] || [[ -z "$(ls -A "$ISO_CACHE_DIR" 2>/dev/null)" ]]; then
        info "Cache is already empty"
        return 0
    fi

    header "Flush ISO Cache"

    local total_size
    total_size=$(du -sh "$ISO_CACHE_DIR" | awk '{print $1}')

    printf '\n'
    printf '%s\n' "  ${RED}${BOLD}This will remove all cached ISOs ($total_size).${RESET}"
    printf '\n'
    printf '%s' "  Type 'yes' to confirm: "

    local confirm
    read -r confirm
    if [[ "$confirm" != "yes" ]]; then
        info "Canceled"
        return 0
    fi

    rm -rf "${ISO_CACHE_DIR:?}/"*
    success "ISO cache flushed"
}

# ==============================================================================
# HELP
# ==============================================================================

# Print a help row: _help_row "cmd args" "description"
# Uses fixed-width column so descriptions align regardless of ANSI bold codes.
_help_row() {
    local cmd="$1" desc="$2"
    printf '    %b%-24s%b%s\n' "${BOLD}" "$cmd" "${RESET}" "$desc"
}

show_usage() {
    local topic="${1:-}"

    case "$topic" in
        commands)   _help_topic_commands ;;
        instances)  _help_topic_instances ;;
        cache)      _help_topic_cache ;;
        examples)   _help_topic_examples ;;
        config)     _help_topic_config ;;
        all)        _help_all ;;
        "")         _help_summary ;;
        *)
            error "Unknown help topic: $topic"
            printf '%s\n' "  Available topics: commands, instances, cache, examples, config, all"
            exit 1
            ;;
    esac
}

_help_summary() {
    printf '%b\n' "${BOLD}${SCRIPT_NAME}${RESET} v${SCRIPT_VERSION} - Windows Docker Container Management"
    printf '\n'
    printf '%b\n' "${BOLD}USAGE${RESET}"
    printf '    %s <command> [options]\n' "${SCRIPT_NAME}"
    printf '\n'
    printf '%b\n' "${BOLD}COMMANDS${RESET}"
    _help_row "start [version...]"      "Start container(s), interactive if no version"
    _help_row "stop [version...|all]"   "Stop container(s) or all running"
    _help_row "restart [version...]"    "Restart container(s)"
    _help_row "status [version...]"     "Show status of container(s)"
    _help_row "logs <version> [-f]"     "View container logs (-f to follow)"
    _help_row "shell <version>"         "Open bash shell in container"
    _help_row "stats [version...]"      "Show real-time resource usage"
    _help_row "build"                   "Build Docker image locally"
    _help_row "rebuild [version...]"    "Destroy and recreate container(s)"
    _help_row "list [category]"         "List versions (desktop/legacy/server/tiny/all)"
    _help_row "inspect <version>"       "Show detailed container info"
    _help_row "monitor [interval]"      "Real-time dashboard (default: 5s refresh)"
    _help_row "check"                   "Run prerequisites check"
    _help_row "refresh"                 "Force refresh status cache"
    _help_row "open <version>"          "Open web viewer in browser"
    _help_row "pull"                    "Pull latest Docker image"
    _help_row "disk [version...]"       "Show disk usage per VM"
    _help_row "snapshot <ver> [name]"   "Back up VM data directory"
    _help_row "restore <ver> [name]"    "Restore VM data from snapshot"
    _help_row "clean [--data]"          "Remove stopped containers"
    _help_row "destroy <instance>"      "Permanently remove an instance"
    _help_row "instances [base]"        "List all registered instances"
    _help_row "cache <sub>"             "Manage ISO cache (download/save/list/rm/flush)"
    _help_row "help [topic]"            "Show help (topics below, or 'all')"
    printf '\n'
    printf '%b\n' "${BOLD}QUICK START${RESET}"
    printf '    %s start win11             # Start Windows 11\n' "${SCRIPT_NAME}"
    printf '    %s status                  # Show all containers\n' "${SCRIPT_NAME}"
    printf '    %s stop win11              # Stop with confirmation\n' "${SCRIPT_NAME}"
    printf '\n'

    # Interactive menu only when running directly in a terminal
    if _is_interactive; then
        _help_interactive_menu
    else
        printf '  Topics: commands, instances, cache, examples, config, all\n'
        printf '\n'
    fi
}

# Check if the script is running interactively (not piped, not inside
# another script, not in a CI/batch environment).
_is_interactive() {
    [[ -t 0 ]] && [[ -t 1 ]] || return 1
    [[ "${TERM:-dumb}" != "dumb" ]] || return 1
    [[ -z "${CI:-}" ]] && [[ -z "${BATCH:-}" ]] && [[ -z "${NONINTERACTIVE:-}" ]] || return 1
    return 0
}

_help_interactive_menu() {
    while true; do
        printf '%b\n' "${BOLD}MORE HELP${RESET}"
        printf '    1) Commands      Full command reference\n'
        printf '    2) Instances     Multi-instance support\n'
        printf '    3) Cache         ISO cache management\n'
        printf '    4) Examples      Usage examples\n'
        printf '    5) Config        Environment settings\n'
        printf '    6) All           Show everything\n'
        printf '\n'
        printf '%s' "  Select [1-6] or Enter to exit: "

        local choice
        read -r choice

        case "$choice" in
            1) printf '\n'; _help_topic_commands ;;
            2) printf '\n'; _help_topic_instances ;;
            3) printf '\n'; _help_topic_cache ;;
            4) printf '\n'; _help_topic_examples ;;
            5) printf '\n'; _help_topic_config ;;
            6) printf '\n'; _help_all; return 0 ;;
            "") return 0 ;;
            *)  warn "Invalid choice: $choice"; printf '\n' ;;
        esac
    done
}

_help_topic_commands() {
    printf '%b\n' "${BOLD}COMMANDS${RESET}"
    printf '\n'
    _help_row "start [version...]"      "Start container(s), interactive if no version"
    _help_row "stop [version...|all]"   "Stop container(s) or all running"
    _help_row "restart [version...]"    "Restart container(s)"
    _help_row "status [version...]"     "Show status of container(s)"
    _help_row "logs <version> [-f]"     "View container logs (-f to follow)"
    _help_row "shell <version>"         "Open bash shell in container"
    _help_row "stats [version...]"      "Show real-time resource usage"
    _help_row "build"                   "Build Docker image locally"
    _help_row "rebuild [version...]"    "Destroy and recreate container(s)"
    _help_row "list [category]"         "List versions (desktop/legacy/server/tiny/all)"
    _help_row "inspect <version>"       "Show detailed container info"
    _help_row "monitor [interval]"      "Real-time dashboard (default: 5s refresh)"
    _help_row "check"                   "Run prerequisites check"
    _help_row "refresh"                 "Force refresh status cache"
    _help_row "open <version>"          "Open web viewer in browser"
    _help_row "pull"                    "Pull latest Docker image"
    _help_row "disk [version...]"       "Show disk usage per VM"
    _help_row "snapshot <ver> [name]"   "Back up VM data directory"
    _help_row "restore <ver> [name]"    "Restore VM data from snapshot"
    _help_row "clean [--data]"          "Remove stopped containers"
    _help_row "destroy <instance>"      "Permanently remove an instance"
    _help_row "instances [base]"        "List all registered instances"
    _help_row "cache <sub>"             "Manage ISO cache (download/save/list/rm/flush)"
    _help_row "help [topic]"            "Show help (topics: commands, instances, cache, examples, config, all)"
    printf '\n'
    printf '%b\n' "${BOLD}CATEGORIES${RESET}"
    printf '    desktop    Win 11/10/8.1/7 (Pro, Enterprise, LTSC variants)\n'
    printf '    legacy     Vista, XP, 2000\n'
    printf '    server     Server 2025/2022/2019/2016/2012/2008/2003\n'
    printf '    tiny       Tiny11, Tiny10\n'
    printf '\n'
    printf '%b\n' "${BOLD}PORTS${RESET}"
    printf '    Each version has unique ports for Web UI and RDP access.\n'
    printf '    Instances auto-allocate ports from 9000+ (web) and 4000+ (RDP).\n'
    printf "    Run '%s list' to see port mappings.\n" "${SCRIPT_NAME}"
    printf '\n'
    printf '%b\n' "${BOLD}ARM64 SUPPORT${RESET}"
    printf '    Auto-detected via uname. Only Win 10/11 variants supported on ARM64.\n'
    printf '    Set WINDOWS_IMAGE=dockurr/windows-arm in .env.modern or .env.legacy.\n'
    printf "    Run '%s check' to see detected architecture.\n" "${SCRIPT_NAME}"
    printf '\n'
}

_help_topic_instances() {
    printf '%b\n' "${BOLD}INSTANCE FLAGS (used with start)${RESET}"
    printf '\n'
    _help_row "--new"          "Create a new instance of a version"
    _help_row "--new [name]"   "Name the instance (default: auto-numbered)"
    _help_row "--clone"        "Clone data from base version to new instance"
    printf '\n'
    printf '%b\n' "${BOLD}INSTANCE EXAMPLES${RESET}"
    printf '\n'
    printf '    %s start winxp --new              # Create winxp-1 with auto ports\n' "${SCRIPT_NAME}"
    printf '    %s start winxp --new lab          # Create winxp-lab\n' "${SCRIPT_NAME}"
    printf '    %s start winxp --new lab --clone  # Clone base data\n' "${SCRIPT_NAME}"
    printf '    %s stop winxp-lab                 # Stop instance\n' "${SCRIPT_NAME}"
    printf '    %s instances                      # List all instances\n' "${SCRIPT_NAME}"
    printf '    %s destroy winxp-lab              # Remove instance\n' "${SCRIPT_NAME}"
    printf '\n'
}

_help_topic_cache() {
    printf '%b\n' "${BOLD}CACHE COMMANDS${RESET}"
    printf '\n'
    _help_row "cache download <version>" "Download original ISO to cache"
    _help_row "cache save <version>"     "Cache ISOs from a VM data directory"
    _help_row "cache list"               "Show all cached ISOs with sizes"
    _help_row "cache rm <version>"       "Remove cached ISOs for a version"
    _help_row "cache flush"              "Clear all cached ISOs"
    printf '\n'
    printf '%b\n' "${BOLD}CACHE EXAMPLES${RESET}"
    printf '\n'
    printf '    %s cache download winxp    # Download original XP ISO to cache\n' "${SCRIPT_NAME}"
    printf '    %s cache list              # Show cached ISOs\n' "${SCRIPT_NAME}"
    printf '    %s start winxp --new       # New instance uses cached ISO\n' "${SCRIPT_NAME}"
    printf '    %s cache rm winxp          # Remove cached winxp ISO\n' "${SCRIPT_NAME}"
    printf '    %s cache flush             # Clear all cached ISOs\n' "${SCRIPT_NAME}"
    printf '\n'
    printf '%b\n' "${BOLD}HOW IT WORKS${RESET}"
    printf '\n'
    printf '    The cache stores original (unprocessed) ISOs. When creating a new\n'
    printf '    instance, the cached ISO is copied to the data directory. The container\n'
    printf '    processes it locally (extract, inject drivers, answer file) without\n'
    printf '    needing to re-download.\n'
    printf '\n'
    printf '    Use "cache download" to pre-download ISOs. "cache save" only works\n'
    printf '    if the data directory has an unprocessed ISO (skips rebuilt ones).\n'
    printf '\n'
}

_help_topic_examples() {
    printf '%b\n' "${BOLD}EXAMPLES${RESET}"
    printf '\n'
    printf '    %s start                   # Interactive menu\n' "${SCRIPT_NAME}"
    printf '    %s start win11             # Start Windows 11\n' "${SCRIPT_NAME}"
    printf '    %s start win11 win10       # Start multiple\n' "${SCRIPT_NAME}"
    printf '    %s stop win11              # Stop with confirmation\n' "${SCRIPT_NAME}"
    printf '    %s stop all                # Stop all running\n' "${SCRIPT_NAME}"
    printf '    %s status                  # Show all containers\n' "${SCRIPT_NAME}"
    printf '    %s logs win11 -f           # Follow logs\n' "${SCRIPT_NAME}"
    printf '    %s list desktop            # List desktop versions\n' "${SCRIPT_NAME}"
    printf '    %s monitor 10              # Dashboard with 10s refresh\n' "${SCRIPT_NAME}"
    printf '    %s rebuild win11           # Recreate container\n' "${SCRIPT_NAME}"
    printf '    %s open win11              # Open web viewer in browser\n' "${SCRIPT_NAME}"
    printf '    %s pull                    # Pull latest image\n' "${SCRIPT_NAME}"
    printf '    %s disk                    # Show disk usage\n' "${SCRIPT_NAME}"
    printf '    %s snapshot win11          # Back up VM data\n' "${SCRIPT_NAME}"
    printf '    %s restore win11           # Restore from snapshot\n' "${SCRIPT_NAME}"
    printf '    %s clean                   # Remove stopped containers\n' "${SCRIPT_NAME}"
    printf '\n'
    printf '%b\n' "${BOLD}INSTANCE EXAMPLES${RESET}"
    printf '\n'
    printf '    %s start winxp --new              # Create winxp-1 with auto ports\n' "${SCRIPT_NAME}"
    printf '    %s start winxp --new lab          # Create winxp-lab\n' "${SCRIPT_NAME}"
    printf '    %s start winxp --new lab --clone  # Clone base data\n' "${SCRIPT_NAME}"
    printf '    %s stop winxp-lab                 # Stop instance\n' "${SCRIPT_NAME}"
    printf '    %s instances                      # List all instances\n' "${SCRIPT_NAME}"
    printf '    %s destroy winxp-lab              # Remove instance\n' "${SCRIPT_NAME}"
    printf '\n'
    printf '%b\n' "${BOLD}CACHE EXAMPLES${RESET}"
    printf '\n'
    printf '    %s cache save winxp        # Cache ISO after first download\n' "${SCRIPT_NAME}"
    printf '    %s cache list              # Show cached ISOs\n' "${SCRIPT_NAME}"
    printf '    %s cache rm winxp          # Remove cached winxp ISO\n' "${SCRIPT_NAME}"
    printf '    %s cache flush             # Clear all cached ISOs\n' "${SCRIPT_NAME}"
    printf '\n'
}

_help_topic_config() {
    printf '%b\n' "${BOLD}CONFIGURATION${RESET}"
    printf '\n'
    printf '  Two env files control per-VM resources (used by compose files):\n'
    printf '\n'
    _help_row ".env.modern"    "8G RAM, 4 CPU, 128G disk — Win 10/11, Server 2016+"
    _help_row ".env.legacy"    "2G RAM, 2 CPU, 32G disk — Win 7/8, Vista, XP, 2000, Tiny"
    printf '\n'
    printf '  Global winctl settings (in .env):\n'
    printf '\n'
    _help_row "AUTO_CACHE=Y|N"  "Auto-cache ISOs on stop (default: N)"
    printf '\n'
    printf '%b\n' "${BOLD}VM SETTINGS (in .env.modern / .env.legacy)${RESET}"
    printf '\n'
    _help_row "RAM_SIZE"        "Memory allocation (e.g. 8G)"
    _help_row "CPU_CORES"       "CPU cores (e.g. 4)"
    _help_row "DISK_SIZE"       "Virtual disk size (e.g. 128G)"
    _help_row "USERNAME"        "Windows username (default: Docker)"
    _help_row "PASSWORD"        "Windows password (default: admin)"
    _help_row "LANGUAGE"        "Installation language (default: en)"
    _help_row "REGION"          "Region setting (default: en-US)"
    _help_row "KEYBOARD"        "Keyboard layout (default: en-US)"
    _help_row "WIDTH"           "Display width (default: 1280)"
    _help_row "HEIGHT"          "Display height (default: 720)"
    _help_row "DHCP"            "Use DHCP networking (default: N)"
    _help_row "SAMBA"           "Enable file sharing (default: Y)"
    _help_row "RESTART_POLICY"  "Container restart policy (default: on-failure)"
    _help_row "DEBUG"           "Debug mode (default: N)"
    _help_row "WINDOWS_IMAGE"   "Docker image (default: dockurr/windows)"
    printf '\n'
}

_help_all() {
    _help_summary
    _help_topic_commands
    _help_topic_instances
    _help_topic_cache
    _help_topic_examples
    _help_topic_config
}

# ==============================================================================
# MAIN
# ==============================================================================

main() {
    # Change to script directory
    cd "$SCRIPT_DIR"

    local command="${1:-}"
    shift || true

    case "$command" in
        start)      cmd_start "$@" ;;
        stop)       cmd_stop "$@" ;;
        restart)    cmd_restart "$@" ;;
        status)     cmd_status "$@" ;;
        logs)       cmd_logs "$@" ;;
        shell)      cmd_shell "$@" ;;
        stats)      cmd_stats "$@" ;;
        build)      cmd_build "$@" ;;
        rebuild)    cmd_rebuild "$@" ;;
        list)       cmd_list "$@" ;;
        inspect)    cmd_inspect "$@" ;;
        monitor)    cmd_monitor "$@" ;;
        check)      cmd_check "$@" ;;
        refresh)    cmd_refresh "$@" ;;
        open)       cmd_open "$@" ;;
        pull)       cmd_pull "$@" ;;
        disk)       cmd_disk "$@" ;;
        snapshot)   cmd_snapshot "$@" ;;
        restore)    cmd_restore "$@" ;;
        clean)      cmd_clean "$@" ;;
        destroy)    cmd_destroy "$@" ;;
        instances)  cmd_instances "$@" ;;
        cache)      cmd_cache "$@" ;;
        help|--help|-h)
            show_usage "$@"
            ;;
        "")
            show_usage
            exit 1
            ;;
        *)
            error "Unknown command: $command"
            printf '%s\n' "Run '${SCRIPT_NAME} help' for usage information"
            exit 1
            ;;
    esac
}

main "$@"

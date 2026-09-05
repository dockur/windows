#!/usr/bin/env bash
set -Eeuo pipefail

# Docker environment variables

: "${VGA:=""}"                # VGA adapter
: "${GPU:=""}"                # GPU acceleration
: "${HELIOS:=""}"             # Enable Helios
: "${DISPLAY:="web"}"         # Display type
: "${LOSSY:="N"}"             # Lossy VNC compression
: "${VNC_PORT:="5900"}"       # VNC port
: "${RENDERNODE:=""}"         # Render node
: "${VRAM_SIZE:="4G"}"        # VirtIO GPU memory budget

# Sanitize variables
VGA=$(strip "$VGA")
LOSSY=$(strip "$LOSSY")
DISPLAY=$(strip "$DISPLAY")
VNC_PORT=$(strip "$VNC_PORT")
VRAM_SIZE=$(strip "$VRAM_SIZE")
RENDERNODE=$(strip "$RENDERNODE")
WSS_SOCKET="${WSS_SOCKET:-$QEMU_DIR/vnc-ws.sock}"

if [ -z "$VGA" ]; then

  if enabled "$HELIOS"; then

    GPU="Y"
    VGA="virtio"

  else

    VGA="vmware"

    if ! enabled "$GPU"; then

      version_file="$(stateFile "ver")"

      if [ -s "$version_file" ]; then

        version_installed=""
        IFS= read -r version_installed < "$version_file" || version_installed=""

        if [[ "$version_installed" =~ ^([0-9]+)\.([0-9]+) ]]; then

          major=$((10#${BASH_REMATCH[1]}))
          minor=$((10#${BASH_REMATCH[2]}))

          if (( major < 6 || (major == 6 && minor < 6) )); then
            (( major > 0 )) && VGA="virtio"
          fi

        fi
      fi
    fi

  fi
fi

VGA_DEVICE="${VGA%%,*}"
VGA_OPTIONS="${VGA#"$VGA_DEVICE"}"

case "${VGA_DEVICE,,}" in
  "std" | "vga" )
    VGA_DEVICE="VGA"
    VGA_ARG="-device" ;;
  "vmware" | "vmware-svga" )
    VGA_DEVICE="vmware-svga"
    VGA_ARG="-device" ;;
  "virtio" )
    VGA_DEVICE="virtio-vga"
    VGA_ARG="-device" ;;
  "virtio-"* )
    VGA_DEVICE="${VGA_DEVICE,,}"
    VGA_ARG="-device" ;;
  * )
    VGA_ARG="-vga" ;;
esac

VGA="${VGA_DEVICE}${VGA_OPTIONS}"
VGA_ARG+=" ${VGA}"

# QEMU accepts a VNC display number rather than a TCP port,
# so translate the configured port back to its :N display index.
port=$(( VNC_PORT - 5900 ))

LOSSY_OPT=""
enabled "$LOSSY" && LOSSY_OPT=",lossy=on"

# Preserve the historic :0 setting as an alias for the managed web display.
[[ "$DISPLAY" == ":0" ]] && DISPLAY="web"

case "${DISPLAY,,}" in

  "vnc" )
    DISPLAY_OPTS="-display vnc=:${port}${LOSSY_OPT} ${VGA_ARG}" ;;
  "web" )
    DISPLAY_OPTS="-display vnc=:${port},websocket=unix:${WSS_SOCKET}${LOSSY_OPT} ${VGA_ARG}" ;;
  "disabled" )
    DISPLAY_OPTS="-display none ${VGA_ARG}" ;;
  "none" )
    DISPLAY_OPTS="-display none -vga none" ;;
  *)
    DISPLAY_OPTS="-display ${DISPLAY} ${VGA_ARG}" ;;

esac

gpuSetupFailure() {

  local reason="$1"

  error "$reason"
  exit 87
}

vmwareLibraryPath() {

  local library="$1"
  local path=""

  if command -v ldconfig >/dev/null 2>&1; then
    path="$(ldconfig -p 2>/dev/null | awk -v library="$library" '$1 == library && !found { print $NF; found = 1 }')"
    if [ -n "$path" ] && [ -r "$path" ]; then
      printf '%s\n' "$path"
      return 0
    fi
  fi

  for path in /usr/lib/*/"$library" /usr/lib/"$library" /usr/lib64/"$library" \
              /usr/local/lib/*/"$library" /usr/local/lib/"$library" /usr/local/lib64/"$library"; do
    [ -r "$path" ] || continue
    printf '%s\n' "$path"
    return 0
  done

  return 1
}

vmwareLibraryReady() {

  local library="$1"
  local path=""
  local dependencies=""
  VMWARE_LIBRARY_REASON=""

  if ! path="$(vmwareLibraryPath "$library")"; then
    VMWARE_LIBRARY_REASON="the $library runtime library is not available in the container"
    return 1
  fi

  if command -v ldd >/dev/null 2>&1; then
    dependencies="$(ldd "$path" 2>&1 || true)"
    if grep -q '=> not found' <<< "$dependencies"; then
      VMWARE_LIBRARY_REASON="$library has missing runtime dependencies"
      return 1
    fi
  fi

  return 0
}

# VMVGA lets DXVK select the Vulkan device itself, so this render node is only
# a host-GPU sanity check and is never passed to QEMU or DXVK.
vmwareRenderNodeReady() {

  local node gpu_fd
  VMWARE_RENDER_NODE=""
  VMWARE_RENDER_NODE_FOUND="N"
  VMWARE_RENDER_REASON=""

  if [ ! -d /dev/dri ]; then
    VMWARE_RENDER_REASON="'/dev/dri' was not added to the devices section of your compose file"
    return 1
  fi

  for node in /dev/dri/renderD*; do

    [ -e "$node" ] || continue
    VMWARE_RENDER_NODE_FOUND="Y"
    [ -c "$node" ] || continue

    if { exec {gpu_fd}<>"$node"; } 2>/dev/null; then
      { exec {gpu_fd}>&-; } 2>/dev/null || true
      VMWARE_RENDER_NODE="$node"
      return 0
    fi

  done

  if [[ "$VMWARE_RENDER_NODE_FOUND" != "Y" ]]; then
    VMWARE_RENDER_REASON="/dev/dri is available, but no GPU render nodes were found"
  else
    VMWARE_RENDER_REASON="no accessible GPU render node was found"
  fi

  return 1
}

vmwareVersionAtLeast() {

  local version="$1"
  local required_major="$2"
  local required_minor="$3"
  local major minor

  IFS='.' read -r major minor _ <<< "$version"
  [[ "$major" =~ ^[0-9]+$ && "$minor" =~ ^[0-9]+$ ]] || return 1

  (( major > required_major || (major == required_major && minor >= required_minor) ))
}

# Match the VMVGA renderer preflight: Vulkan 1.3, its headless WSI instance
# extensions, and the device extensions required by the DXVK D3D9 backend.
vmwareVulkanReady() {

  local summary details loader selected extension
  local api type name driver
  VMWARE_VULKAN_REASON=""

  if ! command -v vulkaninfo >/dev/null 2>&1; then
    VMWARE_VULKAN_REASON="vulkaninfo is not available in the container"
    return 1
  fi

  if ! summary="$(vulkaninfo --summary 2>&1)"; then
    VMWARE_VULKAN_REASON="Vulkan device enumeration failed"
    return 1
  fi

  loader="$(sed -n 's/^Vulkan Instance Version:[[:space:]]*//p' <<< "$summary")"
  if [ -z "$loader" ] || ! vmwareVersionAtLeast "$loader" 1 3; then
    VMWARE_VULKAN_REASON="Vulkan 1.3 or newer is required by VMVGA"
    return 1
  fi

  selected="$(awk '
    function emit() {
      if (found || !in_gpu || api == "" || type == "") {
        return
      }

      split(api, version, ".")
      if (type != "PHYSICAL_DEVICE_TYPE_CPU" &&
          (version[1] > 1 || (version[1] == 1 && version[2] >= 3))) {
        print api "|" type "|" name "|" driver
        found = 1
      }
    }

    /^GPU[0-9]+:/ {
      emit()
      in_gpu = 1
      api = ""
      type = ""
      name = ""
      driver = ""
      next
    }

    in_gpu && /^[[:space:]]*apiVersion[[:space:]]*=/ {
      api = $0
      sub(/^.*=[[:space:]]*/, "", api)
      if (match(api, /\([0-9]+\.[0-9]+(\.[0-9]+)?\)/)) {
        api = substr(api, RSTART + 1, RLENGTH - 2)
      } else {
        sub(/[[:space:]].*$/, "", api)
      }
      next
    }

    in_gpu && /^[[:space:]]*deviceType[[:space:]]*=/ {
      type = $0
      sub(/^.*=[[:space:]]*/, "", type)
      sub(/[[:space:]].*$/, "", type)
      next
    }

    in_gpu && /^[[:space:]]*deviceName[[:space:]]*=/ {
      name = $0
      sub(/^.*=[[:space:]]*/, "", name)
      next
    }

    in_gpu && /^[[:space:]]*driverName[[:space:]]*=/ {
      driver = $0
      sub(/^.*=[[:space:]]*/, "", driver)
      next
    }

    END { emit() }
  ' <<< "$summary")"

  if [ -z "$selected" ]; then
    VMWARE_VULKAN_REASON="no Vulkan 1.3 capable hardware device was found"
    return 1
  fi

  IFS='|' read -r api type name driver <<< "$selected"

  if ! details="$(vulkaninfo 2>&1)"; then
    VMWARE_VULKAN_REASON="Vulkan capability enumeration failed"
    return 1
  fi

  for extension in VK_KHR_surface VK_EXT_headless_surface; do
    if ! grep -Eq "^[[:space:]]*${extension}[[:space:]:]" <<< "$details"; then
      VMWARE_VULKAN_REASON="the Vulkan loader does not support $extension required by VMVGA"
      return 1
    fi
  done

  for extension in VK_KHR_maintenance5 VK_EXT_robustness2; do
    if ! grep -Eq "^[[:space:]]*${extension}[[:space:]:]" <<< "$details"; then
      VMWARE_VULKAN_REASON="no Vulkan device exposes $extension required by VMVGA"
      return 1
    fi
  done

  VMWARE_VULKAN_API="$api"
  VMWARE_VULKAN_DEVICE="$name"
  VMWARE_VULKAN_DRIVER="$driver"
  return 0
}

vmwareGpuSetup() {

  VMWARE_LIBRARY_REASON=""
  VMWARE_RENDER_REASON=""
  VMWARE_VULKAN_REASON=""

  if ! vmwareRenderNodeReady; then
    gpuSetupFailure "VMware GPU acceleration requires a usable host GPU, but $VMWARE_RENDER_REASON"
  fi

  local library
  for library in libvulkan.so.1 libdxvk_d3d9.so.0 libdxvk_d3d11.so.0; do
    if ! vmwareLibraryReady "$library"; then
      gpuSetupFailure "VMware GPU acceleration is unavailable because $VMWARE_LIBRARY_REASON"
    fi
  done

  if ! vmwareVulkanReady; then
    gpuSetupFailure "VMware GPU acceleration is unavailable because $VMWARE_VULKAN_REASON"
  fi

  echo
  info "Hardware rendering enabled:"
  info
  info "Device:     ${VMWARE_VULKAN_DEVICE:-GPU}"
  [ -n "${VMWARE_VULKAN_DRIVER:-}" ] && info "Driver:     $VMWARE_VULKAN_DRIVER"
  info "Vulkan:     $VMWARE_VULKAN_API"

  return 0
}

enabled "$GPU" || return 0

msg="Configuring display drivers..."
enabled "$DEBUG" && echo "$msg"

if [[ "$ARCH" != "amd64" ]]; then
  gpuSetupFailure "GPU acceleration is only supported for the AMD64 platform"
fi

if [[ "${VGA_DEVICE,,}" == "vmware-svga" ]]; then
  vmwareGpuSetup
  return 0
fi

if [[ "${BOOT_MODE:-}" == "windows_legacy" ]]; then
  gpuSetupFailure "GPU acceleration is not supported by your Windows version"
  return 0
fi

case "${VGA_DEVICE,,}" in
  "none" )
    VGA_DEVICE="virtio-gpu-gl" ;;
  "virtio-vga" )
    VGA_DEVICE="virtio-vga-gl" ;;
  "virtio-gpu" )
    VGA_DEVICE="virtio-gpu-gl" ;;
  "virtio-vga-gl"* | "virtio-gpu-gl"* ) ;;
  * )
    gpuSetupFailure "GPU acceleration requires a VirtIO GPU display, but VGA='$VGA'"
    return 0 ;;
esac

VGA="${VGA_DEVICE}${VGA_OPTIONS}"

VRAM_SIZE="${VRAM_SIZE// /}"
[ -z "$VRAM_SIZE" ] && VRAM_SIZE="4G"

# Match the size conventions used by RAM_SIZE: small bare values are GiB,
# while larger bare values remain MiB for compatibility with numeric settings.
if [ -z "${VRAM_SIZE//[0-9. ]}" ]; then
  [ "${VRAM_SIZE%%.*}" -lt "130" ] && VRAM_SIZE="${VRAM_SIZE}G" || VRAM_SIZE="${VRAM_SIZE}M"
fi

VRAM_SIZE=$(echo "${VRAM_SIZE^^}" | sed 's/MB/M/g;s/GB/G/g;s/TB/T/g')
if ! VRAM_BYTES=$(numfmt --from=iec "$VRAM_SIZE" 2>/dev/null); then
  error "Invalid VRAM_SIZE: $VRAM_SIZE"
  exit 16
fi

# The host-visible PCI aperture must be a positive power-of-two size. Requiring
# whole MiB also keeps the renderer's advertised VRAM value exact.
if (( VRAM_BYTES < 1048576 || (VRAM_BYTES & (VRAM_BYTES - 1)) != 0 )); then
  error "VRAM_SIZE must be a power-of-two size of at least 1M: $VRAM_SIZE"
  exit 16
fi

VKR_DEVICE_MEMORY_LIMIT_BYTES="$VRAM_BYTES"
override_vram_size="$(( VRAM_BYTES / 1048576 ))"
export VKR_DEVICE_MEMORY_LIMIT_BYTES override_vram_size

# Return the PCI vendor for a usable DRM render node. Any malformed, missing,
# inaccessible or disappearing node is rejected before hardware rendering is enabled.

gpuNodeVendor() {

  local node="$1"

  local render_name="${node##*/}"
  [[ "$render_name" =~ ^renderD[0-9]{3}$ ]] || return 1

  local render_number="${render_name#renderD}"
  (( 10#$render_number >= 128 )) || return 1
  [ -c "$node" ] || return 1

  local gpu_fd
  if ! { exec {gpu_fd}<>"$node"; } 2>/dev/null; then
    return 1
  fi

  { exec {gpu_fd}>&-; } 2>/dev/null || true

  local vendor_file="/sys/class/drm/${render_name}/device/vendor"
  [ -r "$vendor_file" ] || return 1

  if ! IFS= read -r GPU_VENDOR < "$vendor_file"; then
    return 1
  fi

  GPU_VENDOR="${GPU_VENDOR,,}"
  return 0
}

# qemu-render omits Mesa's legacy i915 Gallium driver. Reject the Gen3 Intel
# devices that have no Crocus or Iris fallback before enabling EGL rendering.

intelMesaReady() {

  local node="$1"
  local render_name="${node##*/}"
  local device=""
  local device_file="/sys/class/drm/${render_name}/device/device"

  [ -r "$device_file" ] || return 1
  IFS= read -r device < "$device_file" || return 1

  case "${device,,}" in
    "0x2582" | "0x258a" | "0x2592" | "0x2772" | "0x27a2" | "0x27ae" | \
    "0x29b2" | "0x29c2" | "0x29d2" | "0xa001" | "0xa011" ) return 1 ;;
  esac

  return 0
}

vulkanLibraryAvailable() {

  local library="$1"

  compgen -G "/usr/lib/*/${library}" >/dev/null 2>&1 \
    || [ -e "/usr/lib/${library}" ] \
    || [ -e "/usr/lib64/${library}" ]
}

vulkanManifestAvailable() {

  local manifest="$1"

  compgen -G "/etc/vulkan/icd.d/${manifest}*.json" >/dev/null 2>&1 \
    || compgen -G "/usr/share/vulkan/icd.d/${manifest}*.json" >/dev/null 2>&1
}

vulkanRuntimeReady() {

  local summary details selected extensions api type
  local external_memory_fd external_memory_dma_buf
  local prime=""
  local vendor="${GPU_VENDOR,,}"
  local device="${GPU_DEVICE,,}"
  VULKAN_REASON=""

  if ! command -v vulkaninfo >/dev/null 2>&1; then
    VULKAN_REASON="vulkaninfo is not available in the container"
    return 1
  fi

  if [ -z "$device" ]; then
    VULKAN_REASON="the selected GPU PCI device ID cannot be determined"
    return 1
  fi

  # Mesa can scope Vulkan enumeration to the exact DRM device by PCI address.
  # Keep this probe local: QEMU still receives the selected render node normally.
  case "$vendor" in
    "0x8086" | "0x1002" )
      if [[ "$GPU_PCI_SLOT" =~ ^[0-9a-fA-F]{4}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.[0-7]$ ]]; then
        prime="pci-${GPU_PCI_SLOT//[:.]/_}!"
      fi ;;
  esac

  if [ -n "$prime" ]; then
    if ! summary="$(DRI_PRIME="$prime" vulkaninfo --summary 2>&1)"; then
      VULKAN_REASON="Vulkan device enumeration failed for the selected GPU"
      return 1
    fi
  elif ! summary="$(vulkaninfo --summary 2>&1)"; then
    VULKAN_REASON="Vulkan device enumeration failed"
    return 1
  fi

  selected="$(awk -v want_vendor="$vendor" -v want_device="$device" '
    function emit() {
      if (!found && in_gpu && tolower(vendor) == want_vendor &&
          tolower(device) == want_device && api != "" && type != "") {
        print api "|" type
        found = 1
      }
    }

    /^GPU[0-9]+:/ {
      emit()
      in_gpu = 1
      vendor = ""
      device = ""
      api = ""
      type = ""
      next
    }

    in_gpu && /^[[:space:]]*apiVersion[[:space:]]*=/ {
      api = $0
      sub(/^.*=[[:space:]]*/, "", api)
      if (match(api, /\([0-9]+\.[0-9]+(\.[0-9]+)?\)/)) {
        api = substr(api, RSTART + 1, RLENGTH - 2)
      } else {
        sub(/[[:space:]].*$/, "", api)
      }
      next
    }

    in_gpu && /^[[:space:]]*vendorID[[:space:]]*=/ {
      vendor = $0
      sub(/^.*=[[:space:]]*/, "", vendor)
      sub(/[[:space:]].*$/, "", vendor)
      next
    }

    in_gpu && /^[[:space:]]*deviceID[[:space:]]*=/ {
      device = $0
      sub(/^.*=[[:space:]]*/, "", device)
      sub(/[[:space:]].*$/, "", device)
      next
    }

    in_gpu && /^[[:space:]]*deviceType[[:space:]]*=/ {
      type = $0
      sub(/^.*=[[:space:]]*/, "", type)
      sub(/[[:space:]].*$/, "", type)
      next
    }

    END { emit() }
  ' <<< "$summary")"

  if [ -z "$selected" ]; then
    VULKAN_REASON="the selected GPU is not available through Vulkan"
    return 1
  fi

  IFS='|' read -r api type <<< "$selected"
  if [[ "$type" == "PHYSICAL_DEVICE_TYPE_CPU" ]]; then
    VULKAN_REASON="the selected Vulkan device is a software CPU renderer"
    return 1
  fi

  local major minor
  IFS='.' read -r major minor _ <<< "$api"
  if ! [[ "$major" =~ ^[0-9]+$ && "$minor" =~ ^[0-9]+$ ]]; then
    VULKAN_REASON="the selected GPU reports an invalid Vulkan API version '$api'"
    return 1
  fi

  if (( major < 1 || (major == 1 && minor < 1) )); then
    VULKAN_REASON="the selected GPU supports Vulkan $major.$minor, but Venus requires Vulkan 1.1 or newer"
    return 1
  fi

  if [ -n "$prime" ]; then
    if ! details="$(DRI_PRIME="$prime" vulkaninfo 2>&1)"; then
      VULKAN_REASON="Vulkan capability enumeration failed for the selected GPU"
      return 1
    fi
  elif ! details="$(vulkaninfo 2>&1)"; then
    VULKAN_REASON="Vulkan capability enumeration failed"
    return 1
  fi

  extensions="$(awk -v want_vendor="$vendor" -v want_device="$device" '
    function finish() {
      if (!found && in_gpu && tolower(vendor) == want_vendor &&
          tolower(device) == want_device) {
        print external_memory_fd "|" external_memory_dma_buf
        found = 1
      }
    }

    /^GPU[0-9]+:/ {
      finish()
      in_gpu = 1
      vendor = ""
      device = ""
      external_memory_fd = 0
      external_memory_dma_buf = 0
      next
    }

    in_gpu && /^[[:space:]]*vendorID[[:space:]]*=/ {
      vendor = $0
      sub(/^.*=[[:space:]]*/, "", vendor)
      sub(/[[:space:]].*$/, "", vendor)
      next
    }

    in_gpu && /^[[:space:]]*deviceID[[:space:]]*=/ {
      device = $0
      sub(/^.*=[[:space:]]*/, "", device)
      sub(/[[:space:]].*$/, "", device)
      next
    }

    in_gpu && /VK_KHR_external_memory_fd/ {
      external_memory_fd = 1
      next
    }

    in_gpu && /VK_EXT_external_memory_dma_buf/ {
      external_memory_dma_buf = 1
      next
    }

    END {
      finish()
    }
  ' <<< "$details")"

  IFS='|' read -r external_memory_fd external_memory_dma_buf <<< "$extensions"

  if [[ "$external_memory_fd" != "1" ]]; then
    VULKAN_REASON="the selected GPU does not support VK_KHR_external_memory_fd required by Venus"
    return 1
  fi

  if [[ "$external_memory_dma_buf" != "1" ]]; then
    VULKAN_REASON="the selected GPU does not support VK_EXT_external_memory_dma_buf required by Helios"
    return 1
  fi

  return 0
}

mesaVulkanReady() {

  local vendor="$1"
  local library manifest
  VULKAN_REASON=""

  if ! vulkanLibraryAvailable "libvulkan.so.1"; then
    VULKAN_REASON="the Vulkan loader is not available in the container"
    return 1
  fi

  case "$vendor" in
    "0x8086" )
      for library in libvulkan_intel.so libvulkan_intel_hasvk.so; do
        if ! vulkanLibraryAvailable "$library"; then
          VULKAN_REASON="the Intel Vulkan driver library '$library' is not available in the container"
          return 1
        fi
      done

      for manifest in intel_icd intel_hasvk_icd; do
        if ! vulkanManifestAvailable "$manifest"; then
          VULKAN_REASON="the Intel Vulkan ICD '$manifest' is not available in the container"
          return 1
        fi
      done ;;

    "0x1002" )
      if ! vulkanLibraryAvailable "libvulkan_radeon.so"; then
        VULKAN_REASON="the AMD Vulkan driver library 'libvulkan_radeon.so' is not available in the container"
        return 1
      fi

      if ! vulkanManifestAvailable "radeon_icd"; then
        VULKAN_REASON="the AMD Vulkan ICD 'radeon_icd' is not available in the container"
        return 1
      fi ;;
  esac

  vulkanRuntimeReady || return 1

  return 0
}

# NVIDIA uses the proprietary host driver injected by NVIDIA Container Toolkit
# rather than a Mesa Gallium driver from qemu-minimal. Require the complete EGL
# and GBM path before selecting an NVIDIA render node. Venus additionally needs
# the Vulkan loader, NVIDIA ICD and NVIDIA Vulkan userspace libraries.

nvidiaDriverVersion() {

  local data=""
  NVIDIA_DRIVER_VERSION=""

  if [ -r /proc/driver/nvidia/version ]; then
    data="$(head -n 1 /proc/driver/nvidia/version 2>/dev/null || true)"
  elif [ -r /sys/module/nvidia/version ]; then
    data="$(cat /sys/module/nvidia/version 2>/dev/null || true)"
  fi

  if [[ "$data" =~ ([0-9]{3,})\.([0-9]+)(\.[0-9]+)? ]]; then
    NVIDIA_DRIVER_VERSION="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}${BASH_REMATCH[3]:-}"
    return 0
  fi

  return 1
}

nvidiaVulkanReady() {

  local icd=""
  local major minor

  if ! nvidiaDriverVersion; then
    NVIDIA_REASON="the NVIDIA driver version cannot be determined"
    return 1
  fi

if ! [[ "$NVIDIA_DRIVER_VERSION" =~ ^([0-9]+)\.([0-9]+) ]]; then
  NVIDIA_REASON="the NVIDIA driver version '$NVIDIA_DRIVER_VERSION' could not be parsed"
  return 1
fi
major="${BASH_REMATCH[1]}"
minor="${BASH_REMATCH[2]}"

  if (( major < 570 || (major == 570 && minor < 86) )); then
    NVIDIA_REASON="NVIDIA driver $NVIDIA_DRIVER_VERSION is older than the 570.86 minimum required by Venus"
    return 1
  fi

  if ! compgen -G '/usr/lib/*/libvulkan.so.1' >/dev/null 2>&1 \
      && [ ! -e /usr/lib/libvulkan.so.1 ] \
      && [ ! -e /usr/lib64/libvulkan.so.1 ]; then
    NVIDIA_REASON="the Vulkan loader is not available in the container"
    return 1
  fi

  for icd in /etc/vulkan/icd.d/nvidia_icd*.json /usr/share/vulkan/icd.d/nvidia_icd*.json; do
    [ -r "$icd" ] && break
    icd=""
  done

  if [ -z "$icd" ]; then
    NVIDIA_REASON="the NVIDIA Vulkan ICD is not available in the container"
    return 1
  fi

  if ! compgen -G '/usr/lib/*/libGLX_nvidia.so.*' >/dev/null 2>&1 \
      && ! compgen -G '/usr/lib/*/nvidia/*/libGLX_nvidia.so.*' >/dev/null 2>&1 \
      && ! compgen -G '/usr/lib/nvidia/*/libGLX_nvidia.so.*' >/dev/null 2>&1 \
      && ! compgen -G '/usr/lib/libGLX_nvidia.so.*' >/dev/null 2>&1 \
      && ! compgen -G '/usr/lib64/nvidia/*/libGLX_nvidia.so.*' >/dev/null 2>&1 \
      && ! compgen -G '/usr/lib64/libGLX_nvidia.so.*' >/dev/null 2>&1; then
    NVIDIA_REASON="the NVIDIA Vulkan driver library is not available in the container"
    return 1
  fi

  if ! compgen -G '/usr/lib/*/libnvidia-glvkspirv.so.*' >/dev/null 2>&1 \
      && ! compgen -G '/usr/lib/*/nvidia/*/libnvidia-glvkspirv.so.*' >/dev/null 2>&1 \
      && ! compgen -G '/usr/lib/nvidia/*/libnvidia-glvkspirv.so.*' >/dev/null 2>&1 \
      && ! compgen -G '/usr/lib/libnvidia-glvkspirv.so.*' >/dev/null 2>&1 \
      && ! compgen -G '/usr/lib64/nvidia/*/libnvidia-glvkspirv.so.*' >/dev/null 2>&1 \
      && ! compgen -G '/usr/lib64/libnvidia-glvkspirv.so.*' >/dev/null 2>&1; then
    NVIDIA_REASON="the NVIDIA Vulkan SPIR-V compiler library is not available in the container"
    return 1
  fi

  if ! vulkanRuntimeReady; then
    NVIDIA_REASON="$VULKAN_REASON"
    return 1
  fi

  return 0
}

nvidiaGpuReady() {

  local modeset=""
  NVIDIA_REASON=""

  if ! compgen -G '/usr/lib/*/libEGL_nvidia.so.*' >/dev/null 2>&1 \
      && ! compgen -G '/usr/lib/libEGL_nvidia.so.*' >/dev/null 2>&1 \
      && ! compgen -G '/usr/lib64/libEGL_nvidia.so.*' >/dev/null 2>&1; then
    NVIDIA_REASON="the NVIDIA EGL driver is not available in the container"
    return 1
  fi

  if ! compgen -G '/usr/lib/*/libnvidia-egl-gbm.so.*' >/dev/null 2>&1 \
      && ! compgen -G '/usr/lib/libnvidia-egl-gbm.so.*' >/dev/null 2>&1 \
      && ! compgen -G '/usr/lib64/libnvidia-egl-gbm.so.*' >/dev/null 2>&1; then
    NVIDIA_REASON="the NVIDIA EGL GBM platform library is not available in the container"
    return 1
  fi

  if ! compgen -G '/usr/lib/*/gbm/nvidia-drm_gbm.so' >/dev/null 2>&1 \
      && [ ! -e /usr/lib/gbm/nvidia-drm_gbm.so ] \
      && [ ! -e /usr/lib64/gbm/nvidia-drm_gbm.so ]; then
    NVIDIA_REASON="the NVIDIA GBM backend is not available in the container"
    return 1
  fi

  if [ ! -r /usr/share/glvnd/egl_vendor.d/10_nvidia.json ] \
      || [ ! -r /usr/share/egl/egl_external_platform.d/15_nvidia_gbm.json ]; then
    NVIDIA_REASON="the NVIDIA EGL vendor configuration is not available in the container"
    return 1
  fi

  if [ ! -r /sys/module/nvidia_drm/parameters/modeset ] \
      || ! IFS= read -r modeset < /sys/module/nvidia_drm/parameters/modeset; then
    NVIDIA_REASON="the nvidia-drm KMS state cannot be determined"
    return 1
  fi

  case "${modeset,,}" in
    "y" | "1" ) ;;
    * )
      NVIDIA_REASON="nvidia-drm modesetting is disabled"
      return 1 ;;
  esac

  return 0
}

hostBlobsSupported() {

  kernelAtLeast 6 13
}

venusGuestPatRequired() {

  local cpu_vendor driver device=""

  # TCG does not use the Intel KVM guest-PAT quirk.
  disabled "${KVM:-}" && return 1

  isIntelCpu || return 1

  case "$GPU_VENDOR" in
    "0x1002" | "0x10de" )
      # RADV/NVIDIA dGPU on an Intel CPU.
      return 0 ;;
    "0x8086" )
      driver=$(readlink -f "/sys/class/drm/${RENDER_NAME}/device/driver" 2>/dev/null || true)
      driver="${driver##*/}"
      [[ "$driver" == "xe" ]] && return 0

      if [ -r "/sys/class/drm/${RENDER_NAME}/device/device" ]; then
        IFS= read -r device < "/sys/class/drm/${RENDER_NAME}/device/device" || device=""
        device="${device,,}"
      fi

      # Meteor Lake requires guest PAT even when it is still using i915.
      case "$device" in
        "0x7d40" | "0x7d45" | "0x7d55" | "0x7d60" | "0x7dd5" ) return 0 ;;
      esac ;;
  esac

  return 1
}

venusGuestPatReady() {

  VULKAN_PAT_REASON=""
  venusGuestPatRequired || return 0

  if ! hasFlag "ss"; then
    VULKAN_PAT_REASON="the Intel CPU cannot safely honor guest PAT because self-snoop is unavailable"
    return 1
  fi

  if ! kernelAtLeast 6 16; then
    VULKAN_PAT_REASON="Linux 6.16 or newer is required for guest PAT support on this Intel CPU/GPU combination"
    return 1
  fi

  VIRTGPU_GUEST_PAT="Y"
  return 0
}

GPU_VENDOR=""
NVIDIA_NODE=""
NVIDIA_REASON=""
VULKAN_REASON=""
VULKAN_PAT_REASON=""
VIRTGPU_GUEST_PAT=""

if [ -n "$RENDERNODE" ]; then

  if ! gpuNodeVendor "$RENDERNODE"; then
    gpuSetupFailure "GPU render node '$RENDERNODE' is unavailable or inaccessible"
    return 0
  fi

  case "$GPU_VENDOR" in
    "0x8086" )
      if ! intelMesaReady "$RENDERNODE"; then
        gpuSetupFailure "Intel GPU at $RENDERNODE is not supported by qemu-render"
        return 0
      fi ;;
    "0x1002" ) ;;
    "0x10de" )
      if ! nvidiaGpuReady; then
        gpuSetupFailure "NVIDIA GPU at $RENDERNODE cannot be used for hardware rendering because $NVIDIA_REASON"
        return 0
      fi ;;
    * )
      gpuSetupFailure "Unsupported GPU at $RENDERNODE"
      return 0 ;;
  esac

else

  if [ ! -d /dev/dri ]; then
    gpuSetupFailure "GPU acceleration was requested, but '/dev/dri' was not added to the devices section of your compose file"
    return 0
  fi

  RENDER_NODE_FOUND="N"

  for node in /dev/dri/renderD*; do

    [ -e "$node" ] || continue
    RENDER_NODE_FOUND="Y"

    if ! gpuNodeVendor "$node"; then
      continue
    fi

    case "$GPU_VENDOR" in
      "0x8086" )
        if intelMesaReady "$node"; then
          RENDERNODE="$node"
          break
        fi ;;
      "0x1002" )
        RENDERNODE="$node"
        break ;;
      "0x10de" )
        NVIDIA_NODE="$node"
        if nvidiaGpuReady; then
          RENDERNODE="$node"
          break
        fi ;;
    esac

  done

  if [ -z "$RENDERNODE" ]; then

    if [ -n "$NVIDIA_NODE" ] && [ -n "$NVIDIA_REASON" ]; then
      gpuSetupFailure "NVIDIA GPU at $NVIDIA_NODE cannot be used for hardware rendering because $NVIDIA_REASON"
    elif [[ "$RENDER_NODE_FOUND" != "Y" ]]; then
      gpuSetupFailure "/dev/dri is available, but no GPU render nodes were found"
    else
      gpuSetupFailure "No usable GPU render node found"
    fi

    return 0
  fi

fi

# Re-read the selected node after auto-detection so the vendor name and device
# number below are based on the final render node and survive hotplug races.
if ! gpuNodeVendor "$RENDERNODE"; then
  gpuSetupFailure "GPU render node '$RENDERNODE' became unavailable"
  return 0
fi

RENDER_NAME="${RENDERNODE##*/}"
CARD_NUMBER="${RENDER_NAME#renderD}"
GPU_DEVICE=""
GPU_DRIVER=""

if [ -r "/sys/class/drm/${RENDER_NAME}/device/device" ]; then
  IFS= read -r GPU_DEVICE < "/sys/class/drm/${RENDER_NAME}/device/device" || GPU_DEVICE=""
  GPU_DEVICE="${GPU_DEVICE,,}"
fi

GPU_DRIVER=$(readlink -f "/sys/class/drm/${RENDER_NAME}/device/driver" 2>/dev/null || true)
GPU_DRIVER="${GPU_DRIVER##*/}"
GPU_DEVICE_NAME=""
GPU_PCI_SLOT=$(readlink -f "/sys/class/drm/${RENDER_NAME}/device" 2>/dev/null || true)
GPU_PCI_SLOT="${GPU_PCI_SLOT##*/}"

if [[ "$GPU_PCI_SLOT" =~ ^[0-9a-fA-F]{4}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.[0-7]$ ]]; then
  GPU_DEVICE_NAME=$(lspci -D -s "$GPU_PCI_SLOT" -vmm 2>/dev/null \
    | sed -n 's/^Device:[[:space:]]*//p' | head -n 1 || true)
fi

case "$GPU_VENDOR" in
  "0x8086" ) GPU_NAME="Intel" ;;
  "0x1002" ) GPU_NAME="AMD" ;;
  "0x10de" ) GPU_NAME="NVIDIA" ;;
  * ) GPU_NAME="GPU" ;;
esac

if [ ! -d /dev/dri ]; then
  mkdir -m 755 /dev/dri 2>/dev/null || true
fi

# Derive the matching DRM card from the validated render node number.
CARD_DEVICE="/dev/dri/card$((10#$CARD_NUMBER - 128))"

# Containers normally have no udev, so reconstruct the matching DRM card and
# render character devices from the render-node minor number when necessary.
if [ ! -c "$CARD_DEVICE" ]; then
  if mknod "$CARD_DEVICE" c 226 $((10#$CARD_NUMBER - 128)) 2>/dev/null; then
    chmod 666 "$CARD_DEVICE" 2>/dev/null || true
  fi
fi

if [ ! -c "$RENDERNODE" ]; then
  if mknod "$RENDERNODE" c 226 "$((10#$CARD_NUMBER))" 2>/dev/null; then
    chmod 666 "$RENDERNODE" 2>/dev/null || true
  fi
fi

if ! gpuNodeVendor "$RENDERNODE"; then
  gpuSetupFailure "GPU render node '$RENDERNODE' became unavailable"
  return 0
fi

if ! hostBlobsSupported; then
  gpuSetupFailure "Windows GPU acceleration requires virtio-gpu host blobs (Linux 6.13+ host kernel)"
fi

VGA+=",hostmem=$VRAM_BYTES,max_hostmem=$VRAM_BYTES,blob=true"
VGA+=",host3d_blob_limit=$VRAM_BYTES"

case "$GPU_VENDOR" in
  "0x8086" | "0x1002" )
    if ! mesaVulkanReady "$GPU_VENDOR"; then
      gpuSetupFailure "Windows GPU acceleration requires Vulkan via Venus, but $VULKAN_REASON"
    fi ;;
  "0x10de" )
    if ! nvidiaVulkanReady; then
      gpuSetupFailure "Windows GPU acceleration requires Vulkan via Venus, but $NVIDIA_REASON"
    fi ;;
esac

if ! venusGuestPatReady; then
  gpuSetupFailure "Windows GPU acceleration requires Vulkan via Venus, but $VULKAN_PAT_REASON"
fi

VGA+=",venus=true"

echo
info "Hardware rendering enabled:"
info

info "Device:     $GPU_NAME${GPU_DEVICE_NAME:+ $GPU_DEVICE_NAME}"

if [ -n "$GPU_DEVICE" ]; then
  info "PCI ID:     ${GPU_VENDOR#0x}:${GPU_DEVICE#0x}"
fi

info "Driver:     ${GPU_DRIVER:-unknown}"

if [[ "$GPU_VENDOR" == "0x10de" ]]; then
  nvidiaDriverVersion || NVIDIA_DRIVER_VERSION="unknown"
  info "Version:    $NVIDIA_DRIVER_VERSION"
else
  MESA_VERSION="$(dpkg-query -W -f='${Provides}\n' qemu-render 2>/dev/null \
    | sed -n 's/.*libgbm1 (= \([^)]*\)).*/\1/p' || true)"

  [ -n "$MESA_VERSION" ] && info "Mesa:       $MESA_VERSION"
fi

info "Render:     $RENDERNODE"

DISPLAY_OPTS="-display egl-headless,rendernode=$RENDERNODE"
DISPLAY_OPTS+=" -device $VGA"

[[ "${DISPLAY,,}" == "vnc" ]] && DISPLAY_OPTS+=" -vnc :${port}${LOSSY_OPT}"
[[ "${DISPLAY,,}" == "web" ]] && DISPLAY_OPTS+=" -vnc :${port},websocket=unix:${WSS_SOCKET}${LOSSY_OPT}"

return 0

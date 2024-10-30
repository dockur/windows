#!/bin/bash
# gpu-switch.sh - Complete GPU management script for Docker containers
# Supports multiple GPUs, optional GPU usage, and handles audio devices

# Set up logging with timestamps
log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    logger "GPU-SWITCH [$timestamp]: $1"
    echo "GPU-SWITCH [$timestamp]: $1" >&2
}

error_exit() {
    log "ERROR: $1"
    exit 1
}

# Store GPU and Audio pairs
declare -A GPU_PAIRS

check_gpu_needed() {
    if [ -z "$NVIDIA_VISIBLE_DEVICES" ]; then
        log "No GPUs specified in NVIDIA_VISIBLE_DEVICES - skipping GPU management"
        return 1
    fi
    # Skip if NVIDIA_VISIBLE_DEVICES is set to none, None, or NONE
    if [[ "${NVIDIA_VISIBLE_DEVICES,,}" == "none" ]]; then
        log "NVIDIA_VISIBLE_DEVICES set to none - skipping GPU management"
        return 1
    fi
    return 0
}

# Convert any GPU identifier to PCI address
convert_to_pci_address() {
    local device="$1"
    local gpu_address=""

    if [[ "$device" =~ ^[0-9]+$ ]]; then
        # Convert GPU index to PCI address
        gpu_address=$(nvidia-smi --id=$device --query-gpu=gpu_bus_id --format=csv,noheader 2>/dev/null | tr -d '[:space:]')
    elif [[ "$device" =~ ^GPU-.*$ ]]; then
        # Handle UUID
        gpu_address=$(nvidia-smi --id=$device --query-gpu=gpu_bus_id --format=csv,noheader 2>/dev/null | tr -d '[:space:]')
    else
        # Direct PCI address provided
        gpu_address=$device
    fi

    # Standardize format
    echo "$gpu_address" | sed 's/0000://' | sed 's/\./:/g'
}

get_gpu_addresses() {
    # Split devices by comma
    IFS=',' read -ra DEVICES <<< "$NVIDIA_VISIBLE_DEVICES"
    
    for device in "${DEVICES[@]}"; do
        local gpu_address=$(convert_to_pci_address "$device")
        if [ -z "$gpu_address" ]; then
            error_exit "Failed to get PCI address for device: $device"
        }

        # Get base address without function number
        local base_address=$(echo "$gpu_address" | sed 's/:[0-9]$//')
        
        # Find audio device with same base address
        local gpu_audio_address=$(lspci | grep -i "audio.*nvidia" | grep "$base_address" | awk '{print $1}' | sed 's/0000://' | sed 's/\./:/g')
        
        if [ -z "$gpu_audio_address" ]; then
            log "Warning: No audio device found for GPU $gpu_address"
            continue
        }

        # Store in associative array
        GPU_PAIRS["$gpu_address"]=$gpu_audio_address
        log "Found GPU: $gpu_address with Audio: $gpu_audio_address"
    done

    if [ ${#GPU_PAIRS[@]} -eq 0 ]; then
        error_exit "No valid GPU devices found"
    fi
}

check_driver_loaded() {
    local driver="$1"
    if ! lsmod | grep -q "^$driver"; then
        return 1
    fi
    return 0
}

cleanup_nvidia() {
    log "Cleaning up NVIDIA processes and drivers"
    
    # Kill any processes using the GPUs
    if lsof -t /dev/nvidia* > /dev/null 2>&1; then
        log "Terminating NVIDIA GPU processes"
        lsof -t /dev/nvidia* | xargs -r kill -9 2>/dev/null || log "Warning: Some processes couldn't be killed"
    fi
    
    # Remove NVIDIA modules in reverse order
    local modules=("nvidia_drm" "nvidia_uvm" "nvidia_modeset" "nvidia")
    for module in "${modules[@]}"; do
        if check_driver_loaded "$module"; then
            log "Removing module: $module"
            modprobe -r "$module" || log "Warning: Couldn't remove $module module"
            sleep 1
        fi
    done

    # Remove audio module if loaded
    if check_driver_loaded "snd_hda_intel"; then
        log "Removing audio module: snd_hda_intel"
        modprobe -r snd_hda_intel || log "Warning: Couldn't remove snd_hda_intel module"
        sleep 1
    fi
}

cleanup_vfio() {
    log "Cleaning up VFIO-PCI bindings"
    
    for gpu in "${!GPU_PAIRS[@]}"; do
        local audio="${GPU_PAIRS[$gpu]}"
        for device in "$gpu" "$audio"; do
            if [ -e "/sys/bus/pci/drivers/vfio-pci/unbind" ]; then
                log "Unbinding $device from VFIO-PCI"
                echo "$device" > /sys/bus/pci/drivers/vfio-pci/unbind 2>/dev/null || \
                    log "Warning: Failed to unbind $device from VFIO"
            fi
            
            if [ -e "/sys/bus/pci/devices/$device/driver_override" ]; then
                echo "" > "/sys/bus/pci/devices/$device/driver_override" 2>/dev/null || \
                    log "Warning: Failed to clear driver override for $device"
            fi
        done
    done
}

bind_to_vfio() {
    log "Binding devices to VFIO-PCI"
    
    # Ensure VFIO modules are loaded
    modprobe vfio-pci || error_exit "Failed to load VFIO-PCI module"
    
    for gpu in "${!GPU_PAIRS[@]}"; do
        local audio="${GPU_PAIRS[$gpu]}"
        for device in "$gpu" "$audio"; do
            # Unbind from current driver if bound
            local current_driver=$(readlink "/sys/bus/pci/devices/$device/driver" 2>/dev/null | awk -F '/' '{print $NF}')
            if [ ! -z "$current_driver" ]; then
                log "Unbinding $device from $current_driver"
                echo "$device" > "/sys/bus/pci/drivers/$current_driver/unbind" 2>/dev/null || \
                    log "Warning: Couldn't unbind $device from $current_driver"
                sleep 1
            fi
            
            # Bind to VFIO-PCI
            log "Binding $device to VFIO-PCI"
            echo "vfio-pci" > "/sys/bus/pci/devices/$device/driver_override" || \
                error_exit "Failed to set driver override for $device"
            echo "$device" > /sys/bus/pci/drivers/vfio-pci/bind || \
                error_exit "Failed to bind $device to VFIO"
            sleep 1
        done
    done
}

bind_to_nvidia() {
    log "Binding devices back to NVIDIA and audio drivers"
    
    # Load NVIDIA modules in order
    local modules=("nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm")
    for module in "${modules[@]}"; do
        log "Loading module: $module"
        modprobe $module || error_exit "Failed to load $module module"
        sleep 1
    done
    
    # Load audio module
    log "Loading audio module: snd_hda_intel"
    modprobe snd_hda_intel || log "Warning: Failed to load snd_hda_intel module"
    sleep 1
    
    for gpu in "${!GPU_PAIRS[@]}"; do
        local audio="${GPU_PAIRS[$gpu]}"
        
        # Bind GPU to nvidia
        log "Binding GPU $gpu to NVIDIA driver"
        echo "$gpu" > /sys/bus/pci/drivers/nvidia/bind || \
            error_exit "Failed to bind GPU to NVIDIA"
        sleep 1
        
        # Bind audio to snd_hda_intel
        if [ ! -z "$audio" ]; then
            log "Binding audio $audio to Intel HDA driver"
            echo "$audio" > /sys/bus/pci/drivers/snd_hda_intel/bind 2>/dev/null || \
                log "Warning: Failed to bind audio to snd_hda_intel"
            sleep 1
        fi
    done
}

update_docker_config() {
    local container_name="$1"
    local action="$2"

    if [ "$action" = "start" ]; then
        local devices_args=""
        for gpu in "${!GPU_PAIRS[@]}"; do
            local audio="${GPU_PAIRS[$gpu]}"
            devices_args+=" --device-add vfio-pci,host=$gpu,multifunction=on"
            if [ ! -z "$audio" ]; then
                devices_args+=" --device-add vfio-pci,host=$audio,multifunction=on"
            fi
        done
        log "Updating Docker container with VFIO devices"
        docker update $devices_args "$container_name" || \
            error_exit "Failed to update Docker container devices"
    else
        log "Removing VFIO devices from Docker container"
        for gpu in "${!GPU_PAIRS[@]}"; do
            local audio="${GPU_PAIRS[$gpu]}"
            docker update --device-rm "vfio-pci,host=$gpu" "$container_name" 2>/dev/null || \
                log "Warning: Failed to remove GPU device from container"
            if [ ! -z "$audio" ]; then
                docker update --device-rm "vfio-pci,host=$audio" "$container_name" 2>/dev/null || \
                    log "Warning: Failed to remove audio device from container"
            fi
        done
    fi
}

verify_gpu_bound() {
    local target_driver="$1"
    log "Verifying device bindings to $target_driver"
    
    for gpu in "${!GPU_PAIRS[@]}"; do
        local audio="${GPU_PAIRS[$gpu]}"
        local current_gpu_driver=$(readlink "/sys/bus/pci/devices/$gpu/driver" 2>/dev/null | awk -F '/' '{print $NF}')
        
        if [[ "$target_driver" == "vfio-pci" ]]; then
            if [[ "$current_gpu_driver" != "vfio-pci" ]]; then
                error_exit "GPU $gpu failed to bind to VFIO-PCI (current: $current_gpu_driver)"
            fi
            
            if [ ! -z "$audio" ]; then
                local current_audio_driver=$(readlink "/sys/bus/pci/devices/$audio/driver" 2>/dev/null | awk -F '/' '{print $NF}')
                if [[ "$current_audio_driver" != "vfio-pci" ]]; then
                    error_exit "Audio device $audio failed to bind to VFIO-PCI (current: $current_audio_driver)"
                fi
            fi
        elif [[ "$target_driver" == "nvidia" ]]; then
            if [[ "$current_gpu_driver" != "nvidia" ]]; then
                error_exit "GPU $gpu failed to bind to NVIDIA (current: $current_gpu_driver)"
            fi
            
            if [ ! -z "$audio" ]; then
                local current_audio_driver=$(readlink "/sys/bus/pci/devices/$audio/driver" 2>/dev/null | awk -F '/' '{print $NF}')
                if [[ "$current_audio_driver" != "snd_hda_intel" ]]; then
                    log "Warning: Audio device $audio not bound to snd_hda_intel (current: $current_audio_driver)"
                fi
            fi
        fi
    done
    log "All devices successfully bound to $target_driver"
}

# Main script
if [ "$#" -ne 2 ]; then
    error_exit "Usage: $0 [start|stop] CONTAINER_NAME"
fi

ACTION="$1"
CONTAINER_NAME="$2"

# Verify container exists
if ! docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    error_exit "Container $CONTAINER_NAME does not exist"
fi

# Check if GPU management is needed
if ! check_gpu_needed; then
    log "Continuing without GPU management"
    exit 0
fi

# Get GPU addresses and proceed with GPU management
get_gpu_addresses

case "$ACTION" in
    "start")
        log "Starting GPU transition to VFIO for container: $CONTAINER_NAME"
        cleanup_nvidia
        bind_to_vfio
        verify_gpu_bound "vfio-pci"
        update_docker_config "$CONTAINER_NAME" "start"
        ;;
    "stop")
        log "Starting GPU transition to NVIDIA for container: $CONTAINER_NAME"
        update_docker_config "$CONTAINER_NAME" "stop"
        cleanup_vfio
        bind_to_nvidia
        verify_gpu_bound "nvidia"
        ;;
    *)
        error_exit "Invalid action. Use 'start' or 'stop'"
        ;;
esac

log "GPU transition completed successfully"
exit 0

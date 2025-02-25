$ErrorActionPreference = "Stop"

# Set Power Plan to High Performance and disable sleep
Write-Output "Configuring Power Plan to High Performance and disabling sleep..."
slmgr /rearm
powercfg -setactive SCHEME_MIN
powercfg /x -hibernate-timeout-ac 0
powercfg /x -hibernate-timeout-dc 0
powercfg /x -disk-timeout-ac 0
powercfg /x -disk-timeout-dc 0
powercfg /x -monitor-timeout-ac 0
powercfg /x -monitor-timeout-dc 0
powercfg /x -standby-timeout-ac 0
powercfg /x -standby-timeout-dc 0

# Disable Windows Search Indexing (optional, for minimal interruption)
Write-Output "Disabling Windows Search indexing service..."
Stop-Service -Name "WSearch" -Force -ErrorAction SilentlyContinue
Set-Service -Name "WSearch" -StartupType Disabled

# Set Network Adapters to not enter Power Saving mode
Write-Output "Disabling Power Saving for Network Adapters..."
Get-WmiObject -Namespace root\wmi -Class MSPower_DeviceEnable -Filter "InstanceName LIKE 'PCI\\\\VEN%'" | ForEach-Object {
    $_.Enable = $false
    $_.Put()
}

# Set Firewall to allow all connections (optional; adjust based on your requirements)
Write-Output "Configuring Windows Firewall to allow all connections (if necessary)..."
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False
netsh advfirewall set allprofiles state off

# This can't be done inside provision script, because a restart is needed for changes to take effect.
Write-Host "Enable IPv6"
reg add hklm\system\currentcontrolset\services\tcpip6\parameters /f /v DisabledComponents /t REG_DWORD /d 0


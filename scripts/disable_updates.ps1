$ErrorActionPreference = "Stop"

function Set-RegistryProperty {
    param (
        [string]$path,
        [string]$name,
        [int]$value
    )

    if (-not (Test-Path $path)) {
        New-Item -Path $path -Force
    }

    if (-not (Test-Path "$path\$name")) {
        New-ItemProperty -Path $path -Name $name -Value $value -Force
    } else {
        Set-ItemProperty -Path $path -Name $name -Value $value -Force
    }
}

Write-Output "Windows Update settings have been configured to disable automatic updates and notifications."

$settings = @(
    @{ Type = "registry"; Name = "NoAutoUpdate"; Value = 1; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" },
    @{ Type = "registry"; Name = "AUOptions"; Value = 0; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" },
    @{ Type = "registry"; Name = "ExcludeWUDriversInQualityUpdate"; Value = 1; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" },
    @{ Type = "registry"; Name = "DisableWindowsUpdateAccess"; Value = 1; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" },
    @{ Type = "registry"; Name = "NoAutoRebootWithLoggedOnUsers"; Value = 1; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" },
    @{ Type = "registry"; Name = "DisableAutoReboot"; Value = 1; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" },
    @{ Type = "registry"; Name = "UseWUServer"; Value = 0; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" },
    @{ Type = "registry"; Name = "ExternalManaged"; Value = 1; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" },
    @{ Type = "registry"; Name = "DODownloadMode"; Value = 0; Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config" },

    @{ Type = "service"; Name = "wuauserv"; Value = 4; Path = "HKLM:\SYSTEM\CurrentControlSet\Services\wuauserv" },
    @{ Type = "service"; Name = "BITS"; Value = 4; Path = "HKLM:\SYSTEM\CurrentControlSet\Services\BITS" },
    @{ Type = "service"; Name = "cryptsvc"; Value = 4; Path = "HKLM:\SYSTEM\CurrentControlSet\Services\cryptsvc" },
    @{ Type = "service"; Name = "dosvc"; Value = 4; Path = "HKLM:\SYSTEM\CurrentControlSet\Services\dosvc" },
    @{ Type = "service"; Name = "usosvc"; Value = 4; Path = "HKLM:\SYSTEM\CurrentControlSet\Services\usosvc" },
    @{ Type = "service"; Name = "msiserver"; Value = 4; Path = "HKLM:\SYSTEM\CurrentControlSet\Services\msiserver" }
)

foreach ($setting in $settings) {
    if ($setting.Type -eq "registry") {
        Set-RegistryProperty -path $setting.Path -name $setting.Name -value $setting.Value
        Write-Output "Set $($setting.Name) to $($setting.Value) in $($setting.Path)."
    } elseif ($setting.Type -eq "service") {
        Set-RegistryProperty -path $setting.Path -name "Start" -value $setting.Value
        Write-Output "Disabled $($setting.Name) service."
    }
}

Write-Output "All specified Windows Update services and group policies have been disabled."

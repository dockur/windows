# This script is designed to be idempotent. It can be run multiple times without causing errors.

# --- Reliable Logging ---
# Start-Transcript now logs to the user's temporary folder, which is always writable.
Start-Transcript -Path "$env:TEMP\transcript.log" -Force

# --- Script Parameters ---
$DomainName = "ttpl.local"
$DomainNetbiosName = "TTPL"
$AdminPassword = "P@raveeen123" # Use a secure method in production

# --- Robust Idempotency Check ---
# This is a much better check. It tries to get the AD Domain information.
# If it succeeds AND the domain name matches our target, we know the script is already done.
try {
    if ((Get-ADDomain).DNSRoot -eq $DomainName) {
        Write-Host "This server is already a Domain Controller for the '$DomainName' domain. No action needed. Exiting."
        exit
    }
}
catch {
    Write-Host "This server is not yet a Domain Controller . Proceeding with configuration."
}

# --- 1. Idempotent Network Configuration ---
Write-Host "Configuring static IP address..."
$ipAddress = "192.168.10.220"
$gateway = "192.168.10.1"
$dnsServer = "127.0.0.1" # The DC is its own DNS server

# This logic is now safe to re-run. It finds the primary network adapter.
$adapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1

if ($adapter) {
    Write-Host "Found active network adapter: $($adapter.Name)"
    
    # First, set the DNS. This is always safe to do.
    Set-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -ServerAddresses $dnsServer
    
    # Check if the correct IP is already set. If not, configure it.
    $currentIP = Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 | Where-Object { $_.IPAddress -eq $ipAddress }
    
    # if (-not $currentIP) { //alwa
    Write-Host "IP address not set correctly. Configuring static IP..."
    # Remove any other IPv4 addresses to prevent conflicts
    Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 | Remove-NetIPAddress -Confirm:$false
    
    # Set the new IP address
    New-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -IPAddress $ipAddress -PrefixLength 24 -DefaultGateway $gateway
    Write-Host "Static IP configured."
    # } else {
    #     Write-Host "IP address is already correctly set to $ipAddress."
    # }
}
else {
    Write-Error "Could not find an active network adapter."
    exit
}

# --- 2. Install Active Directory Domain Services (if needed) ---
if (-not (Get-WindowsFeature -Name AD-Domain-Services).Installed) {
    Write-Host "Installing AD-Domain-Services role..."
    Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools
} else {
    Write-Host "AD-Domain-Services role is already installed."
}

# --- 3. Promote to Domain Controller ---
Write-Host "Promoting server to a Domain Controller for '$DomainName'..."
$securePassword = ConvertTo-SecureString $AdminPassword -AsPlainText -Force

Install-ADDSForest `
    -CreateDnsDelegation:$false `
    -DatabasePath "C:\WINDOWS\NTDS" `
    -DomainMode "Win2025" `
    -DomainName $DomainName `
    -DomainNetbiosName $DomainNetbiosName `
    -ForestMode "Win2025" `
    -InstallDns:$true `
    -LogPath "C:\WINDOWS\NTDS" `
    -SysvolPath "C:\WINDOWS\SYSVOL" `
    -Force:$true `
    -SafeModeAdministratorPassword $securePassword

Write-Host "Configuration complete. The server will restart automatically."
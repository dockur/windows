# This script is designed to be idempotent and robust.

# --- Script Parameters ---
# CRITICAL: Make sure these values are correct!
$DomainName = "ttpl.local"
$DC_IP = "192.168.10.220"  # IMPORTANT: Use the NEW IP address of your DC
$AdminUser = "administrator"
$AdminPassword = "admin" # CRITICAL: This MUST match the password used to create the domain

# --- Idempotency Check ---
Write-Host "Checking if this PC is already joined to the domain..."
if ((Get-ComputerInfo).Domain -eq $DomainName) {
    Write-Host "This PC is already a member of the '$DomainName' domain. Exiting script."
    exit
}
Write-Host "PC is not domain-joined. Proceeding..."

# --- 1. Wait for Domain Controller ---
Write-Host "Waiting for the Domain Controller at $DC_IP to come online..."
while (-not (Test-NetConnection -ComputerName $DC_IP -Port 389 -InformationLevel "Quiet")) {
    Write-Host "DC is not reachable yet. Retrying in 10 seconds..."
    Start-Sleep -Seconds 10
}
Write-Host "Domain Controller is online!"

# --- 2. Robust Network Configuration ---
Write-Host "Configuring static IP and DNS..."
$ipAddress = "192.168.10.219" # A free IP for this client
$gateway = "192.168.10.1"
$dnsServer = $DC_IP # DNS MUST point to the Domain Controller

# Find the primary active network adapter
$adapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1

if ($adapter) {
    Write-Host "Found active network adapter: $($adapter.Name)"
    
    # THE NEW FIX: This logic uses 'Set-' cmdlets to modify the existing configuration.
    # It avoids the '...already exists' error by not trying to create a new configuration.
    
    # First, get the existing IP configuration object.
    $ipconfig = Get-NetIPConfiguration -InterfaceIndex $adapter.InterfaceIndex | Where-Object { $_.IPv4Address } | Select-Object -First 1
    
    if ($ipconfig) {
        Write-Host "Modifying existing IP configuration..."
        # Use Set-NetIPAddress to change the IP and Gateway on the existing configuration
        Set-NetIPAddress -InputObject $ipconfig -IPAddress $ipAddress -PrefixLength 24 -DefaultGateway $gateway
        # Use Set-DnsClientServerAddress to set the DNS
        Set-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -ServerAddresses $dnsServer
    }
    else {
        # Fallback for a completely unconfigured adapter (unlikely in this case, but safe)
        Write-Host "No existing IP configuration found. Creating a new one..."
        New-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -IPAddress $ipAddress -PrefixLength 24 -DefaultGateway $gateway
        Set-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -ServerAddresses $dnsServer
    }
    
    Write-Host "Static IP and DNS configured."
    Start-Sleep -Seconds 15 # Give network settings a moment to apply
}
else {
    Write-Error "Could not find an active network adapter."
    exit
}

# --- 3. Join the Domain ---
Write-Host "Joining the domain '$DomainName'..."
$username = "$DomainName\$AdminUser"
$credential = New-Object System.Management.Automation.PSCredential($username, (ConvertTo-SecureString $AdminPassword -AsPlainText -Force))

Add-Computer -DomainName $DomainName -Credential $credential -Restart -Force
Write-Host "Domain join complete. The computer will restart automatically."


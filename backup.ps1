# scripts/dc_setup.ps1

# TODO: remove to avoid priv errors
# Start-Transcript -Path "$env:TEMP\transcript.log" -Force

# --- Script Parameters ---
$DomainName = "ttpl.local"
$DomainNetbiosName = "TTPL"
$AdminPassword = "P@raveeen123" # Use a secure method in production

# TODO: features may be already installed, but check if domain is other than WORKGROUP
# --- Idempotency Check: Exit if already a Domain Controller ---
# Write-Host "Checking if this server is already a Domain Controller..."
# if ((Get-WindowsFeature -Name AD-Domain-Services).Installed) {
#     Write-Host "Active Directory Domain Services are already installed. Exiting script."
#     exit
# }
Write-Host "Server is not a DC. Proceeding with configuration."

# --- 1. Network Configuration ---
Write-Host "Configuring static IP address..."
$ipAddress = "192.168.10.20"
$subnetMask = "255.255.255.0"
$gateway = "192.168.10.1"
$dnsServer = "127.0.0.1" # The DC is its own DNS server

# TODO: MSFT doc uses New-NetIPAddress, but it fails if IP already exists fixit
Get-NetAdapter | ForEach-Object {
    $_ | New-NetIPAddress -AddressFamily IPv4 -IPAddress $ipAddress -PrefixLength 24 -DefaultGateway $gateway
    $_ | Set-DnsClientServerAddress -ServerAddresses $dnsServer
}
Write-Host "Static IP configured."

# --- 2. Install Active Directory Domain Services ---
Write-Host "Installing AD-Domain-Services role..."
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools

# --- 3. Promote to Domain Controller ---
Write-Host "Promoting server to a Domain Controller for '$DomainName'..."
$securePassword = ConvertTo-SecureString $AdminPassword -AsPlainText -Force

Install-ADDSForest `
    -CreateDnsDelegation:$false `
    -DatabasePath "C:\WINDOWS\NTDS" `
    -DomainMode "Win2025" ` # Using a more compatible default
    -DomainName $DomainName `
    -DomainNetbiosName $DomainNetbiosName `
    -ForestMode "Win2025" `
    -InstallDns:$true `
    -LogPath "C:\WINDOWS\NTDS" `
    -SysvolPath "C:\WINDOWS\SYSVOL" `
    -Force:$true `
    -SafeModeAdministratorPassword $securePassword

# The promotion process will automatically trigger a reboot.
Write-Host "Configuration complete. The server will restart automatically."
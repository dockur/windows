# Define variables
$OpenSSH_URL = "https://github.com/PowerShell/Win32-OpenSSH/releases/latest/download/OpenSSH-Win64.zip"
$OpenSSH_Install_Path = "C:\Program Files\OpenSSH"
$OpenSSH_Zip = "$env:TEMP\OpenSSH-Win64.zip"

# Function to check if running as Administrator
function Test-Admin {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin)) {
    Write-Host "Please run this script as Administrator!" -ForegroundColor Red
    exit 1
}

# Ensure the install path exists
if (!(Test-Path $OpenSSH_Install_Path)) {
    New-Item -ItemType Directory -Path $OpenSSH_Install_Path -Force
}

# Download OpenSSH if not already present
Write-Host "Downloading OpenSSH..." -ForegroundColor Cyan
Invoke-WebRequest -Uri $OpenSSH_URL -OutFile $OpenSSH_Zip

# Extract OpenSSH
Write-Host "Extracting OpenSSH..." -ForegroundColor Cyan
Expand-Archive -Path $OpenSSH_Zip -DestinationPath $OpenSSH_Install_Path -Force

# Check if install-sshd.ps1 exists
if (!(Test-Path "$OpenSSH_Install_Path\OpenSSH-Win64\install-sshd.ps1")) {
    Write-Host "❌ Error: install-sshd.ps1 not found in $OpenSSH_Install_Path. Extraction failed!" -ForegroundColor Red
    exit 1
}

# Navigate to OpenSSH directory
Push-Location -Path $OpenSSH_Install_Path\OpenSSH-Win64

# Run install script
Write-Host "Installing OpenSSH service..." -ForegroundColor Green
powershell.exe -ExecutionPolicy Bypass -File install-sshd.ps1

# Set SSHD service to start automatically
Write-Host "Setting SSHD to start automatically..." -ForegroundColor Green
if (Get-Service sshd -ErrorAction SilentlyContinue) {
    Set-Service -Name sshd -StartupType Automatic
    Start-Service sshd
} else {
    Write-Host "⚠ OpenSSH service was not installed correctly. Try running install-sshd.ps1 manually." -ForegroundColor Red
    exit 1
}

# Verify installation
$sshdStatus = Get-Service -Name sshd -ErrorAction SilentlyContinue
if ($sshdStatus.Status -eq 'Running') {
    Write-Host "✅ OpenSSH installation successful! You can now connect via SSH." -ForegroundColor Green
} else {
    Write-Host "⚠ OpenSSH installation failed. Try restarting your computer and rerun the script." -ForegroundColor Red
}

Pop-Location

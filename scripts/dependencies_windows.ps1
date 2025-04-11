$ErrorActionPreference = "Stop"

# https://stackoverflow.com/questions/9948517/how-to-stop-a-powershell-script-on-the-first-error
function CheckStatus {
    if (-not $?)
    {
        throw "Native Failure"
    }
}

function Validate-FileHash($filePath, $expectedHash, [Parameter(Mandatory=$false)] $algorithm) {
    if ($algorithm -ne $null) {
        $computedHash = Get-FileHash $filePath -Algorithm $algorithm
    } else {
        $computedHash = Get-FileHash $filePath
    }
    if ($computedHash.Hash -ne $expectedHash) {
        Write-Error "incorrect hash for file: $filePath, actual: $($computedHash.Hash), expected: $expectedHash"
        exit 1
    }
}

function Install-STUN() {
    $ZipPath = "stunserver_win64_1_2_16.zip"
    $URL = "http://www.stunprotocol.org/$ZipPath"
    $Destination = "C:\workspace\stunserver"
    $Hash = "CDC8C68400E3B9ECE95F900699CEF1535CFCF4E59C34AF9A33F4679638ACA3A1"

    echo "Downloading $URL"
    curl.exe -L $URL -o $ZipPath
    CheckStatus

    Validate-FileHash $ZipPath $Hash

    echo "Extracting $ZipPath to $Destination"
    Expand-Archive $ZipPath -DestinationPath $Destination
    CheckStatus
}

function Install-iperf() {
    $ZipPath = "iperf3.17_64.zip"
    $URL = "https://files.budman.pw/$ZipPath"
    $Hash = "C1AB63DE610D73779D1003753F8DCD3FAAE0B6AC5BE1EAF31BBF4A1D3D2E3356"
    $Destination = "C:\workspace\iperf3"
    $DestinationTmp = "$Destination.tmp"

    echo "Downloading $URL"
    curl.exe -L $URL -o $ZipPath
    CheckStatus

    Validate-FileHash $ZipPath $Hash

    echo "Extracting $ZipPath to $DestinationTmp"
    Expand-Archive $ZipPath -DestinationPath $DestinationTmp
    CheckStatus

    $firstSubDir = Get-ChildItem -Path $DestinationTmp -Directory | Select-Object -First 1
    echo "Moving $DestinationTmp\$firstSubDir to $Destination"
    mv $DestinationTmp\$firstSubDir $Destination
    Remove-Item $DestinationTmp
}

function Install-Python() {
    $InstallerPath = "python-3.13.0-amd64.exe"
    $URL = "https://www.python.org/ftp/python/3.13.0/$InstallerPath"
    $Hash = "78156AD0CF0EC4123BFB5333B40F078596EBF15F2D062A10144863680AFBDEFC"

    echo "Downloading $URL"
    curl.exe -L $URL -o $InstallerPath
    CheckStatus

    Validate-FileHash $InstallerPath $Hash

    echo "Installing python.."
    Start-Process -NoNewWindow -Wait -FilePath $PWD\$InstallerPath -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1 Include_test=0 Include_doc=0 Include_dev=1 Include_launcher=0 Include_tcltk=0"
    CheckStatus

    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", [System.EnvironmentVariableTarget]::Machine)

    python.exe -m pip install --upgrade pip
}

function Install-WinDump() {
    $InstallerPath = "nmap-7.12-setup.exe"
    $URL = "https://nmap.org/dist/$InstallerPath"
    $Hash = "56580F1EEBDCCFBC5CE6D75690600225738DDBE8D991A417E56032869B0F43C7"

    echo "Downloading $URL"
    curl.exe -L $URL -o $InstallerPath
    CheckStatus

    Validate-FileHash $InstallerPath $Hash

    echo "Installing winpcap.."
    Start-Process -NoNewWindow -Wait -FilePath $PWD\$InstallerPath -ArgumentList "/S"
    CheckStatus

    sc.exe config npf start= auto
    CheckStatus

    $BinaryPath = "WinDump.exe"
    $URL = "https://www.winpcap.org/windump/install/bin/windump_3_9_5/$BinaryPath"
    $Hash = "d59bc54721951dec855cbb4bbc000f9a71ea4d95"

    echo "Downloading $URL"
    curl.exe -L $URL -o $BinaryPath
    CheckStatus

    Validate-FileHash $BinaryPath $Hash SHA1
}

function Install-QGA() {
    # Define QEMU Guest Agent installer URL (change version if needed)
    $QGA_URL = "https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso"
    $QGA_ISO = "$env:TEMP\virtio-win.iso"

    # Download QEMU Guest Agent ISO
    Write-Host "Downloading QEMU Guest Agent ISO..."
    curl.exe -L $QGA_URL -o $QGA_ISO

    # Mount the ISO
    Write-Host "Mounting ISO..."
    $mount = Mount-DiskImage -ImagePath $QGA_ISO -PassThru | Get-Volume
    $QGA_DRIVE = $mount.DriveLetter + ":"

    # Define installer path
    $QGA_MSI = "$QGA_DRIVE\guest-agent\qemu-ga-x86_64.msi"

    # Install QEMU Guest Agent
    Write-Host "Installing QEMU Guest Agent..."
    Start-Process msiexec.exe -ArgumentList "/i `"$QGA_MSI`" /quiet /norestart" -Wait -NoNewWindow

    Get-Service QEMU-GA

    # Unmount the ISO
    Write-Host "Unmounting ISO..."
    Dismount-DiskImage -ImagePath $QGA_ISO

    # Cleanup
    Remove-Item -Path $QGA_ISO -Force

    Write-Host "QEMU Guest Agent installation complete."
}

[System.IO.Directory]::CreateDirectory("C:\workspace")
CheckStatus

cd C:\workspace
setx PATH "%PATH%;C:\workspace\uniffi"

Install-STUN
CheckStatus

Install-iperf
CheckStatus

Install-Python
CheckStatus

Install-WinDump
CheckStatus

Install-QGA
CheckStatus

pip install Pyro5==5.15

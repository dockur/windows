@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "SETUP_STARTED=%SCRIPT_DIR%setup.started"
set "SETUP_COMPLETE=%SCRIPT_DIR%setup.complete"

if "%~1"=="" goto setup
if /i "%~1"=="pe" goto pe
if /i "%~1"=="setup" goto setup
if /i "%~1"=="logon" goto logon
if /i "%~1"=="specialize" goto specialize
exit /b 2

:pe

reg.exe add "HKLM\SYSTEM\Setup\LabConfig" /v BypassTPMCheck /t REG_DWORD /d 1 /f
reg.exe add "HKLM\SYSTEM\Setup\LabConfig" /v BypassSecureBootCheck /t REG_DWORD /d 1 /f
reg.exe add "HKLM\SYSTEM\Setup\LabConfig" /v BypassRAMCheck /t REG_DWORD /d 1 /f
reg.exe add "HKLM\SYSTEM\Setup\MoSetup" /v AllowUpgradesWithUnsupportedTPMOrCPU /t REG_DWORD /d 1 /f

exit /b 0

:specialize

reg.exe add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE" /v BypassNRO /t REG_DWORD /d 1 /f
reg.exe load "HKU\mount" "C:\Users\Default\NTUSER.DAT"
reg.exe add "HKU\mount\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "ContentDeliveryAllowed" /t REG_DWORD /d 0 /f
reg.exe add "HKU\mount\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "FeatureManagementEnabled" /t REG_DWORD /d 0 /f
reg.exe add "HKU\mount\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "OEMPreInstalledAppsEnabled" /t REG_DWORD /d 0 /f
reg.exe add "HKU\mount\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "PreInstalledAppsEnabled" /t REG_DWORD /d 0 /f
reg.exe add "HKU\mount\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "PreInstalledAppsEverEnabled" /t REG_DWORD /d 0 /f
reg.exe add "HKU\mount\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "SilentInstalledAppsEnabled" /t REG_DWORD /d 0 /f
reg.exe add "HKU\mount\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "SoftLandingEnabled" /t REG_DWORD /d 0 /f
reg.exe add "HKU\mount\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "SubscribedContentEnabled" /t REG_DWORD /d 0 /f
reg.exe add "HKU\mount\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "SubscribedContent-310093Enabled" /t REG_DWORD /d 0 /f
reg.exe add "HKU\mount\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "SubscribedContent-338387Enabled" /t REG_DWORD /d 0 /f
reg.exe add "HKU\mount\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "SubscribedContent-338388Enabled" /t REG_DWORD /d 0 /f
reg.exe add "HKU\mount\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "SubscribedContent-338389Enabled" /t REG_DWORD /d 0 /f
reg.exe add "HKU\mount\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "SubscribedContent-338393Enabled" /t REG_DWORD /d 0 /f
reg.exe add "HKU\mount\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "SubscribedContent-353698Enabled" /t REG_DWORD /d 0 /f
reg.exe add "HKU\mount\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "SystemPaneSuggestionsEnabled" /t REG_DWORD /d 0 /f
reg.exe add "HKU\mount\Software\Policies\Microsoft\Windows\CloudContent" /v "DisableCloudOptimizedContent" /t REG_DWORD /d 1 /f
reg.exe add "HKU\mount\Software\Policies\Microsoft\Windows\CloudContent" /v "DisableWindowsConsumerFeatures" /t REG_DWORD /d 1 /f
reg.exe add "HKU\mount\Software\Policies\Microsoft\Windows\CloudContent" /v "DisableConsumerAccountStateContent" /t REG_DWORD /d 1 /f
reg.exe unload "HKU\mount"
reg.exe add "HKLM\Software\Policies\Microsoft\Windows\CloudContent" /v "DisableCloudOptimizedContent" /t REG_DWORD /d 1 /f
reg.exe add "HKLM\Software\Policies\Microsoft\Windows\CloudContent" /v "DisableWindowsConsumerFeatures" /t REG_DWORD /d 1 /f
reg.exe add "HKLM\Software\Policies\Microsoft\Windows\CloudContent" /v "DisableConsumerAccountStateContent" /t REG_DWORD /d 1 /f

rem Set Network Location to Home
reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\CurrentVersion\NetworkList\Signatures\FirstNetwork" /v Category /t REG_DWORD /d 1 /f

rem Install the VMWare display driver before Windows Setup's final reboot.
certutil.exe -addstore -f Root "%SystemRoot%\Drivers\vmsvga\vm3d.cer" >nul 2>&1
certutil.exe -addstore -f TrustedPublisher "%SystemRoot%\Drivers\vmsvga\vm3d.cer" >nul 2>&1
start "" /wait /b pnputil.exe -i -a "%SystemRoot%\Drivers\vmsvga\vm3d.inf" >nul 2>&1

exit /b 0

:setup
if exist "%SETUP_COMPLETE%" exit /b 0

type nul > "%SETUP_STARTED%"

rem Allow guest access to network shares.
reg.exe add "HKLM\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" /v "AllowInsecureGuestAuth" /t REG_DWORD /d 1 /f

rem Disable the SMB signing requirement.
reg.exe add "HKLM\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" /v "RequireSecuritySignature" /t REG_DWORD /d 0 /f

rem Enable the option for passwordless sign-in.
reg.exe add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\PasswordLess\Device" /v "DevicePasswordLessBuildVersion" /t REG_DWORD /d 0 /f

rem BEGIN LOCAL_ACCOUNT
rem Prevent the local user password from expiring.
powershell.exe -ExecutionPolicy Unrestricted -NoLogo -NoProfile -NonInteractive set-localuser -name "Docker" -passwordneverexpires 1
rem END LOCAL_ACCOUNT

rem Disable hibernation.
POWERCFG -H OFF

rem Disable monitor blanking.
POWERCFG -X -monitor-timeout-ac 0

rem Disable first-run experience in Edge.
reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Edge" /v "HideFirstRunExperience" /t REG_DWORD /d 1 /f

rem Disable hibernation in the registry.
reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\Power" /v "HibernateFileSizePercent" /t REG_DWORD /d 0 /f

rem Disable hibernation.
reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\Power" /v "HibernateEnabled" /t REG_DWORD /d 0 /f

rem Disable sleep.
POWERCFG -X -standby-timeout-ac 0

rem Enable RemoteAPP to launch unlisted programs.
reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" /v "fAllowUnlistedRemotePrograms" /t REG_DWORD /d 1 /f

rem Disable RemoteApp allowlist.
reg.exe add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Terminal Server\TSAppAllowList" /v "fDisabledAllowList" /t REG_DWORD /d 1 /f

rem Turn off automatic Windows Update downloads.
reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v "NoAutoUpdate" /t REG_DWORD /d 1 /f

rem Enable Network Discovery.
netsh advfirewall firewall set rule group="@FirewallAPI.dll,-32752" new enable=Yes

rem Enable File Sharing.
netsh advfirewall firewall set rule group="@FirewallAPI.dll,-28502" new enable=Yes

rem Remove the empty Windows.old folder.
if exist "%SystemDrive%\Windows.old" rd /q "%SystemDrive%\Windows.old"

rem Install the VirtIO Balloon service once.
sc.exe query BalloonService >nul 2>&1
if errorlevel 1 "%SystemRoot%\Drivers\Balloon\blnsvr.exe" -i

rem BEGIN PRODUCT_KEY
rem Install the product key without activating Windows immediately.
cscript.exe //B //Nologo "%SystemRoot%\System32\slmgr.vbs" /ipk "XXX"
rem END PRODUCT_KEY

rem Install the VirtIO display driver last to avoid disrupting earlier setup work.
pnputil.exe -i -a "%SystemRoot%\Drivers\viogpudo\viogpudo.inf"

type nul > "%SETUP_COMPLETE%"
exit /b 0

:logon
rem Run the machine setup here when the SetupComplete hook was skipped.
if not exist "%SETUP_COMPLETE%" call "%~f0" setup

rem Hide Copilot button.
reg.exe add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v "ShowCopilotButton" /t REG_DWORD /d 0 /f

rem Show file extensions in Explorer.
reg.exe add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v "HideFileExt" /t REG_DWORD /d 0 /f

rem Remove Task View from the Taskbar.
reg.exe add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v "ShowTaskViewButton" /t REG_DWORD /d 0 /f

rem Remove Widgets from the Taskbar.
reg.exe add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v "TaskbarDa" /t REG_DWORD /d 0 /f

rem Remove Chat from the Taskbar.
reg.exe add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v "TaskbarMn" /t REG_DWORD /d 0 /f

rem Disable unsupported hardware notifications.
reg.exe add "HKCU\Control Panel\UnsupportedHardwareNotificationCache" /v SV1 /d 0 /t REG_DWORD /f

rem Disable unsupported hardware notifications.
reg.exe add "HKCU\Control Panel\UnsupportedHardwareNotificationCache" /v SV2 /d 0 /t REG_DWORD /f

rem BEGIN SHARED_FOLDER
rem Add the shared folder to the desktop and map it to drive Z:.
if not exist "%USERPROFILE%\Desktop\Shared" mklink /d "%USERPROFILE%\Desktop\Shared" \\host.lan\Data
net.exe use Z: \\host.lan\Data /persistent:yes
rem END SHARED_FOLDER

rem BEGIN OEM_SCRIPT
rem Launch the custom script asynchronously in a separate visible window.
if exist "C:\OEM\install.bat" start "Install" cmd.exe /d /c ""C:\OEM\install.bat""
rem END OEM_SCRIPT

exit /b 0

pushd "C:/OEM"

powershell -ExecutionPolicy Bypass -File "dependencies_windows.ps1"
powershell -ExecutionPolicy Bypass -File "optimize.ps1"
powershell -ExecutionPolicy Bypass -File "disable_updates.ps1"

popd

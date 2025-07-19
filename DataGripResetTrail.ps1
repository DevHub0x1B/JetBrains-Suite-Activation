# PowerShell script to reset the JetBrains DataGrip trial period on Windows
# Note: This is an unofficial method and may violate JetBrains' terms of service.
# Run with administrative privileges. Backup your settings before proceeding.

# Define the base directory for JetBrains configuration
$jetBrainsDir = "$env:APPDATA\JetBrains"
$dataGripConfigDir = Get-ChildItem -Path $jetBrainsDir -Directory -Filter "DataGrip*" | Select-Object -First 1 -ExpandProperty FullName

if (-not $dataGripConfigDir) {
    Write-Host "Error: No DataGrip configuration directory found in $jetBrainsDir. Ensure DataGrip is installed."
    exit 1
}

# Define paths for trial-related files
$evalDir = Join-Path $dataGripConfigDir "eval"
$optionsXml = Join-Path $dataGripConfigDir "options\other.xml"
$permanentUserId = Join-Path $jetBrainsDir "PermanentUserId"
$javaPrefsDir = "$env:USERPROFILE\.java\.userPrefs"

# Check and remove trial files
Write-Host "Attempting to reset DataGrip trial by removing configuration files..."

if (Test-Path $evalDir) {
    Remove-Item -Path $evalDir -Recurse -Force
    Write-Host "Removed eval directory: $evalDir"
} else {
    Write-Host "eval directory not found, skipping."
}

if (Test-Path $optionsXml) {
    Remove-Item -Path $optionsXml -Force
    Write-Host "Removed options XML: $optionsXml"
} else {
    Write-Host "options XML not found, skipping."
}

if (Test-Path $permanentUserId) {
    # Modify PermanentUserId by appending a random character instead of deleting to potentially reset trial
    $content = Get-Content $permanentUserId -Raw
    $newContent = $content + (Get-Random -Minimum 0 -Maximum 9).ToString()
    Set-Content -Path $permanentUserId -Value $newContent
    Write-Host "Modified PermanentUserId to reset trial tracking."
} else {
    Write-Host "PermanentUserId not found, skipping."
}

if (Test-Path $javaPrefsDir) {
    Remove-Item -Path $javaPrefsDir -Recurse -Force
    Write-Host "Removed Java preferences directory: $javaPrefsDir"
} else {
    Write-Host "Java preferences directory not found, skipping."
}

# Optional: Remove registry entries if they exist (JetBrains may use these for trial tracking)
$regPath = "HKCU:\Software\JavaSoft\Prefs\jetbrains"
if (Test-Path $regPath) {
    Remove-Item -Path $regPath -Recurse -Force
    Write-Host "Removed JetBrains registry entries at $regPath"
} else {
    Write-Host "JetBrains registry entries not found, skipping."
}

# Prompt to restart DataGrip
Write-Host "Trial reset attempt completed. Please close DataGrip if it is running."
$restart = Read-Host "Restart DataGrip now to start a new trial? (Y/N)"
if ($restart -eq 'Y' -or $restart -eq 'y') {
    # Attempt to launch DataGrip (adjust path based on installation)
    $dataGripExe = Get-ChildItem -Path "$env:ProgramFiles\JetBrains\DataGrip*" -Recurse -File -Filter "datagrip*.exe" | Select-Object -First 1 -ExpandProperty FullName
    if ($dataGripExe) {
        Start-Process -FilePath $dataGripExe
        Write-Host "Launched DataGrip. Check if the trial has reset."
    } else {
        Write-Host "DataGrip executable not found. Please launch it manually."
    }
} else {
    Write-Host "Please launch DataGrip manually after closing it to check the trial status."
}

Write-Host "Note: If the trial does not reset, uninstall and reinstall DataGrip, or contact sales@jetbrains.com for a trial extension."
#requires -Version 5.0
#requires -RunAsAdministrator

# Clear the console and set UTF-8 encoding
Clear-Host
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Global variable for debug output
$script:EnableDebug = $false

# Log output function
function Write-Log {
    param (
        [Parameter(Mandatory)]
        [string]$Message,
        [ValidateSet("INFO", "DEBUG", "WARNING", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )

    if ($Level -eq "DEBUG" -and -not $script:EnableDebug) { return }

    $color = switch ($Level) {
        "INFO"    { "White" }
        "DEBUG"   { "DarkGray" }
        "WARNING" { "Yellow" }
        "ERROR"   { "Red" }
        "SUCCESS" { "Green" }
    }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $output = if ($Message.StartsWith("`n")) {
        $Message = $Message.Substring(1)
        "`n[$timestamp][$Level] $Message"
    } else {
        "[$timestamp][$Level] $Message"
    }

    Write-Host $output -ForegroundColor $color
}

# Helper functions for specific log levels
function Write-DebugLog   { param([string]$Message) Write-Log -Message $Message -Level "DEBUG" }
function Write-WarningLog { param([string]$Message) Write-Log -Message $Message -Level "WARNING" }
function Write-ErrorLog   { param([string]$Message) Write-Log -Message $Message -Level "ERROR" }
function Write-SuccessLog { param([string]$Message) Write-Log -Message $Message -Level "SUCCESS" }

# Exit the program after user input
function Exit-Program {
    $null = Read-Host "Press Enter to exit..."
    exit 1
}

# Custom progress bar
function Write-ProgressCustom {
    param (
        [string]$Message,
        [string]$ProgressBar,
        [double]$Percent,
        [string]$Color = "White"
    )

    $output = "{0} {1} {2:F2}%" -f $Message.PadRight(10), $ProgressBar, $Percent
    Write-Host "`r$output".PadRight(100) -ForegroundColor $Color -NoNewline
}

# Create HttpClient instance
function New-HttpClient {
    param ([int]$TimeoutSeconds = 30)

    Add-Type -AssemblyName System.Net.Http
    $handler = [System.Net.Http.HttpClientHandler]::new()
    $handler.UseDefaultCredentials = $true
    $handler.Proxy = [System.Net.WebProxy]::new()

    $client = [System.Net.Http.HttpClient]::new($handler)
    $client.Timeout = [System.TimeSpan]::FromSeconds($TimeoutSeconds)

    $osVersion = [Environment]::OSVersion.Version.ToString()
    $psVersion = $PSVersionTable.PSVersion.ToString()
    $client.DefaultRequestHeaders.UserAgent.ParseAdd("PowerShell/$psVersion (Windows NT $osVersion)")

    return $client
}

# Read valid date input
function Read-ValidDate {
    param (
        [string]$Prompt,
        [string]$Default = "2099-12-31"
    )

    $date = ""
    while ([string]::IsNullOrWhiteSpace($date) -or $date -notmatch '^\d{4}-\d{2}-\d{2}$') {
        $date = Read-Host -Prompt $Prompt
        if ([string]::IsNullOrWhiteSpace($date)) {
            return $Default
        }

        if ($date -notmatch '^\d{4}-\d{2}-\d{2}$') {
            Write-Host "Invalid format: Please use yyyy-MM-dd" -ForegroundColor Red
            continue
        }

        if (-not [DateTime]::TryParseExact($date, "yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$null)) {
            Write-Host "Invalid date: $date" -ForegroundColor Red
            $date = ""
        }
    }
    return $date
}

# Display JetBrains ASCII logo
function Show-JetBrainsAscii {
    Write-Host @"
JJJJJJ   EEEEEEE   TTTTTTTT  BBBBBBB    RRRRRR    AAAAAA    IIIIIIII  NNNN   NN   SSSSSS
   JJ    EE           TT     BB    BB   RR   RR   AA  AA       II     NNNNN  NN  SS
   JJ    EE           TT     BB    BB   RR   RR   AA  AA       II     NN NNN NN   SS
   JJ    EEEEE        TT     BBBBBBB    RRRRRR    AAAAAA       II     NN  NNNNN    SSSSS
   JJ    EE           TT     BB    BB   RR  RR    AA  AA       II     NN   NNNN         SS
JJ JJ    EE           TT     BB    BB   RR   RR   AA  AA       II     NN    NNN          SS
 JJJJ    EEEEEEE      TT     BBBBBBB    RR   RR   AA  AA    IIIIIIII  NN    NNN    SSSSSS
"@ -ForegroundColor Cyan
}

# Get property value from idea.properties
function Get-PropertyValue {
    param (
        [string]$FilePath,
        [string]$KeyToFind
    )

    Write-DebugLog "Reading config file: $FilePath, searching for key: $KeyToFind"
    try {
        $content = Get-Content -Path $FilePath -Encoding UTF8 -ErrorAction Stop
        foreach ($line in $content) {
            $line = $line.Trim()
            if ($line -notmatch '^#' -and -not [string]::IsNullOrWhiteSpace($line) -and $line -match '^\s*([^#=]+?)\s*=\s*(.*)$') {
                $key = $matches[1].Trim()
                $value = $matches[2].Trim()
                if ($key -eq $KeyToFind) {
                    $value = $value.Replace('${user.home}', $script:UserProfile)
                    $cleanValue = [System.IO.Path]::GetFullPath($value.Replace('/', '\'))
                    Write-DebugLog "Found key '$KeyToFind' with value '$cleanValue'"
                    return $cleanValue
                }
            }
        }
    } catch {
        Write-DebugLog "Failed to read config file: $_"
    }
}

# Remove environment variables
function Remove-EnvironmentVariables {
    param (
        [string]$Scope,
        [array]$Products
    )

    Write-Log "`nProcessing $Scope environment variables"
    foreach ($product in $Products) {
        $keys = @(
        "$($product.Name.ToUpper()).VMOPTIONS",
        "$($product.Name.ToLower()).vmoptions",
        "$($product.Name.ToUpper())_VM_OPTIONS"
        )

        foreach ($key in $keys) {
            $value = [Environment]::GetEnvironmentVariable($key, $Scope)
            Write-DebugLog "Checking [$Scope]: $key = '$value'"
            if ($value) {
                Write-Log "Removing [$Scope]: $key"
                [Environment]::SetEnvironmentVariable($key, $null, $Scope)
            }
        }
    }
}

# Create working directories
function New-WorkingDirectories {
    try {
        if (Test-Path -Path $script:WorkDir) {
            Remove-Item -Path $script:WorkDir -Recurse -Force -ErrorAction Stop
        }
        New-Item -Path $script:WorkDir -ItemType Directory -Force | Out-Null
        New-Item -Path $script:ConfigDir -ItemType Directory -Force | Out-Null
        New-Item -Path $script:PluginsDir -ItemType Directory -Force | Out-Null
    } catch {
        Write-ErrorLog "Files in use. Please close all JetBrains IDEs and try again!"
        Exit-Program
    }
}

# Download required files
function Download-Files {
    $files = @(
    @{ Url = "$script:DownloadUrl/ja-netfilter.jar"; SavePath = $script:NetfilterJar },
    @{ Url = "$script:DownloadUrl/config/dns.conf"; SavePath = Join-Path $script:ConfigDir "dns.conf" },
    @{ Url = "$script:DownloadUrl/config/native.conf"; SavePath = Join-Path $script:ConfigDir "native.conf" },
    @{ Url = "$script:DownloadUrl/config/power.conf"; SavePath = Join-Path $script:ConfigDir "power.conf" },
    @{ Url = "$script:DownloadUrl/config/url.conf"; SavePath = Join-Path $script:ConfigDir "url.conf" },
    @{ Url = "$script:DownloadUrl/plugins/dns.jar"; SavePath = Join-Path $script:PluginsDir "dns.jar" },
    @{ Url = "$script:DownloadUrl/plugins/native.jar"; SavePath = Join-Path $script:PluginsDir "native.jar" },
    @{ Url = "$script:DownloadUrl/plugins/power.jar"; SavePath = Join-Path $script:PluginsDir "power.jar" },
    @{ Url = "$script:DownloadUrl/plugins/url.jar"; SavePath = Join-Path $script:PluginsDir "url.jar" },
    @{ Url = "$script:DownloadUrl/plugins/hideme.jar"; SavePath = Join-Path $script:PluginsDir "hideme.jar" },
    @{ Url = "$script:DownloadUrl/plugins/privacy.jar"; SavePath = Join-Path $script:PluginsDir "privacy.jar" }
    )

    $client = New-HttpClient
    $totalFiles = $files.Count
    $currentFile = 0

    Write-DebugLog "Source ja-netfilter URL: https://gitee.com/ja-netfilter/ja-netfilter/releases/tag/2022.2.0"
    Write-DebugLog "Verify SHA1 for file integrity"

    foreach ($file in $files) {
        $currentFile++
        $percent = [math]::Round(($currentFile / $totalFiles) * 100, 2)
        $barLength = 30
        $filledBars = [math]::Floor($percent / (100 / $barLength))
        $progressBar = "[" + ("#" * $filledBars) + ("." * ($barLength - $filledBars)) + "]"

        Write-ProgressCustom -Message "Configuring ja-netfilter:" -ProgressBar $progressBar -Percent $percent -Color Green

        try {
            $response = $client.GetAsync($file.Url).Result
            $response.EnsureSuccessStatusCode() | Out-Null
            $content = $response.Content.ReadAsByteArrayAsync().Result
            [System.IO.File]::WriteAllBytes($file.SavePath, $content)

            if ($file.Url -like "*.jar") {
                $sha1 = [BitConverter]::ToString([Security.Cryptography.SHA1]::Create().ComputeHash($content)).Replace("-", "")
                Write-DebugLog "SHA1: $sha1"
            }
        } catch {
            Write-ErrorLog "Download failed: $($file.Url)"
            Write-DebugLog "Request failed: $($_.Exception.Message)"
            $client.CancelPendingRequests()
            Exit-Program
        }
    }

    $client.Dispose()
}

# Clean vmoptions file
function Clear-VmOptions {
    param ([string]$FilePath)

    if (Test-Path -Path $FilePath) {
        $lines = Get-Content -Path $FilePath -Encoding UTF8 -ErrorAction SilentlyContinue
        $filteredLines = $lines | Where-Object {
            -not $script:RegexJavaAgent.IsMatch($_) -and
                    -not $script:RegexAsmTree.IsMatch($_) -and
                    -not $script:RegexAsm.IsMatch($_)
        }
        Set-Content -Path $FilePath -Value $filteredLines -Force -Encoding UTF8
        Write-DebugLog "Cleaned VMOptions: $FilePath"
    }
}

# Append to vmoptions file
function Add-VmOptions {
    param ([string]$FilePath)

    if (Test-Path -Path $FilePath) {
        Add-Content -Path $FilePath -Value $script:VmOptionsContent -Force -Encoding UTF8
        Write-DebugLog "Updated VMOptions: $FilePath"
    }
}

# Generate activation key
function New-ActivationKey {
    param (
        [hashtable]$Product,
        [string]$ProductFullName,
        [string]$CustomConfigPath
    )

    Write-DebugLog "Processing config: $($Product.Name), $ProductFullName, $CustomConfigPath"

    $productDir = if ($CustomConfigPath) { $CustomConfigPath } else { Join-Path $script:RoamingJetBrainsDir $ProductFullName }
    if (-not (Test-Path $productDir)) {
        Write-WarningLog "$ProductFullName requires manual activation!"
        return
    }

    $vmOptionsFile = Join-Path $productDir "$($Product.Name)64.exe.vmoptions"
    $keyFile = Join-Path $productDir "$($Product.Name).key"

    if (Test-Path $vmOptionsFile) {
        Write-DebugLog "$ProductFullName config exists, cleaning..."
        Clear-VmOptions -FilePath $vmOptionsFile
    }

    if (Test-Path $keyFile) {
        Write-DebugLog "Key exists, cleaning..."
        Remove-Item -Path $keyFile -Force
    }

    $jsonBody = @{
        assigneeName = $script:License.assigneeName
        expiryDate   = $script:License.expiryDate
        licenseName  = $script:License.licenseName
        productCode  = $Product.product_code
    } | ConvertTo-Json -Compress

    Write-DebugLog "Requesting key: $script:LicenseUrl, Body: $jsonBody, Save to: $keyFile"
    $client = New-HttpClient
    try {
        $content = [System.Net.Http.StringContent]::new($jsonBody, [System.Text.Encoding]::UTF8, "application/json")
        $response = $client.PostAsync($script:LicenseUrl, $content).Result
        $response.EnsureSuccessStatusCode() | Out-Null
        $keyBytes = $response.Content.ReadAsByteArrayAsync().Result
        Write-DebugLog "Writing key, activating: $keyFile"
        [System.IO.File]::WriteAllBytes($keyFile, $keyBytes)
        Write-SuccessLog "$ProductFullName activated successfully!"
    } catch {
        Write-WarningLog "$ProductFullName requires manual activation!"
        Write-DebugLog "$ProductFullName request failed: $($_.Exception.Message)"
    } finally {
        $client.Dispose()
    }
}

# Process JetBrains products
function Update-VmOptions {
    Write-Log "`nProcessing configurations..."

    if (-not (Test-Path $script:LocalJetBrainsDir)) {
        Write-ErrorLog "Directory not found: $script:LocalJetBrainsDir"
        Exit-Program
    }

    $productDirs = Get-ChildItem -Path $script:LocalJetBrainsDir -Directory
    foreach ($dir in $productDirs) {
        $product = Get-Product -ProductDirName $dir.Name
        if (-not $product) { continue }

        Write-Log "`nProcessing: $dir"

        $homeFile = Join-Path $dir.FullName ".home"
        if (-not (Test-Path $homeFile)) {
            Write-WarningLog "Missing .home file: $homeFile"
            continue
        }

        Write-DebugLog "Found .home file: $homeFile"
        $homeContent = Get-Content -Path $homeFile -Encoding UTF8
        if (-not (Test-Path $homeContent)) {
            Write-WarningLog "Path does not exist: $homeContent"
            continue
        }

        Write-DebugLog "Read .home file content: $homeContent"
        $binDir = Join-Path $homeContent "bin"
        if (-not (Test-Path $binDir)) {
            Write-WarningLog "Missing bin directory: $binDir"
            continue
        }

        Write-DebugLog "Found bin directory: $binDir"
        $vmOptionsFiles = Get-ChildItem -Path $binDir -Filter "*.vmoptions" -Recurse
        foreach ($file in $vmOptionsFiles) {
            Clear-VmOptions -FilePath $file.FullName
            Add-VmOptions -FilePath $file.FullName
        }

        $propertiesFile = Join-Path $binDir "idea.properties"
        $customConfigPath = Get-PropertyValue -FilePath $propertiesFile -KeyToFind "idea.config.path"
        New-ActivationKey -Product $product -ProductFullName $dir.Name -CustomConfigPath $customConfigPath
    }
}

# Check if directory corresponds to a JetBrains product
function Get-Product {
    param ([string]$ProductDirName)

    foreach ($product in $script:Products) {
        if ($ProductDirName.ToLower() -like "*$($product.Name)*") {
            return $product
        }
    }
    return $null
}

# Get user license information
function Read-LicenseInfo {
    $licenseName = Read-Host -Prompt "Enter custom license name (default: ckey.run)"
    $script:License.licenseName = if ([string]::IsNullOrEmpty($licenseName)) { "ckey.run" } else { $licenseName }

    $expiry = Read-ValidDate -Prompt "Enter license expiry date (default: 2099-12-31)"
    $script:License.expiryDate = $expiry
}

# Main program
function Main {
    Show-JetBrainsAscii
    Write-Log "`nWelcome to JetBrains Activation Tool | CodeKey Run"
    Write-WarningLog "`nScript date: 2025-07-07 15:54:30"
    Write-ErrorLog "`nWARNING: This script will forcibly reactivate all products!"

    # Check for administrator privileges
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-WarningLog "Requesting administrator privileges. Press Enter to continue..."
        $null = Read-Host
        Start-Process powershell.exe -ArgumentList "-NoProfile -Command irm ckey.run | iex" -Verb RunAs
        exit -1
    }

    Write-WarningLog "`nEnsure all JetBrains software is closed. Press Enter to continue..."
    $null = Read-Host

    # Initialize global variables
    $script:UserProfile = [Environment]::GetEnvironmentVariable("USERPROFILE")
    $script:PublicPath = [Environment]::GetEnvironmentVariable("PUBLIC")
    $script:BaseUrl = "https://ckey.run"
    $script:DownloadUrl = "$script:BaseUrl/ja-netfilter"
    $script:LicenseUrl = "$script:BaseUrl/generateLicense/file"
    $script:WorkDir = Join-Path $script:PublicPath ".jb_run"
    $script:ConfigDir = Join-Path $script:WorkDir "config"
    $script:PluginsDir = Join-Path $script:WorkDir "plugins"
    $script:NetfilterJar = Join-Path $script:WorkDir "ja-netfilter.jar"
    $script:LocalJetBrainsDir = Join-Path $script:UserProfile "AppData\Local\JetBrains"
    $script:RoamingJetBrainsDir = Join-Path $script:UserProfile "AppData\Roaming\JetBrains"

    # Regular expressions
    $script:RegexJavaAgent = [regex]::new('^-javaagent:.*[/\\]*\.jar.*', 'IgnoreCase, Compiled')
    $script:RegexAsmTree = [regex]::new('^--add-opens=java.base/jdk.internal.org.objectweb.asm.tree=ALL-UNNAMED', 'IgnoreCase, Compiled')
    $script:RegexAsm = [regex]::new('^--add-opens=java.base/jdk.internal.org.objectweb.asm=ALL-UNNAMED', 'IgnoreCase, Compiled')

    # VM options content
    $script:VmOptionsContent = @(
    "--add-opens=java.base/jdk.internal.org.objectweb.asm.tree=ALL-UNNAMED",
    "--add-opens=java.base/jdk.internal.org.objectweb.asm=ALL-UNNAMED",
    "-javaagent:$($script:NetfilterJar.Replace('\', '/'))"
    )

    # JetBrains product list
    $script:Products = @(
    @{ Name = "idea";     product_code = "II,PCWMP,PSI" },
    @{ Name = "clion";    product_code = "CL,PSI,PCWMP" },
    @{ Name = "phpstorm"; product_code = "PS,PCWMP,PSI" },
    @{ Name = "goland";   product_code = "GO,PSI,PCWMP" },
    @{ Name = "pycharm";  product_code = "PC,PSI,PCWMP" },
    @{ Name = "webstorm"; product_code = "WS,PCWMP,PSI" },
    @{ Name = "rider";    product_code = "RD,PDB,PSI,PCWMP" },
    @{ Name = "datagrip"; product_code = "DB,PSI,PDB" },
    @{ Name = "rubymine"; product_code = "RM,PCWMP,PSI" },
    @{ Name = "appcode";  product_code = "AC,PCWMP,PSI" },
    @{ Name = "dataspell"; product_code = "DS,PSI,PDB,PCWMP" },
    @{ Name = "dotmemory"; product_code = "DM" },
    @{ Name = "rustrover"; product_code = "RR,PSI,PCWP" }
    )

    # License object
    $script:License = [PSCustomObject]@{
        assigneeName = ""
        expiryDate   = "2099-12-31"
        licenseName  = "ckey.run"
        productCode  = ""
    }

    # Execute main workflow
    Read-LicenseInfo
    Write-Log "`nProcessing, please wait..."

    Remove-EnvironmentVariables -Scope "User" -Products $script:Products
    Remove-EnvironmentVariables -Scope "Machine" -Products $script:Products
    New-WorkingDirectories
    Download-Files
    Update-VmOptions

    Write-Log "`nAll tasks completed. Visit the website for activation codes if needed!"
    Start-Sleep -Seconds 2
    Start-Process "https://ckey.run"
    $null = Read-Host "Press Enter to exit..."
}

# Run main program
Main
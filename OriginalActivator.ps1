# encoding: utf-8

Clear-Host
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# 全局变量：是否启用 DEBUG 输出
$script:enable_debug = $false

# 日志输出函数
function Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$message,

        [ValidateSet("INFO", "DEBUG", "WARNING", "ERROR", "SUCCESS")]
        [string]$level = "INFO"
    )

    if ($level -eq "DEBUG" -and -not $script:enable_debug) { return }

    switch ($level) {
        "INFO" { $color = "White" }
        "DEBUG" { $color = "DarkGray" }
        "WARNING" { $color = "Yellow" }
        "ERROR" { $color = "Red" }
        "SUCCESS" { $color = "Green" }
    }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    if ($message.StartsWith("`n")) {
        $message = $message.Substring(1)
        Write-Host "`n[$timestamp][$level] $message" -ForegroundColor $color
    } else {
        Write-Host "[$timestamp][$level] $message" -ForegroundColor $color
    }
}

function Debug([string]$message) { Log -message $message -level "DEBUG" }
function Warning([string]$message) { Log -message $message -level "WARNING" }
function Error([string]$message) { Log -message $message -level "ERROR" }
function Success([string]$message) { Log -message $message -level "SUCCESS" }

# 结束运行
function Exit-Program{
    $null = Read-Host
    exit 1
}

# 进度条显示
function Write-ProgressCustom ([string]$message, [string]$progress_bar, [double]$percent, [string]$color = "White") {
    $output = "{0} {1} {2}%" -f $message.PadRight(10), $progress_bar, $percent.ToString("F2")
    [Console]::ForegroundColor = $color
    [Console]::Write("`r" + $output.PadRight(100))
    [Console]::ResetColor()
}

# 创建 HttpClient 实例
function Get-HttP_Client ([int]$timeout_seconds = 30) {
    Add-Type -AssemblyName System.Net.Http
    $handler = New-Object System.Net.Http.HttpClientHandler
    $handler.UseDefaultCredentials = $true
    $handler.Proxy = [System.Net.GlobalProxySelection]::GetEmptyWebProxy()

    $obj_http_client = New-Object System.Net.Http.HttpClient($handler)
    $obj_http_client.Timeout = [System.TimeSpan]::FromSeconds($timeout_seconds)

    # 设置 User-Agent
    $os_version = [Environment]::OSVersion.Version.ToString()
    $powershell_ver = $PSVersionTable.PSVersion.ToString()
    $ua = "PowerShell/$powershell_ver (Windows NT $os_version)"
    $obj_http_client.DefaultRequestHeaders.UserAgent.ParseAdd($ua)

    return $obj_http_client
}

# 读取日期输入
function Read-Valid_Date ([string]$prompt, [string]$default = "2099-12-31") {
    $date = ""
    while ([string]::IsNullOrWhiteSpace($date) -or -not ($date -match '^\d{4}-\d{2}-\d{2}$')) {
        $date = Read-Host -Prompt $prompt
        if ([string]::IsNullOrWhiteSpace($date)) {
            $date = $default
            break
        }

        if (-not ($date -match '^\d{4}-\d{2}-\d{2}$')) {
            Write-Host "格式错误：请使用 yyyy-MM-dd 格式" -ForegroundColor Red
            continue
        }

        $date_obj = Get-Date
        if (-not [DateTime]::TryParseExact($date, "yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.Da
        teTimeStyles]::None, [ref]$date_obj)) {
        Write-Host "非法日期：$date" -ForegroundColor Red
        $date = ""
        }
    }
    return $date
}

# 显示 JetBrains ASCII Logo
function Show-Ascii_Jetbrains {
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

# 获取属性值（idea.properties）
function Get_Property_Value ([string]$file_path, [string]$key_to_find) {
    Debug "读取配置文件：$file_path, 寻找键：$key_to_find"

    try {
        Get-Content -Path $file_path -Encoding UTF8 -ErrorAction Stop | ForEach-Object {
            $line = $_.Trim()
            if (-not $line.StartsWith("#") -and -not [string]::IsNullOrWhiteSpace($line)) {
                if ($line -match "^\s*([^#=]+?)\s*=\s*(.*)$") {
                    $key = $matches[1].Trim()
                    $value = $matches[2].Trim()
                    if ($key -eq $key_to_find) {
                        if ($value -match '\$\{user\.home\}') {
                            $value = $value.Replace('${user.home}', $user_path)
                        }
                        $clean_value = [System.IO.Path]::GetFullPath($value.Replace('/', '\').Trim())
                        Debug "找到键 '$key_to_find'，值为 '$clean_value'"
                        return [string]::new($clean_value)
                    }
                }
            }
        }
    } catch {
        Debug "读取配置文件失败：$_"
    }
}

# 清理环境变量
function Remove_Env ([string]$env_scope, [array]$products) {
    Log "`n处理 ${env_scope} 环境变量"

    foreach ($prd in $products) {
        $upper_key = "$($prd.name.ToUpper()).VMOPTIONS"
        $lower_key = "$($prd.name.ToLower()).vmoptions"
        $upper_key2 = "$($prd.name.ToUpper())_VM_OPTIONS"

        $val_upper = [Environment]::GetEnvironmentVariable($upper_key, $env_scope)
        $val_lower = [Environment]::GetEnvironmentVariable($lower_key, $env_scope)
        $val_upper2 = [Environment]::GetEnvironmentVariable($upper_key2, $env_scope)

        Debug "检查 [$env_scope]: $upper_key = '$val_upper'"
        Debug "检查 [$env_scope]: $lower_key = '$val_lower'"
        Debug "检查 [$env_scope]: $upper_key2 = '$val_upper2'"

        if (-not [string]::IsNullOrEmpty($val_upper)) {
            Log "删除 [$env_scope]: $($prd.name)"
            [Environment]::SetEnvironmentVariable($upper_key, $null, $env_scope)
        }

        if ($upper_key -ne $lower_key -and -not [string]::IsNullOrEmpty($val_lower)) {
            Log "删除 [$env_scope]: $($prd.name)"
            [Environment]::SetEnvironmentVariable($lower_key, $null, $env_scope)
        }

        if (-not [string]::IsNullOrEmpty($val_upper2)) {
            Log "删除 [$env_scope]: $($prd.name)"
            [Environment]::SetEnvironmentVariable($upper_key2, $null, $env_scope)
        }
    }
}

# 创建工作目录
function Create_Work_Dir {
    try {
        if (Test-Path -Path $script:dir_work) {
            Remove-Item -Path $script:dir_work -Recurse -Force -ErrorAction Stop
        }
        New-Item -Path $script:dir_work -ItemType Directory -Force | Out-Null
        New-Item -Path $script:dir_config -ItemType Directory -Force | Out-Null
        New-Item -Path $script:dir_plugins -ItemType Directory -Force | Out-Null
    } catch {
        Error "文件被占用，请先关闭所有 JetBrains IDE 后再试！"
        Exit-Program
    }
}

# 下载文件
function File_Download {
    $files = @(
    @{ url = "$script:url_download/ja-netfilter.jar"; save_path = $script:file_netfilter_jar },
    @{ url = "$script:url_download/config/dns.conf"; save_path = [IO.Path]::Combine($script:dir_config, "dns.conf") },
    @{ url = "$script:url_download/config/native.conf"; save_path = [IO.Path]::Combine($script:dir_config, "native.conf") },
    @{ url = "$script:url_download/config/power.conf"; save_path = [IO.Path]::Combine($script:dir_config, "power.conf") },
    @{ url = "$script:url_download/config/url.conf"; save_path = [IO.Path]::Combine($script:dir_config, "url.conf") },

    @{ url = "$script:url_download/plugins/dns.jar"; save_path = [IO.Path]::Combine($script:dir_plugins, "dns.jar") },
    @{ url = "$script:url_download/plugins/native.jar"; save_path = [IO.Path]::Combine($script:dir_plugins, "native.jar") },
    @{ url = "$script:url_download/plugins/power.jar"; save_path = [IO.Path]::Combine($script:dir_plugins, "power.jar") },
    @{ url = "$script:url_download/plugins/url.jar"; save_path = [IO.Path]::Combine($script:dir_plugins, "url.jar") },
    @{ url = "$script:url_download/plugins/hideme.jar"; save_path = [IO.Path]::Combine($script:dir_plugins, "hideme.jar") },
    @{ url = "$script:url_download/plugins/privacy.jar"; save_path = [IO.Path]::Combine($script:dir_plugins, "privacy.jar") }
    )

    $obj_http_client = Get-HttP_Client
    $total_files = $files.Count
    $current_file = 0

    Debug "源 ja-netfilter 地址: https://gitee.com/ja-netfilter/ja-netfilter/releases/tag/2022.2.0"
    Debug "建议核对 SHA1 值以确保完整性"

    foreach ($file in $files) {
        $current_file++
        $percent = [math]::Round(($current_file / $total_files) * 100, 2)
        $bar_length = 30
        $filled_bars = [math]::Floor($percent / (100 / $bar_length))
        $progress_bar = "[" + ("#" * $filled_bars) + ("." * ($bar_length - $filled_bars)) + "]"

        Write-ProgressCustom -message "配置ja-netfilter：" -progress_bar $progress_bar -percent $percent -color Green

        try {
            $response = $obj_http_client.GetAsync($file.url).Result
            $response.EnsureSuccessStatusCode() | Out-Null
            $content = $response.Content.ReadAsByteArrayAsync().Result
            [System.IO.File]::WriteAllBytes($file.save_path, $content)

            if ($file.url.Contains(".jar")) {
                $sha1 = [BitConverter]::ToString([Security.Cryptography.SHA1]::Create().ComputeHash($content))
                Debug "SHA1: $sha1"
            }
        } catch {
            Error "下载失败: $($file.url)"
            Debug "请求失败: $($_.Exception.Message)"
            $obj_http_client.CancelPendingRequests()
            Exit-Program
        }
    }

    $obj_http_client.Dispose()
}

# 清理 vmoptions 文件
function Revert_Vm_Options ([string]$file_path) {
    $lines = Get-Content -Path $file_path -Encoding UTF8 -ErrorAction SilentlyContinue
    $filtered_lines = $lines | Where-Object {
        -not $script:regex.IsMatch($_) -and `
        -not $script:regex_1.IsMatch($_) -and `
        -not $script:regex_2.IsMatch($_)
    }
    Set-Content -Path $file_path -Value $filtered_lines -Force
    Debug "清理 VMOptions: $file_path"
}

# 添加配置到 vmoptions 文件
function Append_Vm_Options ([string]$file_path) {
    if (Test-Path -Path $file_path) {
        Add-Content -Path $file_path -Value $script:content -Force
        Debug "更新 VMOptions: $file_path"
    }
}

# 创建激活密钥
function Create_Key ([hashtable]$product, [string]$prd_full_name, [string]$custom_config_path) {
    Debug "处理配置: $($product.name), $prd_full_name, $custom_config_path"

    if (![string]::IsNullOrWhiteSpace($custom_config_path)) {
        $dir_product = $custom_config_path
    } else {
        $dir_product = Join-Path -Path $script:dir_roaming_jetbrains -ChildPath $prd_full_name
    }

    if (-not (Test-Path -Path $dir_product)) {
        Warning "$prd_full_name 需要手动输入激活码！"
        return
    }

    $file_vm_options = Join-Path -Path $dir_product "$($product.name)64.exe.vmoptions"
    $file_key = Join-Path -Path $dir_product "$($product.name).key"

    if (Test-Path -Path $file_vm_options) {
        Debug "$prd_full_name 配置文件已存在，正在清理..."
        Revert_Vm_Options -file_path $file_vm_options
    }

    if (Test-Path -Path $file_key) {
        Debug "key已存在，正在清理..."
        Remove-Item -Path $file_key -Force
    }

    $json_body = ConvertTo-Json -InputObject @{
        assigneeName = $script:license.assigneeName
        expiryDate   = $script:license.expiryDate
        licenseName  = $script:license.licenseName
        productCode  = $product.product_code
    }
    Debug "请求key: $script:url_license,请求body: $json_body,保存地址: $file_key"
    $obj_http_client = Get-HttP_Client
    try {
        $response = $obj_http_client.PostAsync(
                $script:url_license,
                [System.Net.Http.StringContent]::new($json_body, [System.Text.Encoding]::UTF8, "application/json")
        ).Result

        $response.EnsureSuccessStatusCode() | Out-Null
        $key_bytes = $response.Content.ReadAsByteArrayAsync().Result
        Debug "写入key,激活中: $file_key"
        [System.IO.File]::WriteAllBytes($file_key, $key_bytes)
        Success "$prd_full_name 激活成功！"
    } catch {
        Warning "$prd_full_name 需要手动输入激活码！"
        Debug "$prd_full_name 请求失败: $($_.Exception.Message)"
    } finally {
        $obj_http_client.Dispose()
    }
}

# 处理所有 JetBrains 产品
function Process_Vm_Options {
    Log "`n开始处理配置..."

    #判断$script:dir_local_jetbrains是否存在
    if (!(Test-Path -Path $script:dir_local_jetbrains)) {
        Error "未找到 $script:dir_local_jetbrains 目录!"
        Exit-Program
    }
    $dirs_local_prds = Get-ChildItem -Path $script:dir_local_jetbrains -Directory

    foreach ($dir_prd in $dirs_local_prds) {
        $prd = Is_Product -prd_dir_name $dir_prd.Name
        if ($null -eq $prd) { continue }

        Log "`n处理: $dir_prd"

        $file_home = Join-Path -Path $dir_prd.FullName ".home"
        if (-not (Test-Path -Path $file_home)) {
            Warning "未找到 .home 文件: $file_home"
            continue
        }
        Debug "找到.home文件: $file_home"
        $content_home = Get-Content -Path $file_home -Encoding UTF8
        if (-not (Test-Path -Path $content_home)) {
            Warning "路径不存在: $content_home"
            continue
        }
        Debug "读取.home文件内容: $content_home"
        $dir_real_product = Join-Path -Path $content_home "bin"
        if (-not (Test-Path -Path $dir_real_product)) {
            Warning "未找到 bin 目录: $dir_real_product"
            continue
        }
        Debug "找到bin目录: $dir_real_product"
        $files_vm_options = Get-ChildItem -Path $dir_real_product -Filter "*.vmoptions" -Recurse
        foreach ($file_vm_options in $files_vm_options) {
            Revert_Vm_Options -file_path $file_vm_options.FullName
            Append_Vm_Options -file_path $file_vm_options.FullName
        }

        $file_properties = Join-Path -Path $dir_real_product "idea.properties"
        $custom_config_path = Get_Property_Value -file_path $file_properties -key_to_find "idea.config.path"
        Create_Key -product $prd -prd_full_name $dir_prd.Name -custom_config_path $custom_config_path
    }
}

# 是否是 JetBrains 产品
function Is_Product ([string]$prd_dir_name) {
    foreach ($prd in $script:sPrds) {
        if ($prd_dir_name.ToLower().Contains($prd.name)) {
            return $prd
        }
    }
    return $null
}

# 获取用户授权信息
function Read_Host_License_Info {
    $new_license_name = Read-Host -Prompt "自定义授权名称(回车默认ckey.run)"
    if ([string]::IsNullOrEmpty($new_license_name)) {
        $new_license_name = "ckey.run"
    }
    $script:license.licenseName = $new_license_name

    $new_expiry = Read-Valid_Date -prompt "自定义授权到期时间(回车默认2099-12-31)"
    if ([string]::IsNullOrEmpty($new_expiry)) {
        $new_expiry = "2099-12-31"
    }
    $script:license.expiryDate = $new_expiry
}

# 主程序入口
function Main {
    Show-Ascii_Jetbrains
    Log "`n欢迎使用 JetBrains 激活工具 | CodeKey Run"
    Warning "`n脚本日期：2025-7-7 15:54:30"
    Error "`n注意：此脚本将强制重新激活所有产品！！！"

    # 提权检测
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBui
    ltInRole]"Administrator")) {
    Warning "即将申请管理员权限运行，按回车继续..."
    $null = Read-Host
    Start-Process powershell.exe -ArgumentList "-Command irm ckey.run|iex" -Verb RunAs
    exit -1
    }

    Warning "`n请确保所有 JetBrains 软件已关闭，按回车继续..."
    $null = Read-Host

    # 初始化全局变量
    $user_path = [Environment]::GetEnvironmentVariable("USERPROFILE")
    $public_path = [Environment]::GetEnvironmentVariable("PUBLIC")
    #$script:url_base = "http://127.0.0.1:10768"
    $script:url_base = "https://ckey.run"
    $script:url_download = "$script:url_base/ja-netfilter"
    $script:url_license = "$script:url_base/generateLicense/file"

    $script:dir_work = "$public_path\.jb_run\"
    $script:dir_config = "$script:dir_work\config\"
    $script:dir_plugins = "$script:dir_work\plugins\"
    $script:file_netfilter_jar = Join-Path -Path $script:dir_work "ja-netfilter.jar"
    $script:dir_local_jetbrains = Join-Path -Path $user_path -ChildPath "AppData\Local\JetBrains\"
    $script:dir_roaming_jetbrains = Join-Path -Path $user_path -ChildPath "AppData\Roaming\JetBrains\"

    # 正则表达式
    $pattern = '^-javaagent:.*[/\\]*\.jar.*'
    $script:regex = New-Object System.Text.RegularExpressions.Regex $pattern, ([System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor
    [System.Text.RegularExpressions.RegexOptions]::Compiled)

    $pattern_1 = '^--add-opens=java.base/jdk.internal.org.objectweb.asm.tree=ALL-UNNAMED'
    $script:regex_1 = New-Object System.Text.RegularExpressions.Regex $pattern_1, ([System.Text.RegularExpressions.RegexOptions]::IgnoreCase -
    bor [System.Text.RegularExpressions.RegexOptions]::Compiled)

    $pattern_2 = '^--add-opens=java.base/jdk.internal.org.objectweb.asm=ALL-UNNAMED'
    $script:regex_2 = New-Object System.Text.RegularExpressions.Regex $pattern_2, ([System.Text.RegularExpressions.RegexOptions]::IgnoreCase -
    bor [System.Text.RegularExpressions.RegexOptions]::Compiled)

    # 配置内容
    $script:content = @(
    "--add-opens=java.base/jdk.internal.org.objectweb.asm.tree=ALL-UNNAMED"
    "--add-opens=java.base/jdk.internal.org.objectweb.asm=ALL-UNNAMED"
    "-javaagent:$($script:file_netfilter_jar.Replace("\", "/"))"
    )

    # 产品列表
    $script:sPrds = @(
    @{ name = "idea";     product_code = "II,PCWMP,PSI" }
    @{ name = "clion";    product_code = "CL,PSI,PCWMP" }
    @{ name = "phpstorm"; product_code = "PS,PCWMP,PSI" }
    @{ name = "goland";   product_code = "GO,PSI,PCWMP" }
    @{ name = "pycharm";  product_code = "PC,PSI,PCWMP" }
    @{ name = "webstorm"; product_code = "WS,PCWMP,PSI" }
    @{ name = "rider";    product_code = "RD,PDB,PSI,PCWMP" }
    @{ name = "datagrip"; product_code = "DB,PSI,PDB" }
    @{ name = "rubymine"; product_code = "RM,PCWMP,PSI" }
    @{ name = "appcode";  product_code = "AC,PCWMP,PSI" }
    @{ name = "dataspell"; product_code = "DS,PSI,PDB,PCWMP" }
    @{ name = "dotmemory"; product_code = "DM" }
    @{ name = "rustrover"; product_code = "RR,PSI,PCWP" }
    )

    # 授权信息
    $script:license = [PSCustomObject]@{
    assigneeName = ""
    expiryDate   = "2099-12-31"
    licenseName  = "ckey.run"
    productCode  = ""
    }

    # 开始执行主流程
    Read_Host_License_Info
    Log "`n处理中，请耐心等待..."

    Remove_Env -env_scope "User" -products $script:sPrds
    Remove_Env -env_scope "Machine" -products $script:sPrds

    Create_Work_Dir
    File_Download
    Process_Vm_Options

    Log "`n所有项处理完成，如需激活码，请访问网站获取！"
    Start-Sleep -s 2
    Start-Process "https://ckey.run"
    $null = Read-Host
}

Main
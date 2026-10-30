# kunpeng-jumpbox - shared helpers
# Target: Windows PowerShell 5.1 (Windows 11 default) and PowerShell 7+.

$ErrorActionPreference = 'Stop'

$script:RepoRoot    = Split-Path -Parent $PSScriptRoot
$script:ConfigPath  = Join-Path (Join-Path $script:RepoRoot 'config') 'config.json'

function Write-Info { param([string]$Message) Write-Host "[+] $Message" -ForegroundColor Green }
function Write-Warn { param([string]$Message) Write-Host "[!] $Message" -ForegroundColor Yellow }
function Write-Err  { param([string]$Message) Write-Host "[x] $Message" -ForegroundColor Red }

function Test-Admin {
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-Config {
    if (-not (Test-Path -LiteralPath $script:ConfigPath)) {
        throw "找不到配置文件: $script:ConfigPath"
    }

    $cfg = Get-Content -LiteralPath $script:ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $cfg.forwards) { throw 'config.json 里缺少 forwards' }

    $forwards = @($cfg.forwards)
    if ($forwards.Count -eq 0) { throw 'config.json 里 forwards 为空' }

    foreach ($f in $forwards) {
        if ($null -eq $f.listenPort -or $null -eq $f.targetPort -or [string]::IsNullOrWhiteSpace([string]$f.targetHost)) {
            throw '每条 forwards 都需要 listenPort、targetHost、targetPort'
        }
        if ([string]$f.targetHost -eq 'CHANGE_ME') {
            throw '请先把 config.json 里的 targetHost 改成鲲鹏服务器的内网 IP'
        }

        $lp = 0
        $tp = 0
        if (-not [int]::TryParse([string]$f.listenPort, [ref]$lp) -or $lp -lt 1 -or $lp -gt 65535) {
            throw "listenPort 不合法: $($f.listenPort)"
        }
        if (-not [int]::TryParse([string]$f.targetPort, [ref]$tp) -or $tp -lt 1 -or $tp -gt 65535) {
            throw "targetPort 不合法: $($f.targetPort)"
        }
    }

    if (-not $cfg.sshUser) {
        $cfg | Add-Member -NotePropertyName sshUser -NotePropertyValue '' -Force
    }
    if (-not $cfg.allowFrom) {
        $cfg | Add-Member -NotePropertyName allowFrom -NotePropertyValue 'auto' -Force
    }

    return $cfg
}

function Test-TcpPort {
    param(
        [Parameter(Mandatory = $true)][string]$ComputerName,
        [Parameter(Mandatory = $true)][int]$Port,
        [int]$TimeoutMs = 3000
    )

    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $client.BeginConnect($ComputerName, $Port, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) { return $false }
        $client.EndConnect($iar)
        return $true
    } catch {
        return $false
    } finally {
        try { $client.Close() } catch { }
    }
}

function Get-RdpClientIp {
    # If setup.cmd is being run over RDP, the RDP client's public IP is a very
    # good default for the firewall allow-list.
    try {
        $conn = Get-NetTCPConnection -LocalPort 3389 -State Established -ErrorAction Stop |
            Where-Object { $_.RemoteAddress -and $_.RemoteAddress -notmatch '^(127\.|::1$|::ffff:127\.)' } |
            Select-Object -First 1
        if ($conn) { return $conn.RemoteAddress }
    } catch { }
    return $null
}

function Split-AddressList {
    param([string]$Text)
    return @(
        $Text -split '[,;\s]+' |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object { $_.Trim() }
    )
}

function Resolve-AllowFrom {
    param($ConfigValue)

    $value = $ConfigValue
    if ($value -is [string]) {
        $s = $value.Trim()
        if ($s -eq 'any') { return @('Any') }
        if ($s -ne '' -and $s -ne 'auto') { return @(Split-AddressList $s) }
    } elseif ($value -is [array]) {
        $arr = @($value | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        if ($arr.Count -gt 0) { return $arr }
    }

    $detected = Get-RdpClientIp
    if ($detected) {
        Write-Host "检测到当前远程桌面来源 IP: $detected"
        $answer = Read-Host '只允许这个 IP 访问吗？回车=是；输入 a=任意来源（不推荐）；或输入其他 IP/CIDR'
        if ([string]::IsNullOrWhiteSpace($answer)) { return @($detected) }
        if ($answer.Trim() -eq 'a') {
            Write-Warn '已选择允许任意来源，请只临时使用。'
            return @('Any')
        }
        return @(Split-AddressList $answer)
    }

    Write-Warn '没有检测到远程桌面来源 IP。'
    $answer = Read-Host '请输入允许访问的来源 IP/CIDR（多个用逗号分隔；直接回车=任意来源，不推荐）'
    if ([string]::IsNullOrWhiteSpace($answer)) {
        Write-Warn '已选择允许任意来源，请只临时使用。'
        return @('Any')
    }
    return @(Split-AddressList $answer)
}

function Get-RuleName {
    param([int]$Port)
    return "kunpeng-jumpbox-$Port"
}

function Get-PublicIp {
    foreach ($url in @('https://api.ipify.org', 'https://ifconfig.me/ip')) {
        try {
            $resp = Invoke-WebRequest -Uri $url -TimeoutSec 5 -UseBasicParsing
            $text = ([string]$resp.Content).Trim()
            if ($text -match '^\d{1,3}(\.\d{1,3}){3}$') { return $text }
        } catch { }
    }
    return $null
}

function Get-LocalIPv4 {
    try {
        Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
            Where-Object { $_.IPAddress -ne '127.0.0.1' -and $_.IPAddress -notlike '169.254.*' } |
            Select-Object -ExpandProperty IPAddress |
            Sort-Object -Unique
    } catch { }
}

# kunpeng-jumpbox reverse mode - shared helpers
# Target: Windows PowerShell 5.1 (Windows 11 default) and PowerShell 7+.

$ErrorActionPreference = 'Stop'

$script:ReverseRoot = Split-Path -Parent $PSScriptRoot
$script:ConfigPath  = Join-Path (Join-Path $script:ReverseRoot 'config') 'config.json'
$script:LogDir      = Join-Path $script:ReverseRoot 'logs'
$script:KeyPath     = Join-Path (Join-Path $script:ReverseRoot 'keys') 'tunnel_key'
$script:KnownHosts  = Join-Path (Join-Path $script:ReverseRoot 'config') 'known_hosts'

function Write-Info { param([string]$Message) Write-Host "[+] $Message" -ForegroundColor Green }
function Write-Warn { param([string]$Message) Write-Host "[!] $Message" -ForegroundColor Yellow }
function Write-Err  { param([string]$Message) Write-Host "[x] $Message" -ForegroundColor Red }

function Get-Config {
    if (-not (Test-Path -LiteralPath $script:ConfigPath)) {
        throw "找不到配置文件: $script:ConfigPath"
    }

    $cfg = Get-Content -LiteralPath $script:ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json

    if (-not $cfg.relay) { throw 'config.json 缺少 relay' }
    if ([string]::IsNullOrWhiteSpace([string]$cfg.relay.host)) { throw 'relay.host 为空' }
    if ([string]::IsNullOrWhiteSpace([string]$cfg.relay.user)) { throw 'relay.user 为空' }
    $rp = 0
    if (-not [int]::TryParse([string]$cfg.relay.port, [ref]$rp) -or $rp -lt 1 -or $rp -gt 65535) {
        throw "relay.port 不合法: $($cfg.relay.port)"
    }

    if (-not $cfg.forwards) { throw 'config.json 缺少 forwards' }
    $forwards = @($cfg.forwards)
    if ($forwards.Count -eq 0) { throw 'forwards 为空' }
    foreach ($f in $forwards) {
        if ($null -eq $f.remotePort -or $null -eq $f.targetPort -or [string]::IsNullOrWhiteSpace([string]$f.targetHost)) {
            throw '每条 forwards 都需要 remotePort、targetHost、targetPort'
        }
        $a = 0
        $b = 0
        if (-not [int]::TryParse([string]$f.remotePort, [ref]$a) -or $a -lt 1 -or $a -gt 65535) {
            throw "remotePort 不合法: $($f.remotePort)"
        }
        if (-not [int]::TryParse([string]$f.targetPort, [ref]$b) -or $b -lt 1 -or $b -gt 65535) {
            throw "targetPort 不合法: $($f.targetPort)"
        }
    }

    $defaults = @{
        serverAliveInterval = 30
        serverAliveCountMax = 3
        connectTimeout      = 15
        retryDelaySeconds   = 10
    }
    if (-not $cfg.keepalive) {
        $cfg | Add-Member -NotePropertyName keepalive -NotePropertyValue ([pscustomobject]$defaults) -Force
    } else {
        foreach ($k in $defaults.Keys) {
            $v = $cfg.keepalive.$k
            if ($null -eq $v -or [string]::IsNullOrWhiteSpace([string]$v)) {
                $cfg.keepalive | Add-Member -NotePropertyName $k -NotePropertyValue $defaults[$k] -Force
            }
        }
    }

    if (-not $cfg.sshUser) {
        $cfg | Add-Member -NotePropertyName sshUser -NotePropertyValue '' -Force
    }
    if (-not $cfg.macJumpHost) {
        $cfg | Add-Member -NotePropertyName macJumpHost -NotePropertyValue '' -Force
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

function Get-SshPath {
    $candidates = @(
        (Join-Path $env:SystemRoot 'System32\OpenSSH\ssh.exe'),
        (Join-Path $env:SystemRoot 'Sysnative\OpenSSH\ssh.exe')
    )
    foreach ($p in $candidates) {
        if (Test-Path -LiteralPath $p) { return $p }
    }
    $cmd = Get-Command ssh.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    throw '找不到 ssh.exe。请安装 Windows 可选功能 OpenSSH Client：设置 → 应用 → 可选功能 → 添加功能 → OpenSSH 客户端。'
}

function Protect-KeyFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    # Normalize CRLF in case the key was pasted through Notepad.
    $text = [System.IO.File]::ReadAllText($Path)
    $text = $text -replace "`r`n", "`n"
    if (-not $text.EndsWith("`n")) { $text += "`n" }
    [System.IO.File]::WriteAllText($Path, $text, (New-Object System.Text.UTF8Encoding($false)))

    & icacls.exe $Path /inheritance:r | Out-Null
    $who = $env:USERNAME
    & icacls.exe $Path /grant:r "$($who):(R)" | Out-Null
    if ($LASTEXITCODE -ne 0) {
        & icacls.exe $Path /grant:r "$($env:USERDOMAIN)\$($env:USERNAME):(R)" | Out-Null
    }
    if ($LASTEXITCODE -ne 0) {
        Write-Warn 'icacls 设置私钥权限失败，ssh 可能会报 UNPROTECTED PRIVATE KEY FILE'
    }
}

function Get-SshArgs {
    param($Config)

    $k = $Config.keepalive
    $sshArgs = @(
        '-N', '-T',
        '-i', 'keys/tunnel_key',
        '-o', 'IdentitiesOnly=yes',
        '-o', 'BatchMode=yes',
        '-o', 'ExitOnForwardFailure=yes',
        '-o', "ServerAliveInterval=$($k.serverAliveInterval)",
        '-o', "ServerAliveCountMax=$($k.serverAliveCountMax)",
        '-o', "ConnectTimeout=$($k.connectTimeout)",
        '-o', 'UserKnownHostsFile=config/known_hosts',
        '-o', 'StrictHostKeyChecking=yes',
        '-p', [string]$Config.relay.port
    )

    foreach ($f in @($Config.forwards)) {
        $sshArgs += @('-R', "127.0.0.1:$($f.remotePort):$($f.targetHost):$($f.targetPort)")
    }

    $sshArgs += "$($Config.relay.user)@$($Config.relay.host)"
    return $sshArgs
}

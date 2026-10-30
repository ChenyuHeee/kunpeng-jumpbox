#Requires -Version 5.1
<#
    kunpeng-jumpbox reverse mode - Windows side.

    Opens a reverse SSH tunnel to the public relay:
        127.0.0.1:<remotePort> on relay  ->  <targetHost>:<targetPort> from this Windows host

    The relay only sees this Windows host's outbound SSH connection; the
    intranet target (10.140.35.70:22) is reached from here, not from the relay.
#>

[CmdletBinding()]
param(
    [switch]$Once
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

try {
    $cfg = Get-Config
    $ssh = Get-SshPath

    if (-not (Test-Path -LiteralPath $script:KeyPath)) {
        Write-Err "找不到私钥: $script:KeyPath"
        Write-Host ''
        Write-Host '私钥不在仓库里。请在 Mac 上把下面的文件复制到 Windows：'
        Write-Host '  Mac:     ~/kunpeng-jumpbox-secrets/tunnel_key'
        Write-Host '  Windows: reverse\keys\tunnel_key'
        Write-Host '通过远程桌面的剪贴板或文件传输复制即可，然后再运行 start.cmd。'
        exit 1
    }
    if (-not (Test-Path -LiteralPath $script:KnownHosts)) {
        Write-Err "找不到 pinned host key 文件: $script:KnownHosts"
        exit 1
    }

    New-Item -ItemType Directory -Force -Path $script:LogDir | Out-Null
    $logPath  = Join-Path $script:LogDir 'tunnel.log'
    $errPath  = Join-Path $script:LogDir 'ssh.err.log'
    $pidPath  = Join-Path $script:LogDir 'ssh.pid'
    $stopFlag = Join-Path $script:LogDir 'stop.flag'

    function Log([string]$Message) {
        $line = '{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $Message
        Write-Host $line
        Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8
    }

    if (Test-Path -LiteralPath $stopFlag) { Remove-Item -LiteralPath $stopFlag -Force }

    Write-Info "relay: $($cfg.relay.user)@$($cfg.relay.host):$($cfg.relay.port)"
    foreach ($f in @($cfg.forwards)) {
        Write-Info ("  127.0.0.1:{0} -> {1}:{2}" -f $f.remotePort, $f.targetHost, $f.targetPort)
    }

    if (Test-TcpPort -ComputerName $cfg.relay.host -Port ([int]$cfg.relay.port)) {
        Write-Info "relay $($cfg.relay.host):$($cfg.relay.port) 可达"
    } else {
        Write-Warn "连不上 relay $($cfg.relay.host):$($cfg.relay.port)（可能出站 22 被网络封了；隧道会持续重试）"
    }

    foreach ($f in @($cfg.forwards)) {
        if (Test-TcpPort -ComputerName $f.targetHost -Port ([int]$f.targetPort)) {
            Write-Info "目标 $($f.targetHost):$($f.targetPort) 可达"
        } else {
            Write-Warn "目标 $($f.targetHost):$($f.targetPort) 不可达（如果这是 Windows RDP，只影响 13389）"
        }
    }

    Protect-KeyFile -Path $script:KeyPath
    $sshArgs = Get-SshArgs -Config $cfg

    Write-Host ''
    Write-Host '隧道已启动。保持这个窗口；Ctrl+C 或 close 窗口停止。' -ForegroundColor Cyan
    Write-Host ''

    $attempt = 0
    $baseDelay = [int]$cfg.keepalive.retryDelaySeconds
    if ($baseDelay -lt 1) { $baseDelay = 10 }

    while ($true) {
        if (Test-Path -LiteralPath $stopFlag) { break }

        $attempt++
        Log "connecting (attempt $attempt)"
        $p = Start-Process -FilePath $ssh -ArgumentList $sshArgs -WorkingDirectory $script:ReverseRoot -NoNewWindow -PassThru -RedirectStandardError $errPath
        Set-Content -LiteralPath $pidPath -Value $p.Id -Encoding ASCII

        $started = Get-Date
        $p.WaitForExit()
        $code = $p.ExitCode
        $elapsed = [int]((Get-Date) - $started).TotalSeconds

        Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue

        $errText = ''
        if (Test-Path -LiteralPath $errPath) {
            $errText = [string](Get-Content -LiteralPath $errPath -Raw -ErrorAction SilentlyContinue)
        }
        if (-not [string]::IsNullOrWhiteSpace($errText)) {
            Log ('ssh: ' + $errText.Trim())
        }

        if (Test-Path -LiteralPath $stopFlag) { break }
        if ($Once) { exit $code }

        $delay = [Math]::Min(60, [Math]::Max($baseDelay, $attempt * 5))
        if ($elapsed -gt 60) { $attempt = 0; $delay = $baseDelay }
        Log "ssh exited (code $code) after ${elapsed}s; retry in ${delay}s"
        Start-Sleep -Seconds $delay
    }

    Remove-Item -LiteralPath $stopFlag -Force -ErrorAction SilentlyContinue
    Write-Info '已停止。'
}
catch {
    Write-Err $_.Exception.Message
    exit 1
}

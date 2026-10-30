#Requires -Version 5.1
<#
    Show the reverse-mode state, target reachability and the Mac-side commands.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

try {
    $cfg = Get-Config
    $logDir  = $script:LogDir
    $pidPath = Join-Path $logDir 'ssh.pid'
    $logPath = Join-Path $logDir 'tunnel.log'
    $errPath = Join-Path $logDir 'ssh.err.log'

    Write-Host '== relay ==' -ForegroundColor Cyan
    Write-Host ("  {0}@{1}:{2}" -f $cfg.relay.user, $cfg.relay.host, $cfg.relay.port)

    Write-Host ''
    Write-Host '== forwards ==' -ForegroundColor Cyan
    foreach ($f in @($cfg.forwards)) {
        Write-Host ("  relay 127.0.0.1:{0} -> {1}:{2}" -f $f.remotePort, $f.targetHost, $f.targetPort)
    }

    Write-Host ''
    Write-Host '== process ==' -ForegroundColor Cyan
    $running = $false
    if (Test-Path -LiteralPath $pidPath) {
        $sshPid = 0
        $raw = [string](Get-Content -LiteralPath $pidPath -Raw -ErrorAction SilentlyContinue)
        if ([int]::TryParse($raw.Trim(), [ref]$sshPid)) {
            $proc = Get-Process -Id $sshPid -ErrorAction SilentlyContinue
            if ($proc -and $proc.ProcessName -eq 'ssh') {
                $running = $true
                Write-Info "  ssh 进程在运行，PID $sshPid"
            }
        }
    }
    if (-not $running) { Write-Warn '  没有检测到 ssh 进程（start.cmd 可能没在运行）' }

    Write-Host ''
    Write-Host '== target reachability ==' -ForegroundColor Cyan
    foreach ($f in @($cfg.forwards)) {
        if (Test-TcpPort -ComputerName $f.targetHost -Port ([int]$f.targetPort)) {
            Write-Info ("  {0}:{1} 可达" -f $f.targetHost, $f.targetPort)
        } else {
            Write-Warn ("  {0}:{1} 不可达" -f $f.targetHost, $f.targetPort)
        }
    }

    Write-Host ''
    Write-Host '== last log ==' -ForegroundColor Cyan
    if (Test-Path -LiteralPath $logPath) {
        Get-Content -LiteralPath $logPath -Tail 12 -ErrorAction SilentlyContinue
    } else {
        Write-Host '  (no log yet)'
    }
    if (Test-Path -LiteralPath $errPath) {
        $err = [string](Get-Content -LiteralPath $errPath -Raw -ErrorAction SilentlyContinue)
        if (-not [string]::IsNullOrWhiteSpace($err)) {
            Write-Host '  ssh stderr:'
            Write-Host ('  ' + $err.Trim())
        }
    }

    Write-Host ''
    Write-Host '== Mac commands ==' -ForegroundColor Cyan
    foreach ($f in @($cfg.forwards)) {
        if ([int]$f.targetPort -eq 22) {
            Write-Host ("  ssh -J {0} -p {1} {2}@127.0.0.1" -f $cfg.macJumpHost, $f.remotePort, $cfg.sshUser)
        } else {
            Write-Host ("  ssh -N -L {0}:127.0.0.1:{0} {1}   # 然后连 127.0.0.1:{0}" -f $f.remotePort, $cfg.macJumpHost)
        }
    }
}
catch {
    Write-Err $_.Exception.Message
    exit 1
}

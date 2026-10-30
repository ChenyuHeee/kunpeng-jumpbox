#Requires -Version 5.1
<#
    Stop the Windows-side reverse tunnel and the scheduled task (if installed).
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

try {
    New-Item -ItemType Directory -Force -Path $script:LogDir | Out-Null
    $flag    = Join-Path $script:LogDir 'stop.flag'
    $pidPath = Join-Path $script:LogDir 'ssh.pid'

    # Tell the start loop to exit. Do not delete this flag here: the loop (or
    # the next start) removes it after observing it.
    New-Item -ItemType File -Force -Path $flag | Out-Null

    if (Test-Path -LiteralPath $pidPath) {
        $sshPid = 0
        $raw = [string](Get-Content -LiteralPath $pidPath -Raw -ErrorAction SilentlyContinue)
        if ([int]::TryParse($raw.Trim(), [ref]$sshPid)) {
            $proc = Get-Process -Id $sshPid -ErrorAction SilentlyContinue
            if ($proc -and $proc.ProcessName -eq 'ssh') {
                Stop-Process -Id $sshPid -Force -ErrorAction SilentlyContinue
                Write-Info "已结束 ssh 进程 PID $sshPid"
            }
        }
    }

    Start-Sleep -Seconds 2

    $taskName = 'KunpengJumpboxReverse'
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($task -and $task.State -eq 'Running') {
        Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        Write-Info "已停止计划任务 $taskName"
    }

    Write-Host ''
    Write-Info '反向隧道已停止。'
}
catch {
    Write-Err $_.Exception.Message
    exit 1
}

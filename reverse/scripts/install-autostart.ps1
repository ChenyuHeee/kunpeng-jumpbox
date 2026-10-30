#Requires -Version 5.1
<#
    Register a per-user scheduled task that starts the reverse tunnel at logon.
    Run as the Windows user that owns the tunnel key (no admin normally needed).
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

try {
    $taskName  = 'KunpengJumpboxReverse'
    $startPs1  = Join-Path $script:ReverseRoot 'scripts\start.ps1'
    $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

    $action = New-ScheduledTaskAction -Execute $powershell -Argument "-NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$startPs1`""
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -ExecutionTimeLimit ([TimeSpan]::Zero) `
        -MultipleInstances IgnoreNew `
        -RestartCount 999 `
        -RestartInterval (New-TimeSpan -Minutes 1)

    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Description 'Kunpeng jumpbox reverse SSH tunnel' -Force | Out-Null
    Write-Info "已注册计划任务 $taskName（登录时自动启动）"
    Write-Host '现在可以手动 start.cmd，或注销/重启后自动运行。'
}
catch {
    Write-Err $_.Exception.Message
    Write-Host '如果提示拒绝访问，请用“以管理员身份运行”再试。'
    exit 1
}

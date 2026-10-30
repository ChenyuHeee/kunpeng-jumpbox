#Requires -Version 5.1
<#
    Remove the logon scheduled task. Run stop.cmd first if the tunnel is running.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

try {
    $taskName = 'KunpengJumpboxReverse'
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($task) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        Write-Info "已删除计划任务 $taskName"
    } else {
        Write-Info "计划任务 $taskName 不存在"
    }
}
catch {
    Write-Err $_.Exception.Message
    exit 1
}

#Requires -Version 5.1
<#
    Remove the portproxy listeners and firewall rules created by setup.ps1.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

if (-not (Test-Admin)) {
    Write-Warn '需要管理员权限，正在请求 UAC...'
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

try {
    $cfg = Get-Config

    foreach ($f in @($cfg.forwards)) {
        $lport = [int]$f.listenPort
        $rule  = Get-RuleName $lport

        $null = & netsh.exe interface portproxy delete v4tov4 "listenport=$lport" 'listenaddress=0.0.0.0' 2>&1
        $existing = Get-NetFirewallRule -DisplayName $rule -ErrorAction SilentlyContinue
        if ($existing) { $existing | Remove-NetFirewallRule }

        Write-Info "已移除 0.0.0.0:$lport 的 portproxy 和防火墙规则 $rule"
    }

    Write-Host ''
    Write-Info '跳板已停止。'
    Write-Host '如果还加了安全组/路由器端口映射，记得一并删掉。'
}
catch {
    Write-Err $_.Exception.Message
    exit 1
}

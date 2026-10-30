#Requires -Version 5.1
<#
    Show the current jumpbox state: forwards, portproxy table, firewall source
    addresses, target reachability, and the host's public/local IPs.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

try {
    $cfg = Get-Config

    Write-Host '== 配置 ==' -ForegroundColor Cyan
    foreach ($f in @($cfg.forwards)) {
        Write-Host ("  0.0.0.0:{0} -> {1}:{2}" -f $f.listenPort, $f.targetHost, $f.targetPort)
    }

    Write-Host ''
    Write-Host '== portproxy ==' -ForegroundColor Cyan
    & netsh.exe interface portproxy show v4tov4

    Write-Host ''
    Write-Host '== 防火墙来源 ==' -ForegroundColor Cyan
    foreach ($f in @($cfg.forwards)) {
        $rule = Get-RuleName $f.listenPort
        $r = Get-NetFirewallRule -DisplayName $rule -ErrorAction SilentlyContinue
        if ($r) {
            $r | Get-NetFirewallAddressFilter | ForEach-Object {
                Write-Host ("  {0}: {1}" -f $rule, ($_.RemoteAddress -join ', '))
            }
        } else {
            Write-Warn "  $rule 不存在"
        }
    }

    Write-Host ''
    Write-Host '== 目标可达性 ==' -ForegroundColor Cyan
    foreach ($f in @($cfg.forwards)) {
        if (Test-TcpPort -ComputerName $f.targetHost -Port $f.targetPort) {
            Write-Info ("  {0}:{1} 可达" -f $f.targetHost, $f.targetPort)
        } else {
            Write-Warn ("  {0}:{1} 不可达" -f $f.targetHost, $f.targetPort)
        }
    }

    Write-Host ''
    $pub   = Get-PublicIp
    $local = @(Get-LocalIPv4)
    if ($pub)         { Write-Host "公网出口 IP: $pub" }
    if ($local.Count) { Write-Host "本机 IPv4: $($local -join ', ')" }
}
catch {
    Write-Err $_.Exception.Message
    exit 1
}

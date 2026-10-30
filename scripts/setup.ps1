#Requires -Version 5.1
<#
    Enable the jumpbox: 0.0.0.0:<listenPort> -> <targetHost>:<targetPort>
    using Windows' built-in netsh interface portproxy + a scoped firewall rule.
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
    $cfg      = Get-Config
    $forwards = @($cfg.forwards)
    $allow    = @(Resolve-AllowFrom $cfg.allowFrom)

    $svc = Get-Service -Name iphlpsvc -ErrorAction SilentlyContinue
    if (-not $svc) { throw '找不到 IP Helper (iphlpsvc) 服务，这台 Windows 可能被策略裁剪过。' }
    if ($svc.Status -ne 'Running') {
        Start-Service iphlpsvc
        Write-Info '已启动 IP Helper (iphlpsvc) 服务'
    }

    foreach ($f in $forwards) {
        $lport = [int]$f.listenPort
        $thost = [string]$f.targetHost
        $tport = [int]$f.targetPort
        $rule  = Get-RuleName $lport

        Write-Host ''
        Write-Info "配置转发: 0.0.0.0:$lport -> ${thost}:$tport"

        if (Test-TcpPort -ComputerName $thost -Port $tport) {
            Write-Info "目标 ${thost}:$tport 可达"
        } else {
            Write-Warn "从这台 Windows 连不上 ${thost}:$tport，仍继续配置；请检查服务器在线、IP 和防火墙。"
        }

        # Idempotent: remove our old listener and firewall rule, then re-add.
        $null = & netsh.exe interface portproxy delete v4tov4 "listenport=$lport" 'listenaddress=0.0.0.0' 2>&1
        $existingRule = Get-NetFirewallRule -DisplayName $rule -ErrorAction SilentlyContinue
        if ($existingRule) { $existingRule | Remove-NetFirewallRule }

        $netshArgs = @(
            'interface', 'portproxy', 'add', 'v4tov4',
            "listenport=$lport",
            'listenaddress=0.0.0.0',
            "connectport=$tport",
            "connectaddress=$thost"
        )
        $out = & netsh.exe @netshArgs 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "netsh 配置失败: $out"
        }

        $remote = if ($allow -contains 'Any') { 'Any' } else { $allow }
        New-NetFirewallRule `
            -DisplayName $rule `
            -Direction Inbound `
            -Action Allow `
            -Protocol TCP `
            -LocalPort $lport `
            -RemoteAddress $remote `
            -Profile Any `
            -Description 'kunpeng-jumpbox temporary TCP port proxy' | Out-Null

        Write-Info "防火墙规则已添加: $rule（来源: $($allow -join ', ')）"
    }

    Write-Host ''
    Write-Host '================ kunpeng-jumpbox ================' -ForegroundColor Cyan
    Write-Host '已启用。portproxy 和防火墙规则会随 Windows 重启保留。'
    Write-Host '不用时运行 stop.cmd 删除。'

    $pub   = Get-PublicIp
    $local = @(Get-LocalIPv4)
    if ($pub)            { Write-Host "公网出口 IP: $pub" }
    if ($local.Count)    { Write-Host "本机 IPv4: $($local -join ', ')" }

    Write-Host ''
    Write-Host 'Mac 上连接（把 <IP> 换成能访问这台 Windows 的公网 IP）:' -ForegroundColor Cyan
    foreach ($f in $forwards) {
        if ([int]$f.targetPort -eq 22) {
            Write-Host ("  ssh -p {0} {1}@<IP>" -f $f.listenPort, $cfg.sshUser) -ForegroundColor Cyan
        } else {
            Write-Host ("  外网 <IP>:{0}  ->  {1}:{2}" -f $f.listenPort, $f.targetHost, $f.targetPort)
        }
    }
    Write-Host ''
    Write-Host '如果这台机器在路由器后面，还需要在路由器上把公网 TCP 端口映射到本机；'
    Write-Host '如果它是云服务器，请在安全组放行对应 TCP 端口（来源建议只填你的 Mac 公网 IP）。'
    Write-Host '第一次连接会提示验证鲲鹏服务器的 SSH host key，这是正常的。'
    Write-Host '=================================================' -ForegroundColor Cyan
}
catch {
    Write-Err $_.Exception.Message
    exit 1
}

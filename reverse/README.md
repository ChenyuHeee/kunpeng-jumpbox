# reverse mode — Windows 主动连出，经公网中转机做跳板

用于 **Windows 只有内网地址（如 `10.150.229.206`）、公网进不来**的情况。根目录的 `setup.cmd`（netsh 端口转发）需要 Windows 有公网入站，这里不适用。

```text
你的 Mac
   │ ssh（用你已有的 hcy-chenyu 账号）
   ▼
中转机 114.55.135.102
   │ 只监听 127.0.0.1:2222 / 127.0.0.1:13389
   ▲
   │ Windows 主动连出的 SSH 反向隧道（出站，不需要开任何入站端口）
   │
Windows 11（内网，10.150.229.206）
   ├── ssh 10.140.35.70:22        → 鲲鹏服务器
   └── 127.0.0.1:3389             → Windows 自己的远程桌面（可选）
```

关键点：

- **Windows 仍然是唯一的跳板**。只有它能到 `10.140.35.70`；中转机不直接访问鲲鹏。
- 中转机只提供公网入口和回环端口；它看到的是 Windows 的出站 SSH，连不到你的内网。
- 隧道账号 `kunpeng-tunnel` 没有 shell，key 被限制为只能监听中转机的 `127.0.0.1:2222` 和 `127.0.0.1:13389`。
- 不需要在 Windows 上开防火墙入站端口，也不需要在路由器/安全组做映射。

## 前置条件

1. 这台 Windows 能访问中转机 `114.55.135.102:22`（出站）。在 Windows 上先测：
   ```powershell
   Test-NetConnection 114.55.135.102 -Port 22
   ```
   如果 `TcpTestSucceeded : False`，说明你所在网络封了出站 22；先告诉我，我换端口/中转方案。
2. 这台 Windows 能 `ssh shijiaxin@10.140.35.70`（脚本会先测 TCP）。
3. 你 Mac 的 `~/.ssh/config` 里已有 `hcy-chenyu`（`User chenyu`，`HostName 114.55.135.102`）。
4. Windows 11 自带 OpenSSH 客户端（一般都有；脚本会检查）。

## 一次性准备

### 0. 先停掉旧的 direct 模式（如果跑过根目录的 setup.cmd）

在 Windows 上以管理员运行仓库根目录的：

```powershell
.\stop.cmd
```

它只删除 `netsh portproxy` 和对应的防火墙规则，不影响后面的反向隧道。

### 1. 在中转机上装受限公钥（Mac 上执行一次）

```bash
ssh hcy 'bash -s' < reverse/relay/setup-relay.sh
```

- `hcy` 是你已有的 root 账号（`114.55.135.102`）。
- 脚本创建 `kunpeng-tunnel`（无登录 shell），写入受限的 `authorized_keys`，打印 sshd 策略和 host key 指纹。
- **不改 sshd_config**，不动 root/chenyu 的 key。
- 删除：`ssh hcy 'userdel -r kunpeng-tunnel'`。

### 2. 把私钥放到 Windows

私钥**不在仓库里**，在 Mac 上：

```text
~/kunpeng-jumpbox-secrets/tunnel_key
```

通过你当前远程桌面（RDP/ToDesk 等）的剪贴板或文件传输，把它复制到 Windows 的：

```text
reverse\keys\tunnel_key
```

`start.ps1` 会自动把 CRLF 归一化，并用 `icacls` 收紧权限（只允许当前用户读）。

### 3. 在 Windows 上启动

```powershell
cd reverse
.\start.cmd
```

不需要管理员。脚本会：

1. 检查私钥和 pinned host key；
2. 测中转机 `114.55.135.102:22`；
3. 测 `10.140.35.70:22` 和 Windows 本机 RDP `127.0.0.1:3389`；
4. 启动并保持 SSH 反向隧道，断线自动重连；
5. 日志在 `reverse\logs\tunnel.log`。

想开机自启：

```powershell
.\install-autostart.cmd
```

它注册一个当前用户的登录计划任务；不需要管理员权限（若提示拒绝访问，再用管理员运行一次）。

## Mac 连接

### SSH 到鲲鹏

```bash
ssh -J hcy-chenyu -p 2222 shijiaxin@127.0.0.1
```

第一次会提示 host key——这是**鲲鹏服务器**的 key，不是中转机/Windows 的。可让机主在鲲鹏上运行：

```bash
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
```

对比指纹后再输入 `yes`。

建议配置别名（`reverse/client/ssh_config.example`）：

```sshconfig
Host kunpeng
    HostName 127.0.0.1
    Port 2222
    User shijiaxin
    ProxyJump hcy-chenyu
    ServerAliveInterval 30
    ServerAliveCountMax 3
```

之后 `ssh kunpeng`、`scp file kunpeng:~`、VS Code Remote-SSH 都能直接用。

### RDP 到 Windows（可选）

如果 Windows 开了“远程桌面”，可以先在 Mac 上开本地转发：

```bash
ssh -N -L 13389:127.0.0.1:13389 hcy-chenyu
```

然后用 RDP 客户端连 `127.0.0.1:13389`，账号密码是 Windows 本机的。

也可以一个 SSH 同时开两个本地转发：

```bash
ssh -N -L 2222:127.0.0.1:2222 -L 13389:127.0.0.1:13389 hcy-chenyu
```

这样 2222 直接给 `ssh -p 2222 shijiaxin@127.0.0.1` 用，13389 给 RDP 用。

> Windows 的 RDP 没开时，13389 这条转发仍然会建立（`-R` 是懒连接），只是连上去会失败；不影响 2222。

## 配置

`reverse/config/config.json`：

```json
{
  "sshUser": "shijiaxin",
  "macJumpHost": "hcy-chenyu",
  "relay": {
    "host": "114.55.135.102",
    "port": 22,
    "user": "kunpeng-tunnel"
  },
  "forwards": [
    { "name": "kunpeng-ssh", "remotePort": 2222, "targetHost": "10.140.35.70", "targetPort": 22 },
    { "name": "windows-rdp", "remotePort": 13389, "targetHost": "127.0.0.1", "targetPort": 3389 }
  ],
  "keepalive": {
    "serverAliveInterval": 30,
    "serverAliveCountMax": 3,
    "connectTimeout": 15,
    "retryDelaySeconds": 10
  }
}
```

- `relay.host/user/port`：中转机和隧道账号。
- `forwards[].remotePort`：中转机上要监听的回环端口；必须和 relay 脚本里的 `PORTS` 一致。
- `forwards[].targetHost/targetPort`：从 **Windows** 视角看的地址。鲲鹏是 `10.140.35.70:22`；Windows RDP 是 `127.0.0.1:3389`。
- `macJumpHost`/`sshUser`：只用于 `status.cmd` 打印 Mac 命令。
- 改端口后：在 Mac 上重跑 relay 脚本（`PORTS="2222 13389" ssh hcy 'bash -s' < ...`），再在 Windows 上 `stop.cmd` → 改配置 → `start.cmd`。

## 状态 / 停止

Windows：

```powershell
.\status.cmd    # 进程、目标可达性、最后日志、Mac 命令
.\stop.cmd      # 停隧道；如果装了计划任务也一并停止
```

Mac 上清理中转机账号：

```bash
ssh hcy 'userdel -r kunpeng-tunnel'
```

## 安全须知

- 私钥只在 Windows 上；仓库里只有公钥。不要把 `tunnel_key` 提交或发出去。
- 中转机上的 `kunpeng-tunnel` 没有 shell，key 被 `restrict,port-forwarding,permitlisten=...` 限制；即使 key 泄露，也只能绑中转机的两个回环端口，不能登录、不能开别的端口。
- 2222/13389 只绑在中转机 `127.0.0.1`，公网扫不到；只有能 SSH 登录中转机的人（你，用 `hcy-chenyu`）才能通过本地转发访问。
- 中转机不直连鲲鹏；到鲲鹏的连接是 Windows 发起的，满足“服务器只能从这台 Windows SSH”的限制。
- `kunpeng-tunnel` 的 key 在 Windows 上；这台是朋友的机器，用完记得 `stop.cmd`，并在中转机上删账号。
- Windows 的 RDP 端口只通过中转机回环暴露；RDP 自身仍有 Windows 账号密码保护。

## 排障

| 现象 | 排查 |
| --- | --- |
| Windows 上 `start.cmd` 一直重试，日志 `Connection timed out` | Windows 出站 22 被封，或中转机不可达。先 `Test-NetConnection 114.55.135.102 -Port 22` |
| 日志 `Permission denied (publickey)` | Windows 上的私钥和中转机 authorized_keys 不匹配；重跑 relay 脚本，确认 `tunnel_key.pub` 一致 |
| 日志 `remote port forwarding failed` | relay 的 `PORTS` 和 `config.json` 的 `remotePort` 不一致，或端口被别的进程占了 |
| 日志 `Host key verification failed` | 中转机换了 host key；重新 `ssh-keyscan -p 22 114.55.135.102` 更新 `reverse/config/known_hosts` |
| Windows 报 `UNPROTECTED PRIVATE KEY FILE` | `start.ps1` 会自动 `icacls`；仍报错就右键 `tunnel_key` → 属性 → 安全 → 高级 → 禁用继承，只保留当前用户 |
| Mac 上 `ssh -J hcy-chenyu -p 2222 ...` 卡住 | Windows 隧道没起来；先在 Windows 上跑 `status.cmd` 看进程和日志 |
| 2222 通了但 RDP 13389 不通 | Windows 没开远程桌面，或 3389 没监听；只影响 RDP，不影响 SSH |
| 鲲鹏 `Permission denied` | 鲲鹏账号/密码问题，和隧道无关；先在 Windows 上直接 `ssh shijiaxin@10.140.35.70` 验证 |

# kunpeng-jumpbox

临时 SSH 跳板：在朋友的 **Windows 11** 上用系统自带的 `netsh interface portproxy` 开一个 TCP 端口转发，把内网鲲鹏服务器的 22 端口送到公网。你在 Mac 上直接 `ssh -p 2222` 连过去。

> **两种模式，按网络环境选：**
> - **Windows 有公网入站**（EIP、端口映射、安全组放行）→ 用根目录的 `setup.cmd`，即本文下面的 direct 模式。
> - **Windows 只有内网地址**（例如 `10.150.229.206`，公网进不来）→ 用 [`reverse/`](reverse/README.md)：Windows 主动连公网中转机，Mac 连中转机；Windows 仍然是到鲲鹏的唯一跳板。
>
> 你现在的情况是 `10.150.229.206` 内网地址，**用 `reverse/`**。

- 不需要 frp / ngrok / 另一台公网服务器；
- 跳板本身不需要在鲲鹏服务器上安装任何东西（可选的 `ssh-copy-id` 只是给你的账号加公钥）；
- Windows 只做四层 TCP 转发，不解密 SSH，也不保存密码；
- 规则持久化，Windows 重启后仍然生效，没有常驻进程。

## 拓扑

```text
你的 Mac ── ssh -p 2222 ──> Windows 11（公网入口）
                                 │  netsh portproxy（四层 TCP）
                                 └──> 10.140.35.70:22（鲲鹏 Ubuntu，内网）
```

SSH 是端到端加密的：Windows 只是搬运 TCP 字节，host key 和密码仍然由鲲鹏服务器校验。

## 前置条件

1. Windows 11，管理员权限（脚本会弹 UAC）。
2. 这台 Windows 能访问 `10.140.35.70:22`（`setup.cmd` 会先测）。
3. 公网能访问这台 Windows 的 `2222/tcp`：
   - **云服务器**：安全组入方向放行 TCP 2222，来源建议只填你的 Mac 公网 IP；
   - **路由器后面**：路由器端口映射 `公网 2222 -> Windows 内网 IP:2222`；
   - **直接有公网 IP**：只需 Windows 防火墙，脚本会自动加规则。
4. 仅支持 IPv4 入站。

## 一键启用

```powershell
git clone https://github.com/ChenyuHeee/kunpeng-jumpbox.git
cd kunpeng-jumpbox
.\setup.cmd
```

也可以直接双击 `setup.cmd`。Windows 上没有 git 的话，下载仓库 ZIP 解压后运行 `setup.cmd` 效果一样。

脚本会：

1. 请求管理员权限；
2. 读取 `config/config.json`；
3. 测试 `10.140.35.70:22` 是否可达；
4. 添加 `0.0.0.0:2222 -> 10.140.35.70:22` 的 portproxy；
5. 添加防火墙规则，来源 IP 默认自动检测当前远程桌面的客户端 IP（会问你确认）；
6. 打印公网出口 IP、本机 IPv4 和 Mac 上的连接命令。

规则是**持久化**的：Windows 重启后仍然有效。不用时运行 `stop.cmd`。

## Mac 连接

```bash
ssh -p 2222 shijiaxin@<Windows公网IP>
```

第一次连接会提示验证 host key。这是**鲲鹏服务器**的 host key（不是 Windows 的）。可以在鲲鹏上运行下面的命令对比指纹：

```bash
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
```

确认一致后再输入 `yes`。

配置别名（参考 `client/ssh_config.example`，加到 `~/.ssh/config`）：

```sshconfig
Host kunpeng
    HostName <Windows公网IP>
    Port 2222
    User shijiaxin
    ServerAliveInterval 30
    ServerAliveCountMax 3
```

之后：

```bash
ssh kunpeng
scp local-file kunpeng:~
```

VS Code Remote-SSH 直接选 `kunpeng` 这个 Host。

### 建议装公钥

```bash
ssh-keygen -t ed25519          # 如果还没有 ~/.ssh/id_ed25519
ssh-copy-id -i ~/.ssh/id_ed25519.pub -p 2222 shijiaxin@<Windows公网IP>
```

私钥只在你的 Mac 上；这个仓库里没有任何密钥。

## 配置

`config/config.json`：

```json
{
  "sshUser": "shijiaxin",
  "allowFrom": "auto",
  "forwards": [
    {
      "name": "ssh",
      "listenPort": 2222,
      "targetHost": "10.140.35.70",
      "targetPort": 22
    }
  ]
}
```

| 字段 | 说明 |
| --- | --- |
| `listenPort` | Windows 对公网监听的端口，默认 `2222` |
| `targetHost` / `targetPort` | 鲲鹏的内网地址和端口 |
| `sshUser` | 只用于打印 Mac 连接命令 |
| `allowFrom` | `auto` = 自动检测当前 RDP 来源 IP 并询问；也可以填单个 IP/CIDR、数组，或 `any`（不推荐） |

> 如果你是通过云厂商控制台的 VNC/Workbench 进去的，检测到的可能是控制台的 IP，不是你 Mac 的公网 IP。这时不要直接回车，手动填 Mac 的公网 IP（在 Mac 上 `curl -4 ifconfig.me`），或者先选 `a` 临时放行、连上后再收紧。

要加 RDP/VNC，在 `forwards` 里加一条，重跑 `setup.cmd`：

```json
{ "name": "rdp", "listenPort": 13389, "targetHost": "10.140.35.70", "targetPort": 3389 }
```

注意：如果 Windows 本机开着远程桌面，3389 会被占用，所以外网监听端口要用 `13389` 这类非标准端口。

## 状态 / 停止

```powershell
.\status.cmd    # 看规则、防火墙来源、目标是否可达、公网 IP
.\stop.cmd      # 删除 portproxy + 防火墙规则
```

改了 `listenPort` 之后，先 `stop.cmd` 再 `setup.cmd`，避免旧规则残留。

## 安全须知

- 这个方案会把鲲鹏的 SSH 端口暴露在 Windows 的公网端口上。**务必把 `allowFrom` 限制成你 Mac 的公网 IP**，不要长期用 `any`。
- 你的 Mac 公网 IP 变了以后，重跑 `setup.cmd` 更新防火墙规则。
- 登录密码**没有**写进这个仓库；连接时手动输入。
- 如果条件允许，和机主商量把服务器密码换强一点，或者至少给你自己装上公钥。
- 如果鲲鹏上开了 fail2ban，输错密码可能把 **Windows 主机的内网 IP** 封掉（服务器看到的来源是 Windows）。建议先 `ssh-copy-id` 一次成功，或让机主把 Windows 的 IP 加白。
- 用完跑 `stop.cmd`，并在安全组/路由器里删掉端口映射。

## 排障

| 现象 | 排查 |
| --- | --- |
| `Connection refused` | Windows 防火墙/安全组/路由器没放行 2222；或 `setup.cmd` 没成功 |
| `Connection timed out` | 公网 IP 不对、端口映射没做、安全组没放行 |
| `Permission denied` | 鲲鹏账号/密码不对；在 Windows 上直接 `ssh shijiaxin@10.140.35.70` 试试 |
| `netsh` 报错 | 用管理员权限运行；`Get-Service iphlpsvc` 是否为 Running |
| 目标不可达 | Windows 上 `Test-NetConnection 10.140.35.70 -Port 22`；检查服务器在线和内网路由 |
| 公网 IP 变了 | 重看 `status.cmd` 打印的公网出口 IP；长期用建议上 DDNS |
| 改了配置不生效 | 先 `stop.cmd`，再 `setup.cmd` |

`setup.cmd` 打印的是**出口公网 IP**。如果这台主机在 NAT 后面，入站 IP 以路由器/安全组里配置的为准。

## 原理

`netsh interface portproxy` 是 Windows 自带的四层 TCP 代理（由 IP Helper 服务执行）。它只搬运 TCP 字节，不解析 SSH，所以鲲鹏服务器的 host key、密码、公钥认证都原样工作。防火墙规则把来源限制在你的 IP。

如果这台 Windows 其实没有独立公网入口（只能出站、不能入站），`netsh` 转发就无法被外网访问；那种情况需要反向隧道（一台公网中转机或 Tailscale）。告诉我，我再改。

# keys

- `tunnel_key.pub`：公钥，可以公开，已提交。
- `tunnel_key`：**私钥，不在仓库里**，`.gitignore` 已排除。Windows 上运行前必须把它放到这个目录。

私钥在 Mac 上的位置：

```text
~/kunpeng-jumpbox-secrets/tunnel_key
```

把它通过远程桌面剪贴板/文件传输复制到 Windows 的：

```text
reverse\keys\tunnel_key
```

`start.ps1` 会：

1. 把 CRLF 归一化成 LF（避免 Notepad 粘贴导致格式问题）；
2. 用 `icacls` 去掉继承，只允许当前 Windows 用户读取；
3. 用这个 key 连中转机。

不要把 `tunnel_key` 提交到 git，也不要发到聊天/截图里。中转机上的这个 key 被 `restrict,port-forwarding,permitlisten=...` 限制死了：不能登录 shell，只能监听 `127.0.0.1:2222` 和 `127.0.0.1:13389`。

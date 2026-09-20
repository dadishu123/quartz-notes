---
title: GitHub连接失败排查记录
date: 2026-09-20
tags:
  - Quartz
  - GitHub
  - Git
  - Proxy
---

# GitHub连接失败排查记录

## 问题现象

在使用自动发布脚本：

```powershell
.\publish.ps1
```

发布 Obsidian 笔记到 GitHub Pages 时，前面的步骤均正常：

```
[1/5] Sync Obsidian public notes
Sync completed

[2/5] Build Quartz
Build completed

[3/5] Git add

[4/5] Git commit
```

但是在最后：

```
[5/5] Git push
```

出现错误：

```
fatal: unable to access 
'https://github.com/dadishu123/quartz-notes.git/'

schannel: failed to receive handshake,
SSL/TLS connection failed
```

发布失败：

```
PUBLISH FAILED

Step: Git Push

Reason:
GitHub connection failed.
```

---

# 原因分析

本地 Git 访问 GitHub 依赖代理。

浏览器可以正常打开 GitHub，并不代表 Git 命令可以正常访问 GitHub。

Git 使用独立的网络连接，需要配置代理：

```
Git
 |
 | HTTP/HTTPS Proxy
 |
127.0.0.1:7881
 |
代理软件
 |
GitHub
```

当代理软件没有启动、端口变化或者连接不稳定时：

- `git push`
- `git pull`
- `git ls-remote`

都会失败。

---

# 排查步骤

## 1. 检查 Git 代理配置

查看 HTTP 代理：

```powershell
git config --global --get http.proxy
```

查看 HTTPS 代理：

```powershell
git config --global --get https.proxy
```

正常应该都返回：

```
http://127.0.0.1:7881
```

如果为空，需要重新设置：

```powershell
git config --global http.proxy http://127.0.0.1:7881

git config --global https.proxy http://127.0.0.1:7881
```

---

# 2. 检查代理端口

PowerShell执行：

```powershell
Test-NetConnection 127.0.0.1 -Port 7881
```

正常：

```
TcpTestSucceeded : True
```

如果：

```
TcpTestSucceeded : False
```

说明：

- 代理软件没有启动
- 代理端口改变
- 代理服务异常


---

# 3. 测试 GitHub 连接

执行：

```powershell
git ls-remote https://github.com/dadishu123/quartz-notes.git
```

成功应该出现：

```
45b1c5c...   HEAD

45b1c5c...   refs/heads/main
```

说明：

Git → GitHub 网络恢复。


---

# 4. 重新执行发布

连接恢复后：

```powershell
.\publish.ps1
```

即可完成：

```
Obsidian
    ↓
Wenqiang_files/public
    ↓
Quartz/content
    ↓
Quartz build
    ↓
Git commit
    ↓
Git push
    ↓
GitHub Pages
```

---

# 经验总结

## 浏览器能访问 GitHub ≠ Git能访问 GitHub

浏览器：

```
Chrome
 ↓
系统代理
 ↓
GitHub
```

Git：

```
Git.exe
 ↓
Git自己的proxy配置
 ↓
GitHub
```

两者网络路径不同。


---

# 后续优化方向

目前 `publish.ps1` 已经可以反馈：

- 同步失败
- Quartz构建失败
- Git提交失败
- GitHub连接失败


后续可以增加：

1. 发布前自动检测 GitHub 连通性

例如：

```powershell
git ls-remote origin
```

失败时提前终止。


2. 自动检测代理端口

检查：

```
127.0.0.1:7881
```

是否可用。


3. 发布日志记录

记录：

- 发布时间
- commit id
- 发布状态
- 失败原因


---

# 当前稳定发布流程

日常写作：

```
Obsidian
    ↓
编辑公开笔记
    ↓
运行

.\publish.ps1

    ↓

GitHub Pages自动更新
```

如果失败：

优先检查：

1. 代理软件是否启动
2. Git proxy是否正确
3. git ls-remote 是否成功

```
---

## 维护记录

2026-09-20

问题：
Git push SSL/TLS handshake failed

解决：

重新确认：

```powershell
git config --global http.proxy http://127.0.0.1:7881

git config --global https.proxy http://127.0.0.1:7881
```

测试：

```powershell
git ls-remote https://github.com/dadishu123/quartz-notes.git
```

恢复后重新执行：

```powershell
.\publish.ps1
```

发布成功。
```
# P1-mvp 端到端验证清单 (T-009 download-to-gallery 流程)

> 配套文档：`MILESTONES.md`、项目根 `REQUIREMENTS.md §8 P1-mvp 出口准则`。
>
> **目标**：iOS simulator / 真 iPhone 能点开 Windows 端 LocalSend 的 `D:\Photos`，下载一张图片到相册。
>
> **测试环境**（你的实际环境）：
> - **Windows 端**：`feature/applechang/dev` 分支 build 的 `localsend.exe`（含 v2.3 capability + enableFs 开关）
> - **macOS 端**：开发 + build 工具（iOS simulator host）
> - **iOS 端**：iPhone 17 Pro simulator（已重 build 到 commit `32bec536`）
> - **网络**：三者同 Wi-Fi（你的 iOS simulator 已能看到 "炽热的木瓜 / HTTP / Windows" 设备）

---

## 步骤 1：在 Windows 端准备 fs 端点

### 1.1 打开加密 (HTTPS) —— **fs 命名空间前置条件 (T-005 / N-SEC-3)**

```
Windows 上打开 LocalSend → 设置 (Settings) → 网络 (Network)
  → 找到 Encryption（HTTPS）开关 → 打开
```

打开后 Windows 端会：
- 自动重启 server（rustls 切换监听）
- 设备标签从 "HTTP" 变为 "HTTPS"（其他设备可见）

### 1.2 打开 enableFs —— **T-006/T-007 capability 触发**

```
同页面 → 找到 "Allow other devices to browse my drives" 开关 → 打开
```

打开后 Windows 端会：
- 写 `ls_enable_fs=true` 到 SharedPreferences
- 触发 `serverProvider.restartServerFromSettings()`
- 重启后 multicast announce 携带 `capabilities: ["send","receive","fs"]`
- **iOS 端 5 秒内** 收到新 announce → PeerRow 评估 → 📂 按钮出现

### 1.3 验证 announce 内容

**PowerShell** 抓包：

```powershell
# 在 Windows 上跑 5 秒抓包
netsh trace start capture=yes ipv4.address=224.0.0.251
timeout /t 5
netsh trace stop
# 在生成的 etl 文件里搜 "capabilities" 应看到 ["send","receive","fs"]
```

或者直接 curl 验证 fs 路由已注册：

```powershell
# ⚠️ 必须用 -k 跳过自签名证书
curl.exe -k -m 3 https://127.0.0.1:53317/api/localsend/v2/fs/roots
# 期望: 200 + JSON {"roots":[...]}
# 如果返回 "Could not resolve host" 或 "Connection aborted" → TLS 没启
# 如果 404 → fs 路由没注册（enableFs 没开 或 TLS 没启）
```

### 1.4 准备测试文件

插一个 U 盘到 Windows，把一张 jpg 放进根目录，例如 `D:\test.jpg`。

Windows 端 LocalSend → 设置 → 网络 → **Mount table 白名单**（如果 P1-mvp 没有 settings UI 暴露挂载点，参考下面备选方案 B）：

**备选方案 A（白名单自动）**：
如果 `FsConfig::default()` 是空白名单但 `FsMount::list` 自动枚举可移动盘，那 U 盘**应当**自动出现。

**备选方案 B（手动加白名单）**：
在 Windows PowerShell 跑：

```powershell
# LocalSend 配置文件
code $env:APPDATA\org.localsend.localsend\settings.json
# 添加（不要覆盖已有项）：
# "fsWhitelist": ["D:\\"]
# 保存后 LocalSend 自动重启
```

---

## 步骤 2：iOS simulator 重新 build

```bash
cd /Users/zego/Documents/localsend/src/localsend/app
fvm flutter run -d "iPhone 17 Pro"
```

预期：
- 启动后看到 "附近的设备" 列表里有 "炽热的木瓜 / HTTPS / Windows"（标签从 HTTP 变 HTTPS）
- 设备行右侧出现 📂 浏览驱动器按钮（capability 含 fs）

---

## 步骤 3：进入浏览页 → 看 roots

点击 📂 → 进入 `RemoteBrowserPage`。

### 期望 (Windows 配置正确)

**目录层级**：
```
📁 浏览驱动器 · 炽热的木瓜   [≡ 排序] [☷ 视图切换]
└─ 驱动器
   ├─ 💾 D: 工作盘 (exFAT)
   └─ ...
```

### 期望 (Windows fs 没正确配置)

按 `32bec536` 修复后的错误卡片：

| 情况 | 卡片内容 |
|---|---|
| TLS 没启 + fs 路由没挂 | 🔒 "该设备未开启驱动器浏览" + 操作指引 |
| enableFs 没开（仍 HTTPS） | 同上 |
| 路径越权（403） | 🚫 "路径未被共享" |

---

## 步骤 4：进子目录 → 列出文件

点 D: → 进入 `/` 目录 → 应该看到 `test.jpg` + Windows 系统根目录的目录（Windows / RECYCLER / $Recycle.Bin 等通常被 `is_macos_system_volume` 类似的 `is_windows_system_volume` 过滤掉）。

**期望文件行**：
```
📄 test.jpg   2.8 MB   2026-09-23
📁 Documents  —         —
📁 Downloads  —         —
...
```

---

## 步骤 5：点击 jpg → 弹 action sheet

点击 `test.jpg` 行 → 弹 `showFileActionSheet`。

**期望**（图片扩展名走 image 分支）：
```
┌─────────────────────────┐
│ ─                        │
│ 🖼 保存到相册             │
│ 📁 保存到文件             │
│ 👁 预览                   │
└─────────────────────────┘
```

---

## 步骤 6：选「保存到相册」

点击 "保存到相册"。

### 内部流程

1. `RemoteBrowserPage._handleFileTap` 显示 "Downloading..." snackbar
2. `performFileAction` 调用 `fsDownloadService.downloadToCache`
3. Rust FRB stream 流回 `RsFsDownloadEvent::Started` → `Chunk*` → `Finished`
4. Dart 端 `IOSink` 写入 `getCacheDirectory()/fs-<sessionId>-test.jpg`
5. cache 写完后调 `saveFileToGallery(cachedPath, isImage: true)`
6. `Gal.requestAccess(toAlbum: false)` → 用户授权（首次会弹系统权限）
7. `Gal.putImage(cachedPath)` 写入系统相册

### 期望结果

- snackbar 变为 "Saved to Photos"（zh-CN：已保存到相册）
- iOS 系统 Photos app 里能看到 `test.jpg`（打开 Photos app 验证）
- snackbar 持续 2 秒后消失

### 已知限制

- iOS simulator 的 Photos app 是空的 / 受限——写入可能在 simulator 上失败（gal 在 simulator 上的行为因 iOS 版本而异）
- **如果 simulator 失败**，把同样 build 装到真 iPhone 上即可验证

---

## 步骤 7：选「保存到文件」

返回上层 → 重新点 `test.jpg` → 选 "保存到文件"。

### 期望

iOS 上弹系统 `file_selector.getSaveLocation` 对话框 → 用户选目录 + 文件名 → 拷贝完成 → snackbar "Saved to {path}"。

桌面端（不在本次测试范围）：直接拷到 OS Downloads 目录。

---

## 步骤 8：选「预览」

返回上层 → 重新点 `test.jpg` → 选 "预览"。

### 期望

- snackbar "Downloading..." → 完成后跳 `ImagePreviewPage`
- 全屏显示 jpg（支持 InteractiveViewer 缩放 / 拖动）

---

## 步骤 9：错误路径

### 9.1 中途取消

模拟场景：网络抖动 / iOS 端按 Cancel 按钮。

`fsDownloadService.cancel()` 设置 `status: cancelled` → 缓存文件删除 → snackbar "Cancelled"。

### 9.2 文件不存在 / 被删

模拟场景：开始下载后 Windows 端删除 test.jpg。

iOS 端 `fsDownload` 流结束，chunk 累积 0 → Rust 端 `Failed` 事件 → Dart 端 `FsDownloadFailedResult` → snackbar "Download failed"。

---

## 步骤 10：Range 测试 (AC-5)

video / audio 文件用 Range 协议。

### 10.1 准备测试视频

U 盘放一个 mp4（任何大小，>10 MB 即可看出效果）。

### 10.2 通过 Range 下载

验证逻辑：T-009 客户端用 `rangeStart / rangeEnd` 参数；P5 (T-023) 真正用于视频 player。

测试方法：在 Dart 端手动调：

```dart
ref.read(fsDownloadProvider.notifier).downloadToCache(
  device: device,
  entry: entry,
  fullPath: 'D:/test.mp4',
  rangeStart: 0,
  rangeEnd: 1024 * 1024,  // 1MB
);
// 期望：cache 文件大小 ≈ 1MB（partial content）
```

P1-mvp 不强制要这个 UI 入口（媒体预览 UI 是 P5 T-023），但 FRB API + Rust 实现**已经 ready**。

---

## 验收对照 (REQUIREMENTS.md §8 P1-mvp 出口准则)

| 准则 | 验证步骤 | 期望 |
|---|---|---|
| 移动端能发现挂载端 | 步骤 2 | iOS 显示 "炽热的木瓜 HTTPS Windows" |
| PeekWindow 显示「浏览驱动器」按钮 | 步骤 2 | 📂 按钮可见 |
| 进入后看到挂载点列表 | 步骤 3 | U 盘 / 系统盘 / 移动盘 列出 |
| 进入子目录看到文件 | 步骤 4 | jpg / mp4 / 普通目录 |
| 点击 jpg 弹 action sheet | 步骤 5 | 三选项底部 sheet |
| 保存到相册成功 | 步骤 6 | Photos app 看到 test.jpg |
| (P5 验收) Range 206 正确 | 步骤 10 | partial content 字节数正确 |

---

## 已知限制 / 备注

1. **iOS simulator 写入相册**：gal 在 simulator 上 Photos app 是空的，写入会失败（这是 Apple simulator 限制，不是我们的 bug）。验证 P1-mvp 下载到相册流程需要**真 iPhone**。

2. **Windows MountTable 默认白名单**：v1.19.0 默认 `whitelist = []`。如果 U 盘不出现，需要手动 `FsConfig::from_config(whitelist: vec![PathBuf::from("D:\\")])`。我们**没在 settings UI 暴露**这个设置（应该 T-002 + settings_page 都做了，但 Windows 端的 P1-mvp 设置里没有 mount table 配置项）。Workaround：在 Windows 端编辑 `%APPDATA%\org.localsend.localsend\settings.json` 加 `"fsWhitelist": ["D:\\"]`。

3. **挂载端**：当前截图里 Windows 端的设备标签是 "HTTP"（步骤 1.1 后应变 "HTTPS"）。如果忘了开 TLS，fs 路由**完全不挂**，即使 enableFs 开了也是 404。

4. **macOS ↔ iOS simulator 同台**：已知 v1.18 老问题（macOS LocalSend 与 iOS simulator 都绑 `0.0.0.0:53317`，muticast NAT + port 冲突），**与本工单无关**。P1-mvp 验证请用 iOS simulator ↔ Windows 跨设备场景。

---

## 我能远程帮你做的

1. 改任何 Dart / Rust 代码
2. 跑 test / build / 分析
3. 解析错误日志（粘贴 iOS Xcode / Windows stderr / 任何端 log）
4. 修 mDNS / 路由 / capability 相关 bug

**不能**：
- 操作你 Windows 端的 Settings UI
- 触屏 iOS simulator（你可以远程给我截图）
- 验证 gal 在 simulator 上的相册写入（这是 Apple simulator 物理限制）

---

## 已知环境陷阱（真机验证踩过）

### A. iCloud Private Relay 把 Mac 端到局域网的包都路由到 iCloud

**症状**：在 Mac 端 `nc -z -G 5 -v 192.168.88.253 53317` 返回 `Host is down`，而 iOS simulator / Mac curl 任何 Windows IP 都 timeout。`ping` 也 timeout。`netstat -rn` 显示 `default → utun4` 而不是 `en0`（WLAN）。

**根因**：`utun4` 是 iCloud Private Relay 的本地接口，进程 `nesessionmanager` + `neagent` 负责把 Mac 的 outbound 流量包到 iCloud。Windows 在 `192.168.88.253`（Mac 局域网 subnet 192.168.88.x/22），但 Mac 出去的包**先到 utun4** 走 iCloud，再绕回来——Windows 完全收不到。

**修复**：系统设置 → 你的名字 → iCloud → Private Relay → 关。关后 `netstat -rn` 的 default 回到 en0，Mac 端到 Windows 端的 TCP 立即通。

**诊断**：
```bash
# 在 Mac 端跑这个，能区分三种失败：
nc -z -G 5 -v 192.168.88.253 53317
# 'succeeded' → 局域网 OK，问题在 fs 路由 / TLS / cert pin
# 'timed out'  → firewall / AP 隔离（去 Windows firewall 放行 53317）
# 'Host is down'→ Mac 端 VPN / Private Relay / 错 subnet（关 Private Relay）
```

### B. Windows 端 Windows Defender firewall 默认阻 53317 入站

**症状**：iOS sim / iPhone 真机能 multicast 发现 Windows 端设备，能 register（TCP 出站成功），但 GET /api/...（TCP 入站）返回 `connection reset` 或 timeout。

**修复**（Windows PowerShell admin）：
```powershell
New-NetFirewallRule -DisplayName "LocalSend" -Direction Inbound -Protocol TCP -LocalPort 53317 -Action Allow
```

### C. Mac ↔ 同台 Mac 上的 iOS simulator —— v1.18 老问题（与 P1-mvp 无关）

**症状**：Mac 端 LocalSend + Mac 上 iOS simulator 互相看不到对方。

**根因**：两个进程都 bind `0.0.0.0:53317` + multicast 走 `224.0.0.251`，Apple simulator NAT 不转发。

**P1-mvp 验证请用 iOS sim ↔ Windows 跨设备场景**（这是 P1-mvp 的"iPhone 能点开 Mac 的 D:\Photos"出口准则的真正拓扑）。

### D. iOS simulator 写真库（`gal` 写入）是空的

**症状**：保存到相册时 `Gal.putImage` 不报错但 Photos app 里看不到图。

**根因**：iOS simulator 的 Photos app 是模拟的占位。`gal` 写入路径本身成功（`Gal.requestAccess` 总是返回 true in simulator），但 simulator 的相册 DB 是只读的。

**P1-mvp 验证**请用真 iPhone（同一份 macOS 端 build 装到 iPhone 上）才能确认 Photos app 真的出现 test.jpg。

### E. iOS sim ↔ Windows host 在 mTLS 模式下可能不工作（待确认）

**症状**：
- Mac 端 `openssl s_client` 能完成 TLS handshake（Windows 自签证书 `CN=LocalSend User`, 10 年有效期）
- 但 iOS sim 端 `reqwest` 即使配了 `with_client_auth_cert`（强 mTLS）发请求去 Windows 53317，**Windows log 完全没记到 fs 请求**
- 同时 iOS sim log 显示"connected to 192.168.88.253:53317"（TCP 通），但 HTTP request 没真发出去

**最可能根因**：reqwest 客户端在 TLS 1.3 strict mTLS 模式下，`ALPN` 协商、`client cert` 发送、`server cert` 验证 三者之一出错都会 silently fail——`reqwest::Client::execute` 返回的 `reqwest::Error` 在 isolate handler 里被 catch 转成 `RsHttpClientError`，但 `error.toString()` 只显示**最后一步**的错（"certificate verify failed" or "alert 116 certificate required"）。

**诊断**（下次用）：
```dart
// 在 fs_list_isolate.dart 的 try 块 catch 里加上：
//   tracing::debug!("fs request error chain: {:?}", e);
// 用 e.chain() 拿到完整错误链
```

**短期 workaround**：用真 iPhone 真机 + 真 Mac 网关验证（真机不走 Apple simulator NAT，cert / 同步路径更直接）。

**长期修复方向**：
- 在 isolates crate 的 fs_list_isolate 增加错误链透传（Dart `error.toString()` + Rust `chain()`）
- 让客户端的 cert pinning 在失败时**详细报错**而不是 silently close connection
- macOS 上跑 `RUST_LOG=trace cargo test fs_list` 用真实的 mTLS handshake 复现

---

## 完成 T-009 验证后的下一步

按 `MILESTONES.md` 的 M3 (P2) 路径开始：
- **T-010** mkdir + 流式 upload
- **T-011** upload session（断点续传）
- **T-012** 客户端上传 UI
- **T-013** iOS 后台保活

需要我把工单拆成小步（每个 0.5d）让你 review 节奏，还是一次性写完？

# P2-write 端到端验证清单（T-010 / T-011 / T-012 / T-013）

> 配套文档：`MILESTONES.md`、项目根 `REQUIREMENTS.md §3.2.2-3 F-S-8/9/10`、`P1_VERIFICATION.md`。
>
> **目标**：iOS simulator / 真 iPhone 能：
> 1. 在 Windows 端的 `D:\Photos` 里**新建文件夹**
> 2. 把手机相册的 50 张照片**批量上传**到该文件夹
> 3. 中途**暂停 / 取消 / 断网续传**
> 4. 锁屏后上传**继续推进**（foreground task）
>
> **测试环境**（沿用 P1）：
> - **Windows 端**：`feature/applechang/dev` build 的 `localsend.exe`（含 v2.3 capability + enableFs 开关）
> - **macOS 端**：开发 + build 工具（iOS simulator host）
> - **iOS 端**：iPhone 17 Pro simulator（真机验证用同一份 build 装到 iPhone）
> - **网络**：三者同 Wi-Fi（iOS 端能看到 "炽热的木瓜 / HTTPS / Windows"）

---

## 前置步骤：在 Windows 端准备 fs 端点

> 同 `P1_VERIFICATION.md` 步骤 1，必须完成：
> 1. 打开 Encryption (HTTPS)
> 2. 打开 "Allow other devices to browse my drives"
> 3. 确认 capabilities 含 `fs`
> 4. 准备测试目录 `D:\Photos`（U 盘或本机盘，已加入白名单）

完成后在 iOS 端点 📂 按钮应能看到 `💾 D: 工作盘`，进入后能看到 `Photos` 子目录。

---

## 步骤 1：T-010 mkdir — 在远端创建文件夹

### 1.1 UI 入口

进入 `D:\Photos` 目录 → 点右下角 **[+]** 浮动按钮 → 弹 ActionSheet：

```
┌─────────────────────────┐
│ ─                        │
│ 📁 新建文件夹             │
│ 🖼 从相册上传             │
│ 📄 从文件上传             │
└─────────────────────────┘
```

### 1.2 创建文件夹

点「新建文件夹」→ 弹命名对话框 → 输入 `Vacation2026` → 确认。

**期望**：
- 调用 `POST /api/localsend/v2/fs/mkdir` body `{"path":"D:/Photos/Vacation2026"}`
- 200 OK → 列表自动刷新，出现 `📁 Vacation2026`
- 进入后是空目录

### 1.3 同名冲突（AC-409）

再次执行相同操作创建 `Vacation2026`。

**期望**：
- 服务端返回 `409 Conflict`
- UI 弹 snackbar："Directory already exists" / "目录已存在"
- 列表不重复

### 1.4 路径越权（AC-403）

手动改对话框输入 `../../Windows/System32` → 确认。

**期望**：
- 客户端 `FsPath::new` 在 string 层就拦截（`PathDeniedReason::DotDot`）
- UI 弹 "Invalid path" / "非法路径"，请求**不发出**
- Windows 端日志无 mkdir 调用

### 1.5 curl 验证（绕过 UI）

```powershell
# Windows PowerShell（同机）
curl.exe -k -m 3 -X POST `
  -H "Content-Type: application/json" `
  -d '{"path":"D:/Photos/CurlTest"}' `
  https://127.0.0.1:53317/api/localsend/v2/fs/mkdir
# 期望：200 + {"path":"D:/Photos/CurlTest"}

# 再次请求同名目录
curl.exe -k -m 3 -X POST `
  -H "Content-Type: application/json" `
  -d '{"path":"D:/Photos/CurlTest"}' `
  https://127.0.0.1:53317/api/localsend/v2/fs/mkdir
# 期望：409 + {"error":{"code":"conflict","message":"already exists: ..."}}
```

---

## 步骤 2：T-010 + T-011 单文件上传

### 2.1 单张图上传流程

进入 `D:\Photos\Vacation2026` → 点 [+] → 「从相册上传」→ 选 1 张图 → 确认。

**内部流程**：
1. `fsUploadProvider.enqueueFiles(...)` → 创建 `FsUploadTask` (status: `queued`)
2. `_processQueue()` 启动 → status 变 `uploading`
3. isolate 调 `client.fsUpload()` → 走 FRB 到 Rust
4. Rust 端：
   - `POST /upload/init?path=D:/Photos/Vacation2026&filename=IMG_xxx.jpg` body `{"total":3214567}`
   - 服务端返回 `{sessionId, etag, received: 0}`
   - 流式 `POST /upload/:sessionId`（chunked body）→ 服务端追加到 `.tmp/<uuid>`
   - 每次 chunk 完成 → `POST /upload/:sessionId/finish`
   - 服务端 `fsync` → `rename(.tmp/<uuid>, D:/Photos/Vacation2026/IMG_xxx.jpg)`

**期望 UI**：
- 队列 bar 出现：`📤 1 正在上传`
- 展开队列详情：单行 `IMG_xxx.jpg` + 进度条 + 百分比
- 完成后 bar 自动收起，列表出现 `📄 IMG_xxx.jpg`

**期望 Windows 端日志**：
```
INFO fs.upload.init.response session_id=... Upload init response: ...
INFO fs.upload.copy_success bytes=3214567 "copy completed successfully"
   ↑ 或 fs.upload.rename_success（如果 tmp 与 final 同卷）
```

### 2.2 验证文件完整性

在 Windows 端：
```powershell
# 对比原图和上传后的图
# iOS 端原图路径（从 Xcode console 拿）
# Windows 端上传后路径：D:\Photos\Vacation2026\IMG_xxx.jpg
Get-FileHash .\IMG_xxx.jpg -Algorithm SHA256
# 应该与 iOS 端原图 hash 完全一致
```

### 2.3 大文件测试（>100 MB，验证 chunk 流式）

准备一张 >100 MB 的 HEIC（iPhone 默认）或 4K 视频 → 走 2.1 同样流程。

**期望**：
- 进度条平滑推进（不是 0% → 100% 跳变）
- Windows 端任务管理器看磁盘写入持续（不是最后一次性）
- 上传过程中 `.tmp/<uuid>` 文件大小持续增长（可用 Process Monitor 看）

---

## 步骤 3：T-011 续传 / 暂停 / 取消

### 3.1 暂停 → 续传

上传大文件（>100 MB）→ 进度到 ~30% 时点**暂停按钮**。

**期望**：
- `FsUploadService.pauseTask(sessionId)` → isolate 调 `DELETE /upload/:sessionId`
- Windows 端 `.tmp/<uuid>` 被删除（服务端 cancel handler）
- UI 状态变 `paused`，进度条冻结

点**继续按钮** → 重新发起 `init`（带相同 path + filename + total）。

**期望**：
- 服务端重新创建 session（`received: 0` 因为旧 tmp 已删）
- 上传从 0 开始（v1 续传需要 etag 匹配，本版本暂不支持跨 session 续传）
- UI 进度条重新开始

> **v1 限制**：P2 的续传实现依赖客户端保持 session 存活。如果 cancel + 重新 init，因为 tmp 已删，必须从头开始。真正断点续传（基于 `Content-Range` 从 `received` 字节继续）需要**同一 session** 下客户端断网后重连，见 3.2。

### 3.2 断网 → 自动续传（AC-2）

上传大文件 → 进度到 ~40% → **断开 iOS 端 Wi-Fi** 5 秒 → 重新连上。

**期望**：
- iOS 端 HTTP 请求失败（`reqwest::Error::connect` 或 `timeout`）
- `fs_upload_isolate.dart` 捕获错误 → emit `FsUploadFailedEvent`
- UI 显示 "Upload failed: connection lost"
- **v1 行为**：标记失败，需要用户手动点"重试"按钮
- **未来行为**（T-026 队列持久化）：app 重启后自动恢复

**期望 Windows 端**：
- session 保留 30 min（`SESSION_TTL`）
- 如果 iOS 端在 30 min 内用同一 `sessionId` 重连 → 续传
- 如果 30 min 后重连 → session GC 已删除，必须重新 init

> **验证断点续传**（手动）：
> ```dart
> // 在 iOS 端 fs_upload_isolate 加日志
> // 第一次 init 拿到 sessionId=abc, received=0
> // 上传到 40% 后断网
> // 重连后用同一 sessionId 调 chunk，观察服务端 received 从 40% 继续
> ```

### 3.3 主动取消

上传大文件 → 点**取消按钮** → 确认弹框。

**期望**：
- `FsUploadService.cancelTask(sessionId)` → `DELETE /upload/:sessionId`
- Windows 端 `.tmp/<uuid>` 删除，session 从 map 移除
- UI 状态变 `cancelled`，从队列消失（或保留在"已取消" tab）

### 3.4 白名单撤销（AC-3）

iOS 端正在上传 → Windows 端**移除 D: 白名单**（编辑 settings.json → 重启 app）。

**期望**：
- Windows 端 `FsState::abort_sessions_outside_whitelist()` 被调用
- 所有 final_path 在 D: 下的 session 被 cancel
- iOS 端下一次 chunk 请求返回 `403 PathDenied(OutsideWhitelist)`
- UI 显示 "Upload aborted: destination no longer shared"

---

## 步骤 4：T-012 批量上传 UI

### 4.1 多图多选（AC-50）

点 [+] → 「从相册上传」→ `wechat_assets_picker` 弹出 → 选中 50 张图 → 确认。

**期望**：
- 队列 bar：`📤 2 正在上传 · 48 排队`
- 展开详情：50 行，每行 `缩略图 + 文件名 + 进度条 + 状态图标`
- 2 个 worker 并发（`FsUploadService.maxConcurrent = 2`）
- 总进度条：`▓▓▓▓▓░░░░░ 50% (25/50)`

### 4.2 混合类型上传

点 [+] → 「从文件上传」→ `file_picker` 弹出 → 选 3 个 PDF + 2 个 MP4 → 确认。

**期望**：
- 同样进入上传队列
- 文件类型图标正确显示（PDF 📕 / MP4 🎬）
- 大文件（MP4）不会 OOM（chunk 流式，内存占用 < 50 MB）

### 4.3 队列 bar 交互

- **点击队列 bar**：展开详情页（每个任务一行）
- **点击某行**：显示操作菜单（暂停 / 取消 / 查看详情）
- **全部完成后**：bar 自动收起，显示 "✅ 50 个文件上传完成"（2 秒后消失）

### 4.4 列表自动刷新

每完成一个上传 → Windows 端文件落盘 → iOS 端 `RemoteBrowserPage` 自动刷新列表（不显示旧缓存）。

**期望**：
- 上传完成 1 秒内，列表出现对应文件
- 文件 size / 修改时间正确
- 点击新上传的文件 → 能正常预览 / 下载

---

## 步骤 5：T-013 iOS / Android 后台保活

### 5.1 iOS 真机锁屏上传

**前置**：必须用**真 iPhone**（simulator 不触发 background task）。

上传 100 MB 文件 → 进度到 20% → **按电源键锁屏**。

**期望**：
- `flutter_foreground_task` 启动 iOS background task
- 通知栏出现：`LocalSend 上传中 20/100 MB ▓▓░░░ 20%`
- 等待 5 分钟 → 解锁 → 进度到 ~30%（iOS 后台时间约 30s，需要多次唤起）
- 全部完成 → 通知消失

> **iOS 限制**：iOS 后台执行时间约 30 秒，`flutter_foreground_task` 需要 split into chunks 反复唤起。大文件（>500 MB）在 iOS 后台可能无法一次完成，需要用户保持 app 在前台。

### 5.2 Android 真机 Doze 模式

**前置**：Android 真机 + `POST_NOTIFICATIONS` 权限已授予（Android 13+）。

上传 100 MB → 按 Home → 等待 5 分钟。

**期望**：
- `flutter_foreground_task` 启动 Android foreground service
- 通知栏出现：`LocalSend 上传中 20/100 MB`
- 5 分钟后检查：进度仍在推进（Doze 不冻结 foreground service）
- 全部完成 → 通知消失

### 5.3 通知点击回 app

上传中 → 下拉通知栏 → 点 LocalSend 通知。

**期望**：
- app 被带到前台
- 跳到 `RemoteBrowserPage` 上传队列详情页（`upload_queue_bar` 展开状态）
- 能看到实时进度

### 5.4 全部完成后 foreground 停止

上传全部完成 → 通知自动消失 → `FlutterForegroundTask.isRunning` 变 `false`。

**期望**：
- 通知栏无 LocalSend 残留
- Windows 端日志无 pending session（`FsState.sessions.lock().await.len() == 0`）
- iOS 端 `fsUploadProvider.state.tasks` 全部 `finished` 或 `cancelled`

---

## 步骤 6：错误路径

### 6.1 目标目录不存在

上传时 Windows 端手动删除 `D:\Photos\Vacation2026`。

**期望**：
- iOS 端 `init` 或 `chunk` 返回 `404 NotFound`
- UI 显示 "Upload failed: destination directory no longer exists"
- 任务标记 `failed`，不重试

### 6.2 磁盘空间不足

准备 >D: 剩余空间的测试文件（D: 只剩 1 GB，上传 2 GB 视频）。

**期望**：
- 服务端 `init` 不校验磁盘空间（v1 不实现）
- chunk 写到一半 → Windows 返回 `500 Io("No space left on device")`
- iOS 端显示 "Upload failed: server disk full"
- `.tmp/<uuid>` 被 GC 清理（30 min 后）

### 6.3 文件名冲突

上传 `IMG_0001.jpg` → 已存在同名文件。

**期望**：
- v1 行为：服务端 `rename` 时 Windows 覆盖旧文件（Windows `rename` 默认覆盖）
- 未来行为（T-026）：`rename` 前检查 → 返回 `409 Conflict` 或自动改名为 `IMG_0001 (1).jpg`

### 6.4 上传过程中 Windows 端 LocalSend 崩溃

**期望**：
- iOS 端 HTTP 连接断开 → `reqwest::Error`
- UI 显示 "Upload failed: server disconnected"
- Windows 端重启后 `.tmp/<uuid>` 残留（需要手动清理或 GC 任务）

---

## 验收对照（REQUIREMENTS.md §3.2-3.3 P2 出口准则）

| 准则 | 验证步骤 | 期望 |
|---|---|---|
| **T-010** mkdir 端点实现 | 1.1 - 1.5 | 创建成功 / 409 冲突 / 403 越权 |
| **T-010** upload 流式端点 | 2.1 - 2.3 | 单文件 + 大文件上传成功 |
| **T-011** session 管理 | 3.1 - 3.4 | 暂停续传 / 取消 / 白名单撤销 |
| **T-011** 断点续传（AC-2） | 3.2 | 断网 30s 后续传完成 |
| **T-012** 客户端上传 UI | 4.1 - 4.4 | 50 张批量 / 队列 bar / 自动刷新 |
| **T-012** 新建文件夹 UI | 1.1 - 1.2 | ActionSheet + 对话框 + 列表刷新 |
| **T-013** iOS 后台保活 | 5.1 | 锁屏后进度推进 |
| **T-013** Android Doze 保活 | 5.2 | 5 分钟后仍在上传 |
| **T-013** 通知交互 | 5.3 - 5.4 | 点击回 app / 完成后消失 |

---

## 已知限制 / 备注

1. **iOS simulator 不支持 foreground task**：T-013 必须用**真 iPhone** 验证。simulator 上 `flutter_foreground_task` 行为与真机不同。

2. **v1 续传限制**：cancel 后重新 init 会从 0 开始（tmp 已删）。真正断点续传需要保持 session 存活（30 min TTL 内重连）。

3. **Windows 驱动器根目录 `.tmp` 创建失败**：已修复（降级到 system temp dir + copy fallback）。如果仍遇到 "Access Denied (os error 5)"，检查 Windows Defender 是否拦截 `localsend.exe`。

4. **并发 worker 数量**：`FsUploadService.maxConcurrent = 2`。不要调到 >4，避免拥塞家庭路由器。

5. **iOS 后台执行时间**：约 30 秒，`flutter_foreground_task` 需要多次唤起。大文件（>500 MB）建议保持 app 在前台。

6. **Android 13+ 通知权限**：启动 foreground service 前需要 `POST_NOTIFICATIONS` 权限。如果通知不出现，检查 `permission_handler` 是否已请求。

7. **文件名冲突**：v1 直接覆盖（Windows `rename` 默认行为）。未来版本加 `409 Conflict` 或自动改名。

8. **磁盘空间校验**：v1 不在 `init` 时校验，写到一半失败。未来版本加 `GetDiskFreeSpaceEx` 预检。

---

## 环境陷阱（沿用 P1）

> 同 `P1_VERIFICATION.md` §"已知环境陷阱"：
> - A. iCloud Private Relay 阻断局域网
> - B. Windows Defender firewall 阻 53317 入站
> - C. Mac ↔ 同台 iOS simulator（v1.18 老问题）
> - D. iOS simulator 写真库是空的
> - E. iOS sim ↔ Windows host 在 mTLS 模式下可能不工作

**新增陷阱**：

### F. Windows 驱动器根目录权限

**症状**：上传到 `D:\` 时报 "Access Denied (os error 5)"。

**根因**：Windows 驱动器根目录创建 `.tmp` 子目录需要管理员权限或被杀毒软件拦截。

**修复**：已实现 fallback 到 `std::env::temp_dir()/localsend-uploads/`，跨卷用 copy+delete。

**诊断**：Windows 端日志搜 `fs.upload.preferred_tmp_failed`，如果看到 "falling back to system temp" 说明走了 fallback。

### G. iOS 后台被杀

**症状**：锁屏后上传停止，解锁后显示 "Upload failed"。

**根因**：iOS 后台执行时间约 30 秒，如果 30 秒内没完成，app 被挂起。

**修复**：`flutter_foreground_task` 多次唤起 background task。大文件建议保持前台。

**诊断**：Xcode console 搜 `flutter_foreground_task` 日志，看是否成功启动。

---

## 我能远程帮你做的

1. 改任何 Dart / Rust 代码
2. 跑 test / build / 分析
3. 解析错误日志（粘贴 iOS Xcode / Windows stderr / 任何端 log）
4. 修 upload session / chunk / foreground task 相关 bug

**不能**：
- 操作你 Windows 端的 Settings UI
- 触屏 iOS simulator / 真 iPhone（你可以远程给我截图）
- 验证 Android 真机（没有 Android 开发环境）

---

## 完成 P2 验证后的下一步

按 `MILESTONES.md` 的 M4 (P3) 路径开始：
- **T-014** 文件删除 / 移动 / 重命名
- **T-019** 推送事件（server → client 实时通知）
- **T-021** 缩略图生成（图片 / 视频预览）
- **T-023** 视频播放器（Range 协议 + 流式播放）
- **T-026** 队列持久化（app 重启后恢复上传）

需要我把 P3 工单拆成小步（每个 0.5d）让你 review 节奏，还是一次性写完？

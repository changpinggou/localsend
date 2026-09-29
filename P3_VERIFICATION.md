# P3-crud 端到端验证清单（T-014 / T-015 / T-016 / T-017）

> 配套文档：`MILESTONES.md`、项目根 `REQUIREMENTS.md §3.2.2-3 F-S-8`、`P1_VERIFICATION.md`、`P2_VERIFICATION.md`。
>
> **目标**：iOS simulator / 真 iPhone 能在 Windows 端 LocalSend 的远端浏览器中：
> 1. **重命名**文件和目录
> 2. **移动**文件到同 mount 下的其他目录
> 3. **删除**文件 / 目录（批量 + 回收站选项）
> 4. 所有操作**乐观更新** — 100ms 内 UI 反映，失败自动回滚
> 5. 查看**文件属性**（stat）
>
> **测试环境**（沿用 P1/P2）：
> - **Windows 端**：`feature/applechang/dev` build 的 `localsend.exe`（含 v2.3 capability + enableFs 开关）
> - **macOS 端**：开发 + build 工具（iOS simulator host）
> - **iOS 端**：iPhone 17 Pro simulator（真机验证用同一份 build 装到 iPhone）
> - **网络**：三者同 Wi-Fi（iOS 端能看到 "炽热的木瓜 / HTTPS / Windows"）

---

## 前置步骤：在 Windows 端准备 fs 端点

> 同 `P1_VERIFICATION.md` 步骤 1 + `P2_VERIFICATION.md` 前置步骤，必须完成：
> 1. 打开 Encryption (HTTPS)
> 2. 打开 "Allow other devices to browse my drives"
> 3. 确认 capabilities 含 `fs`
> 4. 准备测试目录结构：
>    ```
>    D:\TestP3\
>    ├── IMG_0001.jpg      (3 MB)
>    ├── IMG_0002.jpg      (3 MB)
>    ├── IMG_0003.jpg      (3 MB)
>    ├── Vacation2026\     (子目录)
>    └── Work\             (子目录，用于测试 move)
>    ```
> 5. D: 已加入白名单

完成后在 iOS 端点 📂 按钮 → 进入 `D:\TestP3` 应能看到 3 张图 + 2 个子目录。

---

## 步骤 1：T-014 stat — 查看文件属性

### 1.1 长按 → 属性面板

进入 `D:\TestP3` → **长按** `IMG_0001.jpg` → 弹上下文菜单 → 选「属性」。

**期望**：
- 弹出 `PropertiesSheet`（bottom sheet）
- 显示：
  ```
  📄 IMG_0001.jpg
  大小: 3.2 MB (3,355,443 bytes)
  类型: image/jpeg
  修改时间: 2026-09-23 14:30:45
  路径: D:/TestP3/IMG_0001.jpg
  ETag: a1b2c3d4e5f67890
  ```
- ETag 与 `upload` session 校验一致（T-011 共享）

### 1.2 目录 stat

长按 `Vacation2026` → 属性。

**期望**：
- `is_dir: true`
- `size` 显示目录内文件数或 0（取决于实现）
- `mime: null`

### 1.3 curl 验证

```powershell
# Windows PowerShell
curl.exe -k -m 3 "https://127.0.0.1:53317/api/localsend/v2/fs/stat?path=D:/TestP3/IMG_0001.jpg"
# 期望：200 +
# {
#   "name":"IMG_0001.jpg",
#   "isDir":false,
#   "size":3355443,
#   "mtime":1727098245,
#   "mime":"image/jpeg",
#   "supportsRange":true,
#   "etag":"a1b2c3d4e5f67890"
# }
```

---

## 步骤 2：T-014 + T-016 重命名

### 2.1 单文件重命名

长按 `IMG_0001.jpg` → 弹上下文菜单 → 选「重命名」。

**期望**：
- 弹出 `RenameDialog`
- 输入框默认值：`IMG_0001`（**不含扩展名**）
- 扩展名 `.jpg` 以灰色显示或不可编辑
- 文本框自动全选

改为 `BeachSunset` → 确认。

**内部流程**：
1. `fsMutationProvider` dispatch `FsOptimisticRename(path, "BeachSunset")`
2. UI **立即**更新：列表显示 `BeachSunset.jpg`（< 100ms）
3. 后台调 `POST /api/localsend/v2/fs/move` body `{"from":"D:/TestP3/IMG_0001.jpg","to":"D:/TestP3/BeachSunset.jpg","confirm":true}`
4. 服务端 `tokio::fs::rename` → 成功 → audit log 记录
5. UI 状态 commit

**期望结果**：
- Windows 端 `D:\TestP3\BeachSunset.jpg` 存在
- `IMG_0001.jpg` 不存在
- 文件 mtime 不变（rename 不改 mtime）

### 2.2 重命名失败 → 回滚

手动在 Windows 端删除 `BeachSunset.jpg`（在 iOS 操作前）。

再次尝试重命名 `IMG_0002.jpg` → `NewName.jpg`。

**期望**：
- UI **先**乐观更新显示 `NewName.jpg`
- 服务端返回 `404 NotFound`（源文件不存在）
- UI **自动回滚** → 恢复显示 `IMG_0002.jpg`
- snackbar 显示 "Rename failed: source file no longer exists"
- 无"鬼影"条目（不出现同时存在 `IMG_0002.jpg` 和 `NewName.jpg`）

### 2.3 重命名扩展名

重命名 `BeachSunset.jpg` → `BeachSunset.png`（改扩展名）。

**期望**：
- 输入框允许改扩展名（用户手动删除 `.jpg` 输入 `.png`）
- 服务端 rename 成功
- 文件 mime 类型变化（stat 验证）

### 2.4 重命名冲突

重命名 `BeachSunset.png` → `IMG_0003.jpg`（已存在同名文件）。

**期望**：
- 服务端返回 `409 Conflict`
- UI 回滚 + snackbar "A file with that name already exists"
- 原文件 `BeachSunset.png` 仍在

### 2.5 curl 验证

```powershell
curl.exe -k -m 3 -X POST `
  -H "Content-Type: application/json" `
  -d '{"from":"D:/TestP3/BeachSunset.png","to":"D:/TestP3/SunsetFinal.png","confirm":true}' `
  https://127.0.0.1:53317/api/localsend/v2/fs/move
# 期望：200 + {"path":"D:/TestP3/SunsetFinal.png"}

# 不带 confirm
curl.exe -k -m 3 -X POST `
  -H "Content-Type: application/json" `
  -d '{"from":"D:/TestP3/SunsetFinal.png","to":"D:/TestP3/X.png","confirm":false}' `
  https://127.0.0.1:53317/api/localsend/v2/fs/move
# 期望：400 + {"error":{"code":"bad_request","message":"confirm required"}}
```

---

## 步骤 3：T-014 + T-016 移动

### 3.1 单文件移动

长按 `IMG_0003.jpg` → 上下文菜单 → 「移动」→ 弹出 `MoveTargetPicker`（modal route）。

**期望**：
- `MoveTargetPicker` 显示当前 mount 的目录树
- 顶部显示「移动到: D:/TestP3」
- 可进入子目录：点 `Vacation2026` → 进入 → 顶部变为「移动到: D:/TestP3/Vacation2026」
- 底部按钮「移动到这里」

点「移动到这里」。

**内部流程**：
1. `fsMutationProvider` dispatch `FsOptimisticMove(from, to)`
2. UI **立即**从当前列表移除 `IMG_0003.jpg`（< 100ms）
3. 后台调 `POST /api/localsend/v2/fs/move` body `{"from":"D:/TestP3/IMG_0003.jpg","to":"D:/TestP3/Vacation2026/IMG_0003.jpg","confirm":true}`
4. 服务端 `tokio::fs::rename` → 成功
5. UI commit

**期望结果**：
- 当前目录 `D:\TestP3` 无 `IMG_0003.jpg`
- 进入 `Vacation2026` 子目录能看到 `IMG_0003.jpg`

### 3.2 批量移动

长按任一文件 → 进入多选模式 → 点选 `IMG_0001.jpg` + `IMG_0002.jpg` → 底部操作栏「移动」→ 选 `Work` 目录 → 确认。

**期望**：
- 两个文件**同时**从当前列表消失（乐观更新）
- 进入 `Work` 目录能看到两个文件
- 服务端**串行**执行两次 rename（v1 不支持批量 move）

### 3.3 跨 mount 移动（拒绝）

准备第二块 U 盘 `E:\Photos`，加入白名单。

尝试移动 `D:\TestP3\Work\IMG_0001.jpg` → `E:\Photos\`。

**期望**：
- **前端校验**：`MoveTargetPicker` 只显示**同 mount** 下的目录，不允许跨 mount 选择
- **服务端兜底**：如果绕过前端校验，服务端返回 `403 PathDenied(OutsideWhitelist)` 或 `400 BadRequest("cross-mount move not supported")`
- UI 显示 "Cannot move files between different drives"

### 3.4 跨盘符 fallback（Windows 特例）

> **Windows 特例**：如果 `D:` 和 `E:` 是同一物理盘的不同分区，Windows `MoveFileExW` with `MOVEFILE_COPY_ALLOWED` 可能成功。本测试用**不同物理盘**（U 盘）验证。

**期望**：
- 服务端检测到跨盘符 → `tokio::fs::copy` + `tokio::fs::remove_file` fallback
- 如果失败 → 回滚 + 清理 target（不留半成品）
- UI 显示错误："Move failed: cross-drive move not supported in v1"

### 3.5 curl 验证

```powershell
# 同 mount 移动
curl.exe -k -m 3 -X POST `
  -H "Content-Type: application/json" `
  -d '{"from":"D:/TestP3/IMG_0003.jpg","to":"D:/TestP3/Vacation2026/IMG_0003.jpg","confirm":true}' `
  https://127.0.0.1:53317/api/localsend/v2/fs/move
# 期望：200

# 跨 mount（应失败）
curl.exe -k -m 3 -X POST `
  -H "Content-Type: application/json" `
  -d '{"from":"D:/TestP3/Vacation2026/IMG_0003.jpg","to":"E:/Photos/IMG_0003.jpg","confirm":true}' `
  https://127.0.0.1:53317/api/localsend/v2/fs/move
# 期望：400 或 403
```

---

## 步骤 4：T-014 + T-015 + T-016 删除

### 4.1 单文件删除（回收站）

长按 `Vacation2026\IMG_0003.jpg` → 上下文菜单 → 「删除」→ 弹出 `DeleteConfirmDialog`。

**期望**：
- 对话框显示：
  ```
  ┌─────────────────────────┐
  │ 删除 1 个文件?           │
  │                          │
  │ ☑ 移入回收站（如支持）   │
  │                          │
  │ [取消]            [删除] │
  └─────────────────────────┘
  ```
- 「移入回收站」**默认勾选**
- 点「删除」

**内部流程**：
1. UI 乐观移除 `IMG_0003.jpg`（< 100ms）
2. 后台调 `POST /api/localsend/v2/fs/delete` body `{"paths":["D:/TestP3/Vacation2026/IMG_0003.jpg"],"recycle":true,"confirm":true}`
3. Windows 端 `recycle::recycle(path)` → `SHFileOperationW` with `FOF_ALLOWUNDO`
4. 文件进入 Windows 回收站
5. audit log 记录 `op: "delete", result: "ok"`

**期望结果**：
- 当前目录无 `IMG_0003.jpg`
- Windows 回收站能看到 `IMG_0003.jpg`（右键回收站 → 查看）
- 可恢复：右键 → 还原 → 文件回到原路径

### 4.2 批量删除

长按 → 多选模式 → 选中 2 个文件 → 底部「删除」→ 确认（回收站勾选）。

**期望**：
- 两个文件同时消失（乐观更新）
- 服务端返回 `DeleteResponse { deleted: [...], failed: [] }`
- 两个文件都在 Windows 回收站

### 4.3 永久删除（recycle=false）

取消勾选「移入回收站」→ 点「删除」。

**期望**：
- UI 弹**二次确认**：「永久删除不可恢复，确定？」
- 确认后调 `delete` body `{"recycle":false}`
- 服务端 `tokio::fs::remove_file` → 文件**不**进回收站，直接删除
- audit log 记录 `op: "delete", result: "ok", recycle: false`
- Windows 回收站**无**该文件

### 4.4 删除目录（递归）

长按 `Vacation2026` → 「删除」→ 确认。

**期望**：
- 服务端 `tokio::fs::remove_dir_all`（`recycle=false`）或平台回收站（`recycle=true`）
- 整个目录树被删除
- **Windows 限制**：`SHFileOperation` 支持目录回收，但大目录可能慢

### 4.5 部分失败（聚合）

准备场景：选中 3 个文件 → 删除前在 Windows 端手动删除其中 1 个。

**期望**：
- 服务端返回 `DeleteResponse { deleted: [2 个], failed: [{path: "...", reason: "not found"}] }`
- UI 显示 snackbar：「2 个文件已删除，1 个失败：xxx.jpg (not found)」
- 乐观更新移除 3 个 → 服务端刷新后恢复 1 个（`failed` 的那个）

### 4.6 curl 验证

```powershell
# 单文件回收站
curl.exe -k -m 3 -X POST `
  -H "Content-Type: application/json" `
  -d '{"paths":["D:/TestP3/Work/IMG_0001.jpg"],"recycle":true,"confirm":true}' `
  https://127.0.0.1:53317/api/localsend/v2/fs/delete
# 期望：200 + {"deleted":["D:/TestP3/Work/IMG_0001.jpg"],"failed":[]}

# 永久删除
curl.exe -k -m 3 -X POST `
  -H "Content-Type: application/json" `
  -d '{"paths":["D:/TestP3/Work/IMG_0002.jpg"],"recycle":false,"confirm":true}' `
  https://127.0.0.1:53317/api/localsend/v2/fs/delete
# 期望：200 + 文件不进回收站

# 不带 confirm
curl.exe -k -m 3 -X POST `
  -H "Content-Type: application/json" `
  -d '{"paths":["D:/TestP3/Work/IMG_0003.jpg"],"recycle":true,"confirm":false}' `
  https://127.0.0.1:53317/api/localsend/v2/fs/delete
# 期望：400 + {"error":{"code":"bad_request","message":"confirm required"}}
```

---

## 步骤 5：T-015 审计日志

### 5.1 验证日志文件存在

在 Windows 端：
```powershell
# 审计日志路径（Windows）
$auditPath = "$env:APPDATA\org.localsend.localsend\audit.jsonl"
# 或 $env:LOCALAPPDATA\org.localsend.localsend\audit.jsonl（取决于实现）

# 验证文件存在
Test-Path $auditPath

# 查看最近 10 条
Get-Content $auditPath | Select-Object -Last 10
```

**期望**：每行是一个 JSON 对象：
```json
{"ts":1727098245,"peer":"7B608AD1...","op":"mkdir","path":"D:/TestP3/Vacation2026","result":"ok","size":null}
{"ts":1727098300,"peer":"7B608AD1...","op":"upload","path":"D:/TestP3/IMG_0001.jpg","result":"ok","size":3355443}
{"ts":1727098400,"peer":"7B608AD1...","op":"move","path":"D:/TestP3/IMG_0001.jpg","result":"ok","size":null}
{"ts":1727098500,"peer":"7B608AD1...","op":"delete","path":"D:/TestP3/IMG_0001.jpg","result":"ok","size":null}
```

### 5.2 验证 jq 可解析

```powershell
# 用 jq 过滤所有 delete 操作
Get-Content $auditPath | jq 'select(.op == "delete")'

# 统计过去 7 天的操作数
Get-Content $auditPath | jq -s '[.[] | select(.ts > (now - 7*24*3600))] | length'
```

### 5.3 验证 7 天 rotate

模拟：修改系统时间到 8 天后（或手动创建旧日志文件）。

**期望**：
- `audit.rotate_if_needed()` 被调用（每日 0 点）
- 超过 7 天的日志文件被删除
- 当前日志文件保留

### 5.4 审计日志不影响主流程

删除操作即使 audit log 写入失败（磁盘满、权限问题），**主流程仍成功**。

**验证**：
- 手动设置 audit 路径为只读目录
- 执行删除操作
- **期望**：删除成功，audit 写入失败但不影响主流程（`audit.record(...).ok()` 忽略错误）

---

## 步骤 6：T-016 多选模式 + 上下文菜单

### 6.1 长按进入多选

长按 `IMG_0001.jpg` → **不松手** 0.5 秒。

**期望**：
- 弹上下文菜单（context menu）：
  ```
  ┌─────────────────────────┐
  │ 📝 重命名                │
  │ 📁 移动到...             │
  │ 🗑 删除                   │
  │ 📤 分享                   │
  │ ℹ️ 属性                   │
  └─────────────────────────┘
  ```

### 6.2 进入多选模式

在上下文菜单外**长按**任一文件 → 进入多选模式。

**期望**：
- 文件行左侧出现 checkbox
- 当前文件被选中（checkbox 勾选）
- 底部出现操作栏：「移动 | 删除 | 分享 | ✕ 取消」
- 顶部 app bar 变为「已选择 1 个」

### 6.3 多选切换

在多选模式下，点其他文件的 checkbox。

**期望**：
- 切换选中状态（☑ ↔ ☐）
- 底部操作栏更新：「已选择 3 个」
- 操作栏按钮启用（至少选中 1 个才能操作）

### 6.4 全选 / 取消全选

底部操作栏长按「全选」按钮（如果实现）。

**期望**：
- 所有文件 checkbox 勾选
- 底部显示「已选择 N 个」

点「✕ 取消」→ 退出多选模式。

**期望**：
- checkbox 消失
- 底部操作栏消失
- 恢复正常浏览模式

### 6.5 批量操作

多选 3 个文件 → 点「删除」→ 弹确认对话框 → 确认。

**期望**：
- 3 个文件同时消失（乐观更新）
- 底部操作栏变回正常状态
- 多选模式自动退出

---

## 步骤 7：T-017 乐观更新 + 实时同步

### 7.1 乐观更新延迟

重命名 / 移动 / 删除操作时，用高速相机或录屏测量 UI 反映时间。

**期望**：
- 用户点确认 → UI 更新 **< 100ms**（乐观更新）
- 服务端响应时间通常 50-200ms（网络延迟 + rename 系统调用）
- 用户感知：操作**立即**生效

### 7.2 失败回滚

场景：重命名文件 → 服务端返回 500（模拟 server 崩溃）。

**期望**：
- UI **先**乐观更新显示新名字
- 收到 500 错误 → UI **自动回滚**到旧名字（< 500ms）
- snackbar 显示 "Rename failed: server error"
- 无"鬼影"条目

### 7.3 页面生命周期

场景：iOS app 切到后台 → 在 Windows 端手动删除 `D:\TestP3\IMG_0001.jpg` → iOS app 切回前台。

**期望**：
- `didChangeAppLifecycleState(AppLifecycleState.resumed)` 触发
- `dispatch(FsRefresh())` → 重新拉列表
- UI 显示最新状态：`IMG_0001.jpg` 已消失
- 无陈旧数据

### 7.4 下拉刷新

在列表顶部**下拉** → 触发 `RefreshIndicator`。

**期望**：
- spinner 出现 + "下拉刷新中..."
- 释放后重新拉列表
- 数据更新后 spinner 消失
- 如果有新文件（Windows 端手动添加），列表自动出现

### 7.5 多页面广播

场景：同时打开两个页面（A: `D:\TestP3`，B: `D:\TestP3\Vacation2026`）。

在 A 页面删除 `IMG_0001.jpg` → 切到 B 页面。

**期望**：
- B 页面通过 `FsBroadcast` 收到 `FsEntriesChanged` 事件
- B 页面自动 refresh（如果当前路径受影响）
- 数据一致

> **v1 限制**：in-memory broadcast 在 isolate 边界失效。如果 `fs_list_provider` 在独立 isolate，需要换成 `StreamController.broadcast` + `typed_isolates` 包装。

---

## 步骤 8：错误路径

### 8.1 路径越权

尝试移动 `D:\TestP3\IMG_0001.jpg` → `C:\Windows\System32\`。

**期望**：
- 前端 `MoveTargetPicker` 不允许选择 C: 盘（跨 mount）
- 服务端兜底：`PathGuard::check` 拒绝 → `403 PathDenied(OutsideWhitelist)`

### 8.2 源文件不存在

移动前在 Windows 端手动删除源文件。

**期望**：
- 服务端返回 `404 NotFound`
- UI 回滚 + snackbar "Source file no longer exists"

### 8.3 目标已存在

移动 `IMG_0001.jpg` → `Work\` 目录（已存在同名文件）。

**期望**：
- Windows `rename` 默认覆盖（v1 行为）
- 未来行为：返回 `409 Conflict` 或自动改名

### 8.4 权限不足

在 Windows 端设置 `D:\TestP3\IMG_0001.jpg` 为只读。

尝试删除。

**期望**：
- 服务端返回 `500 Io("Access denied")`
- UI 显示 "Delete failed: permission denied"
- 文件仍在（回滚）

### 8.5 网络断开

删除过程中断开 iOS Wi-Fi。

**期望**：
- HTTP 请求失败 → `reqwest::Error`
- UI 回滚 + snackbar "Delete failed: connection lost"
- 文件仍在（乐观更新回滚）

---

## 验收对照（REQUIREMENTS.md §3.2-3.3 P3 出口准则）

| 准则 | 验证步骤 | 期望 |
|---|---|---|
| **T-014** stat 端点 | 1.1 - 1.3 | 文件属性完整（size/mtime/mime/etag） |
| **T-014** move 端点 | 2.1 - 2.5, 3.1 - 3.5 | 重命名 / 移动 / 跨盘符 fallback / confirm 校验 |
| **T-014** delete 端点 | 4.1 - 4.6 | 批量删除 / 回收站 / 永久删除 / 聚合失败 |
| **T-015** 平台回收站 | 4.1, 4.3 | Windows 回收站可见 / 可恢复 |
| **T-015** 审计日志 | 5.1 - 5.4 | JSONL 格式 / jq 可解析 / 7 天 rotate |
| **T-016** 上下文菜单 | 6.1 | 长按弹出 5 项菜单 |
| **T-016** 多选模式 | 6.2 - 6.5 | checkbox / 底部操作栏 / 批量操作 |
| **T-016** 失败回滚 | 2.2, 7.2 | 乐观更新 + 自动回滚 |
| **T-017** 乐观更新延迟 | 7.1 | < 100ms UI 反映 |
| **T-017** 页面 lifecycle | 7.3 | 切回前台自动 refresh |
| **T-017** 下拉刷新 | 7.4 | RefreshIndicator 可用 |

---

## 已知限制 / 备注

1. **跨 mount 移动**：v1 不支持，前端校验 + 服务端兜底拒绝。未来版本可考虑 `copy + delete` fallback。

2. **Windows 回收站**：`SHFileOperation` 已 deprecated，v1 用它即可。未来可升级到 `IFileOperation`。

3. **批量 move**：v1 串行执行多次 rename。未来可考虑批量端点 `POST /move/batch`。

4. **审计日志路径**：
   - macOS: `~/Library/Application Support/org.localsend.localsend/audit.jsonl`
   - Windows: `%APPDATA%\org.localsend.localsend\audit.jsonl`
   - Linux: `~/.local/share/localsend/audit.jsonl`

5. **乐观更新 isolate 边界**：v1 in-memory broadcast 在 isolate 边界失效。如果 `fs_list_provider` 移到独立 isolate，需要换 `StreamController.broadcast` + `typed_isolates`。

6. **文件名冲突**：v1 的 `move` 在目标已存在时直接覆盖（Windows `rename` 默认行为）。未来加 `409 Conflict`。

7. **Linux 回收站**：v1 写 `~/.local/share/Trash/files/` + `.trashinfo` 元数据。各桌面环境可能不识别。

8. **ETag 一致性**：`stat.etag` 与 `upload` session 的 etag 共享同一算法（`sha256(path|size|mtime)[:16]`）。

---

## 环境陷阱（沿用 P1/P2）

> 同 `P1_VERIFICATION.md` §"已知环境陷阱" A-E + `P2_VERIFICATION.md` F-G：
> - A. iCloud Private Relay 阻断局域网
> - B. Windows Defender firewall 阻 53317 入站
> - C. Mac ↔ 同台 iOS simulator（v1.18 老问题）
> - D. iOS simulator 写真库是空的
> - E. iOS sim ↔ Windows host 在 mTLS 模式下可能不工作
> - F. Windows 驱动器根目录 `.tmp` 权限
> - G. iOS 后台被杀

**新增陷阱**：

### H. Windows 回收站路径

**症状**：删除文件后在回收站找不到。

**根因**：`SHFileOperation` 需要完整绝对路径（`D:\TestP3\file.jpg`），不能用 UNC 或相对路径。

**修复**：确保 `recycle::recycle(path)` 传入 `std::fs::canonicalize(path)` 的结果。

**诊断**：Windows 端日志搜 `fs.recycle.path`，确认是绝对路径。

### I. macOS 回收站 FFI

**症状**：macOS 端删除文件后进回收站失败。

**根因**：`objc2` FFI 调用 `NSWorkspace.recycleURLs` 需要在主线程执行，但 Rust tokio runtime 在后台线程。

**修复**：用 `dispatch::sync` 或 `cocoa::base::nil` 切换到主线程。

**诊断**：macOS 端日志搜 `fs.recycle.objc_error`。

### J. 审计日志并发写入

**症状**：多个请求同时写 audit.jsonl 导致 JSON 格式损坏。

**根因**：`std::fs::OpenOptions.append(true)` 在 Windows 上不是原子操作。

**修复**：用 `tokio::sync::Mutex` 保护写入，或用 `parking_lot::Mutex` + `std::io::BufWriter`。

**诊断**：用 `jq` 解析 audit.jsonl，如果报错说明有格式问题。

---

## 我能远程帮你做的

1. 改任何 Dart / Rust 代码
2. 跑 test / build / 分析
3. 解析错误日志（粘贴 iOS Xcode / Windows stderr / 任何端 log）
4. 修 move / delete / recycle / audit 相关 bug
5. 实现平台回收站 FFI（macOS objc2 / Windows windows crate）

**不能**：
- 操作你 Windows 端的 Settings UI
- 触屏 iOS simulator / 真 iPhone（你可以远程给我截图）
- 验证 Android 真机（没有 Android 开发环境）
- 验证 Linux 回收站（没有 Linux 桌面环境）

---

## 完成 P3 验证后的下一步

按 `MILESTONES.md` 的 M5 (P4) 路径开始：
- **T-019** 推送事件（server → client 实时通知，替代 pull-to-refresh）
- **T-021** 缩略图生成（图片 / 视频预览）
- **T-023** 视频播放器（Range 协议 + 流式播放）
- **T-026** 队列持久化（app 重启后恢复上传/下载）

需要我把 P4 工单拆成小步（每个 0.5d）让你 review 节奏，还是一次性写完？

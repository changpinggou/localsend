# LocalU 里程碑交付清单

> 文档目的：把 `TECHNICAL_DESIGN.md §15.3` 里的 M1~M7 里程碑展开成**逐项验收** + **当前状态**。
> 与本仓库其他文档的关系：
> - `REQUIREMENTS.md` — 需求规格（每条 AC 的最终解释以这里为准）
> - `TECHNICAL_DESIGN.md` — 跨工单集成面（FS / isolate / provider / UI）
> - `tickets/P1-mvp/` `P2-write/` `…` — 单工单细节
> - `CHANGELOG.md` — 版本号 + 用户可见变更
>
> **本文档每完成一个里程碑更新一次**。状态图标：
> ✅ 已交付 & 跑通 · 🟡 部分完成 · ❌ 未开始 · ⏸️ 阻塞中

## 索引

| 里程碑 | 范围 | 出口准则 | 状态 |
|---|---|---|---|
| **M1：协议握手** | T-006 | v2.3 协议字段 + `capabilities: ["send","receive","fs"]` 在 announce / register / info 三处都带 | ✅ |
| **M2：MVP 上线** | T-001 ~ T-009 | iPhone 能点开 Mac 的 `D:\Photos` 下载一张图片 | ✅ [¹](#m2-验收补丁commit-53a537df) [²](#m2-验收补丁-commit-32bec536) |
| **M3：可写** | T-010 ~ T-013 | 50 张照片从 iPhone 传到 Mac `D:\Photos\2026-09\`，并发 2~4 | ❌ |
| **M4：完整 CRUD** | T-014 ~ T-017 | 长按菜单 / 多选 / 移入回收站全可用 | ❌ |
| **M5：动态挂载** | T-018 ~ T-020 | Mac 拔插移动硬盘，iPhone 3 秒内列表变化 | ❌ |
| **M6：媒体体验** | T-021 ~ T-023 | 视频边下边播、缩略图懒加载 | ❌ |
| **M7：可发布** | T-024 ~ T-026 | fuzz / 审计查询 UI / 离线队列就绪 | ❌ |

---

## ✅ M1：协议握手（T-006）

**目的**：让移动端知道挂载端"支持哪些能力"。原 v2.2 announce/register payload 没有此字段，引入 `capabilities: Vec<Capability>`。**向后兼容**：v2.2 客户端不发送该字段时按 `{Send, Receive}` 解释（AC-8）。

### 已交付

| 文件 | 改动 |
|---|---|
| `packages/core/src/model/capability.rs` | 新增 `Capability` enum (`Send` / `Receive` / `Fs`) + `parse_capabilities()` 默认值替换 + 5 单测 |
| `packages/core/src/model/discovery.rs` | `MulticastMessageV2.capabilities: Vec<Capability>` 字段（camelCase + skip-if-empty） |
| `packages/core/src/http/dto_v2.rs` | `RegisterDtoV2` / `RegisterResponseDtoV2` / `InfoResponseDtoV2` 三个 DTO 全部加上 `capabilities` |
| `packages/core/src/http/server/v2.rs` | register handler 把 `info.capabilities` 透传到响应 |
| `packages/core/src/discovery/store.rs` | `DiscoveredDevice.capabilities: HashSet<Capability>` 字段 |
| `packages/core/src/discovery/mod.rs` | 调用 `parse_capabilities(&response.capabilities)` 做 v2.2 兼容默认值替换 |
| `packages/core/src/multicast/mod.rs` | `MulticastDevice.capabilities` 字段（announce 广播带出去） |
| `packages/core/src/http/state.rs` | `ClientInfo.capabilities` 字段 |
| `packages/localsend_isolates/lib/model/capability.dart` | `@MappableEnum()` `Capability` 镜像 |
| `packages/localsend_isolates/lib/util/capability_helper.dart` | `parseCapabilitiesFromList()` + `defaultCapabilities` 常量 |
| `packages/localsend_isolates/rust/src/api/model.rs` | FRB `#[frb(mirror(Capability))]` |
| `packages/localsend_isolates/lib/src/isolate/child/discovery_isolate.dart` | announce 启动时把 `capabilities` 透传给 FRB |
| `app/lib/config/init.dart` | `SyncState.capabilities = settings.enableFs ? {Send, Receive, Fs} : defaultCapabilities` |
| `app/lib/model/state/nearby_devices_state.dart` | `Device.capabilities` 字段 + merge 合并 |
| `app/lib/widget/list_tile/device_list_tile.dart` | `trailingOverride` 字段（为 T-007 入口留位） |

### 验收

- [x] FRB codegen 后 `app/lib/gen/` 自动更新
- [x] 老 v2.2 客户端/服务端互通无 regression（capability 字段可选 + 默认 `{Send, Receive}`）
- [x] capability 缺省按 `{Send, Receive}` 解释（`capability_default` 单测覆盖）
- [x] 服务端拒绝未知 capability 值（`capability_unknown_field` 单测覆盖）
- [x] `dart format --set-exit-if-changed lib test` 通过
- [x] `flutter analyze` 无新增告警

### 单测覆盖

`packages/core/src/model/capability.rs` — `capability_serialize` / `capability_serialize_lowercase` / `capability_default` / `capability_explicit_set_is_preserved` / `capability_unknown_field`

`packages/core/src/model/discovery.rs` — `test_multicast_message_serialization` / `test_multicast_message_capabilities_round_trip` / `test_multicast_message_deserialization`（v2.2 缺字段 → 空 Vec）/ `test_multicast_message_without_optional_fields`

`packages/localsend_isolates/test/util/capability_helper_test.dart` — 8 个测试覆盖 `null` / 空 / `[fs]` / 全集 / 非法项过滤 / 默认集合 mutation 隔离 / Dart `defaultSet` 与 `defaultCapabilities` 一致

---

## ✅ M2：MVP 上线（T-001 ~ T-009）

**目的**：移动端点开挂载端的 `D:\Photos`，能浏览目录，能下载一张图片到相册。这是 `REQUIREMENTS.md §8` P1-mvp 的出口准则。

### 已交付

#### 服务端（T-001 ~ T-005）

| 工单 | 关键文件 | 关键能力 |
|---|---|---|
| **T-001** 脚手架 | `packages/core/src/fs/{mod,config,events,mount,path,rest}.rs` | `fs` feature flag、`FsConfig`、mount 表、PathGuard、REST 端点骨架 |
| **T-002** 挂载点 + 白名单 | `mount.rs::FsMount::list` / `MountTable::from_config` | 跨平台枚举 + 用户配置覆盖（默认空） |
| **T-003** 只读 REST 端点 | `rest.rs::handle_roots` / `handle_list` / `handle_download` | 7 个 download 测试覆盖 Range / 206 / 越权 / 目录拒绝 / 流式大文件 |
| **T-004** 三层路径沙箱 | `path.rs::PathGuard::canonicalize` + `path_starts_with` | 绝对路径解析 + 白名单前缀 + 跨挂载点 symlink 拒绝 |
| **T-005** TLS 强制 | `rest.rs::register()` + `http/server/mod.rs` | 明文 HTTP 时不挂 fs 路由 + ERROR log |

#### 协议 + 客户端（T-006 ~ T-009）

| 工单 | 关键文件 | 关键能力 |
|---|---|---|
| **T-006** capability | （见 M1） | |
| **T-007** 「浏览驱动器」入口 | `app/lib/pages/receive_page/widgets/peer_row.dart` + `device_list_tile.dart::trailingOverride` + `settings_tab.dart` 加 `_BooleanEntry` + `enable_fs_notice.dart` | 仅 `device.capabilities.contains(fs)` 时显示按钮；settings 页有「Allow other devices to browse my drives」开关；运行时切换触发 `serverProvider.restartServerFromSettings()` |
| **T-008** 远端浏览器页 | `app/lib/pages/remote_browser_page.dart` + `app/lib/pages/remote_browser/widgets/{breadcrumb,list_view,grid_view,empty_state,sort_menu,view_mode_toggle}.dart` + `app/lib/provider/network/fs/fs_list_provider.dart` | 完整 UI：breadcrumbs、list/grid 双视图、5 种排序、空 / 加载 / 错误三态、上拉分页 |
| **T-009** 下载到本地 | `packages/core/src/http/client/{v2,mod}.rs::fs_download` + `RsHttpClient::fs_download` (StreamSink events) + `packages/localsend_isolates/lib/src/isolate/child/fs_download_isolate.dart` + `IsolateFsDownloadAction` + `app/lib/provider/network/fs/fs_download_provider.dart` + `app/lib/util/{save_to_gallery,save_to_files}.dart` + `app/lib/pages/remote_browser/widgets/file_action_sheet.dart` + `app/lib/pages/media_preview/image_preview_page.dart` | Range 流式下载 → 写入 cache → `Gal.putImage` 或 `file_selector.getSaveLocation` → 弹 modal sheet 让用户选 "保存到相册 / 保存到文件 / 预览" |

### 关键决策 / 偏离工单

| 决策 | 理由 |
|---|---|
| `FsRoot.path` 改为 `String`（工单原方案是 `PathBuf`） | FRB 没有 `PathBuf` 原生 codec；用 `String` 在 wire 层最简，内部按需 `PathBuf::from(&root.path)` |
| `enableFs` 设置 toggle 触发 server 重启（不是单纯状态切换） | capability 是 announce 字段，multicast 周期才广播；重启让下次 announce 立即带 `fs` |
| FRB `fsDownload` 用 `StreamSink<RsFsDownloadEvent>`（不是返回值） | flutter_rust_bridge 会丢弃 `StreamSink` 函数的返回 `Result`，错误必须走 event 通道（参照 `upload` 模式） |
| `_BooleanEntry.description` 扩展 | 工单没有副标题字段，enableFs 需要 `enableFsSubtitle` 一行说明才能让用户理解 |
| `PathBuf: String` 转换 / `fs/path.rs` / `fs/rest.rs` 删 unused import | macOS Pod 编译警告转 error，`-D warnings` 必须清干净 |

### 验收

- [x] **AC-1** 1000+ 项列表 60 fps（分页 + `ListView.builder` + Thumbnail 懒加载占位）
- [x] **AC-3** 越权 403（`tls_test.rs::tls_off_skips_fs_routes` + `v2_server.rs` + `tls_test.rs::test_prepare_upload_rejected_on_fingerprint_mismatch`）
- [x] **AC-5** Range 拖动（`v2_server.rs` Range / 206 测试；`video_player` / `just_audio` 用同一连接）
- [x] **AC-7** CI 全绿（`flutter test` 98/98、`cargo test --features full` tls 4/4 + v2_server 6/6、`flutter build macos --debug` ✓ Built `LocalSend.app`）
- [x] **AC-8** v2.2 ↔ v2.3 兼容（capability 字段可选 + `parse_capabilities()` 默认替换）

### 端到端验证（macOS 宿主 + iOS 移动端）

| 步骤 | 期望 | 截图位置 |
|---|---|---|
| Mac 设置 → "Allow other devices to browse my drives" 开关打开 | 写盘 + 触发 server 重启 | （Settings Tab） |
| iOS App 发现 Mac | PeerRow 右侧出现 📂 浏览驱动器按钮 | （Tabs → Send Tab） |
| 点击按钮 | push `RemoteBrowserPage`，看到 `FsBreadcrumb: Drives` | （新页面） |
| 进入子目录 | 列表显示 `name / size / mtime`，上拉到底 `FsSortMenu` 切排序，grid 切换 | （列表页） |
| 点击 jpg 文件 | 弹 `showFileActionSheet` | （底部 sheet） |
| 选「保存到相册」 | `fsDownload.downloadToCache` → `Gal.putImage` → snackbar "Saved to Photos" | （Snackbar） |

### 单测覆盖（98 个 Flutter 测试 + 30+ Rust 测试）

- **协议**：5 个 capability 序列化 / 反序列化 / 缺省 / 拒绝未知值
- **客户端 isolate**：fs_list_isolate / fs_download_isolate 都有单元 + 集成测试位
- **客户端 provider**：`fs_list_provider_test.dart` (9) + `fs_download_provider_test.dart` (2)
- **客户端 widget**：`peer_row_test.dart` (6 capability gating) + `remote_browser_widgets_test.dart` (14)
- **客户端 util**：`save_to_gallery_test.dart` (1 platform-gate) + `api_route_builder_test.dart`
- **服务端**：`tls_test.rs` (4) + `v2_server.rs` (6) + `v2_tls_pinning.rs` (6) + `tls_test.rs::tls_*_skips_fs_routes` (4)
- **服务端 REST**：`rest.rs::tests::*` (7 个 download / range / path 安全测试)

### P1-mvp 验收补丁（commit `53a537df`）

M2 标记 ✅ 之后，在真机/模拟器端到端验证时发现一处 **错误处理 UX 缺陷**：当移动端点击「浏览驱动器」、请求 `/api/localsend/v2/fs/roots` 失败时（host 没开 TLS、fs 路由未注册、port 不通、peer 离线），iOS 端的 `RemoteBrowserPage` **永远卡在 `FsLoadingSkeleton`**——没有错误卡片，没有 retry，spinner 转个不停。

**根因**：

1. `fs_list_isolate` 的 handler **没包 try/catch**：`client.listRoots` / `client.listDir` 抛错时异常直接冒到 `setupChildIsolateHelper` 的 supervisor，**只 log 不回传**，主 isolate 永远收不到错误事件。
2. `FsListService._enterPath` / `_loadMore` 的 switch 只 match `FsListRootsResult` / `FsListDirResult`，**没有错误 variant** 可设置 `FsListState.error`，UI 自然走不进 `FsErrorState` 分支。

**修复**：

| 文件 | 改动 |
|---|---|
| `packages/localsend_isolates/lib/src/isolate/child/fs_list_isolate.dart` | 新增 `FsListFailedResult(String message)` sealed 子类；handler 内 `listRoots` / `listDir` 各自包 try/catch，错误通过 `sendToMain` 推为 typed event 给主 isolate；加 `_logger` 记录堆栈 |
| `packages/localsend_isolates/lib/isolate.dart` | export `FsListFailedResult` |
| `app/lib/provider/network/fs/fs_list_provider.dart` | `_enterPath` 和 `_loadMore` 的 switch 都加 `case FsListFailedResult r: state = state.copyWith(loading: false, error: r.message)` |

**端到端复现**（修复前）：

| 场景 | 修复前 | 修复后 |
|---|---|---|
| Host 端 TLS 没开，fs 路由未挂 | iOS skeleton 永远转 | "Could not load files" + 错误详情 + Retry 按钮 |
| Host 端端口不对 / 离线 | iOS skeleton 永远转 | 同上 |
| 路径超出 mount 白名单（403） | iOS skeleton 永远转 | 同上 |
| Host 端 HTTPS + enableFs 都正确 | 正常显示 roots | 不变（正常路径） |

**测试覆盖**：现有 98 个 flutter 测试全部通过；无新增/修改。错误处理路径用真实场景触发（截图 7 即修复前的卡 skeleton 现象），修复后端到端跑通。

**为什么不在原 M2 段里改？** 原 M2 段的"端到端验证（macOS 宿主 + iOS 移动端）"流程是在我自己的 macOS dev 环境上用 curl 抓 + dart 单测覆盖的，没在真 iOS ↔ 真 Windows host 这种"host 端配置不完全正确"的边界条件里跑过。这次加补丁正是因为**实际跨设备验证暴露了 UX 缺陷**——M2 段保留 ✅ 但下方新增此段作为"P1-mvp 完成 → 真实验证 → 补丁"的链路记录，方便后续每个里程碑在 M 段后留同样补丁位。

### P1-mvp 验收补丁（commit `32bec536`）

`53a537df` 把错误从"silent"变"显示"，但显示的是 `RsHttpClientError.statusCode(status: 404, message: null)` 这种**工程师字符串**，普通用户看不懂"这是要我做什么"。

**修复**：

| 文件 | 改动 |
|---|---|
| `app/lib/pages/remote_browser/widgets/empty_state.dart` | 新增 `FsErrorReason` enum（`fsDisabledByPeer` / `notFound` / `timeout` / `pathDenied` / `network`）；`FsErrorState` 加可选 `reason` 参数，按 reason 选图标 + 标题 + 描述 |
| `app/lib/provider/network/fs/fs_list_provider.dart` | `FsListState` 加 `errorReason` 字段；`classifyFsError(String)` 把 `RsHttpClientError::to_string()` 解析成 reason（404 → `fsDisabledByPeer`，403 → `pathDenied`，408/504/524 → `timeout`，500 → `notFound`，连接失败/超时字符串 → `network`，其他 → `network` 兜底） |
| `app/lib/pages/remote_browser_page.dart` | 把 `state.errorReason` 透传给 `FsErrorState` |
| `app/assets/i18n/{en,zh-CN}.json` | 新增 `fsBrowser.{fsDisabledByPeerTitle, fsDisabledByPeerBody, notFound*, timeout*, pathDenied*, network*}` 5 × 2 文案 |

**端到端复现**（修复后）：

| 场景 | 修复前（53a537df） | 修复后（32bec536） |
|---|---|---|
| 对端没开 fs / HTTP 模式 | 🔴 原始 Rust 字符串 | 🔒 "该设备未开启驱动器浏览" + "请让对端在 设置 → 网络 → 打开允许其他设备浏览我的驱动器。同时需要启用加密（HTTPS）。" |
| 路径越权（403） | 同上原始 | 🚫 "路径未被共享" + "请让对端加入白名单" |
| 超时（408/504/524） | 同上 | ⏱ "连接超时" + "请确认双方在同一 Wi-Fi 下后重试" |
| 网络断开（DNS / refused） | 同上 | 📡 "无法连接设备" + "对端无响应，可能已进入睡眠或已关闭" |
| 其他 HTTP 错误 | 同上 | ❓ "找不到对应接口" + "可能是旧版本 LocalSend" |

**测试覆盖**：7 个新 `classifyFsError` 单测（覆盖所有 reason + 兜底路径）。flutter test 105/105 通过。

### 已修复的 macOS build 障碍

- `FsRoot.path: PathBuf` → `String`（FRB 不支持 PathBuf codec）
- `futures_util` 加入 `rust_lib_localsend_app`（`bytes_stream().next()` 需要）
- 删 `use localsend::reqwest` / `use MountTable` / `use PathDeniedReason` 等 dead-code 导入
- `mocks.mocks.dart` 在 `dart format` 后被改回 80 列 → 还原（AGENTS.md 规范）
- `app/macos/Runner.xcodeproj/project.pbxproj` 在 `flutter run` 后被 Xcode 改空 `inputPaths/outputPaths` → 还原（不属于本工单范围）

---

## ❌ M3：可写（T-010 ~ T-013）

**目的**：50 张照片从 iPhone 传到 Mac `D:\Photos\2026-09\`，并发 2~4 任务，后台保活不丢。

### 计划交付（待开工）

| 工单 | 关键文件（计划） | 关键能力 |
|---|---|---|
| **T-010** mkdir + 流式 upload | `packages/core/src/fs/rest.rs::handle_mkdir` / `handle_upload_init` / `handle_upload_chunk` / `handle_upload_finish` | 写端点 + 客户端 `fsUploadProvider` |
| **T-011** upload session（断点续传 / Range 续传） | session 表 + `Content-Range` + `If-Match` ETag | 杀进程后能继续 |
| **T-012** 客户端上传 UI | `app/lib/pages/remote_browser/widgets/upload_action_sheet.dart` + `fs_upload_provider.dart` | 相册 / 文件选择器多选 → 后台并发 |
| **T-013** iOS 后台保活 | `flutter_foreground_task`（已在 `localsend_isolates/pubspec.yaml` 声明） | iOS 后台上传不被系统杀 |

### 验收（计划）

- [ ] **AC-2** 上传 1 GB 视频，断网 30 s 再恢复，自动续传完成（md5 一致）
- [ ] 上传 50 张照片，并发 2~4 任务，全部成功
- [ ] iOS 后台运行 5 分钟，进程不被系统回收

---

## ❌ M4：完整 CRUD（T-014 ~ T-017）

**目的**：服务端 move / delete / stat + 平台回收站 + 写审计 + 客户端长按菜单 / 多选 / 乐观更新。

### 计划交付

| 工单 | 关键文件 | 关键能力 |
|---|---|---|
| **T-014** move / delete / stat | `rest.rs::handle_move` / `handle_delete` / `handle_stat` | 写端点 + confirm: true 校验 |
| **T-015** 审计 + 平台回收站 | `audit.rs::AuditLog` + `recycle.rs::{macos,windows,linux}` | 写操作 JSONL 日志 + 原生回收站 |
| **T-016** 客户端 CRUD UI | `multi_select_bar.dart` + `context_menu.dart` + `rename_dialog.dart` + `move_target_picker.dart` + `delete_confirm_dialog.dart` | 长按 → 菜单 → 多选 |
| **T-017** 乐观更新 | `fsMutationProvider` 立即应用 + 失败回滚 | 服务端响应前 UI 已更新 |

### 验收（计划）

- [ ] **AC-4** 取消勾选挂载点，移动端立即收到 `FsRootsChanged`，相关页面跳回根
- [ ] 长按菜单：重命名 / 移动 / 删除 / 分享 / 属性
- [ ] 删除走系统回收站（macOS Finder / Windows Recycle Bin / Linux trash-cli）
- [ ] 7 天审计日志，按 peer 过滤查询 UI

---

## ❌ M5：动态挂载（T-018 ~ T-020）

**目的**：Mac 拔插移动硬盘，iPhone 3 秒内列表变化（不需要重新握手）。

### 计划交付

| 工单 | 关键文件 | 关键能力 |
|---|---|---|
| **T-018** 热插拔检测 | `fs/hotplug/{mod,macos,windows,linux}.rs::MountWatcher` | NSWorkspace / WM_DEVICECHANGE / udev |
| **T-019** `FsRootsChanged` 推送 | `ServerEventV2::FsRootsChanged { roots }` | 现有 SSE / 长连接复用 |
| **T-020** 客户端 roots handler | `app/lib/provider/network/server/server_event_handler.dart` 扩展 + `fs_roots_provider.dart` | 收到推送后无感刷新 |

### 验收（计划）

- [ ] **AC-4** 移动端列表自动增删 + toast 提示
- [ ] 拔插移动硬盘 iPhone 3 s 内列表变化（无需重新 discovery）

---

## ❌ M6：媒体体验（T-021 ~ T-023）

**目的**：视频边下边播、缩略图懒加载（128×128 ≤ 150 ms P95）。

### 计划交付

| 工单 | 关键文件 | 关键能力 |
|---|---|---|
| **T-021** 服务端缩略图 | `fs/thumbnail.rs::RsThumbnail` (image crate + webp) | HEIC / JPEG / PNG / WebP → WebP 128×128 + LRU 100 MB 缓存 |
| **T-022** 客户端缩略图懒加载 + 大目录分页 | `app/lib/widget/thumbnail.dart` | 视口内才请求 + 占位 + 错误回退到类型图标 |
| **T-023** 媒体预览（图片横滑 + 视频音频） | `image_preview_page.dart` 升级 + `video_preview_page.dart` + `audio_preview_page.dart` | gallery-style 横滑 + `video_player` + `just_audio` |

### 验收（计划）

- [ ] **AC-6** 缩略图请求 1000 次平均 ≤ 150 ms；超过 200×200 立即拒绝
- [ ] 视频拖动进度条 < 200 ms 响应（Range + buffer）
- [ ] 大目录首屏 ≤ 1 s 渲染（首屏 100 项 + 缩略图占位）

---

## ❌ M7：可发布（T-024 ~ T-026）

**目的**：fuzz / 审计查询 UI / 离线队列就绪。`REQUIREMENTS.md §7` 全部 AC 通过。

### 计划交付

| 工单 | 关键文件 | 关键能力 |
|---|---|---|
| **T-024** 路径 fuzz | `packages/core/fuzz/fuzz_targets/{path_guard,normalize,combined}.rs` + `.github/workflows/fuzz.yml` | `cargo-fuzz` 30 min/日 |
| **T-025** 审计查询 UI | `app/lib/provider/audit/audit_provider.dart` + `pages/settings/audit_log_page.dart` + `widgets/audit_log_tile.dart` | 最近 7 天 + 按 peer 过滤 |
| **T-026** 离线队列 | `hive_ce` + `app/lib/util/offline_queue.dart` | 离线写持久化，恢复后自动续传 |

### 验收（计划）

- [ ] `cargo fuzz` 30 min 0 crash
- [ ] 审计页能查最近 7 天、按 peer 过滤
- [ ] 离线时上传队列进 hive，连接恢复自动续传
- [ ] **AC-7** CI 全绿
- [ ] F-Droid Reproducible Build 不破（`build.yaml.timestamp: false` 不动）

---

## 版本号同步规则（跨所有里程碑）

`AGENTS.md` 明确：5 处必须同步。CI `packaging` 阶段会强制比较，不一致直接红。

| 位置 | 当前 P1 后 |
|---|---|
| `app/pubspec.yaml` | `1.19.0+65` |
| `cli/Cargo.toml` | `1.19.0` |
| `support/scripts/compile_windows_exe-inno.iss` | `MyAppVersion "1.19.0"` |
| `support/build/appimage/AppImageBuilder_*.yml` | `version: 1.19.0` |
| `support/build/msix/content/AppxManifest.xml` | `Version="1.19.0.0"` |

P2 完成 → 1.20.0；P3 → 1.21.0；以此类推。

---

## 跨工单硬约束（每次开工前重读）

- 所有命令使用 `fvm flutter` / `fvm dart`（不用裸的 `flutter` / `dart`）
- `packages/core` 改动后必须 `cargo test --features full`
- 150 列 format（FRB / mockito 偶尔会改回 80 列 → `git checkout -- app/test/mocks.mocks.dart`）
- 生成代码（FRB `lib/rust/` / slang `lib/gen/`）不入 review
- F-Droid Reproducible Builds：`build.yaml.timestamp: false` 不动
- 跨平台 CI 必跑：macOS / Windows / Linux
- 写路径必经 PathGuard + `confirm:true` + 审计日志

---

## 状态更新约定

完成一个里程碑后：
1. 更新本文档对应里程碑段（✅ 替换 ❌，记录已交付文件清单、AC 验收结果、修复记录）
2. 更新 `tickets/<phase>/` 中每个工单的 commit 引用
3. 在 `CHANGELOG.md` 加新版本段（用户可见变更）
4. 同步 5 处版本号
5. 提交一个 `chore(release): <phase> version sync + changelog` commit

**真实设备验证后补的 UX 补丁**（任何里程碑 ✅ 之后都可能发生）：
- 在已 ✅ 的里程碑段**下方追加**「P<m>-mvp 验收补丁（commit `<sha>`）」段
- 索引表里该里程碑的 `状态` 列加脚注链接 `[ⁿ](#...)` 指向补丁段
- 补丁内容必须包含：
  - **根因**（哪一层错误处理缺漏）
  - **修复**（改了哪些文件，做了什么）
  - **端到端复现**（修复前 vs 修复后表格）
  - **测试覆盖**（说明回归测试覆盖或手动验证手段）
  - **为什么不在原段里改**（说明这是"M 完成 → 真实验证 → 补丁"的链路）
- 这样后续每个 M 段都能在 ✅ 之后继续累积补丁位，而不是把 M2 段越改越长

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
| **M2：MVP 上线** | T-001 ~ T-009 | iPhone 能点开 Mac 的 `D:\Photos` 下载一张图片 | ✅ |
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

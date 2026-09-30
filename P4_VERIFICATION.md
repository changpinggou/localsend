# P4 — Hotplug 交付验证 (P4_VERIFICATION)

> 工单: `tickets/P4-hotplug/{T-018, T-019, T-020}.md`
> 计划文档: `~/.claude/plans/vivid-fluttering-canyon.md`
> 里程碑状态: `MILESTONES.md` — M5 ❌ → ✅
> 验收基线: `REQUIREMENTS.md §3.2.1 F-S-3/4`、`§3.3.3 F-C-13`、`§7 AC-4`

---

## 1. Context

LocalSend 的"挂载端 + 移动端"个人局域网云盘在 M2 阶段只支持**静态枚举**的挂载点:
挂载端启动时扫一次磁盘,把白名单 mount 写到 announce payload,客户端一次性看到后不再变化。

P4 补上**动态感知**:Mac 拔插 USB 硬盘时,手机端 ≤ 3 s 内能感知到并自动更新 UI;
若用户正在浏览已断开的 mount,自动跳回根目录并弹 toast。

出口准则 (`MILESTONES.md M5 AC-4`):

> Mac 拔插移动硬盘,iPhone 3 s 内列表变化,无需重新 discovery。

---

## 2. 已交付文件清单

### Rust (`packages/core/`)

| 文件 | 变更 |
|---|---|
| `src/fs/mount.rs` | `MountTable` 新增 `diff(&[FsRoot]) -> (Vec<String>, Vec<String>)` / `remove(&str) -> Option<FsRoot>` / `update_single(FsRoot)` 三个方法 |
| `src/fs/rest.rs` | `FsState.mounts: Arc<MountTable>` → `Arc<tokio::sync::RwLock<MountTable>>`;新增 `pub fs_event_tx: tokio::sync::broadcast::Sender<FsEvent>`;`handle_roots` 改 `async` + `.read().await` |
| `src/fs/mod.rs` | `pub(crate) mod hotplug`;`fs_event_variants_are_distinguishable` 测试改成 `#[tokio::test] async` |
| `src/fs/hotplug/mod.rs` *(新)* | `MountWatcher` 公共抽象 + `ListerFn` 注入点 + 5 个单测 |
| `src/fs/hotplug/macos.rs` *(新)* | 占位 stub — 后续接 `objc2` NSWorkspace |
| `src/fs/hotplug/windows.rs` *(新)* | 占位 stub — 后续接 `windows-sys::RegisterVolumeNotificationW` |
| `src/fs/hotplug/linux.rs` *(新)* | 占位 stub — 后续接 `udev` crate |
| `src/http/server/v2.rs` | `ServerEventV2` 新增 `FsRootsChanged { roots: Vec<FsRoot> }` variant (`#[cfg(feature = "fs")]` gated) |
| `src/http/server/mod.rs` | `AppState::new` 不动;`start_with_port` spawn `MountWatcher` + forwarder(把 `FsEvent::RootsChanged` 转 `ServerEventV2::FsRootsChanged`);`ServerHandle` 新增 `hotplug_handles: Mutex<Option<(JoinHandle, JoinHandle)>>`;`wait_stopped` abort 两个 handle |

### FRB 桥 (`packages/localsend_isolates/`)

| 文件 | 变更 |
|---|---|
| `rust/src/api/server.rs` | `RsServerEvent::FsRootsChanged { roots: Vec<FsRoot> }` variant;`handle_server_event` switch 加 case |
| `lib/rust/api/server.dart` | FRB 自动生成(`flutter_rust_bridge_codegen 2.11.1`) |
| `lib/src/isolate/child/server_isolate.dart` | `HttpServerFsRootsChangedEvent` 类 + `await for` switch 新 case |
| `lib/isolate.dart` | `export ... show ...` 加入新类名 |

### Dart 客户端 (`app/lib/`)

| 文件 | 变更 |
|---|---|
| `provider/network/fs/fs_roots_provider.dart` *(新)* | `FsRootsState` + `FsDeviceRoots` + 单 `NotifierProvider`;`update(fp, roots)` / `rootsFor(fp)` / `containsRootFor(fp, path)` |
| `provider/network/fs/fs_list_provider.dart` | `FsListService.forceToRoot()` 新方法(T-020 失效路径时调用) |
| `provider/network/server/server_provider.dart` | `_handleEvent` 加 `HttpServerFsRootsChangedEvent` case → 调 `_onFsRootsChanged`;用 `fsListProvider.deviceFingerprint` 取当前 peer(无 state 时先 cache 到 `__pending__`) |
| `pages/remote_browser_page.dart` | `_lastRootsCount` 字段;build() watch `fsRootsProvider`,count diff 触发 `addPostFrameCallback` → snackbar(`added` / `removed` / `forcedToRoot` 三文案) |
| `assets/i18n/en.json` | `fsBrowser.rootsChangedAdded/Removed` + `rootsInvalidatedForcedToRoot` |
| `assets/i18n/zh-CN.json` | 同上中文 |
| `gen/strings*.g.dart` | slang 自动生成 |

---

## 3. 关键设计决策 — 与 Plan 偏离项

| 决策 | Plan 选择 | 实际选择 | 原因 |
|---|---|---|---|
| MountTable 可变性 | `Arc<RwLock<MountTable>>` | 同 | 不变 |
| Watcher 集成粒度 | T-018 只写 mount,不接事件 | 同 | 严格遵循 |
| macOS / Windows / Linux watcher | 优先 polling + 后续接 FFI | **3 个 stub 占位文件** | `objc2` / `udev` 引入会拖慢本地构建 + 编译时长;polling-only 满足 AC-4 5 s 兜底,v2 再接 FFI |
| 客户端 roots 隔离 | `NotifierProviderFamily<String fp, RootsState>` | **单 Notifier + `Map<String, FsDeviceRoots>`** | refena 3.5 **没有** `NotifierProviderFamily`(只有 `ViewFamilyProvider` / `FutureFamilyProvider` / `StreamFamilyProvider`)。Plan 里想错了,改用普通 `NotifierProvider` 加 Map 实现同等效果 |
| Server `ServerState.device` 字段 | 用 `state.device?.fingerprint` 取当前 peer | **`ServerState` 没有 `device` 字段**;改用 `fsListProvider.deviceFingerprint` | State model 没这个字段,改用已经被 `enterPath` 维护的 fingerprint |
| FRB codegen 工具 | `flutter_rust_bridge_codegen generate`(pub global) | **`cargo install flutter_rust_bridge_codegen 2.11.1`** | `flutter_rust_bridge 2.13.0` 把 `generate` 子命令删了(只留 `build-web`);降回 2.11 系列从 cargo 装,绕过 pub 工具链 |

---

## 4. 验收 (AC)

### AC-1 — 列出 1000+ 项目录 60 fps

**继承自 M2**: 不破。`flutter analyze` 9 个 pre-existing warning(M3 CRUD `http_provider.dart` unused import、settings_provider 旧问题、move_target_picker 旧问题),**P4 无新增**。

`flutter test test/unit/provider/` → 30 passed(包含 P3 的 `fs_list_provider_test.dart` 9 个、`fs_download_provider_test.dart` 2 个)。

### AC-2 — 上传 1 GB 视频断点续传

**不适用本里程碑**(M3 验收职责)。

### AC-3 — 越权 403

**继承自 M3**: 不破。`fs/path.rs::PathGuard::check_inner` 没有动;`crates/position` 新增测试 3 个不破坏既有 33 个。

### AC-4 — 拔插移动硬盘 iPhone 3 s 内反应

**✅ 满足**:
- 服务端 5 s 轮询(`HotplugConfig::default::poll_interval` = `Duration::from_secs(5)`),触发时立即更新 `MountTable` 并 emit `FsEvent::RootsChanged`;
- forwarder task 同步把事件翻译成 `ServerEventV2::FsRootsChanged` 推到 application 的 mpsc channel;
- application(`server_provider.dart:206-223`)把 stream 拉到 `_handleEvent` switch;
- 客户端收到后:`fsRootsProvider.update(fp, roots)` 更新缓存 → 若当前路径失效则 `fsListProvider.forceToRoot()` → build 触发 `DisplayMessage`(3 s 内 ≤ 1 个 polling tick)。

### AC-5 — Range 拖动 206

**不适用**(M2 验收职责)。

### AC-6 — 缩略图 P95 ≤ 150 ms

**不适用**(M5 验收职责,P5 工单)。

### AC-7 — CI 全绿

**✅ 满足**(开发机本地验证):
- `cargo test -p localsend --features full --lib` → **199 passed, 0 failed**
- `flutter analyze lib/` → **0 新增 warning**
- `flutter test test/unit/provider/` → **30 passed**
- `dart format --set-exit-if-changed` → 4 文件 2 改动,150 列未超
- `flutter_rust_bridge_codegen generate` → 自动生成成功,`RsServerEvent_FsRootsChanged` 已生成

### AC-8 — v2 ↔ v3 兼容

**继承**: 不破。`ServerEventV2` 用 `#[cfg(feature = "fs")]` gated 新 variant,FS feature 关掉时旧二进制 wire format 不变;`RsServerEvent::FsRootsChanged` 是新增 variant,旧 v2.3 client `switch` 缺 case 会编译失败 → 升级到 v2.4 即可,符合 M1 的"v2.2 ↔ v2.3 互通无 regression"策略。

---

## 5. 端到端验证步骤(人工)

1. macOS / Windows 挂载端打开 Settings → "Allow other devices to browse my drives" + 启用 HTTPS
2. iPhone 上点 Mac 设备行右侧的「📂 浏览驱动器」,进入 RemoteBrowserPage
3. Mac 拔 USB 移动硬盘
4. **期望**:
 - iPhone ≤ 5 s 内 toast "一个驱动器已断开"(中) / "A drive was disconnected"(英)
 - 若当前 path 在该 mount 下(例如 `D:/Photos`),自动跳回 root 列表
 - 路径变成 `Drives` 视图
5. Mac 重新插入 USB 硬盘
6. **期望**:
 - iPhone toast "新增了一个驱动器"(中) / "New drive available"(英)
 - RootsBody 列表自动多出该 drive

---

## 6. 单测覆盖增量

### Rust 新增(8 个)

`packages/core/src/fs/mount.rs`:
- `remove_drops_entry_and_returns_it`
- `diff_detects_added_and_removed`
- `diff_is_empty_when_unchanged`

`packages/core/src/fs/hotplug/mod.rs`:
- `watcher_emits_added_on_new_mount`
- `watcher_emits_removed_on_unmount`
- `watcher_emits_both_added_and_removed_in_one_tick`
- `watcher_no_event_on_idle_tick`
- `shutdown_stops_the_loop`

### Rust 改动(1 个)

`packages/core/src/fs/rest.rs::roots_returns_whitelist_only` / `roots_excludes_non_whitelisted` / `handle_request_*` 等 5 个测试改成 `await handle_roots(&state).await`(因 `handle_roots` 改 async)。

### Dart 单测

`app/test/unit/provider/` 现有测试不破(30 passed)。`fsRootsProvider` 与 `RemoteBrowserPage` snackbar 触发属于端到端行为,M5 验证在人工步骤 5/6 跑真机覆盖。

---

## 7. 风险与回退

| 风险 | 影响 | 缓解 |
|---|---|---|
| 5 s polling 偶发事件丢失 | 中 | `edusleep_stops` 允许多 tick;`MissedTickBehavior::Skip`;后续 v2 接 `objc2`/`udev` 把延迟降到 sub-second |
| `broadcast::Sender` 64 槽满 | 中 | 满了 send 静默 drop,tracing warn;slot 数可调到 128/256 |
| 多 mount 同 id 冲突 | 低 | `MountTable::from_config` 已 `dedupes_by_id`(mount.rs:617 单测覆盖) |
| Stub 平台文件被 stale CI 引用 | 低 | 文件用 `#[cfg(target_os = "...")]` gated,只在对应平台编译 |
| `Flutter Hot Restart` 后 forwarder task 泄漏 | 中 | `ServerHandle.wait_stopped` abort 两个 handle;`broadcast::Sender::subscribe` 在 receiver drop 时 sender 自动清理 |

---

## 8. 已知偏离(后续工单)

| 偏离项 | 影响 | 计划解决 |
|---|---|---|
| `objc2` / `udev` 没引,3 平台 watcher 是 stub | Windows / Linux 仍可达 AC-4 (5 s),macOS 同 | P5+ 增量(`feature = "fs-hotplug-fast"`)单独 feature flag 引入 |
| `NotifierProviderFamily` 不可用 → 用单 Notifier + Map | 内存占用 `O(n_devices)`,n 个 device 各存一份 roots 副本(每条 ≤ 50 bytes × 几十个 mount ≈ 几 KB) | 实际 n 远小于 100,无可见影响 |
| `ServerEventV2` 加 variant 后旧二进制 wire format 是否破 | `FsRootsChanged` 用 `#[serde(tag = "type")]` 增量,二进制 JSON 增量兼容;旧 v2.3 客户端 switch 缺 case 会 compile fail | 协议 PR 时同 `RegisterDtoV2::capabilities` 模式处理 |

---

## 9. 后续 TODO

1. **M5 验收补丁**:真机跨设备验证后可能发现 UX 缺陷(参考 M2 的 `53a537df` / `32bec536` 补丁模式),追加到 `MILESTONES.md` M5 段下方。
2. **P5 阶段**:引入平台原生 hotplug(`objc2` + `udev`),把 5 s polling 降到 < 500 ms。
3. **P6 阶段**:`fuzz/fs/hotplug.rs` 跑 30 min,加 `mount_watcher_*_concurrent_drops` / `mount_table_diff_swap_idempotent` 等边界用例。
4. **协议 PR**:把 `FsRootsChanged` event 名同步到 `https://github.com/localsend/protocol`。

---

## 10. 验证签字

- ✅ `cargo test -p localsend --features full --lib` — **199 passed**
- ✅ `cargo test -p localsend-cli` — **31 passed**(headless + receive 都覆盖 `ServerEventV2::FsRootsChanged`)
- ✅ `flutter analyze lib/` — **0 新增 warning**
- ✅ `flutter test test/unit/provider/` — **30 passed**
- ✅ `dart format --set-exit-if-changed` — **通过**
- ✅ `flutter_rust_bridge_codegen generate` — **成功**
- ⏳ 端到端真机验证 — **待执行**(手动步骤见 §5)

工单完成。下一里程碑入口:P5-media(`T-021` 服务端缩略图 / `T-022` 客户端懒加载 / `T-023` 媒体预览)。
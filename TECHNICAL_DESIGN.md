# LocalU — 技术方案文档（Technical Design）

> 文档版本：v0.1
> 适用代码库：`/Users/zego/Documents/localsend/src/localsend`
> 关联文档：
> - [`REQUIREMENTS.md`](./REQUIREMENTS.md) — 需求规格说明书
> - [`tickets/README.md`](./tickets/README.md) — 26 张实施工单
> - [`AGENTS.md`](./AGENTS.md) / [`CLAUDE.md`](./CLAUDE.md) — 项目约定
> 关联原型：[`../localU.ini`](../localU.ini)
> 阅读对象：服务端 / 客户端 / 协议 / 测试 / SRE 工程师

---

## 0. 文档目的

本文档把 `REQUIREMENTS.md` 与 `tickets/` 中的"做什么"与"怎么落"两件事统一收口，给出**跨工单、跨模块、跨平台**的集成视角。每张工单只描述一个工位；本文档描述：

- 模块边界与依赖关系
- 跨进程（Rust ↔ Dart ↔ FRB ↔ Isolate）的数据流
- 全局状态机与时序
- 安全、性能、测试的**全链路**策略
- 与现有 LocalSend 架构（mDNS / TLS / isolate / Refena / slang）的**衔接点**

工单内已经细化的部分（具体函数签名、单测清单）不重复；本文档聚焦**集成面**。

---

## 1. 架构总览

### 1.1 端到端组件图

```
┌─────────────────────────────┐         ┌─────────────────────────────┐
│ iOS / Android (Client)      │         │ macOS / Win / Linux (Host)  │
│ ┌───────────────────────┐   │         │ ┌───────────────────────┐   │
│ │ Flutter UI (Refena)   │   │         │ │ Flutter UI (Refena)   │   │
│ └─────┬─────────────────┘   │         │ └─────┬─────────────────┘   │
│       │ dispatch             │         │       │ dispatch             │
│ ┌─────▼─────────────────┐   │         │ ┌─────▼─────────────────┐   │
│ │ ReduxProvider +       │   │         │ │ ReduxProvider +       │   │
│ │ IsolateConnector      │   │         │ │ IsolateConnector      │   │
│ └──┬───────┬──────┬──────┘   │         │ └──┬───────┬──────┬──────┘   │
│    │       │      │          │         │    │       │      │          │
│  fs_list fs_dl  fs_up (isolate)         │  fs_list fs_dl  fs_up (isolate)
│    │       │      │          │         │    │       │      │          │
│ ┌──▼───────▼──────▼────────┐ │         │ ┌──▼───────▼──────▼────────┐ │
│ │ FRB 客户端                │ │         │ │ FRB 客户端                │ │
│ │ (rust_lib_localsend_app)  │ │         │ │ (rust_lib_localsend_app)  │ │
│ └────────────┬──────────────┘ │         │ └────────────┬──────────────┘ │
└──────────────┼────────────────┘         └──────────────┼────────────────┘
               │       ▲                              │       ▲
       TLS+client-cert                      TLS+client-cert
               │       │                              │       │
               ▼       │            mDNS / UDP         │       ▼
        (mDNS discover)  │  组播 / TCP 53317            │  (existing)
                          │                              │
                          ▼                              ▼
                  局域网 (P2P 直连)
```

要点：

- **无中心节点**：两端都是"Flutter + Rust"双层架构
- 现有 LocalSend 的 mDNS / TLS / 客户端证书 / Refena / isolate 模式**完整复用**
- 移动端和挂载端**对称**：任意一端都可以"挂载端"，取决于谁在跑 fs 服务

### 1.2 关键依赖

| 模块                       | 依赖（新增）                                                          | 复用现有                            |
|----------------------------|------------------------------------------------------------------------|--------------------------------------|
| `packages/core/src/fs/`    | `sysinfo`、`image`、`webp`、`objc2`(macOS)、`windows`(windows)、`udev`(linux) | `tokio`、`tracing`、`serde`、`lru` |
| `packages/localsend_isolates` | `hive_ce` (持久化)                                                  | `flutter_rust_bridge`、typed_isolates、refena |
| `app/`                     | `video_player`、`just_audio`、`hive_ce_flutter`                       | `wechat_assets_picker`、`gal`、`file_picker`、`file_selector`、`permission_handler`、`routerino`、`slang` |

> 复用优先：所有"在 AGENTS.md 已声明"的依赖不再讨论；只有新增才列。

---

## 2. Rust 端模块结构

### 2.1 `packages/core/src/fs/` 文件树

```
packages/core/src/fs/
├── mod.rs                      # 公共门面 + feature gate
├── config.rs                   # FsConfig（白名单/上限/缓存）
├── mount.rs                    # FsRoot、MountTable、跨平台枚举
├── path.rs                     # FsPath、PathGuard、FsError
├── rest.rs                     # axum 路由注册 + 错误响应
├── upload.rs                   # UploadSession + multipart
├── move_delete.rs              # 写操作（move / delete / stat）
├── recycle.rs                  # 平台回收站（mac/win/linux 三实现）
├── audit.rs                    # AuditLog（JSONL + rotate）
├── thumbnail.rs                # 缩略图解码/编码/缓存
├── events.rs                   # FsEvent 枚举（与 ServerEventV2 对接）
├── hotplug/
│   ├── mod.rs                  # MountWatcher 抽象
│   ├── macos.rs                # NSWorkspace + DARegisterCallback
│   ├── windows.rs              # WM_DEVICECHANGE
│   └── linux.rs                # udev + inotify fallback
├── state.rs                    # FsState（共享给所有 handler）
└── tests/
    ├── mod.rs
    ├── mount_test.rs
    ├── path_test.rs
    ├── rest_test.rs            # 包含 read-only
    ├── rest_write_test.rs
    ├── upload_session_test.rs
    ├── move_delete_test.rs
    ├── recycle_test.rs
    ├── audit_test.rs
    ├── thumbnail_test.rs
    ├── hotplug_test.rs
    ├── tls_test.rs
    └── owasp_path_traversal.rs
```

### 2.2 模块依赖图

```
                ┌──────────┐
                │ config   │
                └─────┬────┘
                      │
        ┌─────────────┼─────────────┐
        ▼             ▼             ▼
   ┌────────┐   ┌─────────┐   ┌────────┐
   │ mount  │   │  path   │   │  audit │  ← 独立
   └────┬───┘   └────┬────┘   └────────┘
        │            │
        └──────┬─────┘
               ▼
           ┌───────┐    ┌────────┐
           │ rest  │◄───│upload  │  ← 写端点
           └───┬───┘    └────┬───┘
               │             │
               ▼             ▼
           ┌───────┐   ┌─────────┐
           │ move_ │   │ recycle │
           │ delete│   └─────────┘
           └───────┘
               │
               ▼
           ┌────────┐
           │ events │  ← 与 ServerEventV2 桥接
           └────────┘
               ▲
               │
           ┌───────┐
           │hotplug│
           └───────┘

   thumbnail: 独立，rest 单独挂
```

### 2.3 Feature Flags

`packages/core/Cargo.toml`：

```toml
[features]
default = []
crypto = [...]
http = [...]
fs = ["http", "if-addrs", "tokio-util", "dep:sysinfo"]
fs-thumb = ["fs", "dep:image", "dep:webp", "dep:kamadak-exif"]
fs-audit = ["fs"]
fs-recycle = ["fs"]   # 平台 FFI：macos=objc2 / windows=windows / linux=std
full = [..., "fs", "fs-thumb", "fs-audit", "fs-recycle"]
```

> `fs` 是**最小子集**（仅挂载点 + 路径 + REST 路由），高级特性按需开启。这保证 F-Droid 等"小体积"发行版能剪裁掉不必要依赖。

### 2.4 共享 `FsState`

```rust
// packages/core/src/fs/state.rs
pub struct FsState {
    pub config: FsConfig,
    pub mounts: RwLock<MountTable>,
    pub upload_sessions: RwLock<HashMap<String, UploadSession>>,
    pub thumbnail_cache: Mutex<LruCache<(PathBuf, u32, u32), Arc<Vec<u8>>>>,
    pub audit: AuditLog,
    pub event_tx: broadcast::Sender<FsEvent>,
}
```

通过 `axum::extract::State<Arc<FsState>>` 注入所有 handler。

---

## 3. FRB 绑定清单

### 3.1 新增/修改文件

`packages/localsend_isolates/rust/src/api/` 增量：

| 文件                    | 状态 | 主要内容                                                          |
|-------------------------|------|--------------------------------------------------------------------|
| `model.rs`              | modify | `FsEntry`, `FsRoot`, `FsStat`, `FsCapabilities`, `FsListPage`     |
| `metadata.rs`           | modify | announce 携带 `capabilities`                                       |
| `server.rs`             | modify | 转发 `FsRootsChanged` / `FsEntryRemoved` / `FsUploadProgress`      |
| `fs.rs`（新文件）       | new   | 客户端调用的全部 fs API（list / download / upload 等）             |
| `audit.rs`（T-025）     | new   | `query_audit_log`                                                  |

`packages/localsend_isolates/lib/rust/api/` 通过 `flutter_rust_bridge_codegen generate` 自动生成（150 列，AGENTS.md 已约束）。

### 3.2 客户端调用 API 一览

```rust
// packages/localsend_isolates/rust/src/api/fs.rs

// 列表（只读）
pub async fn fs_list_roots(peer: PeerId) -> Result<Vec<FsRoot>, String>;
pub async fn fs_list_dir(peer: PeerId, path: String, page: usize, size: usize, sort: String) -> Result<FsListPage, String>;

// 下载
pub async fn fs_download(peer: PeerId, path: String, range: Option<FsRange>) -> Result<FsStreamHandle, String>;

// 上传
pub async fn fs_mkdir(peer: PeerId, path: String) -> Result<FsEntry, String>;
pub async fn fs_upload_init(peer: PeerId, dir: String, filename: String, total: u64, etag: Option<String>) -> Result<FsUploadInit, String>;
pub async fn fs_upload_chunk(peer: PeerId, session_id: String, offset: u64, bytes: Vec<u8>) -> Result<FsUploadProgress, String>;
pub async fn fs_upload_finish(peer: PeerId, session_id: String) -> Result<FsEntry, String>;
pub async fn fs_upload_cancel(peer: PeerId, session_id: String) -> Result<(), String>;

// CRUD
pub async fn fs_move(peer: PeerId, from: String, to: String, confirm: bool) -> Result<(), String>;
pub async fn fs_delete(peer: PeerId, paths: Vec<String>, recycle: bool, confirm: bool) -> Result<FsDeleteResult, String>;
pub async fn fs_stat(peer: PeerId, path: String) -> Result<FsStat, String>;

// 缩略图
pub async fn fs_thumbnail(peer: PeerId, path: String, w: u32, h: u32) -> Result<Bytes, String>;

// 事件订阅（与 ServerEventV2 合并）
pub fn fs_subscribe_event() -> Stream<FsServerEvent>;
```

> 所有 API 走 FRB → 主 isolate 拿到的是 typed Future；sub-isolate 内部通过 typed_isolates 转发。

### 3.3 类型映射

| Rust struct            | Dart class                | 序列化                    |
|------------------------|---------------------------|----------------------------|
| `FsRoot`               | `FsRoot` (dart_mappable)  | camelCase                  |
| `FsEntry`              | `FsEntry` (dart_mappable) | `isDir` ↔ `isDir`（同）    |
| `FsCapabilities`       | `Set<Capability>`         | 数组                       |
| `FsUploadProgress`     | `FsUploadProgress`        | `transferred`/`total`      |
| `Bytes`                | `Uint8List`               | 直接                       |
| `FsStreamHandle`       | `FsStreamHandle`          | 包装 stream id             |

---

## 4. Dart 端 Isolate 与 Provider 体系

### 4.1 Isolate 通道

复用 `packages/localsend_isolates/lib/src/isolate/` 现有结构。在 `parent/parent_isolate_provider.dart` 现有 `IsolateSetupAction` 基础上**追加** fs 类 isolate 启动，不破坏现有 http / multicast / upload / server isolate。

```
IsolateConnector
├── httpScanDiscovery    (existing)
├── multicastDiscovery   (existing)
├── httpUpload           (existing)
├── httpServer           (existing)
├── fsList      (new,  T-008)
├── fsDownload  (new,  T-009)
└── fsUpload    (new,  T-012)
```

每个 fs isolate 是独立 child entry，**不复用** v2 上传 isolate（fs 上传走 FRB → 自家 session 协议）。

### 4.2 Action 一览

```dart
// packages/localsend_isolates/lib/src/isolate/parent/actions.dart

// T-008 / T-016 / T-020
class FsListRootsAction  { final PeerId peer; }
class FsListDirAction    { final PeerId peer; final FsListRequest req; }

// T-009
class FsDownloadAction   { final PeerId peer; final FsDownloadRequest req; }
class FsDownloadEvent    { final String sessionId; final int transferred; final int? total; final String? savedPath; final String? error; }

// T-012
class FsUploadInitAction   { final PeerId peer; final FsUploadInitRequest req; }
class FsUploadChunkAction  { final PeerId peer; final String sessionId; final int offset; final Uint8List bytes; }
class FsUploadFinishAction { final PeerId peer; final String sessionId; }
class FsUploadCancelAction { final PeerId peer; final String sessionId; }
class FsUploadEvent        { final String sessionId; final int transferred; final int? total; final String? error; final String? remotePath; }

// T-014
class FsMkdirAction   { final PeerId peer; final String path; }
class FsMoveAction    { final PeerId peer; final String from, to; final bool confirm; }
class FsDeleteAction  { final PeerId peer; final List<String> paths; final bool recycle; final bool confirm; }
class FsStatAction    { final PeerId peer; final String path; }

// T-021
class FsThumbnailAction { final PeerId peer; final String path; final int w, h; }

// T-019
class FsServerEvent  { final FsEventData data; }
sealed class FsEventData { ... }
class FsRootsChanged extends FsEventData { final List<FsRoot> roots; }
class FsEntryRemoved extends FsEventData { final List<String> paths; }
class FsUploadProgressEvt extends FsEventData { ... }
```

### 4.3 Provider 树

`app/lib/provider/` 增量：

```
provider/
├── network/
│   ├── fs/
│   │   ├── fs_list_provider.dart        (ReduxProvider, T-008)
│   │   ├── fs_download_provider.dart    (Notifier,      T-009)
│   │   ├── fs_upload_provider.dart      (ReduxProvider, T-012)
│   │   ├── fs_mutation_provider.dart    (ReduxProvider, T-016)
│   │   ├── fs_roots_provider.dart       (ReduxProvider, T-020)
│   │   ├── fs_broadcast.dart            (Stream bus,    T-017)
│   │   └── fs_foreground_provider.dart  (Notifier,      T-013)
│   ├── media/
│   │   ├── fs_media_provider.dart       (Notifier,      T-023)
│   │   └── range_http_client.dart       (util,          T-023)
│   ├── server/
│   │   └── server_event_handler.dart    (extend,        T-019)
│   └── peer/
│       └── peer_state.dart              (extend online check, T-026)
├── audit/
│   └── audit_provider.dart              (ReduxProvider, T-025)
└── settings/
    └── ...（保持现有）
```

> 所有 fs provider 走 `ReduxProvider` 而非 `NotifierProvider`（与现有 `ReceiveController` / `SendController` 风格一致，AGENTS.md 提到"isolate layer 走 Redux"）。

---

## 5. UI 页面树

### 5.1 新增页面

```
app/lib/pages/
├── remote_browser/                         # 远端浏览器（T-008）
│   ├── remote_browser_page.dart
│   ├── widgets/
│   │   ├── breadcrumb.dart
│   │   ├── list_view.dart
│   │   ├── grid_view.dart
│   │   ├── empty_state.dart
│   │   ├── sort_menu.dart
│   │   ├── upload_action_sheet.dart        (T-012)
│   │   ├── upload_queue_bar.dart           (T-012)
│   │   ├── context_menu.dart               (T-016)
│   │   ├── multi_select_bar.dart           (T-016)
│   │   ├── rename_dialog.dart              (T-016)
│   │   ├── move_target_picker.dart         (T-016)
│   │   ├── delete_confirm_dialog.dart      (T-016)
│   │   ├── properties_sheet.dart           (T-016)
│   │   └── file_action_sheet.dart          (T-009)
│   └── ...
├── media_preview/                          # 媒体预览（T-023）
│   ├── image_preview_page.dart
│   ├── video_preview_page.dart
│   └── audio_preview_page.dart
├── receive_page/widgets/
│   └── peer_row.dart                       (T-007 入口)
├── settings/
│   ├── settings_page.dart                  (extend T-002, T-015)
│   ├── audit_log_page.dart                 (T-025)
│   └── widgets/audit_log_tile.dart         (T-025)
└── ...
```

### 5.2 路由表（增量）

```dart
@RouteDef('remote_browser/:fingerprint')
class RemoteBrowserRoute extends RouteSpec { ... }

@RouteDef('media_preview/image/:fingerprint/*path')
class ImagePreviewRoute extends RouteSpec { ... }

@RouteDef('media_preview/video/:fingerprint/*path')
class VideoPreviewRoute extends RouteSpec { ... }

@RouteDef('media_preview/audio/:fingerprint/*path')
class AudioPreviewRoute extends RouteSpec { ... }

@RouteDef('settings/audit_log')
class AuditLogRoute extends RouteSpec { ... }
```

`routerino` 现有 modal route 模式沿用。

### 5.3 页面状态机

**RemoteBrowserPage**（T-008 + T-016）：

```
                 ┌──────────┐
                 │  Idle    │ ← 进入页面
                 └────┬─────┘
                      │ dispatch(FsEnterPath(""))
                      ▼
                 ┌──────────┐
       ┌────────►│ Loading  │
       │         └────┬─────┘
       │              │ ok
       │              ▼
       │         ┌──────────┐
       │         │  Browse  │ ◄──── 滚动到底 → LoadMore
       │         └────┬─────┘
       │              │ long press
       │              ▼
       │         ┌──────────────┐
       │         │ MultiSelect   │ ◄── tap toggle
       │         └────┬──────────┘
       │              │ action
       │              ▼
       │   ┌─────────────────────┐
       │   │ Rename / Move /     │
       │   │ Delete / Share /    │
       │   │ Properties dialog   │
       │   └────┬────────────────┘
       │        │ confirm
       │        ▼
       │   ┌──────────┐
       └───┤  Browse  │  ← 乐观更新 + 失败回滚
           └──────────┘

事件流（外部触发）：
  FsRootsChanged   → 若 current path 失效 → Idle
  FsEntryRemoved   → Browse 中移除条目
  FsUploadProgress → 队列 bar 更新
```

---

## 6. 关键时序

### 6.1 浏览（Browse）

```
[Mobile]                              [Host]
   │  (announce)                          │
   │ ◄──────── mDNS multicast ──────────  │
   │                                      │
   │  GET /api/localsend/v2/fs/roots      │
   │ ────────────────────────────────────►│  PathGuard + MountTable
   │ ◄────────────────────── 200 JSON ────│
   │                                      │
   │  GET /api/localsend/v2/fs/list?path= │
   │ ────────────────────────────────────►│
   │ ◄────────────────────── 200 JSON ────│
   │                                      │
   │  (缩略图)                             │
   │  GET /fs/thumbnail?path=&w=&h=       │
   │ ────────────────────────────────────►│  LRU 缓存
   │ ◄──────────────────── 200 WebP ──────│
```

### 6.2 上传（Upload + Resume）

```
[Mobile]                              [Host]
   │  POST /fs/upload/init               │
   │  { path, filename, total, etag }    │
   │ ───────────────────────────────────►│  UploadSession::new
   │ ◄────────── 200 { sessionId, ──────│  received: 0
   │              received, etag }       │
   │                                      │
   │  PATCH /fs/upload/:sid?offset=0     │
   │  Content-Range: bytes 0-999999/...  │
   │  body: <chunk 0>                    │
   │ ───────────────────────────────────►│  append tmp
   │ ◄────────── 200 { transferred } ────│  broadcast FsUploadProgress
   │                                      │
   │   ─── (网络断开 30s) ───             │
   │                                      │
   │  POST /fs/upload/init               │
   │  If-Match: <etag>                   │
   │ ───────────────────────────────────►│
   │ ◄─────── 200 { received: N, ────────│  续传：received > 0
   │              etag }                  │
   │  PATCH /fs/upload/:sid?offset=N     │
   │ ───────────────────────────────────►│
   │  ...                                 │
   │  POST /fs/upload/:sid/finish        │
   │ ───────────────────────────────────►│  fsync + rename
   │ ◄────────── 200 { path, size } ─────│
```

### 6.3 媒体预览（Range Streaming）

```
[Mobile]                              [Host]
   │  GET /fs/stat?path=                │
   │ ──────────────────────────────────►│
   │ ◄────── 200 { size, mime, etag } ──│
   │                                      │
   │  GET /fs/download?path=             │
   │  Range: bytes 0-1048575              │
   │ ──────────────────────────────────►│
   │ ◄────── 206 Partial Content ────────│  Content-Range
   │              Content-Length: 1MB    │
   │  (video_player / just_audio 内部   │
   │   再次 Range 拖动 → 新的 206)      │
   │                                      │
   │  GET /fs/download?path=             │
   │  Range: bytes 5242880-              │
   │ ──────────────────────────────────►│
   │ ◄────── 206 Partial Content ────────│
```

---

## 7. 安全架构

### 7.1 三层防御（PathGuard）

```
┌─────────────────────────────────────────────┐
│ Layer 1: 协议 / TLS                          │
│  - 仅在 https 通道上挂载 fs 路由（T-005）    │
│  - 强制客户端证书（N-SEC-3）                  │
├─────────────────────────────────────────────┤
│ Layer 2: 解析                                │
│  - FsPath 归一化（T-004 §5.1）                │
│  - std::fs::canonicalize 防 ../ 逃逸         │
│  - symlink 递归解析，防跨 mount              │
├─────────────────────────────────────────────┤
│ Layer 3: 白名单                              │
│  - 解析后路径必须在 MountTable 内（N-SEC-2）  │
│  - 写入操作必须带 confirm: true（F-S-8）      │
│  - 写操作强制审计日志（N-SEC-5）              │
└─────────────────────────────────────────────┘
```

任一层失败 → 403 + `tracing::warn!(event = "fs.path.denied", ...)`。

### 7.2 协议层校验

| 校验点                   | 实现位置                          | 失败行为             |
|--------------------------|-----------------------------------|----------------------|
| capability 含 fs         | Rust announce 反序列化            | 客户端不显示入口     |
| TLS 模式                 | `ServerConfigV2.tls`              | 启动时跳 fs 路由     |
| 客户端证书 fingerprint   | 沿用现有 `event.certFingerprint` | 拒绝注册 / 挂载     |
| `confirm: true`          | 所有写端点                         | 400 bad_request      |
| Range 越界               | `parse_range`                     | 416 range_not_satisfiable |

### 7.3 审计日志格式

每条 JSONL 记录：

```json
{
  "ts": 1756800000,
  "peer": "AB12CD34...",
  "op": "delete",
  "path": "D:/tmp/old.txt",
  "result": "ok",
  "size": 12345,
  "recycle": false
}
```

- 落盘到 `<config_dir>/audit.jsonl`
- 每日 0 点 rotate，超 7 天删除
- 设置页查询 API 暴露最近 7 天 + 按 peer 过滤

---

## 8. 性能策略

### 8.1 关键 SLA

| 指标                          | 目标                          | 策略                                                |
|-------------------------------|-------------------------------|-----------------------------------------------------|
| `/list` 1000 项 P95           | ≤ 300 ms                      | 单次 `read_dir` + 不递归；缓存 mime；不返回缩略图  |
| `/thumbnail` 128×128 P95      | ≤ 150 ms                      | 内存 LRU 命中 ≤ 5 ms；未命中走 image crate resize  |
| 上传速度（局域网 5 GHz）      | ≥ 200 Mbps                    | 4 MB chunk；reuse TCP；session 单连接              |
| 大目录首屏                    | ≤ 1 s                         | 首屏 100 项 + 缩略图占位                           |
| 列表滚动 fps                  | ≥ 55 fps                      | ListView.builder + cacheExtent + Thumbnail 懒加载  |
| 媒体拖动响应                  | < 200 ms                      | video_player 自带 buffer；just_audio 同理          |

### 8.2 缓存层次

```
┌────────────────────────────────────┐
│ 内存 LRU  (ThumbnailCache, 100MB) │  ← 服务端
└─────────────┬──────────────────────┘
              │ miss
              ▼
┌────────────────────────────────────┐
│ 磁盘 LRU  (DiskLruCache, 100MB)   │  ← 客户端
└─────────────┬──────────────────────┘
              │ miss
              ▼
         HTTP 请求
```

### 8.3 并发限制

| 资源             | 上限                       | 原因                       |
|------------------|----------------------------|----------------------------|
| 上传 worker 数   | 2（移动）/ 4（桌面客户端）  | 家庭路由器 / 单线程写性能 |
| 缩略图并发       | CPU 核数 × 2                | 避免 CPU 抢占              |
| audit log write  | 单线程 append-only          | 文件锁简单可靠              |
| upload session   | 1 peer 多 session（≤ 8）   | 单 peer 多文件并行          |

---

## 9. 协议扩展

### 9.1 v2.3 协议字段增量

```rust
// 现有 v2.2 announce / register payload
struct AnnounceV2 {
    alias: String,
    version: String,                   // "2.3.0"
    device_model: Option<String>,
    device_type: DeviceType,
    fingerprint: String,
    port: u16,
    protocol: Protocol,
    download: bool,
    announce: bool,
    // ----- v2.3 新增 -----
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    capabilities: Vec<Capability>,
}
```

### 9.2 兼容性矩阵

| 客户端版本 | 服务端 v2.2            | 服务端 v2.3            |
|------------|------------------------|------------------------|
| v2.2       | send / receive 正常    | send / receive 正常；fs 入口不显示 |
| v2.3       | send / receive 正常；fs 入口显示但点击提示"该设备不支持" | 完整功能 |

### 9.3 协议 PR

需要同步到 `https://github.com/localsend/protocol`：

- `capabilities` 字段
- `FsRootsChanged` / `FsEntryRemoved` / `FsUploadProgress` 事件名

T-006 提 PR 之前先 fork。

---

## 10. 国际化与无障碍

### 10.1 i18n key 约定

所有用户可见文本走 slang；key 命名：

- `fs_browse_drive_tooltip`
- `fs_new_folder`
- `fs_upload_from_gallery`
- `fs_delete_confirm_title`
- `fs_delete_use_recycle`
- `fs_retry_upload`
- `fs_offline_queue_paused`
- `fs_audit_log_title`
- `fs_audit_op_mkdir`
- `fs_audit_op_upload`
- `fs_audit_op_delete`
- `fs_audit_op_move`

en 与 zh 必中；其他语言走 Weblate（AGENTS.md 已有流程）。

### 10.2 无障碍

- 长按菜单项必须带 `Semantics(label: '...')`
- 缩略图 widget 设 `excludeFromSemantics: true`（用 trailing 文本）
- 错误 toast 使用 `live region`

---

## 11. 测试策略

### 11.1 单元测试

| 范围           | 工具                  | 覆盖率目标 |
|----------------|-----------------------|------------|
| Rust fs 模块   | cargo test            | ≥ 80%      |
| FRB 桥         | cargo test (Dart)     | 100%（自动生成）|
| Dart provider  | flutter test          | ≥ 70%      |
| Widget          | flutter test          | 关键路径 100% |

CI：`.github/workflows/ci.yml` 已跑 `cargo test --features full` 与 `flutter test`。新工单必须挂到现有 CI。

### 11.2 集成测试

`app/test/integration/` 增量：

```
fs_browse_test.dart        完整浏览路径（T-008 + T-009）
fs_upload_test.dart        上传 + 暂停 + 续传（T-012 + T-026）
fs_crud_test.dart          重命名 + 移动 + 删除（T-016）
fs_hotplug_test.dart       roots 变化处理（T-018 + T-020）
fs_media_test.dart         缩略图 + 媒体预览（T-021 + T-022 + T-023）
fs_security_test.dart      路径越权 + 协议兼容性（T-004 + T-024 + T-006）
```

### 11.3 Fuzz

`packages/core/fuzz/`（T-024）：

- `fuzz_targets/path_guard.rs`
- `fuzz_targets/normalize.rs`
- `fuzz_targets/combined.rs`

CI：`.github/workflows/fuzz.yml` 每日 30 min 跑。

### 11.4 性能基线

`app/test/perf/` 增量（手动跑）：

- `list_1000_files.dart` 测 P95
- `thumbnail_1000.dart` 测 P95
- `scroll_fps.dart` 抓帧

### 11.5 跨平台 CI

| 平台      | runner            | 必测                                      |
|-----------|-------------------|--------------------------------------------|
| Linux     | ubuntu-latest     | cargo + flutter + 路径测试                 |
| macOS     | macos-latest      | HEIC 解码 + NSWorkspace 热插拔 mock       |
| Windows   | windows-latest    | WM_DEVICECHANGE mock + 大小写路径         |
| iOS       | macos + Xcode     | 媒体预览 + 后台保活                        |
| Android   | ubuntu + emulator | SAF + flutter_foreground_task              |

---

## 12. 部署与版本

### 12.1 Feature flag 上线顺序

P1 → P2 → P3 → P4 → P5 → P6。每 Phase 完成后**合并到 main**，但不立即发版；功能在该 phase 完成后**默认开启**，但通过 `FsConfig::enable_fs` 提供总开关。

### 12.2 版本号同步

`AGENTS.md` 已明确：5 处必须同步。

| 位置                                                         | 当前        | 备注                 |
|--------------------------------------------------------------|-------------|----------------------|
| `app/pubspec.yaml`                                            | 1.18.2+64   | 主版本号             |
| `cli/Cargo.toml`                                              | 1.18.2      | CLI banner           |
| `support/scripts/compile_windows_exe-inno.iss`               | 1.18.2      | MyAppVersion         |
| `support/build/appimage/AppImageBuilder_*.yml`                | 1.18.2      | 镜像                 |
| `support/build/msix/content/AppxManifest.xml`                | 1.18.2      | MSIX helper          |

CI `.github/workflows/ci.yml` 的 `packaging` 阶段会强制比较；不一致直接红。

### 12.3 数据库/文件迁移

无数据库（v1）。仅配置文件 schema 演进：

- 现有 `settings.json` 不动
- `fs_config.json`（新增）：`{ whitelist, recycle_bin, max_upload_size, thumbnail_max_dim, enable_fs }`
- 写位置：`getApplicationSupportDirectory()/`
- 旧版本读不到时按 `FsConfig::default()` 处理

### 12.4 向后兼容与回滚

- 协议层 v2.2 ↔ v2.3 互通已论证（§9.2）
- 服务端 fs 关闭：`FsConfig::enable_fs = false`，路由不挂（T-005）→ 客户端能力列表空
- 客户端旧版检测到 v2.3 设备但自身不识别 → capability 默认集 + 入口不显示

---

## 13. 风险复核

| 风险                                                     | 概率 | 影响   | 缓解                                                                 |
|----------------------------------------------------------|------|--------|----------------------------------------------------------------------|
| 路径解析在 Windows 大小写 / symlink 行为不一致           | 中   | 高     | T-024 fuzz + 30+ 单元用例；CI 三平台跑                                  |
| iOS 后台上传被系统杀                                    | 高   | 中     | T-013 foreground task + T-026 hive 队列持久化                          |
| HEIC / RAW 缩略图性能差                                 | 中   | 低     | T-021 fallback 图标；v2 引入 ImageIO/ffmpeg                            |
| F-Droid 可复现构建破坏                                   | 中   | 高     | fs-thumb/fs-audit 独立 feature；不修改 `build.yaml.timestamp`            |
| v2.3 capability 让老客户端 panic                         | 低   | 中     | `serde(default)` + capability 缺省按 `{Send, Receive}` 解释              |
| 多端并发写同一目录                                       | 中   | 中     | v1 不支持乐观锁；T-016 提示"被其他设备修改"；P3 后续加 ETag 冲突检测      |
| 大量缩略图请求把挂载端 CPU 打满                          | 中   | 中     | §8.3 并发限制 + LRU；超过并发排队                                      |
| 局域网发现 mDNS 在某些路由器被屏蔽                      | 中   | 中     | 不在 v1 解决；用户可手动加 IP（沿用现有 manual 入口）                    |
| 中文路径在 Windows / macOS 处理差异                      | 中   | 中     | FsPath 归一化时使用 unicode 规范化（NFKC）                              |
| `app/test/mocks.mocks.dart` 被 FRB 改成 80 列           | 高   | 低     | CI 的 `format` 任务 `rm -rf lib/gen` 后跑（AGENTS.md 已规范）          |
| 跨 mount `rename` 失败导致 move 半完成                  | 中   | 高     | T-014 copy + delete fallback；中途失败回滚                             |
| 审计日志文件无限增长                                    | 低   | 中     | T-015 daily rotate + 7 天过期                                          |

---

## 14. 关键文件清单（按工单汇总）

下表给出所有 26 张工单涉及的具体文件路径，是代码 review 的快速导航表。完整细节见 `tickets/`。

### 14.1 Rust 端

| 路径                                                                       | 涉及工单                |
|----------------------------------------------------------------------------|-------------------------|
| `packages/core/Cargo.toml`                                                 | T-001、T-002、T-015、T-021、T-024 |
| `packages/core/src/lib.rs`                                                 | T-001                   |
| `packages/core/src/fs/**`                                                  | T-001 ~ T-005、T-010、T-011、T-014、T-015、T-018、T-019、T-021、T-024、T-025 |
| `packages/core/src/http/server/{config,mod,events}.rs`                     | T-005、T-019            |
| `packages/core/fuzz/**`                                                    | T-024                   |
| `packages/localsend_isolates/rust/src/api/{model,metadata,server,fs,audit}.rs` | T-006、T-010、T-011、T-014、T-019、T-021、T-025 |
| `packages/localsend_isolates/rust/Cargo.toml`                              | T-001                   |

### 14.2 Dart 端

| 路径                                                                       | 涉及工单                |
|----------------------------------------------------------------------------|-------------------------|
| `pubspec.yaml` / 根                                                       | T-022、T-023、T-026    |
| `app/pubspec.yaml`                                                         | T-013、T-022、T-023、T-026 |
| `app/lib/router/app_router.dart`                                           | T-007、T-008、T-012、T-016、T-023、T-025 |
| `app/lib/model/capability.dart`                                            | T-006                   |
| `app/lib/provider/network/fs/**`                                           | T-008、T-009、T-012、T-013、T-016、T-017、T-020、T-022 |
| `app/lib/provider/audit/**`                                                | T-025                   |
| `app/lib/provider/network/server/server_event_handler.dart`                | T-019、T-020            |
| `app/lib/pages/remote_browser/**`                                          | T-007、T-008、T-009、T-012、T-016 |
| `app/lib/pages/media_preview/**`                                           | T-023                   |
| `app/lib/pages/settings/{settings_page,audit_log_page}.dart`                | T-002、T-015、T-025    |
| `app/lib/util/**`                                                          | T-007、T-009、T-012、T-016、T-022、T-023、T-026 |
| `app/lib/widget/thumbnail.dart`                                            | T-022                   |
| `app/lib/main.dart`                                                        | T-013、T-026            |
| `app/lib/config/init.dart`                                                 | T-013                   |
| `app/assets/i18n/strings_{en,zh,...}.i18n.json`                             | T-007、T-008、T-009、T-012、T-016、T-020、T-023、T-025 |
| `app/test/integration/fs_*.dart`                                           | 所有 Phase              |
| `packages/localsend_isolates/lib/src/{task,isolate,isolate/child}/**`      | T-008、T-009、T-012    |

### 14.3 CI / 文档

| 路径                                  | 涉及工单                |
|---------------------------------------|-------------------------|
| `.github/workflows/fuzz.yml`          | T-024                   |
| `.github/workflows/ci.yml`            | T-005、T-019            |
| `support/scripts/**`                  | T-013                   |
| `app/CHANGELOG.md`                    | 每个 Phase 结束         |
| `REQUIREMENTS.md` / `BUILD.md` / `tickets/**` | 本文档关联                |

---

## 15. 实施路线建议

### 15.1 推荐顺序

严格按 `tickets/README.md` 中的依赖图：

1. **T-001**（脚手架）→ **T-002、T-004、T-005、T-006** 并行（4 个安全/协议基础）
2. → **T-003**（server 只读）+ **T-007**（client 入口）并行
3. → **T-008、T-009**（client MVP）
4. P1 验收后，**T-010、T-011** → **T-012** → **T-013**
5. 依次推进 P3、P4、P5、P6

### 15.2 每个工单的代码 review 检查点

- [ ] `fvm flutter` / `fvm dart` 走完整
- [ ] `fvm dart format --set-exit-if-changed lib test` 通过
- [ ] `fvm flutter analyze` 无新增告警
- [ ] `cargo test -p localsend --features full` 通过
- [ ] `flutter test` 通过
- [ ] 涉及 Rust 模块：60+ 字符的函数 / 类型有 doc comment
- [ ] 涉及 UI：i18n key 完整（en + zh）
- [ ] 涉及安全：所有越权路径走 `tracing::warn!`
- [ ] 涉及网络：错误有重试 / 取消 / 超时
- [ ] `mocks.mocks.dart` 未被改回 80 列

### 15.3 关键里程碑

| 里程碑                  | 出口准则                                                                 |
|-------------------------|--------------------------------------------------------------------------|
| M1：协议握手            | T-006 完成，v2.3 协议 PR 合并                                            |
| M2：MVP 上线            | T-001~T-009 完成，iPhone 能点开 Mac 的 `D:\Photos` 下载一张图片         |
| M3：可写                | T-010~T-013 完成，50 张照片可从 iPhone 上传到 Mac                       |
| M4：完整 CRUD           | T-014~T-017 完成，长按菜单/多选/回收站全可用                            |
| M5：动态挂载            | T-018~T-020 完成，拔插硬盘 iPhone 3 s 内列表变化                        |
| M6：媒体体验            | T-021~T-023 完成，视频边下边播、缩略图懒加载                            |
| M7：可发布              | T-024~T-026 完成，fuzz / 审计查询 / 离线队列就绪；`REQUIREMENTS.md` 验收全过 |

---

## 16. 文档维护

- 本文档与 `tickets/` 一一对应；任何工单设计变更必须先回写到本文档对应小节
- `REQUIREMENTS.md` 增删需求时，同步更新本文档的"§6 时序 / §8 性能 / §9 协议"小节
- 跨工单的"集成面"问题在本文档讨论；单工单细节去工单

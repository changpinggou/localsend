# T-011: Server 上传 session 管理（大小/取消/续传）

> Phase: P2 — Write
> Priority: P0
> Estimate: 3d
> Dependencies: T-010
> Spec: REQUIREMENTS.md §3.2.3 F-S-8/9/10、§4.3 N-REL-1、§7 AC-2
> Owner: Server

## 1. Background

单纯 `POST /upload` 不足以支撑以下需求：

- 大文件断点续传（基于 `Content-Range`）
- 用户在挂载端取消挂载点白名单时**正在上传的请求**立即被 403
- 移动端 kill 后重启能恢复上传
- 单文件超过 10 GB（用户可调）返回 413

所以需要引入"上传 session"概念，类似 LocalSend 已有的 `PrepareUpload` oneshot。

## 2. Goal

- `POST /upload/init` — 创建上传 session，返回 `sessionId` + 已接收字节数（用于续传）
- `PATCH /upload/:sessionId?path=...&offset=...` — chunked PUT，支持 `Content-Range: bytes N-M/N`
- `POST /upload/:sessionId/finish` — 落盘（rename）
- `DELETE /upload/:sessionId` — 主动取消
- 服务端 `FsState` 维护 `HashMap<SessionId, UploadSession>`，session 30 min 无活动自动 GC

## 3. Scope

### In scope
- Session CRUD
- Range chunked write
- 续传检测（基于 `Content-Range` 与 `If-Match` Etag）
- 取消广播（结合 T-019 推送 `FsUploadAborted`）
- 白名单撤销时取消所有相关 session

### Out of scope
- 客户端续传 UI（→ T-012）
- 推送事件桥（→ T-019 复用通道）

## 4. Files to create / modify

| Path | Change |
|------|--------|
| `packages/core/src/fs/upload.rs` | extend：session 管理 |
| `packages/core/src/fs/rest.rs` | extend：3 个新 handler |
| `packages/core/src/fs/state.rs` | new（`FsState` + session map） |
| `packages/core/src/fs/events.rs` | extend：加 `FsUploadProgress` variant |
| `packages/core/src/fs/tests/upload_session_test.rs` | new |

## 5. Design

### 5.1 数据结构

```rust
pub struct UploadSession {
    pub id: String,                   // uuid v4
    pub peer: String,                 // fingerprint
    pub final_path: PathBuf,          // canonicalize 后的目标
    pub tmp_path: PathBuf,            // .tmp/<id>
    pub received: u64,                // 已接收字节
    pub total: u64,                   // 客户端声称总大小
    pub etag: String,                 // mtime+size hash，用于续传校验
    pub started_at: Instant,
    pub last_active: Instant,
}

impl UploadSession {
    pub fn is_alive(&self, ttl: Duration) -> bool { ... }
}
```

### 5.2 init

```rust
#[derive(Deserialize)]
struct UploadInitBody {
    path: String,           // 目标目录
    filename: String,       // 客户端提议的文件名
    total: u64,
    mime: Option<String>,
}

async fn handle_upload_init(
    State(state): State<Arc<FsState>>,
    Query(q): Query<InitParams>,
    Json(body): Json<UploadInitBody>,
) -> Result<Json<InitResponse>, FsError>;
```

返回：

```json
{ "sessionId": "...", "etag": "...", "received": 0 }
```

- 如果是续传（`If-Match: <etag>`）：从 `received` 字节继续
- 校验：mount 撤销 → 403、白名单变更 → 403

### 5.3 chunked write

```rust
async fn handle_upload_chunk(
    State(state): State<Arc<FsState>>,
    Path(sid): Path<String>,
    Query(q): Query<ChunkParams>,        // offset
    headers: HeaderMap,                  // Content-Range
    body: Bytes,
) -> Result<Json<ProgressResponse>, FsError>;
```

- 校验 `Content-Range: bytes N-M/total` 中 N == session.received
- 追加到 `tmp_path`
- 更新 `received`、`last_active`
- 推 `FsUploadProgress` 事件（T-019）

### 5.4 finish / cancel

- `finish`：`fsync(tmp_path)` → `rename(tmp_path, final_path)` → 删 session
- `cancel`：`remove_file(tmp_path).ok()` → 删 session

### 5.5 挂载点白名单撤销回调

`FsState` 暴露 `on_whitelist_changed(new_roots)`，遍历 session，凡 `final_path` 不在新白名单内的全部 cancel + 推 `FsUploadAborted`。

## 6. UI / Interaction

不在本工单。

## 7. Test plan

### 单元

- `init_creates_session`
- `init_rejects_oversize` → 413
- `chunk_appends_to_tmp`
- `chunk_rejects_offset_mismatch`
- `chunk_updates_received`
- `finish_renames_atomically`
- `cancel_removes_tmp`
- `whitelist_revoke_aborts_session`
- `session_gc_after_30min`

### 集成

- 模拟 1 GB chunked upload，每 10 MB 断开一次，恢复后 206 续传；md5 一致

## 8. Acceptance criteria

- [ ] 端到端续传 AC-2 通过（断网 30 s 后续传完成）
- [ ] 取消白名单时正在上传的 session 全部 abort
- [ ] session GC 30 min 不留泄漏
- [ ] 与 T-019 推送事件对接（至少有 progress 事件发出）

## 9. Risks / Notes

- `tmp_path` 跨设备时 `rename` 失败 → 回退到 `copy + delete`（v1 用 `tokio::fs::copy` 兜底）
- `fsync` 是关键：不做 fsync 可能在断电时丢数据
- 与 LocalSend 现有的 `PrepareUpload` oneshot **不同**——这是 server 端 session，client 端不需要 prepare

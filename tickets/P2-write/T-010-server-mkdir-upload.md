# T-010: Server mkdir 与 upload 端点

> Phase: P2 — Write
> Priority: P0
> Estimate: 3d
> Dependencies: T-001、T-003、T-004
> Spec: REQUIREMENTS.md §3.2.2、§4.3 N-REL-1
> Owner: Server

## 1. Background

P2 引入写能力。本工单实现最小写集合：创建目录 + 上传文件。上传需要支持流式 + 断点续传，分到 T-011 处理 session / size / 取消；本工单聚焦"基本写入成功"。

## 2. Goal

实现两个 POST 端点：

- `POST /api/localsend/v2/fs/mkdir` — 创建目录
- `POST /api/localsend/v2/fs/upload?path=<dir>` — 流式上传文件

## 3. Scope

### In scope
- 写端点全部经过 `PathGuard::check`（T-004）
- `mkdir` 409 if exists
- `upload` multipart 或 chunked TE 接收
- 临时文件落盘 → rename 到目标路径（保证原子性）
- 错误结构沿用 T-003 §5.4

### Out of scope
- 上传 session 管理（→ T-011）
- 缩略图生成（→ T-021）
- 推送事件（→ T-019）

## 4. Files to create / modify

| Path | Change |
|------|--------|
| `packages/core/src/fs/rest.rs` | extend：加 `handle_mkdir` / `handle_upload` |
| `packages/core/src/fs/upload.rs` | new（多部分解析 + 临时文件） |
| `packages/core/src/fs/tests/rest_write_test.rs` | new |

## 5. Design

### 5.1 mkdir

```rust
#[derive(Deserialize)]
struct MkdirBody { path: String }

#[derive(Serialize)]
struct MkdirResponse { path: String }

async fn handle_mkdir(
    State(state): State<Arc<FsState>>,
    Json(body): Json<MkdirBody>,
) -> Result<Json<MkdirResponse>, FsError>;
```

服务端：

1. `PathGuard::check(&body.path)` → 解析后绝对路径
2. 若已存在 → `FsError::Conflict`
3. `tokio::fs::create_dir_all(abs).await` → 落盘
4. 返回 `{ path }`

### 5.2 upload

请求体（multipart/form-data）：

```
Content-Type: multipart/form-data; boundary=...
<boundary>
Content-Disposition: form-data; name="file"; filename="IMG_0001.jpg"
Content-Type: image/jpeg

<binary>
```

服务端：

1. `PathGuard::check(&query.path)` → 解析后目录
2. 流式解析 multipart，落到 `target_dir/.tmp/<uuid>`
3. 接收完整 → `tokio::fs::rename(tmp, target)`
4. 返回 `{ path, size }`

### 5.3 FsError 增量

```rust
pub enum FsError {
    // ...
    #[error("conflict: {0}")]
    Conflict(String),                  // 409
    #[error("payload too large: {0}")]
    PayloadTooLarge(u64),              // 413
}
```

## 6. UI / Interaction

不在本工单。客户端 UI 在 T-012。

## 7. Test plan

### 单元

- `mkdir_creates_dir`
- `mkdir_returns_409_on_existing_dir`
- `mkdir_rejects_path_outside_whitelist`
- `upload_streams_to_tmp_then_renames`
- `upload_atomic_rename_on_full`
- `upload_rejects_zero_byte`
- `upload_rejects_path_outside_whitelist`
- `upload_respects_max_size_returns_413`

## 8. Acceptance criteria

- [ ] 两个端点实现 + 单测
- [ ] 写操作强制走 PathGuard
- [ ] 原子 rename 保证"传一半失败不会留下半成品"
- [ ] 错误响应符合 §5.3

## 9. Risks / Notes

- multipart 解析在 Rust 用 `axum::extract::Multipart`，不要自己手写
- 临时文件清理：`Drop` guard 避免崩溃时遗留；或单独后台清理任务（v1 用 Drop 即可）
- 上传大小限制（默认 10 GB）在 T-011 引入，本工单只校验"硬上限"

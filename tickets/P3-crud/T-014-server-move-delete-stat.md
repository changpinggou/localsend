# T-014: Server move / delete / stat 端点

> Phase: P3 — CRUD
> Priority: P0
> Estimate: 2d
> Dependencies: T-001、T-004
> Spec: REQUIREMENTS.md §3.2.2、§3.2.3 F-S-8
> Owner: Server

## 1. Background

P3 补齐剩余 CRUD：

- `POST /move`：rename / 跨目录移动（系统调用 `rename`，**不**走网络传输）
- `POST /delete`：批量删除；可选走系统回收站
- `GET /stat`：单文件元数据，给客户端做断点续传 + 媒体播放器预探测

## 2. Goal

3 个端点全部带 PathGuard、confirm flag（写操作）、审计日志。

## 3. Scope

### In scope
- 3 个端点
- `confirm: true` 字段
- 批量删除结果聚合
- `move` 跨盘符失败 → 友好错误

### Out of scope
- 平台回收站 FFI（→ T-015 单独实现）
- 缩略图（→ T-021）
- 推送事件（→ T-019）

## 4. Files to create / modify

| Path | Change |
|------|--------|
| `packages/core/src/fs/rest.rs` | extend：3 个 handler |
| `packages/core/src/fs/move_delete.rs` | new（move/delete 业务逻辑） |
| `packages/core/src/fs/stat.rs` | new |
| `packages/core/src/fs/tests/move_delete_test.rs` | new |

## 5. Design

### 5.1 move

```rust
#[derive(Deserialize)]
struct MoveBody {
    from: String,
    to: String,
    confirm: bool,
}

async fn handle_move(...) -> Result<Json<MoveResponse>, FsError>;
```

- `from` / `to` 都走 `PathGuard::check`
- `confirm=false` → `FsError::BadRequest("confirm required")`
- 调用 `tokio::fs::rename(from, to)`
- 跨盘符：Windows 上 `MoveFileExW` with `MOVEFILE_COPY_ALLOWED`，macOS/Linux 退化为 `copy + delete`
- 失败回滚：copy 模式中途失败要清理 target

### 5.2 delete

```rust
#[derive(Deserialize)]
struct DeleteBody {
    paths: Vec<String>,
    recycle: bool,        // false = 永久删除
    confirm: bool,
}

#[derive(Serialize)]
struct DeleteResponse {
    deleted: Vec<String>,
    failed: Vec<DeleteFailure>,
}

struct DeleteFailure { path: String, reason: String }
```

- 每个 path 走 `PathGuard::check`
- `recycle=true` → 走 T-015 平台回收站
- `recycle=false` → `tokio::fs::remove_file` / `remove_dir_all`
- 单项失败不影响其他项（聚合到 `failed`）

### 5.3 stat

```rust
#[derive(Deserialize)]
struct StatParams { path: String }

#[derive(Serialize)]
struct StatResponse {
    name: String,
    is_dir: bool,
    size: u64,
    mtime: i64,
    mime: Option<String>,
    supports_range: bool,    // 恒为 true（FileUpload 流都支持）
    etag: String,             // mtime+size hash
}
```

- 一次性返回所有元数据
- `etag` 是断点续传续传的关键（与 T-011 UploadSession 共享）

## 6. UI / Interaction

不在本工单。

## 7. Test plan

### 单元

- `move_renames_file`
- `move_moves_across_dir`
- `move_cross_drive_falls_back_to_copy`
- `move_rejects_without_confirm`
- `move_rejects_path_outside_whitelist`
- `delete_files_batch`
- `delete_recursive_dir`
- `delete_partial_failure_aggregated`
- `delete_rejects_without_confirm`
- `stat_returns_etag_consistent`
- `stat_rejects_path_outside_whitelist`

## 8. Acceptance criteria

- [ ] 3 个端点全实现 + 单测
- [ ] 写操作强制 `confirm: true`
- [ ] 删除聚合失败（单条不影响其他）
- [ ] `move` 跨盘符走 copy fallback
- [ ] `stat.etag` 与 `upload` session 校验一致

## 9. Risks / Notes

- `confirm` 字段看似多此一举，但防止自动化脚本误删
- macOS `rename` 跨 APFS 卷是 atomic（同一卷），跨外接盘可能慢；不要 await 在主线程
- 永久删除的 audit log 字段包含 `confirm: true, recycle: false`

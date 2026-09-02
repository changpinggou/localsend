# T-015: Server 写审计日志 + 平台回收站

> Phase: P3 — CRUD
> Priority: P0
> Estimate: 2d
> Dependencies: T-014
> Spec: REQUIREMENTS.md §3.2.3 F-P-3、§4.1 N-SEC-5
> Owner: Server + 平台

## 1. Background

T-014 的 `delete` 端点 `recycle=true` 时需要走系统回收站：

- macOS：`NSWorkspace.recycle`（Swift API，需 FFI / `objc` crate）
- Windows：`SHFileOperation` with `FO_DELETE` + `FOF_ALLOWUNDO`（或 `IFileOperation`）
- Linux：`freedesktop` trash 规范 `~/.local/share/Trash/files/`

审计日志：所有写操作记录 `who / what / when / result`，保留 7 天。

## 2. Goal

- 跨平台回收站实现（macOS / Windows / Linux）
- 审计日志模块：tracing + 持久化（JSONL 文件，rotate 7 天）

## 3. Scope

### In scope
- `packages/core/src/fs/recycle.rs` — 平台分发
- `packages/core/src/fs/audit.rs` — 审计 logger
- macOS 通过 `objc2` crate
- Windows 通过 `windows` crate
- Linux 写文件到 `~/.local/share/Trash/files/<basename>` + 更新 `info` 元数据

### Out of scope
- 审计日志查询 UI（由 app 设置页提供，本工单不写 UI）
- 集中日志收集（v1 只本地 JSONL）

## 4. Files to create / modify

| Path | Change |
|------|--------|
| `packages/core/src/fs/recycle.rs` | new |
| `packages/core/src/fs/audit.rs` | new |
| `packages/core/src/fs/move_delete.rs` | modify：delete 走 recycle |
| `packages/core/Cargo.toml` | 加 `objc2`（macOS）/ `windows`（windows）依赖（按 target） |
| `packages/core/src/fs/tests/recycle_test.rs` | new |
| `packages/core/src/fs/tests/audit_test.rs` | new |

## 5. Design

### 5.1 Recycle 抽象

```rust
pub async fn recycle(path: &Path) -> Result<(), FsError>;

#[cfg(target_os = "macos")]
mod imp {
    pub async fn recycle(path: &Path) -> Result<(), FsError> {
        // 调用 NSWorkspace URLForFile + recycle
    }
}

#[cfg(target_os = "windows")]
mod imp {
    pub async fn recycle(path: &Path) -> Result<(), FsError> {
        // SHFileOperationW with FOF_ALLOWUNDO
    }
}

#[cfg(target_os = "linux")]
mod imp {
    pub async fn recycle(path: &Path) -> Result<(), FsError> {
        // 写 ~/.local/share/Trash/files/<basename>
        // 追加 ~/.local/share/Trash/info/<basename>.trashinfo
    }
}
```

### 5.2 Audit logger

```rust
pub struct AuditLog {
    path: PathBuf,                // ~/.local/share/localsend/audit.jsonl
}

impl AuditLog {
    pub fn new(config_dir: &Path) -> Result<Self, FsError>;

    pub fn record(&self, entry: AuditEntry) -> Result<(), FsError>;

    pub fn query(&self, since: DateTime, peer: Option<&str>) -> Result<Vec<AuditEntry>, FsError>;

    pub fn rotate_if_needed(&self) -> Result<(), FsError>;
}

#[derive(Serialize, Deserialize)]
pub struct AuditEntry {
    pub ts: i64,                   // unix epoch
    pub peer: String,              // fingerprint
    pub op: String,                // "mkdir" | "upload" | "delete" | "move"
    pub path: String,
    pub result: String,            // "ok" | error code
    pub size: Option<u64>,
}
```

rotate 策略：每日 0 点执行；保留 7 天；超出删除。

### 5.3 集成

`move_delete.rs::delete_paths` 中：

```rust
if recycle {
    recycle::recycle(&abs).await?;
} else {
    tokio::fs::remove_file(&abs).await?;
}
audit.record(AuditEntry { ... result: "ok" }).ok();
```

## 6. UI / Interaction

不在本工单。

## 7. Test plan

### 单元

- `recycle_moves_to_trash_dir`（mock 平台函数）
- `recycle_fails_if_path_already_in_trash`
- `audit_writes_jsonl_line`
- `audit_query_filters_by_since`
- `audit_rotate_drops_old_files`

### 集成

- macOS / Windows / Linux 各在 CI 跑一个真机回收站测试（用临时目录 mock 系统路径）

## 8. Acceptance criteria

- [ ] 3 平台回收站实现
- [ ] 审计日志 JSONL 可被 `jq` 解析
- [ ] 7 天 rotate 自动化
- [ ] 与 T-014 delete 端点集成

## 9. Risks / Notes

- macOS FFI 通过 `objc2`（更安全）而非老的 `objc` crate
- Windows `SHFileOperation` 已 deprecated，新代码应用 `IFileOperation`；本工单 v1 用 SHFileOperation 即可
- Linux 不保证各桌面环境都识别 `~/.local/share/Trash/`；v1 写到一个明确子目录并提示用户
- 审计日志是**附加**的，不替代 `tracing` 的运行时日志

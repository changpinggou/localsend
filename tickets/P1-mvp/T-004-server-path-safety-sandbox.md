# T-004: Server 路径安全沙箱

> Phase: P1 — MVP
> Priority: P0
> Estimate: 2d
> Dependencies: T-001
> Spec: REQUIREMENTS.md §3.2.3、§4.1 N-SEC-1/N-SEC-2、§7 AC-3
> Owner: Server + 安全

## 1. Background

开放文件系统操作的安全核心是"路径解析与白名单判定"。LocalU 要求三道防线全部命中：

1. **绝对路径解析**：`..` 与符号链接必须被解析为真实绝对路径
2. **白名单兜底**：解析后的路径必须以**某个白名单根**为前缀
3. **跨挂载点 symlink 拒绝**：避免软链逃逸到 `/etc`、`C:\Windows` 等

任何越权必须返回 `403 path_denied` 并触发审计日志。

## 2. Goal

实现 `FsPath` 类型 + `PathGuard::check(path: &str) -> Result<PathBuf, FsError>`，被所有 fs REST handler 强制调用。

## 3. Scope

### In scope
- `FsPath::new(input: &str)` 接收任意字符串，做归一化（`/` vs `\` 兼容 Windows 客户端）
- `PathGuard::check(&FsPath, &MountTable) -> Result<PathBuf, FsError>` 输出解析后绝对路径
- 跨平台 `Path::canonicalize` 与 symlink 解析策略
- 审计日志：`tracing::warn!(event = "fs.path.denied", reason, requested, fingerprint)`
- 30+ fuzz 单元测试

### Out of scope
- REST handler 业务（→ T-003、T-010、T-014）
- 平台 FFI（symlink 在 Windows 是 `CreateSymbolicLinkW`，本工单用 `std::fs::metadata` 的 `file_type()` 判断）

## 4. Files to create / modify

| Path | Change |
|------|--------|
| `packages/core/src/fs/path.rs` | implement |
| `packages/core/src/fs/mod.rs` | re-export `FsPath`, `PathGuard` |
| `packages/core/src/fs/tests/path_test.rs` | new（30+ cases） |

## 5. Design

### 5.1 FsPath

```rust
#[derive(Debug, Clone)]
pub struct FsPath(String);   // 内部存归一化后字符串

impl FsPath {
    /// 接受 "D:/Photos" / "/Volumes/A/foo" / "D:\\Photos"
    pub fn new(input: &str) -> Result<Self, FsError>;

    pub fn as_str(&self) -> &str;

    /// 解析为绝对路径，未在白名单内时返回 Err
    pub fn resolve(&self, mounts: &MountTable) -> Result<PathBuf, FsError>;
}
```

归一化规则：

- Windows：盘符大写、反斜杠 → 正斜杠、去除尾部分隔符
- macOS / Linux：折叠重复 `/`、去除 `/.` 与 `..` 段（**不**调用 FS，只在字符串层）

### 5.2 PathGuard

```rust
pub struct PathGuard<'a> { mounts: &'a MountTable }

impl<'a> PathGuard<'a> {
    pub fn new(mounts: &'a MountTable) -> Self;

    /// 三道防线：绝对路径解析 → 白名单前缀 → 跨挂载点 symlink 拒绝
    pub fn check(&self, input: &str) -> Result<PathBuf, FsError>;
}
```

三道防线伪代码：

```rust
let candidate = FsPath::new(input)?;
let abs = std::fs::canonicalize(&candidate)?;          // 1) 解析真实路径
let mount_root = self.mounts.find_root_containing(&abs)
    .ok_or(FsError::PathDenied)?;                       // 2) 白名单前缀
let resolved = walk_symlinks(&abs)?;                    // 3) symlink 审计
if !is_within(&resolved, &mount_root) {
    return Err(FsError::PathDenied);
}
Ok(resolved)
```

### 5.3 错误与审计

```rust
#[derive(Debug, thiserror::Error)]
pub enum FsError {
    #[error("path denied: {0}")]
    PathDenied(String),                  // reason: dotdot | symlink_escape | outside_whitelist | invalid
    #[error("not found: {0}")]
    NotFound(String),
    #[error("bad request: {0}")]
    BadRequest(String),
    // ...
}
```

每个 `PathDenied` 必须同时调用 `tracing::warn!`（N-SEC-5 审计基础）。

## 6. UI / Interaction

不在本工单。

## 7. Test plan

### 单元（`path_test.rs`，30+ cases）

**字符串归一化**：
- `D:\Photos` ↔ `D:/Photos` 等价
- `D:/Photos/.` → `D:/Photos`
- `D:/Photos/../Work` → `D:/Work`（在白名单内时）
- `D:/Photos/../../etc` → 路径被 canonicalize 抛出或不在白名单
- 大小写：Windows 下 `d:` 与 `D:` 等价

**白名单判定**：
- 白名单仅含 `D:` 时 `D:/Photos/ok.txt` ✓
- 白名单仅含 `D:` 时 `E:/Photos/x.txt` ✗ → PathDenied
- 白名单仅含 `D:` 时 `D:/../etc/passwd` ✗ → PathDenied（即便 `etc` 是合法路径）

**Symlink 逃逸**（使用 tempfile 创建 symlink）：
- `D:/a -> /etc` → PathDenied("symlink_escape")
- `D:/a -> D:/b`（合法内部 symlink）→ Ok
- `D:/a -> /Volumes/Other/x`（跨白名单）→ PathDenied

**性能**：
- 10000 次 check 调用耗时 < 1 s（避免反复 canonicalize 大目录树）

### Fuzz

`cargo-fuzz` target：`fuzz_path`（见 T-024）。

## 8. Acceptance criteria

- [ ] 30+ 单元测试全通过
- [ ] 任何越权请求返回 403 + 审计日志
- [ ] `FsError::PathDenied` 至少细分四种 reason（`dotdot` / `symlink_escape` / `outside_whitelist` / `invalid`）
- [ ] 在 Windows / macOS / Linux CI 各跑一次 path_test

## 9. Risks / Notes

- `std::fs::canonicalize` 在路径不存在时会失败；提前 `FsPath::new` 就要把"空段"清理掉
- Windows 下符号链接默认需要 SeCreateSymbolicLinkPrivilege；测试要 `SKIP_PRIVILEGED=1` 时跳过
- 切勿在 PathGuard 中使用 `set_current_dir` 之类全局副作用

# T-002: 挂载点枚举 + 白名单

> Phase: P1 — MVP
> Priority: P0
> Estimate: 2d
> Dependencies: T-001
> Spec: REQUIREMENTS.md §3.2.1、F-S-1、F-S-2
> Owner: Server

## 1. Background

LocalU 需要在桌面端枚举"挂载点"（macOS 的 `/Volumes/*`、Windows 的可移动盘符、Linux 的 `/media/$USER/*`），并通过白名单决定哪些对外暴露。这是**安全边界的第一道门**（N-SEC-2 默认拒绝），所以**默认 `whitelist = []`**，必须由用户主动勾选。

## 2. Goal

实现：

- `FsMount::list()` 跨平台枚举当前所有候选挂载点
- `MountTable::from_config(roots)` 加载白名单，并提供 `contains(path)` / `roots()` 访问器
- 在 `core::http::server` 启动时根据 FsConfig 注册挂载点变更事件源
- 单元测试覆盖 macOS / Windows / Linux 三种枚举路径

## 3. Scope

### In scope
- 跨平台枚举（macOS / Windows / Linux）— 通过 `cfg(target_os)` 分发
- `FsRoot { id, label, total_bytes, free_bytes, filesystem }` 数据结构
- `MountTable` 增删查
- `IsReadOnly` / `IsSystem` 等元信息（仅用于 UI 提示，不影响安全判定）

### Out of scope
- 热插拔监听（→ T-018）
- UI（→ T-007、T-008；本工单只产出数据）
- 路径白名单判定（→ T-004 path safety）

## 4. Files to create / modify

| Path | Change |
|------|--------|
| `packages/core/src/fs/mount.rs` | implement：枚举 + MountTable |
| `packages/core/src/fs/config.rs` | extend：`FsConfig::whitelist` 改为 `Vec<FsRoot>` 加上 `update_whitelist` |
| `packages/core/Cargo.toml` | add：跨平台需要的 crate（见 §5.2） |
| `packages/core/src/fs/tests/mount_test.rs` | new |

## 5. Design

### 5.1 数据结构

```rust
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct FsRoot {
    pub id: String,           // "D:" or "/Volumes/External"
    pub label: String,        // "工作盘 (D:)"
    pub path: PathBuf,        // 绝对路径
    pub total_bytes: u64,
    pub free_bytes: u64,
    pub filesystem: String,   // "exFAT" / "APFS" / "ext4"
    pub is_removable: bool,
    pub is_read_only: bool,
}
```

### 5.2 跨平台枚举

- **macOS**：`std::fs::read_dir("/Volumes").ok()` + `df -P <path>` 获取 `total/free/fs`（用 `sysinfo` crate，0.32+）
- **Windows**：调用 `GetLogicalDrives` + `GetDriveTypeW` 排除 `DRIVE_FIXED` 中 system-only 盘；体积信息走 `GetDiskFreeSpaceExW`（走 FFI 或 `windows` crate）
- **Linux**：`/media/$USER/*` 与 `/run/media/$USER/*` 两个目录扫描；体积走 `statvfs`

依赖（`packages/core/Cargo.toml` 新增）：

```toml
sysinfo = { version = "0.32", default-features = false, optional = true }
[target.'cfg(target_os = "windows")'.dependencies]
windows = { version = "0.58", features = ["Win32_Storage_FileSystem", "Win32_System_Storage"] }
```

### 5.3 MountTable

```rust
pub struct MountTable { roots: HashMap<String, FsRoot> }

impl MountTable {
    pub fn from_config(roots: Vec<FsRoot>) -> Self;
    pub fn roots(&self) -> Vec<FsRoot>;
    pub fn contains(&self, abs_path: &Path) -> bool;   // 路径在某个白名单根之下
    pub fn update(&mut self, roots: Vec<FsRoot>);
    pub fn label_of(&self, abs_path: &Path) -> Option<String>;
}
```

## 6. UI / Interaction

不在本工单。

## 7. Test plan

### 单元（`mount_test.rs`）

- `test_enumerate_macos` — 注入 `/Volumes` mock 目录，断言至少一个挂载点
- `test_enumerate_windows_excludes_c` — 注入 mock 盘符集合
- `test_enumerate_linux_user_media` — 注入 `/media/$USER/*`
- `test_mount_table_contains` — `contains("/Volumes/A/foo")` 当 `/Volumes/A` 在白名单时 true
- `test_mount_table_case_insensitive_windows` — `contains("d:/a")` 当 `D:` 在白名单时 true
- `test_default_whitelist_is_empty` — 关键安全测试，**不能**移除

### Integration

CI 上 macOS / Windows / Linux runner 各自跑 mount_test。

## 8. Acceptance criteria

- [ ] `FsRoot` 字段齐全
- [ ] `MountTable::default()` 不暴露任何挂载点（N-SEC-2）
- [ ] macOS / Windows / Linux 三平台编译并通过各自测试
- [ ] 不引入重型新依赖：`sysinfo` 限定 features、`windows` 仅 windows 目标
- [ ] 单测覆盖率 ≥ 80% for `mount.rs`

## 9. Risks / Notes

- `sysinfo` 是中等体积的 crate；只在本工单新增一次，后续 T-018 热插拔会复用
- Windows 排除 `C:` 是默认行为，但用户仍可手动勾选；本工单不阻止，只是不在 `FsRoot::is_system` 上做主动 hide
- macOS 的 `/System/Volumes/Data` 内部挂载要过滤（`is_system` 字段）

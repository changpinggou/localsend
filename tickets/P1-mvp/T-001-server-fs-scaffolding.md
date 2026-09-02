# T-001: Server 端 fs 模块脚手架

> Phase: P1 — MVP
> Priority: P0（阻塞 T-002/003/004/005/010/014/018/021/024/025）
> Estimate: 1d
> Dependencies: 无
> Spec: REQUIREMENTS.md §1.3、§3.2
> Owner: Server

## 1. Background

`packages/core` 当前只暴露协议、HTTP server、组播、加密等模块。LocalU 需求要求新增"远程文件系统 CRUD"，必须有一个独立的 `fs` 子模块：

- 沿用 `packages/core` 现有的 feature-gate 风格（`crypto` / `http` / `multicast` / `webrtc` / `webrtc-signaling` / `full`），新增 `fs` feature
- 改动需对所有调用方不破坏：feature 关闭时模块不参与编译
- 内部按"挂载点 → 安全路径 → REST handler → 事件桥"分层

## 2. Goal

在 `packages/core/src/fs/` 下建立具备以下结构的脚手架：

- `mod.rs` 仅声明子模块，不写实现
- `config.rs` 定义 `FsConfig { whitelist, recycle_bin, max_upload_size, thumbnail_max_dim }`
- `mount.rs` 挂载点抽象（具体枚举逻辑在 T-002）
- `path.rs` 安全路径解析工具（具体规则在 T-004）
- `rest.rs` REST 路由注册（具体 handler 在 T-003/010/014）
- `events.rs` 推送事件类型（具体发放在 T-019）
- 单元测试占位文件

## 3. Scope

### In scope
- 目录与文件骨架
- `Cargo.toml` 中新增 `fs = ["http", "if-addrs", "tokio-util"]` feature
- 在 `packages/core/src/lib.rs` 中 `#[cfg(feature = "fs")] pub mod fs;`
- 把 `fs` 加入 `full` 聚合 feature
- 单元测试入口与一个 dummy 编译通过测试

### Out of scope
- 任何具体业务逻辑（由 T-002 ~ T-005、T-010、T-014 实现）

## 4. Files to create / modify

| Path | Change |
|------|--------|
| `packages/core/src/fs/mod.rs` | new（声明子模块） |
| `packages/core/src/fs/config.rs` | new（FsConfig 默认值） |
| `packages/core/src/fs/mount.rs` | new（仅 trait/struct 占位） |
| `packages/core/src/fs/path.rs` | new（仅占位） |
| `packages/core/src/fs/rest.rs` | new（仅占位） |
| `packages/core/src/fs/events.rs` | new（仅占位） |
| `packages/core/src/fs/tests/mod.rs` | new |
| `packages/core/Cargo.toml` | modify：新增 `fs` feature，加入 `full` |
| `packages/core/src/lib.rs` | modify：加 `pub mod fs`（cfg 包裹） |

## 5. Design

### 5.1 模块树

```
packages/core/src/fs/
├── mod.rs           # pub use 子模块对外门面
├── config.rs        # FsConfig
├── mount.rs         # FsMount, MountTable
├── path.rs          # FsPath, PathGuard
├── rest.rs          # register_routes(router: &mut Router)
├── events.rs        # FsEvent
└── tests/mod.rs     # #[cfg(test)] 子模块
```

### 5.2 FsConfig（默认实现，无任何外部依赖）

```rust
#[derive(Debug, Clone)]
pub struct FsConfig {
    pub whitelist: Vec<FsRoot>,            // 初始为空
    pub recycle_bin: bool,                  // 默认 false
    pub max_upload_size: u64,               // 默认 10 * 1024 * 1024 * 1024
    pub thumbnail_max_dim: u32,             // 默认 200
    pub max_list_page_size: usize,          // 默认 200
}

impl Default for FsConfig {
    fn default() -> Self { ... }
}
```

## 6. Test plan

### 单元

```rust
// packages/core/src/fs/tests/mod.rs
#[test]
fn fs_compiles_with_full_feature() {
    let _ = FsConfig::default();
}
```

`cargo test -p localsend --features full` 必须通过（CI 已覆盖）。

## 7. Acceptance criteria

- [ ] `cargo check -p localsend --features full` 通过
- [ ] `cargo check -p localsend`（裸，不带 feature）**依然**失败（保持现有的"裸 build 失败"语义，AGENTS.md 明确）
- [ ] `cargo test -p localsend --features full --lib fs::` 至少 1 个测试通过
- [ ] `pub mod fs` 用 `#[cfg(feature = "fs")]` 包裹；不启用 `fs` feature 时编译期不出现

## 8. Risks / Notes

- 后续 T-002 等会扩展本脚手架；不要在 mod.rs 中预设任何具体业务 trait，避免与未来签名冲突
- 默认 `whitelist = vec![]` 是**有意的安全默认**，必须保留（SPEC §N-SEC-2）

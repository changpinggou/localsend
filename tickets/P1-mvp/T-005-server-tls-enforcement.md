# T-005: Server 端 TLS 强制与 fs 命名空间挂载

> Phase: P1 — MVP
> Priority: P0
> Estimate: 1d
> Dependencies: T-001
> Spec: REQUIREMENTS.md §4.1 N-SEC-3、§6.1
> Owner: Server

## 1. Background

LocalU 明确要求 fs 端点**仅**在 TLS + 客户端证书通道上暴露。如果挂载端配置了"明文 HTTP"（部分测试场景需要），整个 `/api/localsend/v2/fs/*` 路由必须 panic 启动并打 ERROR 日志，不能静默放行。

## 2. Goal

- 在 `http::server` 启动时，根据 `ServerConfigV2` 判断 TLS 状态
- TLS 关闭 → 跳过 fs 路由注册 + `tracing::error!` + 返回（不 panic，避免主流程崩溃；上层由 `app/lib` 提示用户）
- TLS 开启 → 注册 fs REST 路由（T-003、T-010、T-014、T-021 后续会加入）

## 3. Scope

### In scope
- `ServerConfigV2` 新增 `enable_fs: bool` 字段
- `http::server::start_with_port` 内根据 `tls` 配置 + `enable_fs` 决定是否调用 `fs::register`
- 单测验证"无 TLS 时 fs 路由不存在"

### Out of scope
- TLS 自身实现（沿用现有 rcgen + rustls）
- 客户端证书校验（沿用现有 `event.certFingerprint` 逻辑，AGENTS.md 已说明）

## 4. Files to create / modify

| Path | Change |
|------|--------|
| `packages/core/src/http/server/config.rs` | modify：加 `enable_fs: bool`，默认 `true` |
| `packages/core/src/http/server/mod.rs` | modify：fs 模块注册条件分支 |
| `packages/core/src/fs/rest.rs` | modify：暴露 `register(router, state)`，无 TLS 时返回 `Ok(())` 不挂路由 |
| `packages/core/src/fs/tests/tls_test.rs` | new |

## 5. Design

### 5.1 ServerConfigV2 字段增量

```rust
pub struct ServerConfigV2 {
    // ...existing fields...
    pub enable_fs: bool,            // 默认 true
}
```

### 5.2 路由注册逻辑

```rust
// packages/core/src/http/server/mod.rs
pub async fn start_with_port(cfg: ServerConfigV2) -> Result<HttpServerHandle> {
    let router = build_base_router(&cfg)?;
    let mut router = router;
    if cfg.tls.is_some() {
        // Always: v2 + web send
        register_v2_routes(&mut router, &cfg);
        if cfg.enable_fs {
            fs::rest::register(&mut router, &cfg)?;
        } else {
            tracing::info!("fs namespace disabled by config");
        }
    } else {
        // Plain HTTP mode: refuse fs entirely
        tracing::error!("fs namespace requires TLS; skipping registration");
    }
    // ...
}
```

## 6. UI / Interaction

不在本工单。客户端 UI 上对应：

- 挂载端：设置页给"明文模式"开关加 hint："开启后无法共享文件系统"
- 移动端：发现挂载端 capability 列表里不带 `fs` 时隐藏"浏览驱动器"入口（T-007）

## 7. Test plan

### 单元

- `tls_off_skips_fs_routes` — `start_with_port({tls: None, enable_fs: true})` 后 GET `/api/localsend/v2/fs/roots` 返回 404
- `tls_on_registers_fs_routes` — 同上但 tls=Some，roots 返回 200
- `enable_fs_false_skips_routes` — tls=Some + enable_fs=false，roots 404
- `tls_off_emits_error_log` — `tracing-subscriber` 抓 ERROR 级日志

### Integration

`cargo test -p localsend --features full http::server::tls_test`

## 8. Acceptance criteria

- [ ] 无 TLS 时 fs 路由在 axum Router 中不存在
- [ ] 有 TLS + `enable_fs=true` 时 fs 路由全部挂载
- [ ] 错误日志格式固定为 `fs namespace requires TLS; skipping registration`
- [ ] 现有 v2 协议路由不受影响（向兼容 AC-8）

## 9. Risks / Notes

- 避免 panic：上层 App 还在跑别的主流程，fs 不可用应是降级而非崩溃
- `enable_fs` 字段未来可能细化为"按挂载点级别控制"；本工单先做全局开关

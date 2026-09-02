# T-019: Server 推送 `FsRootsChanged` 事件

> Phase: P4 — Hotplug
> Priority: P0
> Estimate: 1.5d
> Dependencies: T-018、T-014（依赖其 stat API）、T-005
> Spec: REQUIREMENTS.md §3.2.1 F-S-4、§6.2
> Owner: Server

## 1. Background

热插拔事件（T-018）触发后，ServerState 必须把 `FsRootsChanged` 推送给**所有已配对移动端**。LocalSend 现有的 `ServerEventV2` 通道已具备推送机制（AGENTS.md 描述），本工单在其上扩展 variant。

## 2. Goal

- `ServerEventV2` 新增 `FsRootsChanged { roots: Vec<FsRoot> }` / `FsEntryRemoved { paths: Vec<String> }` / `FsUploadProgress { ... }`（T-011 配合）
- 在 mount watcher 触发时，向所有 active connection 推送
- 通过 FRB → Dart 端的 ServerEvent 流

## 3. Scope

### In scope
- Rust `ServerEventV2` enum 扩展
- `packages/core/src/http/server/events.rs` 增 variant + dispatch
- `packages/localsend_isolates/rust/src/api/server.rs` 转发
- FRB codegen 同步
- Dart 端 `HttpServerEvent` 对应扩展

### Out of scope
- 客户端订阅处理（→ T-020）
- 推送的 QoS（v1 一次性推，不重试）

## 4. Files to create / modify

| Path | Change |
|------|--------|
| `packages/core/src/http/server/events.rs` | extend：3 个 variant |
| `packages/core/src/http/server/mod.rs` | modify：dispatch mount 事件到所有 connection |
| `packages/localsend_isolates/rust/src/api/server.rs` | modify：转发 |
| `packages/localsend_isolates/lib/rust/api/server.dart` | regenerate |
| `app/lib/provider/network/server/server_event.dart` | modify：加新 case |

## 5. Design

### 5.1 Rust event variant

```rust
// packages/core/src/http/server/events.rs
#[derive(Debug, Clone, Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ServerEventV2 {
    // ...existing...
    FsRootsChanged { roots: Vec<FsRoot> },
    FsEntryRemoved { paths: Vec<String> },
    FsUploadProgress {
        session_id: String,
        transferred: u64,
        total: u64,
    },
}
```

### 5.2 Dispatch

```rust
// packages/core/src/http/server/mod.rs
fn broadcast_fs_event(state: &ServerStateV2, ev: ServerEventV2) {
    let connections = state.active_connections.read();
    for tx in connections.values() {
        let _ = tx.send(ev.clone());
    }
}
```

`MountWatcher::run` 末尾调用：

```rust
broadcast_fs_event(&state, ServerEventV2::FsRootsChanged {
    roots: table.roots(),
});
```

### 5.3 T-011 集成

`UploadSession::chunk_received` 推 `FsUploadProgress`：

```rust
broadcast_fs_event(&state, ServerEventV2::FsUploadProgress {
    session_id: sid.clone(),
    transferred: session.received,
    total: session.total,
});
```

## 6. UI / Interaction

不在本工单。

## 7. Test plan

### 单元（Rust）

- `event_serializes_to_snake_case`
- `broadcast_to_multiple_connections`

### 单元（Dart）

- `server_event_parses_fs_roots_changed`
- `server_event_parses_fs_upload_progress`

## 8. Acceptance criteria

- [ ] FRB codegen 成功
- [ ] 3 个新 variant 全序列化正确
- [ ] 多个移动端同时收到事件
- [ ] 现有 v2 事件不受影响

## 9. Risks / Notes

- 不要破坏现有 variant 的序列化兼容性；用 `#[serde(tag = "type")]` 增量添加
- 推送的 `roots` 数组可能很大（10+）；客户端要做 diff 不要全量替换（T-020 处理）
- `FsUploadProgress` 频率限制：每 200ms 至少一次，避免每 chunk 一次导致事件风暴

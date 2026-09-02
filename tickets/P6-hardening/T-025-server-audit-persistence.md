# T-025: Server 审计日志持久化与查询

> Phase: P6 — Hardening
> Priority: P0
> Estimate: 1d
> Dependencies: T-015
> Spec: REQUIREMENTS.md §4.1 N-SEC-5
> Owner: Server

## 1. Background

T-015 实现了审计日志的写与 7 天 rotate。本工单：

- 让查询 API 暴露给 Dart 端
- 在 app 设置页提供"查看最近活动"入口
- 关联到 fingerprint，恶意 peer 可被识别

## 2. Goal

- FRB 暴露 `query_audit_log(since: DateTime, peer: Option<String>) -> Vec<AuditEntry>`
- 设置页：最近 7 天列表 + 按 peer 过滤
- 日志按 fingerprint 着色

## 3. Scope

### In scope
- FRB binding
- 设置页 UI

### Out of scope
- 日志上传到云（v1 仅本地）
- 日志加密

## 4. Files to create / modify

| Path | Change |
|------|--------|
| `packages/localsend_isolates/rust/src/api/audit.rs` | new |
| `packages/localsend_isolates/lib/rust/api/audit.dart` | regenerate |
| `app/lib/provider/audit/audit_provider.dart` | new |
| `app/lib/pages/settings/audit_log_page.dart` | new |
| `app/lib/pages/settings/widgets/audit_log_tile.dart` | new |
| `app/lib/router/app_router.dart` | 加路由 |
| `app/lib/pages/settings/settings_page.dart` | modify：加"查看审计"入口 |
| `app/assets/i18n/strings_en.i18n.json` | 加 key |
| `app/assets/i18n/strings_zh.i18n.json` | 加 key |

## 5. Design

### 5.1 FRB API

```rust
// packages/localsend_isolates/rust/src/api/audit.rs
pub fn query_audit_log(
    config_dir: String,
    since_ts: i64,
    peer: Option<String>,
) -> Result<Vec<AuditEntry>, String> {
    let log = AuditLog::new(Path::new(&config_dir))?;
    log.query(&DateTime::from_timestamp(since_ts, 0)?, peer.as_deref())
        .map_err(|e| e.to_string())
}
```

### 5.2 Audit log state

```dart
@ReduxProvider()
class AuditState {
  final List<AuditEntry> entries;
  final DateTimeRange? range;
  final String? peerFilter;
  final bool loading;
}
```

### 5.3 UI

设置页加 "审计日志" 入口 → 跳转新页：

```
┌────────────────────────────┐
│ ← 审计日志                  │
│ [全部 peer ▼] [最近 7 天 ▼] │
├────────────────────────────┤
│ 09-02 11:30 AB12..  mkdir   │
│         D:/Photos/2026-09    │
│ 09-02 11:32 AB12..  upload  │
│         D:/Photos/IMG_0001   │
│ 09-02 11:33 CD34..  delete  │
│         D:/tmp/old.txt       │
└────────────────────────────┘
```

## 6. UI / Interaction

见 §5.3。

## 7. Test plan

### 单元

- `audit_provider_loads_entries`
- `audit_provider_filters_by_peer`
- `audit_provider_filters_by_range`
- `audit_log_tile_formats_path`

### 集成

- 写入 100 条 → FRB 查询 → 验证顺序与过滤

## 8. Acceptance criteria

- [ ] FRB API 暴露
- [ ] 设置页可查看 7 天
- [ ] 按 peer 过滤生效
- [ ] 列表滚动流畅

## 9. Risks / Notes

- 日志文件可能很大（10+ MB），一次性读全部可能爆内存 → 后端用 `BufReader` + 增量
- UI 默认仅显示 7 天，但 query API 可查询任意时间
- 审计日志**包含**路径信息，注意不要让 app 自身把它泄露给非授权 peer

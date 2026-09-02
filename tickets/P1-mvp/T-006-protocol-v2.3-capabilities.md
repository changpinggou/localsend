# T-006: 协议 v2.3 capability 扩展

> Phase: P1 — MVP
> Priority: P0
> Estimate: 1.5d
> Dependencies: T-001
> Spec: REQUIREMENTS.md §3.1 F-D-4、§6.1、§7 AC-8
> Owner: Server + 协议

## 1. Background

LocalU 需要让移动端知道挂载端"支持哪些能力"（send / receive / fs）。原 v2.2 announce / register payload 没有此字段，所以需要：

- 字段**可选**（缺省按 `["send","receive"]` 处理，向后兼容 AC-8）
- 在 announce / register 中都带
- Rust 端枚举 `Capability` + Dart 端 `Set<Capability>`
- 配合 F-D-3 入口可见性

## 2. Goal

- Rust 端：`pub enum Capability { Send, Receive, Fs }`，可序列化 `"send" | "receive" | "fs"`
- announce 事件携带 `capabilities: Vec<Capability>`
- Dart 端 FRB 绑定 `Set<Capability>`；移动端 UI 据此显示"浏览驱动器"入口（T-007）
- 缺省时反序列化为 `{Send, Receive}`
- 单元测试覆盖序列化 / 反序列化 / 缺省

## 3. Scope

### In scope
- Rust model
- 注册逻辑在 `packages/localsend_isolates/rust/src/api/metadata.rs`（沿用现 announce 路径）
- FRB codegen 输出后 Dart 端 `Capability` enum
- 单测

### Out of scope
- UI（→ T-007）
- 服务端 push 事件（→ T-019）

## 4. Files to create / modify

| Path | Change |
|------|--------|
| `packages/core/src/model/capability.rs` | new（enum + serde） |
| `packages/core/src/model/mod.rs` | 声明 `pub mod capability;` |
| `packages/core/src/model/announce.rs` | extend：`announce::Announce { capabilities: Vec<Capability> }` |
| `packages/localsend_isolates/rust/src/api/metadata.rs` | modify：announce 时附加 capabilities |
| `packages/localsend_isolates/lib/rust/api/metadata.dart` | regenerate（FRB） |
| `app/lib/model/capability.dart` | new（dart_mappable） |
| `app/lib/util/capability_helper.dart` | new（解析 + 缺省） |

## 5. Design

### 5.1 Rust

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum Capability {
    #[serde(rename = "send")]
    Send,
    #[serde(rename = "receive")]
    Receive,
    #[serde(rename = "fs")]
    Fs,
}

impl Default for Capability {
    fn default() -> Self { Capability::Send }     // 仅作为"无值时的兜底"
}

// 在 Announce 上
#[derive(Deserialize)]
#[serde(default)]
struct AnnounceRaw { ... }  // 已有

// 反序列化时如果 capabilities 字段缺失，fallback 到 vec![Send, Receive]
fn parse_capabilities(raw: Option<Vec<Capability>>) -> HashSet<Capability> {
    raw.map(|v| v.into_iter().collect()).unwrap_or_else(|| {
        [Capability::Send, Capability::Receive].into_iter().collect()
    })
}
```

### 5.2 Dart（dart_mappable）

```dart
@MappableEnum()
enum Capability {
  send,
  receive,
  fs;

  static const Set<Capability> defaultSet = {Capability.send, Capability.receive};
}

extension CapabilityListParsing on List<dynamic> {
  Set<Capability> toCapabilities() { ... }
}
```

## 6. UI / Interaction

T-007 会消费本工单输出。展示策略：

- 移动端发现设备列表读取 `peer.capabilities.contains(Capability.fs)` 决定"浏览驱动器"按钮可见性

## 7. Test plan

### 单元（Rust）

- `capability_serialize` — `vec![Fs]` ↔ `["fs"]`
- `capability_default` — `None` → `{Send, Receive}`
- `capability_unknown_field` — 服务端拒绝未知值

### 单元（Dart）

- `parse_capabilities_from_list` — 已知列表 / 空 / null 三种
- `defaultSet_applied_when_field_missing`

## 8. Acceptance criteria

- [ ] FRB codegen 后 `app/lib/gen/` 自动更新
- [ ] 老 v2.2 客户端/服务端互通无 regression（AC-8）
- [ ] capability 缺省按 `{Send, Receive}` 解释
- [ ] `dart format --set-exit-if-changed lib test` 通过
- [ ] `flutter analyze` 无新增告警

## 9. Risks / Notes

- 这是**协议层**变更；改完需同步 PR 到 `https://github.com/localsend/protocol` 仓库
- Rust 端的 `Capability::default()` 不暴露给业务；业务用 `parse_capabilities`
- 移动端 `Capability` 字段是同步字段，移动端展示时要加版本判断：低于 v2.3 时强制走默认集合

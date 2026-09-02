# T-007: 移动端「浏览驱动器」入口

> Phase: P1 — MVP
> Priority: P0
> Estimate: 1d
> Dependencies: T-006
> Spec: REQUIREMENTS.md §3.1 F-D-3、§5.2
> Owner: Client

## 1. Background

能力声明协议（T-006）落地后，移动端需要在"接收方设备选择列表"中显示「浏览驱动器」按钮，**仅**在该设备 capability 含 `fs` 时出现。

## 2. Goal

- 在 `app/lib/pages/receive_page/` 或 `home_page/` 现有设备选择列表中，每个设备行右侧追加"浏览驱动器"图标
- 仅当 `device.capabilities.contains(Capability.fs)` 显示
- 点击后 push 一个新的"远端浏览器"占位页（具体 UI 在 T-008 实现）
- i18n：图标 tooltip + 按钮文案走 slang（`@` 字段保留）

## 3. Scope

### In scope
- 设备列表行的 UI 增量
- 根据 capability 显隐
- 跳转路由

### Out of scope
- 浏览器页具体内容（→ T-008）
- 数据请求（→ T-008 内部用 T-003）
- 设置（与"浏览驱动器"无关）

## 4. Files to create / modify

| Path | Change |
|------|--------|
| `app/lib/pages/receive_page/widgets/peer_row.dart` | new（封装单行） |
| `app/lib/pages/receive_page/receive_page.dart` | modify：用 PeerRow 重构列表 |
| `app/lib/router/app_router.dart` | modify：加 `RouteDef.remoteBrowser` |
| `app/assets/i18n/strings_en.i18n.json` | 加 `browse_drive_tooltip`, `browse_drive` |
| `app/assets/i18n/strings_zh.i18n.json` | 加 `browse_drive_tooltip`, `browse_drive` |

## 5. Design

### 5.1 行结构

```
[device-name]   [browse-drive icon] [send-file button]
```

- macOS 宽屏：图标放右侧，"发送"按钮在更右
- iOS 窄屏：长按行展开 menu，包含「浏览驱动器」「发送文件」

### 5.2 路由

```dart
@RouteDef('remote_browser/:fingerprint')
class RemoteBrowserRoute extends RouteSpec { ... }
```

- 传 `fingerprint` 即可（用 `Provider` 查 peer 详情）
- 浏览器页内部需要的 root/路径状态用页内 state 或独立 `ReduxProvider`

## 6. UI / Interaction

```
┌────────────────────────────┐
│ 常平zego-mac        ⌬   ➤  │  ← 接收方行（macOS）
│ 常平的iphone17pro    ⌬   ➤  │
└────────────────────────────┘
```

- `⌬` = 浏览驱动器（仅 fs 能力时显示）
- `➤` = 发送文件（所有设备都有）
- tooltip 走 i18n key `browse_drive_tooltip`

## 7. Test plan

### 单元

- `peer_row_shows_browse_when_fs`
- `peer_row_hides_browse_when_no_fs`
- `peer_row_tap_browse_pushes_route`

### 集成

`app/test/integration/peer_row_test.dart`（widget test）

## 8. Acceptance criteria

- [ ] capability 含 fs 的设备行显示浏览驱动器入口
- [ ] 缺省/老 v2.2 设备的 capability 集合不含 fs，入口不显示
- [ ] i18n key 至少 en + zh 完整
- [ ] 路由跳转不破现有发送流程
- [ ] `flutter analyze` 无新增告警

## 9. Risks / Notes

- 注意列表性能：每个 PeerRow 包 `Selector` / `Consumer`，避免大列表时全量 rebuild
- 未来挂载端"按挂载点级别控制"时（T-005 后续），入口需要再细化为"哪些 root 可浏览"

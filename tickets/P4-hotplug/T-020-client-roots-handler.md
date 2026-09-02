# T-020: 客户端 roots 变化处理

> Phase: P4 — Hotplug
> Priority: P0
> Estimate: 1d
> Dependencies: T-019、T-008
> Spec: REQUIREMENTS.md §3.3.3 F-C-13、§7 AC-4
> Owner: Client

## 1. Background

`FsRootsChanged` 事件从挂载端推过来时，移动端要：

1. 更新 roots 列表（挂载点选择器 / 设置页）
2. 如果当前正在浏览的挂载点被移除，**立即跳回根**并 toast
3. 如果新增了挂载点，在 UI 上加提示

## 2. Goal

- 订阅 `ServerEvent.FsRootsChanged` / `FsEntryRemoved`
- 更新 `FsRootsState` provider
- 当前路径不在新白名单 → 跳回根 + toast
- 新增挂载点 → 显示 toast

## 3. Scope

### In scope
- 事件订阅
- 状态更新
- UI 反馈

### Out of scope
- 列表 diff 优化（v1 全量替换）
- 多端并发处理

## 4. Files to create / modify

| Path | Change |
|------|--------|
| `app/lib/provider/network/fs/fs_roots_provider.dart` | new |
| `app/lib/provider/network/server/server_event_handler.dart` | extend：监听 fs 事件 |
| `app/lib/pages/remote_browser/remote_browser_page.dart` | modify：监听当前路径失效 |
| `app/lib/util/toast.dart` | extend：toast 类型 |
| `app/assets/i18n/strings_en.i18n.json` | 加 key |
| `app/assets/i18n/strings_zh.i18n.json` | 加 key |

## 5. Design

### 5.1 State

```dart
@ReduxProvider()
class FsRootsState {
  final List<FsRoot> roots;
  final DateTime updatedAt;
}
```

### 5.2 事件处理

```dart
void _onServerEvent(HttpServerEvent ev) {
  switch (ev) {
    case HttpServerEvent_FsRootsChanged(:final roots):
      dispatch(FsRootsUpdate(roots));
      final currentIsValid = roots.any((r) => currentPath.startsWith(r.id));
      if (!currentIsValid) {
        dispatch(FsNavigateToRoot());
        showToast('当前挂载点已断开');
      } else {
        showToast('挂载点已更新');
      }
    case HttpServerEvent_FsEntryRemoved(:final paths):
      for (final p in paths) {
        if (currentPath.startsWith(p)) {
          dispatch(FsRemoveEntries(p));
        }
      }
    default:
      // 已有逻辑
  }
}
```

### 5.3 挂载端挂载点选择器

在设备列表行（T-007 入口）旁加一个 dropdown：

```
[常平zego-mac ⌬] [选择根 ▼]
```

点了 ⌬ 后，先弹"选择根" sheet 选一个，再进入远端浏览器。

## 6. UI / Interaction

```
┌────────────────────────────┐
│  ← 工作盘 (D:) / Photos    │
│  ...                        │
│  列表正常渲染                │
│                              │
│  [toast] 挂载点已更新          │  ← 短暂提示
└────────────────────────────┘
```

断开时：

```
[toast] 当前挂载点已断开, 已返回根
[toast] 挂载点已断开, 返回中...
（自动跳回根页面）
```

## 7. Test plan

### 单元

- `fs_roots_provider_updates`
- `fs_roots_provider_detects_invalid_current_path`
- `server_event_handler_dispatches_roots_changed`
- `server_event_handler_dispatches_entry_removed`

### 集成

mock 事件：插入 3 个 root → 模拟 removed 第 2 个 → 验证 toast + 跳转

## 8. Acceptance criteria

- [ ] 收到 `FsRootsChanged` 后 3 s 内 UI 反映（AC-4）
- [ ] 断开时跳回根 + toast
- [ ] 新增时 toast 提示
- [ ] 不影响其他 peer

## 9. Risks / Notes

- 一次性推送 10+ roots 也要流畅，避免全量 rebuild：可对 `Roots` provider 加 `distinct`
- "当前路径失效"判定用 startsWith(prefix)；要小心 mount 路径前缀碰撞
- toast 文案 i18n 要分两段："已断开" + "新增"

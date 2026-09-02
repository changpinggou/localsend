# T-016: 移动端重命名 / 移动 / 删除 UI

> Phase: P3 — CRUD
> Priority: P0
> Estimate: 3d
> Dependencies: T-014、T-008
> Spec: REQUIREMENTS.md §3.3.2 F-C-8/9、§5.2
> Owner: Client

## 1. Background

P3 客户端要支持长按弹菜单 + 多选模式，覆盖重命名 / 移动 / 删除 / 分享 / 属性。

## 2. Goal

- 单击：进入目录 / 打开文件
- 长按：弹上下文菜单
- 多选模式：长按进入选择态，再次点击切换选择
- 选中后底部出现操作栏：移动 / 删除 / 分享 / 取消选择
- 所有写操作前弹确认（移动端 UI 二次确认 + 服务端 `confirm: true`，F-S-8）

## 3. Scope

### In scope
- 长按 / 多选状态机
- 重命名对话框
- 移动目标选择器（复用远端浏览器页）
- 删除二次确认 + 回收站选项
- 分享 / 属性面板

### Out of scope
- 列表无感刷新策略（→ T-017）
- 媒体预览（→ T-023）

## 4. Files to create / modify

| Path | Change |
|------|--------|
| `app/lib/pages/remote_browser/remote_browser_page.dart` | modify：加 gesture + state |
| `app/lib/pages/remote_browser/widgets/context_menu.dart` | new |
| `app/lib/pages/remote_browser/widgets/multi_select_bar.dart` | new |
| `app/lib/pages/remote_browser/widgets/rename_dialog.dart` | new |
| `app/lib/pages/remote_browser/widgets/move_target_picker.dart` | new |
| `app/lib/pages/remote_browser/widgets/delete_confirm_dialog.dart` | new |
| `app/lib/pages/remote_browser/widgets/properties_sheet.dart` | new |
| `app/lib/provider/network/fs/fs_mutation_provider.dart` | new |
| `app/lib/router/app_router.dart` | 加 move_target_picker 路由（modal） |
| `app/assets/i18n/strings_en.i18n.json` | 加 key |
| `app/assets/i18n/strings_zh.i18n.json` | 加 key |

## 5. Design

### 5.1 状态机

```
Idle ──long press──> MultiSelect (selectedIds: {id})
                       │
                       ├──tap──> toggle select
                       │
                       └──close──> Idle

MultiSelect ──action──> { MoveDialog | DeleteDialog | Share | Properties }
```

### 5.2 mutation provider

```dart
@ReduxProvider()
class FsMutationState {
  final Set<String> selectedIds;
  final bool isMultiSelect;
  final Map<String, FsEntryDto> snapshotBefore;   // 失败回滚用
}
```

Actions：

- `FsEnterMultiSelect(firstId)`
- `FsToggleSelect(id)`
- `FsExitMultiSelect`
- `FsOptimisticDelete(path)` / `FsOptimisticMove(from, to)` / `FsOptimisticRename(path, newName)`
- `FsCommitMutation` / `FsRollbackMutation`

### 5.3 移动目标选择器

复用 `RemoteBrowserPage` 的子树，但作为 modal route：

- 顶部多了"移动到这里"按钮
- 选完目录点"移动到这里" → 调 `move` 端点
- 跨 mount 不允许（前端校验 + 服务端兜底）

## 6. UI / Interaction

**多选 + 底部操作栏**：

```
┌────────────────────────────┐
│  ← 工作盘 (D:) / Photos    │
│  ☑ IMG_0001.jpg   20 MB    │
│  ☐ IMG_0002.jpg   18 MB    │
│  ☑ note.txt       12 KB    │  ← 选中态
│  ...                        │
│  [移动] [删除] [分享] [✕]   │  ← 操作栏
└────────────────────────────┘
```

**重命名对话框**：

```
┌─────────────────────┐
│ 重命名                │
│ ┌─────────────────┐ │
│ │ IMG_0001.jpg    │ │  ← 输入框，默认选中文件名（不含扩展名）
│ └─────────────────┘ │
│ [取消]      [确定]   │
└─────────────────────┘
```

**删除二次确认**：

```
┌─────────────────────────┐
│ 删除 2 个文件?           │
│                          │
│ ☑ 移入回收站（如支持）   │
│                          │
│ [取消]            [删除] │
└─────────────────────────┘
```

## 7. Test plan

### 单元

- `fs_mutation_provider_enter_multi_select`
- `fs_mutation_provider_toggle`
- `fs_mutation_provider_optimistic_delete`
- `fs_mutation_provider_rollback_on_failure`
- `rename_dialog_extracts_basename`

### Widget

- `context_menu_shows_on_long_press`
- `multi_select_bar_appears_in_multi_mode`
- `delete_dialog_defaults_recycle_checked`

## 8. Acceptance criteria

- [ ] 长按 → 菜单；菜单中重命名 / 移动 / 删除 / 分享 / 属性全部可用
- [ ] 多选模式可批量操作
- [ ] 删除前弹确认，回收站默认勾选
- [ ] 移动目标选择器跨 mount 时给出错误
- [ ] 失败时状态回滚（不出现"鬼影"条目）

## 9. Risks / Notes

- 乐观更新一定要有 snapshot，失败立即 rollback
- 移动跨 mount 时服务端会返回 403，前端要明确提示
- 移动目标选择器的 modal route 在 iOS 上需要自定义 transition（沿用 `routerino` 现成 modal）

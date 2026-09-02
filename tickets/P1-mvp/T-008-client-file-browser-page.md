# T-008: 移动端远端浏览器页（只读）

> Phase: P1 — MVP
> Priority: P0
> Estimate: 4d
> Dependencies: T-003、T-006、T-007
> Spec: REQUIREMENTS.md §3.3.1 F-C-1/2/3/4、§3.3.2 F-C-10/12、§7 AC-1
> Owner: Client

## 1. Background

点击"浏览驱动器"后，移动端进入远端文件浏览页。MVP 阶段只读：列出挂载点 → 进入某挂载点 → 进入子目录 → 列表渲染。

## 2. Goal

- 顶部：面包屑（`根 / 一级 / 二级`），可点击任意级跳转
- 右上：视图切换（列表 / 网格） + 排序菜单（名称/大小/mtime 升降序）
- 主体：列表 / 网格
  - 列表：name / size / mtime 三列
  - 网格：缩略图 + name
- 加载/空/错误三态
- 分页：上拉加载 100 条/页

## 3. Scope

### In scope
- 页面 UI（macOS / iOS 响应式布局）
- 状态管理：Refena `ReduxProvider`（与现有 `ReceiveController` 风格一致）
- 与 isolate 通道打通：`packages/localsend_isolates` 暴露新 task 类型 `FsListTask`
- 单测 / widget test

### Out of scope
- 写操作（→ T-012 / T-016）
- 缩略图请求（→ T-022）
- 媒体预览（→ T-023）
- 删除/重命名 UI（→ T-016）

## 4. Files to create / modify

| Path | Change |
|------|--------|
| `packages/localsend_isolates/lib/src/task/fs_list_task.dart` | new |
| `packages/localsend_isolates/lib/src/isolate/child/fs_list_isolate.dart` | new |
| `packages/localsend_isolates/lib/src/isolate/parent/actions.dart` | modify：加 `FsListAction` |
| `packages/localsend_isolates/lib/src/isolate/parent/parent_isolate_provider.dart` | modify：spawn 一个 `fs_list` 子 isolate |
| `app/lib/provider/network/fs/fs_list_provider.dart` | new（Refena ReduxProvider） |
| `app/lib/pages/remote_browser/remote_browser_page.dart` | new |
| `app/lib/pages/remote_browser/widgets/breadcrumb.dart` | new |
| `app/lib/pages/remote_browser/widgets/list_view.dart` | new |
| `app/lib/pages/remote_browser/widgets/grid_view.dart` | new |
| `app/lib/pages/remote_browser/widgets/empty_state.dart` | new |
| `app/lib/pages/remote_browser/widgets/sort_menu.dart` | new |
| `app/lib/router/app_router.dart` | 加路由 |
| `app/assets/i18n/strings_en.i18n.json` | 加 key |
| `app/assets/i18n/strings_zh.i18n.json` | 加 key |

## 5. Design

### 5.1 Isolate task

```dart
// packages/localsend_isolates/lib/src/task/fs_list_task.dart
class FsListRequest {
  final String peerFingerprint;
  final String path;        // "" = roots
  final int page;
  final int size;
  final String sort;        // "name_asc" ...
}

class FsListResponse {
  final List<FsEntryDto> entries;
  final int total;
  final bool hasMore;
}

Future<FsListResponse> runFsList(FsListRequest req) async { ... }
```

实现走 FRB：`rust_lib_localsend_app::fs::list_roots(...)` / `list_dir(...)`，在 isolate 内部调用，避免主线程卡顿。

### 5.2 ReduxProvider

```dart
@ReduxProvider()
class FsListState {
  final String currentPath;             // "" = roots
  final List<FsEntryDto> entries;
  final bool hasMore;
  final FsViewMode viewMode;            // list | grid
  final FsSort sort;
  final bool loading;
  final String? error;
}
```

Actions：

- `FsEnterPath(path)`
- `FsLoadMore`
- `FsChangeView(FsViewMode)`
- `FsChangeSort(FsSort)`
- `FsRefresh`

### 5.3 UI 组件

- 列表行：缩略图占位（v1 用类型图标）+ name + size + mtime + trailing
- 网格：正方形缩略图 + 文件名 1~2 行截断
- 排序菜单：底部 sheet（iOS）/ 右键菜单（macOS）

## 6. UI / Interaction

```
┌──────────────────────────────────────────┐
│ ←  工作盘 (D:) / Photos / 2026     [≡][⇅]│
├──────────────────────────────────────────┤
│ 📁  2026-09                  ─       >   │
│ 🖼  IMG_0001.jpg           20.0 MB   >   │
│ 🎬 travel.mp4              1.2 GB    >   │
│ 📄  note.txt               12 KB     >   │
├──────────────────────────────────────────┤
│                加载更多                    │
└──────────────────────────────────────────┘
```

- 暗色模式：背景 `#0F0F0F`，强调色 `#0FB6A6`
- 浅色模式：背景 `#FFFFFF`，强调色 `#0FB6A6`

## 7. Test plan

### 单元

- `fs_list_provider_reduces_enter_path`
- `fs_list_provider_reduces_load_more`
- `fs_list_provider_reduces_sort_change`
- `breadcrumb_truncates_long_path`

### Widget

- `remote_browser_page_shows_empty_state`
- `remote_browser_page_shows_error_state`
- `remote_browser_page_toggles_view_mode`

### 集成

`flutter test test/integration/remote_browser_test.dart` — mock isolate 通道，验证完整流程

## 8. Acceptance criteria

- [ ] 能从设备列表进入"工作盘"→"Photos"→点文件名
- [ ] 列表 / 网格 / 排序切换流畅，无明显掉帧
- [ ] 上拉加载 100 条后正确追加
- [ ] 错误态展示 i18n 文案
- [ ] 主线程掉帧 ≥ 55 fps（DevTools 抓帧）
- [ ] 现有"发送文件"流程不受影响

## 9. Risks / Notes

- 大量 entries 渲染用 `ListView.builder` + `cacheExtent` 控制内存
- isolate 通道**复用**现有 `IsolateConnector` 模式，不要新增独立通道
- 缩略图占位用品牌色块，避免 v1 阶段卡渲染（T-022 会接上真缩略图）

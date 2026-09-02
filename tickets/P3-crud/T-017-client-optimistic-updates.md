# T-017: 客户端列表无感刷新 / 实时同步

> Phase: P3 — CRUD
> Priority: P1
> Estimate: 1d
> Dependencies: T-016
> Spec: REQUIREMENTS.md §3.3.3 F-C-14、§4.3 N-REL-2
> Owner: Client

## 1. Background

当本地（移动端）执行重命名 / 移动 / 删除时，UI 要立即反映；同时如果用户在挂载端用其他工具（Finder / Explorer）修改了文件，UI 也要能拉到新数据。N-REL-2 明确要求"不能展示陈旧列表"。

## 2. Goal

- 乐观更新 + 失败回滚（T-016 已部分实现，本工单补齐"通知其他打开同目录的页面"）
- 切换回页面时自动 refresh
- 监听 `FsRootsChanged` 事件（T-019 配合）
- 提供"下拉刷新"手势

## 3. Scope

### In scope
- 页面 lifecycle 监听
- 乐观更新广播
- 下拉刷新
- 事件订阅

### Out of scope
- 多端并发写同一目录的乐观锁（v1 不支持，N-REL 仅限 N-REL-2）
- WebSocket 实时双向（沿用 T-019 服务推送通道）

## 4. Files to create / modify

| Path | Change |
|------|--------|
| `app/lib/pages/remote_browser/remote_browser_page.dart` | modify：下拉刷新 + lifecycle |
| `app/lib/provider/network/fs/fs_list_provider.dart` | extend：加 `refresh()` action |
| `app/lib/provider/network/fs/fs_broadcast.dart` | new（in-memory event bus） |
| `app/lib/main.dart` | 初始化时挂 broadcast |

## 5. Design

### 5.1 In-memory broadcast

```dart
class FsBroadcast {
  final _entriesController = StreamController<FsEvent>.broadcast();
  Stream<FsEvent> get onEvent => _entriesController.stream;

  void emit(FsEvent e) => _entriesController.add(e);
}

abstract class FsEvent {
  const FsEvent();
}
class FsEntriesChanged extends FsEvent { final String path; }
class FsRootsChanged extends FsEvent { final List<FsRoot> roots; }
class FsEntryRemoved extends FsEvent { final List<String> paths; }
```

### 5.2 乐观更新

```dart
void _onMutation(FsMutation m) {
  final snapshot = state.entries;     // 拷贝
  final newEntries = applyOptimistic(state.entries, m);
  dispatch(FsApplyOptimistic(newEntries));
  dispatch(FsBroadcastEmit(FsEntriesChanged(currentPath)));

  try {
    await isolate.dispatch(FsMutationAction(m));
  } catch (e) {
    dispatch(FsApplyOptimistic(snapshot));   // rollback
    dispatch(FsBroadcastEmit(FsEntriesChanged(currentPath)));
  }
}
```

### 5.3 页面 lifecycle

```dart
@override
void initState() {
  super.initState();
  _sub = context.ref.read(fsBroadcastProvider).onEvent.listen((e) {
    if (e is FsEntriesChanged && e.path == currentPath) {
      dispatch(FsRefresh());
    } else if (e is FsRootsChanged) {
      dispatch(FsRootsUpdate(e.roots));
    }
  });
}

@override
void didChangeAppLifecycleState(AppLifecycleState s) {
  if (s == AppLifecycleState.resumed) {
    dispatch(FsRefresh());
  }
}
```

### 5.4 下拉刷新

`RefreshIndicator` + `dispatch(FsRefresh())`，refresh 走 `state.etag` 增量请求（v1 用全量重拉，简单）。

## 6. UI / Interaction

```
┌────────────────────────────┐
│  ← 工作盘 (D:) / Photos    │
│  ↓ 下拉刷新中…               │  ← RefreshIndicator spinner
│  ...                        │
└────────────────────────────┘
```

## 7. Test plan

### 单元

- `fs_broadcast_emit_listens`
- `fs_list_provider_refresh_replaces_entries`
- `fs_mutation_optimistic_then_rollback`

### 集成

- 模拟：重命名 → 列表立即改名 → mock isolate 失败 → 自动回滚
- 模拟：A 页面删除条目 → B 页面（同 path）通过 broadcast 收到事件 → 自动刷新

## 8. Acceptance criteria

- [ ] 本地修改 100ms 内 UI 反映
- [ ] 失败回滚后无残留
- [ ] 切回 app 时自动 refresh
- [ ] 下拉刷新可用

## 9. Risks / Notes

- in-memory broadcast 在 isolate 边界失效；如果未来要把 fs 列表放进独立 isolate，需要换成 `StreamController.broadcast` + typed_isolates 包装
- v1 不用 ETag 增量，N-REL-2 暂靠"切回 refresh"实现

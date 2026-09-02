# T-012: 移动端上传 UI（相册多选 + 新建文件夹）

> Phase: P2 — Write
> Priority: P0
> Estimate: 3d
> Dependencies: T-010、T-011、T-008
> Spec: REQUIREMENTS.md §3.3.2 F-C-5/6、§5.2
> Owner: Client

## 1. Background

P2 客户端需要从远端浏览器页"上传到当前目录"：

- 入口：底部 + 按钮（iOS / Android）/ 工具栏按钮（macOS）
- 选项：从相册 / 从文件 / 新建文件夹
- 上传任务走后台并发（2~4 worker），断点续传 / 取消

## 2. Goal

- 底部"+ 按钮" 弹 ActionSheet
- 选择"从相册" → `wechat_assets_picker` 多选 → 进入上传队列
- 选择"从文件" → `file_picker` 多选 → 进入上传队列
- 选择"新建文件夹" → 弹命名对话框 → 调 `mkdir`
- 上传队列由 Refena `ReduxProvider` 管理
- 进度事件 → 队列条目更新 → UI 渲染

## 3. Scope

### In scope
- UI + state
- 上传任务封装（沿用 T-011 的 session 协议）
- 取消 / 断点续传
- 后台 worker（foreground task 框架 → T-013，本工单先实现应用内 worker）

### Out of scope
- iOS/Android 后台保活（→ T-013）
- 队列持久化（→ T-026）

## 4. Files to create / modify

| Path | Change |
|------|--------|
| `packages/localsend_isolates/lib/src/task/fs_upload_task.dart` | new |
| `packages/localsend_isolates/lib/src/isolate/child/fs_upload_isolate.dart` | new |
| `packages/localsend_isolates/lib/src/isolate/parent/actions.dart` | modify：加 `FsUploadAction` |
| `app/lib/provider/network/fs/fs_upload_provider.dart` | new |
| `app/lib/pages/remote_browser/widgets/upload_action_sheet.dart` | new |
| `app/lib/pages/remote_browser/widgets/upload_queue_bar.dart` | new |
| `app/lib/pages/remote_browser/remote_browser_page.dart` | modify：加 + 按钮 + 队列 bar |
| `app/lib/util/pick_from_gallery.dart` | new（`wechat_assets_picker` 包装） |
| `app/lib/util/pick_from_files.dart` | new（`file_picker` 包装） |
| `app/lib/util/mkdir_dialog.dart` | new |
| `app/assets/i18n/strings_en.i18n.json` | 加 key |
| `app/assets/i18n/strings_zh.i18n.json` | 加 key |

## 5. Design

### 5.1 Upload queue state

```dart
class UploadTask {
  final String sessionId;        // 续传校验
  final String localPath;
  final String remotePath;
  final int total;
  final int transferred;
  final UploadStatus status;     // queued | running | paused | done | failed
  final String? error;
}

@ReduxProvider()
class FsUploadState {
  final List<UploadTask> tasks;
  final int concurrent;          // 默认 2，移动端可调到 4
}
```

Actions：

- `FsEnqueueUpload({localPath, remoteDir, peer})`
- `FsUploadTick({sessionId, transferred})`
- `FsUploadPause(sessionId)` / `FsUploadResume(sessionId)`
- `FsUploadCancel(sessionId)`
- `FsUploadDone(sessionId)` / `FsUploadFailed(sessionId, error)`

### 5.2 并发 worker

```dart
class UploadWorker {
  void run() async {
    while (state.tasks.any(_isRunnable)) {
      final task = pickNext();
      if (task == null) {
        await Future.delayed(const Duration(milliseconds: 500));
        continue;
      }
      await runSession(task);   // init → chunk ×N → finish
    }
  }
}
```

每个 worker 在 isolate 内运行；并发数由 `concurrent` 控制。

### 5.3 断点续传

```dart
Future<void> runSession(UploadTask t) async {
  final init = await isolate.dispatch(FsUploadInitAction(t));
  if (init.received > 0 && init.etag == t.etag) {
    t.transferred = init.received;       // 续传
  }
  while (t.transferred < t.total) {
    final chunk = await readNextChunk(t);
    final r = await isolate.dispatch(FsUploadChunkAction(t, chunk));
    t.transferred = r.transferred;
    dispatch(FsUploadTick(t.id, r.transferred));
  }
  await isolate.dispatch(FsUploadFinishAction(t));
  dispatch(FsUploadDone(t.id));
}
```

### 5.4 UI 行为

- 队列 bar 始终在底部（iOS safe-area 内）
- 点击队列 bar 展开详情页（每个任务一行：缩略图 / name / 进度条 / 取消按钮）
- 全部完成后自动收起

## 6. UI / Interaction

```
┌────────────────────────────┐
│  ← 工作盘 (D:) / Photos   │
│  ...                        │
│                              │
│  [+]                         │ ← 浮动按钮
│                              │
│  ───────────────────────    │
│  1 正在上传 · 2 排队         │ ← 队列 bar
└────────────────────────────┘
```

## 7. Test plan

### 单元

- `fs_upload_provider_enqueue`
- `fs_upload_provider_pause_resume`
- `fs_upload_provider_cancel`
- `worker_picks_next_runnable`
- `worker_resume_from_received`
- `mkdir_dialog_returns_path_on_confirm`

### 集成

mock isolate 通道，模拟：选中 5 个文件 → enqueue → 2 worker 并发 → 全部完成 → 列表无感刷新

## 8. Acceptance criteria

- [ ] 50 张照片多选 → 后台并发上传成功
- [ ] 主动暂停后从暂停字节恢复
- [ ] 取消后立即从队列移除
- [ ] 当前目录创建文件夹成功，列表自动出现新目录
- [ ] 队列 bar 状态实时更新

## 9. Risks / Notes

- 并发 worker 不要超过 4，避免拥塞家庭路由器
- 大文件 (> 1 GB) 默认单 worker，避免重复 OOM
- iOS 后台被杀问题在 T-013 处理

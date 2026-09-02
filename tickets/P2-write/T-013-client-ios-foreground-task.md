# T-013: iOS / Android 后台保活的文件传输 worker

> Phase: P2 — Write
> Priority: P1
> Estimate: 2d
> Dependencies: T-012
> Spec: REQUIREMENTS.md §3.3.2 F-C-6、§9 风险
> Owner: Client

## 1. Background

iOS 在 app 切到后台后会冻结 Dart isolate，Android 在 Doze 模式下也会暂停。要让"50 张照片"在锁屏后仍能继续上传，必须用 `flutter_foreground_task`（已在 `packages/localsend_isolates/pubspec.yaml` 中声明）。

## 2. Goal

- 启动一次上传队列时，如果 app 退到后台，自动起 foreground service（Android）/ background task（iOS）
- 通知显示总进度："LocalSend: 上传 12/50"
- 上传全部完成 / 全部失败时关闭 foreground task

## 3. Scope

### In scope
- 集成 `flutter_foreground_task`
- 上传 / 下载（沿用 T-009）共享同一 foreground service
- 通知点击回 app

### Out of scope
- Android 自定义通知 channel 设计（沿用 default）
- 通知权限请求时机（沿用 T-009 已有 `permission_handler` 流程）

## 4. Files to create / modify

| Path | Change |
|------|--------|
| `packages/localsend_isolates/lib/src/foreground/fs_foreground_handler.dart` | new |
| `app/lib/provider/network/fs/fs_foreground_provider.dart` | new |
| `app/lib/main.dart` | modify：注册 `FlutterForegroundTask.init` |
| `app/lib/util/permission_helpers.dart` | extend：加 `requestNotificationPermission` |

## 5. Design

### 5.1 启动策略

```dart
class FsForegroundController {
  void ensureRunning() {
    if (FlutterForegroundTask.isRunning) return;
    FlutterForegroundTask.startService(
      notificationTitle: 'LocalSend 上传中',
      notificationText: '准备...',
      callback: startCallback,
    );
  }

  void updateProgress(int done, int total) {
    FlutterForegroundTask.updateService(
      notificationTitle: 'LocalSend 上传中',
      notificationText: '$done / $total',
      progress: done,
      maxProgress: total,
    );
  }

  void stopIfIdle() {
    if (state.allDoneOrFailed) FlutterForegroundTask.stopService();
  }
}
```

### 5.2 callback

```dart
@pragma('vm:entry-point')
void startCallback() {
  // 在 Android 上是 background isolate 的入口
  // 这里只保留一个 refena 容器观察状态变化
  final container = RefenaContainer.of(foregroundScope);
  container.listen<FcUploadState>((prev, next) {
    if (next.allDone) FlutterForegroundTask.stopService();
  });
}
```

## 6. UI / Interaction

通知样式：

```
┌────────────────────────────┐
│ LocalSend                  │
│ 正在上传 12/50              │
│ ▓▓▓▓▓░░░░░░░░░  24%         │
└────────────────────────────┘
```

点击通知 → 打开 app 并跳到上传队列详情页。

## 7. Test plan

### 单元

- `foreground_controller_starts_when_uploads_present`
- `foreground_controller_stops_when_idle`
- `progress_text_format`

### 集成

- Android 真机：上传 100 MB → 按 home → 等 5 min → 进度仍然推进
- iOS 真机：上传 100 MB → 锁屏 → 等 5 min → 进度仍然推进

## 8. Acceptance criteria

- [ ] Android Doze 模式下上传不被冻结（手动验证）
- [ ] iOS 锁屏后上传继续（手动验证）
- [ ] 全部完成后通知消失
- [ ] 通知点击回 app

## 9. Risks / Notes

- `flutter_foreground_task` 在 iOS 上是有限的后台时间（约 30 s）；大文件需要 split into chunks 反复唤起
- Android 13+ 需要 `POST_NOTIFICATIONS` 权限；启动前先 `permission_handler.request`
- 不要在 foreground service 中跑 Dart main isolate，而是单独的 background isolate

# T-026: 客户端离线写队列持久化

> Phase: P6 — Hardening
> Priority: P1
> Estimate: 2d
> Dependencies: T-012、T-013
> Spec: REQUIREMENTS.md §4.3 N-REL-1、§5.3
> Owner: Client

## 1. Background

N-REL-1 要求上传中断后重启 app 能断点续传。T-012 已经支持单 session 的续传，但需要把 upload 队列**整体**持久化到本地：

- 关闭 app 时未完成的任务保留
- 重启后自动恢复
- 网络恢复后自动重试

## 2. Goal

- `shared_preferences` 或 sqlite（hive）持久化 upload queue
- app 启动时 load → 校验 peer 在线 → 续传 / 取消
- 后台 worker 接管（T-013）

## 3. Scope

### In scope
- 队列持久化（hive box 优先）
- 启动恢复逻辑
- peer 离线检测

### Out of scope
- 跨设备同步
- 队列加密（v1 信任设备）

## 4. Files to create / modify

| Path | Change |
|------|--------|
| `app/pubspec.yaml` | 加 `hive_ce` + `hive_ce_flutter`（如未声明） |
| `app/lib/provider/network/fs/fs_upload_provider.dart` | extend：persist |
| `app/lib/util/persistent_upload_queue.dart` | new |
| `app/lib/main.dart` | modify：init hive + load queue |
| `app/lib/provider/network/peer/peer_state.dart` | modify：加 online check |

## 5. Design

### 5.1 Hive box

```dart
class PersistentUploadQueue {
  static const _boxName = 'fs_upload_queue';
  late Box<UploadTask> _box;

  Future<void> init() async {
    _box = await Hive.openBox(_boxName);
  }

  Future<void> save(UploadTask t) async { await _box.put(t.sessionId, t); }
  Future<void> remove(String sessionId) async { await _box.delete(sessionId); }
  List<UploadTask> loadAll() => _box.values.toList();
}
```

`UploadTask` 需 `@HiveType` + adapter：

```dart
@HiveType(typeId: 42)
class UploadTask {
  @HiveField(0) String sessionId;
  @HiveField(1) String localPath;
  @HiveField(2) String remotePath;
  @HiveField(3) int total;
  @HiveField(4) int transferred;
  @HiveField(5) String peerFingerprint;
  @HiveField(6) String etag;        // 续传校验
  @HiveField(7) DateTime createdAt;
}
```

### 5.2 启动恢复

```dart
Future<void> restoreQueue() async {
  final tasks = queue.loadAll();
  final online = await checkPeersOnline(tasks.map((t) => t.peerFingerprint).toSet());
  for (final t in tasks) {
    if (online.contains(t.peerFingerprint)) {
      dispatch(FsUploadResume(t));
    } else {
      // 保留在队列，等下次启动 / 主动重试
      t.status = UploadStatus.paused;
      queue.save(t);
    }
  }
}
```

### 5.3 peer 在线检测

复用现有 `IsolateSyncServerStateAction` 与 peer 状态：

```dart
Future<Set<String>> checkPeersOnline(Iterable<String> fps) async {
  final known = ref.read(peerListProvider);
  return fps.where((fp) => known.any((p) => p.fingerprint == fp)).toSet();
}
```

## 6. UI / Interaction

启动后：

- 队列 bar 显示"3 个待恢复任务"
- 用户点开 → 看哪些 peer 在线 / 离线
- 离线任务的"重试"按钮

## 7. Test plan

### 单元

- `persistent_upload_queue_save_load`
- `persistent_upload_queue_survives_restart`（临时 hive dir）
- `restore_queue_resumes_online`
- `restore_queue_pauses_offline`

### 集成

模拟：写入 5 个 task → 杀 app → 重启 → 3 peer 在线 → 验证 3 个 resume

## 8. Acceptance criteria

- [ ] 杀 app 后任务保留
- [ ] 重启后在线任务自动续传
- [ ] 离线任务保留到下次启动
- [ ] 队列 bar 正确显示

## 9. Risks / Notes

- Hive 持久化路径：`getApplicationSupportDirectory()/hive/`
- LocalSend 已经在用 `shared_preferences`，如需强 schema 改用 hive
- 任务超过 30 天未完成应自动归档 / 删除（避免队列膨胀）
- 注意 hive_ce vs hive 包名差异

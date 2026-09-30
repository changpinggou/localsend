# T-027: 相册增量同步

> Phase: P2 — Write
> Priority: P1
> Estimate: 3d
> Dependencies: T-008, T-012
> Spec: 相册增量同步到远端目录
> Owner: Client

## 1. Background

用户的核心需求是将手机相册里的照片**增量同步**到远端设备的某个目录。这是文件浏览器功能最重要的应用场景之一。

## 2. Goal

- 工具栏添加「同步相册」按钮
- 扫描本地相册 + 远端目录
- 增量对比（filename + size）
- 复用现有上传队列
- 显示同步进度和结果

## 3. Scope

### In scope
- 同步按钮 UI
- 本地相册扫描
- 远端目录扫描
- 差异计算
- 上传进度显示
- 结果统计

### Out of scope
- 后台定时同步
- 双向同步
- 子目录结构保持
- 视频缩略图同步

## 4. Files to create / modify

| Path | Change |
|------|--------|
| `app/lib/provider/network/fs/photo_sync_provider.dart` | new |
| `app/lib/pages/remote_browser/widgets/sync_progress_dialog.dart` | new |
| `app/lib/pages/remote_browser_page.dart` | modify: 加同步按钮 |
| `app/assets/i18n/en.json` | 加 sync key |
| `app/assets/i18n/zh-CN.json` | 加 sync key |

## 5. Design

### 5.1 核心流程

```
用户点击「同步相册」→ 选择远端目标目录
  ↓
1. 扫描本地相册（PhotoManager 枚举所有资源）
2. 扫描远端目录（多次 listDir 获取全部文件）
3. 对比差异（filename + size）
4. 上传差异文件（复用现有 upload queue）
5. 显示进度和结果
```

### 5.2 PhotoSyncService

```dart
class PhotoSyncState {
  PhotoSyncPhase phase;           // idle/scanningLocal/scanningRemote/comparing/uploading/done/failed
  int localScannedCount;
  int remoteScannedCount;
  int uploadedCount;
  int skippedCount;
  int failedCount;
  int totalToUpload;
  String? currentFilename;
  String? error;
}

Future<int> startSync({
  required Device device,
  required String remoteDir,
})
```

### 5.3 本地扫描

```dart
final paths = await PhotoManager.getAssetPathList(type: RequestType.common);
for (final path in paths) {
  int page = 0;
  while (true) {
    final assets = await path.getAssetListPaged(page: page, size: 300);
    if (assets.isEmpty) break;
    for (final asset in assets) {
      final file = await asset.originFile;
      photos.add(LocalPhoto(
        filename: await asset.titleAsync,
        size: await file.length(),
        localPath: file.path,
      ));
    }
    page++;
  }
}
```

### 5.4 远端扫描

```dart
int page = 0;
while (true) {
  final response = await client.listDir(..., page: page, size: 100);
  allFiles.addAll(response.entries);
  if (!response.hasMore) break;
  page++;
}
```

### 5.5 差异计算

```dart
List<LocalPhoto> _computeDiff(
  List<LocalPhoto> local,
  List<FsEntry> remote,
) {
  final remoteMap = <String, int>{};
  for (final entry in remote) {
    if (!entry.isDir) remoteMap[entry.name] = entry.size.toInt();
  }
  return local.where((photo) {
    final remoteSize = remoteMap[photo.filename];
    return remoteSize == null || remoteSize != photo.size;
  }).toList();
}
```

### 5.6 上传

复用 `fs_upload_provider.enqueueFiles()`：

```dart
final paths = toUpload.map((p) => p.localPath).toList();
ref.notifier(fsUploadProvider).enqueueFiles(
  device: device,
  localPaths: paths,
  remotePath: remoteDir,
);
```

## 6. UI / Interaction

### 工具栏按钮

```
┌─────────────────────────────────────┐
│ ← 工作盘 (D:) / Photos   [🔄] [≡]  │
│                                      │
│  [文件夹] [图片] [图片] [视频] ...   │
│                                      │
│  [+]                                  │
└─────────────────────────────────────┘
```

### 确认对话框

```
┌─────────────────────────┐
│     同步相册             │
│                          │
│  将同步本地所有照片到当前│
│  目录 Photos             │
│                          │
│  已存在的文件会被跳过    │
│  （同名同大小），不同的  │
│  文件会覆盖。             │
│                          │
│     [取消]  [开始同步]   │
└─────────────────────────┘
```

### 进度对话框

```
┌─────────────────────────┐
│     同步相册             │
│                          │
│  正在扫描本地相册…       │
│  已扫描：1234            │
│  ━━━━━━━━━━━━━━━━━━━━━  │
│                          │
│                  [关闭]  │
└─────────────────────────┘
```

完成：

```
┌─────────────────────────┐
│     同步相册             │
│                          │
│       ✓                  │
│  已上传：10              │
│  已跳过：1224            │
│                          │
│                  [关闭]  │
└─────────────────────────┘
```

## 7. Test plan

### 单元
- `_computeDiff` 的正确性（新增/修改/跳过）
- 本地扫描的分页逻辑（mock PhotoManager）
- 远端扫描的分页逻辑（mock listDir）

### 集成
- 10 张新照片 → 全部上传
- 5 张已存在（同名同大小）→ 全部跳过
- 3 张同名但大小不同 → 上传覆盖
- 混合场景：20 张本地 vs 15 张远端 → 正确计算差异

### 手动
1. 打开远端目录（非根目录）
2. 点击 🔄 同步按钮
3. 确认对话框显示正确
4. 进度对话框显示三个阶段
5. 完成后刷新目录，确认新文件已出现
6. 再次同步 → 显示「已跳过」

## 8. Acceptance criteria

- [ ] 工具栏显示同步按钮（非根目录时）
- [ ] 根目录时点击同步显示提示
- [ ] 确认对话框显示正确信息
- [ ] 进度对话框显示三个阶段
- [ ] 增量同步正确（跳过同名同大小）
- [ ] 同名不同大小文件被覆盖
- [ ] 上传复用现有队列（断点续传）
- [ ] 完成后刷新目录显示新文件
- [ ] 错误处理（权限拒绝、网络断开）

## 9. Risks / Notes

- **PhotoManager 权限**：需要相册访问权限，首次使用会弹出系统授权
- **大目录性能**：1000+ 张照片扫描可能需要 5-10 秒
- **后台执行**：Android 需要前台服务保活，iOS 后台可能受限
- **文件冲突**：同名文件按大小判断，不考虑 mtime（相册导出时 mtime 可能丢失）
- **子目录**：只同步到目标目录根级别，扁平存放

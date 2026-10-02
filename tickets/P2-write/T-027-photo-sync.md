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
final photos = <LocalPhoto>[];
// iOS 相册互相重叠（"最近项目" isAll=true 包含全部），同一 asset 会
// 出现在多个相册里——必须按 asset.id 去重，否则每个任务重复扫描/上传。
final seenAssetIds = <String>{};

final paths = await PhotoManager.getAssetPathList(type: RequestType.common);
for (final path in paths) {
  int page = 0;
  while (true) {
    final assets = await path.getAssetListPaged(page: page, size: 300);
    if (assets.isEmpty) break;
    for (final asset in assets) {
      if (!seenAssetIds.add(asset.id)) continue;
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

复用 `fs_upload_provider.enqueueFiles()`。**必须显式传 `filenames`**（见 §10 不变量）：

```dart
final paths = toUpload.map((p) => p.localPath).toList();
final names = toUpload.map((p) => p.filename).toList();   // titleAsync
final enqueued = await ref.notifier(fsUploadProvider).enqueueFiles(
  device: device,
  localPaths: paths,
  remotePath: remoteDir,
  filenames: names,
);
// 按 enqueued 的 sessionId（不是文件名）跟踪进度：iOS 上任务的
// localPath 是乱码 tmp 路径，文件名匹配永远失败；队列里消失的
// session 记为 failed，防止轮询死循环。
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

## 10. 定型语义与实现记录（2026-10-02）

首次联调（iOS 模拟器 → macOS 对端）暴露三个 bug 并修复后，语义定型如下。

### 10.1 语义（当前实现）

- **方向**：单向备份，**只增不删**——从不清理对端已有文件（与 §3 out-of-scope 的"双向同步"一致）。
- **扫描范围**：全图库（含"最近项目" isAll=true），按 `asset.id` 去重。
- **远端文件名** = `asset.titleAsync`（相册库里的原始文件名，如 `IMG_0001.JPG`），经 `FsUploadRequest.filename` 显式传到 Rust 上传层。
- **diff 规则**：远端存在同名且同 size → 跳过；否则上传覆盖。
- **进度追踪**：按 `sessionId` 跟踪上传队列（并发 2）。

### 10.2 不变量（改代码前必读）

> diff/跳过完全依赖"**同一张照片每次得到同一个远端文件名**"。这条链路是
> `titleAsync → LocalPhoto.filename → enqueueFiles(filenames:) → FsUploadRequest.filename → Rust fsUpload`。
> **新增上传路径禁止回退到 `basename(localPath)`**——iOS 的 `originFile.path` 是
> `/tmp/.image/UUID_L0_001_..._o_IMG_0111.HEIC` 乱码临时副本（模拟器必现），曾导致
> 远端文件名与 diff 名字永不匹配 → 每次同步全量重传、对端乱码文件堆积。

### 10.3 已修复的三个 bug（日志特征：local=14 / remote=10 / toUpload=14 / skip=0）

1. 上传文件名用了 tmp 乱码 basename → diff 永不匹配 → 全量重传（10.2 所述）。
2. 扫描未按 `asset.id` 去重 → 9 张照片扫出 14 个任务。
3. 进度按文件名匹配上传任务 → iOS 上两套名字对不上 → 进度对话框冻结在 0/N。

### 10.4 已知边界（未做产品决策）

- **删除语义**：iOS 从自建相册删除 ≠ 从图库删除（照片仍在"最近项目"），全库扫描仍会扫到——"相册里删了又同步过去"是当前语义的预期行为。镜像语义（删除传播）或相册范围选择需另行立项。
- **同名异内容**：从"文件"App 导入的同名照片会上传互相覆盖；size 恰好也相同时会被误跳过。相机照片（IMG_XXXX）不重名，日常不受影响。
- **编辑照片**：上传的是 `originFile` = 未编辑原图，不含 iOS 相册内的裁剪/滤镜。
- **一次性清理**：2026-10-02 修复前遗留的对端乱码文件（UUID 前缀、`fs-*` 前缀）需手动删除；修复后不会再产生。

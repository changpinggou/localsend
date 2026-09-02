# T-022: 客户端缩略图懒加载 + 大目录分页

> Phase: P5 — Media
> Priority: P0
> Estimate: 2d
> Dependencies: T-008、T-021
> Spec: REQUIREMENTS.md §3.3.2 F-C-10/12、§7 AC-6
> Owner: Client

## 1. Background

1000+ 文件时一次性拉全量缩略图卡顿。需要：

- 视口内才请求（懒加载）
- 滚动到底分页加载更多
- 占位 → 加载中 → 真实图 3 态

## 2. Goal

- `Thumbnail` widget 包装，命中 `VisibilityDetector`
- 列表 / 网格共用
- 分页：`ScrollController` 监听到底 → `FsLoadMore`
- 缩略图缓存：本地 disk LRU 7 天

## 3. Scope

### In scope
- widget
- 缓存（`path_cache` 插件或自写 disk LRU）
- 分页

### Out of scope
- 图片全屏预览（→ T-023）
- 视频缩略图

## 4. Files to create / modify

| Path | Change |
|------|--------|
| `app/lib/widget/thumbnail.dart` | new |
| `app/lib/widget/visibility_aware.dart` | new |
| `app/lib/util/disk_lru_cache.dart` | new（key=url, value=bytes） |
| `app/lib/pages/remote_browser/widgets/list_view.dart` | modify：用 Thumbnail |
| `app/lib/pages/remote_browser/widgets/grid_view.dart` | modify：用 Thumbnail |
| `app/lib/provider/network/fs/fs_list_provider.dart` | extend：分页 + 缩略图 URL 拼接 |

## 5. Design

### 5.1 Thumbnail widget

```dart
class Thumbnail extends StatefulWidget {
  final String peerFingerprint;
  final String path;
  final double width;
  final double height;
  final IconData placeholderIcon;   // 类型图标
}

class _ThumbnailState extends State<Thumbnail> {
  Uint8List? _bytes;
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    if (_bytes != null) {
      return Image.memory(_bytes!, ...);
    }
    if (_loading) {
      return Container(color: brandColor, child: CircularProgressIndicator(...));
    }
    return VisibilityDetector(
      key: ValueKey(widget.path),
      onVisibilityChanged: (info) {
        if (info.visibleFraction > 0.1) _load();
      },
      child: Icon(widget.placeholderIcon, size: ...),
    );
  }
}
```

### 5.2 分页

```dart
ScrollController _scroll;
void initState() {
  _scroll.addListener(() {
    if (_scroll.position.pixels >=
        _scroll.position.maxScrollExtent - 200) {
      dispatch(FsLoadMore());
    }
  });
}
```

### 5.3 磁盘缓存

```dart
class DiskLruCache {
  final String dir;
  final int maxBytes;

  Future<Uint8List?> get(String key) async { ... }
  Future<void> put(String key, Uint8List bytes) async { ... }
}
```

- key = `sha1(peerFingerprint + path + w + h)`
- 目录：`getApplicationSupportDirectory()/fs_thumb_cache/`
- LRU 通过文件 mtime 实现

## 6. UI / Interaction

```
┌──────────────────────┐
│ [缩略图] IMG_0001.jpg │
│          20.0 MB     │
└──────────────────────┘
```

加载中：

```
┌──────┐
│ ░░░░ │ ← 品牌色块
│  ⏳  │
└──────┘
```

## 7. Test plan

### 单元

- `disk_lru_cache_put_get`
- `disk_lru_cache_evicts_oldest`
- `thumbnail_loads_when_visible`
- `thumbnail_skips_when_not_visible`
- `pagination_loads_more_at_end`

### Widget

- `list_view_triggers_load_more_at_bottom`
- `grid_view_triggers_load_more_at_bottom`

## 8. Acceptance criteria

- [ ] 1000+ 文件目录滚动 ≥ 55 fps
- [ ] 缩略图缓存命中后无网络请求
- [ ] 上拉加载更多 100 条/页
- [ ] 切到列表/网格保留滚动位置

## 9. Risks / Notes

- `VisibilityDetector` 在 macOS 上有 bug 风险；测试要 macOS runner 验证
- 磁盘缓存大小默认 100 MB，可在设置中调整
- 占位图标按 `mime` 选：image → 🖼，video → 🎬，audio → 🎵，text → 📄，dir → 📁

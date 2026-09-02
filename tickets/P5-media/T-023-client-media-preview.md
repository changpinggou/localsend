# T-023: 客户端媒体预览（图片 / 视频 / 音频）

> Phase: P5 — Media
> Priority: P1
> Estimate: 3d
> Dependencies: T-009、T-022
> Spec: REQUIREMENTS.md §3.3.2 F-C-11、§7 AC-5
> Owner: Client

## 1. Background

点击文件应能直接在 app 内预览，**不**先下载到本地：

- 图片：全屏相册式横滑
- 视频 / 音频：边下边播（HTTP Range）

## 2. Goal

- 图片：横滑 + 双击缩放 + 滑动切下一张
- 视频：`video_player` 走 Range 协议
- 音频：`just_audio` 走 Range 协议 + 锁屏控件

## 3. Scope

### In scope
- 三种 media 全屏页
- Range 协议 client
- 媒体元数据加载（mime / size / duration）

### Out of scope
- 图片编辑（裁剪 / 旋转）
- 字幕 / 章节
- 投屏

## 4. Files to create / modify

| Path | Change |
|------|--------|
| `app/pubspec.yaml` | 加 `video_player`, `just_audio`（如尚未声明） |
| `app/lib/pages/media_preview/image_preview_page.dart` | new |
| `app/lib/pages/media_preview/video_preview_page.dart` | new |
| `app/lib/pages/media_preview/audio_preview_page.dart` | new |
| `app/lib/util/range_http_client.dart` | new（带 Range 头的 http client） |
| `app/lib/provider/network/fs/fs_media_provider.dart` | new（stat + mime + Range 流） |
| `app/lib/router/app_router.dart` | 加路由 |
| `app/assets/i18n/strings_en.i18n.json` | 加 key |
| `app/assets/i18n/strings_zh.i18n.json` | 加 key |

## 5. Design

### 5.1 Range HTTP client

`RangeHttpClient` 包装 `package:http`：

```dart
class RangeHttpClient {
  Future<StreamController<List<int>>> openRange({
    required String url,
    required int start,
    int? end,
  });

  Future<int> contentLength(String url);
  Future<({int size, String mime, bool supportsRange})> head(String url);
}
```

服务端 `/download` 已经支持 206 Range（T-003 实现）。

### 5.2 视频预览

```dart
class VideoPreviewPage extends StatefulWidget {
  final FsEntryDto entry;
  final String peerFingerprint;
}

class _State extends State<VideoPreviewPage> {
  late VideoPlayerController _ctl;

  @override
  void initState() {
    final url = buildRangeUrl(peer: peer, path: entry.path);
    _ctl = VideoPlayerController.networkUrl(
      Uri.parse(url),
      httpHeaders: {'Range': 'bytes=0-'},   // 全量预加载
    );
    _ctl.initialize().then((_) => setState((){}));
  }
}
```

Range 拖动：`_ctl.seekTo` 时由 video_player 内部发新 Range 请求。

### 5.3 图片预览

```dart
class ImagePreviewPage extends StatefulWidget {
  final List<FsEntryDto> entries;     // 当前目录所有 image/*
  final int initialIndex;
}

PageView.builder(
  controller: PageController(initialPage: widget.initialIndex),
  itemBuilder: (ctx, i) {
    final entry = widget.entries[i];
    return InteractiveViewer(
      child: Image.network(
        buildFullUrl(peer: peer, path: entry.path),
        headers: {'Authorization': '...'},  // 客户端证书由 isolate 注入
      ),
    );
  },
);
```

### 5.4 音频预览 + 锁屏

`just_audio` 自带 `AudioHandler`，挂上 `MediaSession`：

```dart
final player = AudioPlayer();
await player.setAudioSource(
  ProgressiveAudioSource(Uri.parse(url), headers: {'Range': 'bytes=0-'}),
);
```

## 6. UI / Interaction

**图片**：

```
┌────────────────────────┐
│ ← IMG_0001.jpg  ⤓     │
│ ┌────────────────────┐ │
│ │                    │ │
│ │      [图片]         │ │
│ │                    │ │
│ │                    │ │
│ └────────────────────┘ │
│      1/50              │
└────────────────────────┘
```

**视频**：

```
┌────────────────────────┐
│ ← travel.mp4           │
│ ┌────────────────────┐ │
│ │      ▶            │ │
│ └────────────────────┘ │
│ ━━━━━━●───────── 30%  │
└────────────────────────┘
```

## 7. Test plan

### 单元

- `range_http_client_parses_206`
- `range_http_client_handles_416`
- `video_url_contains_path`
- `image_url_contains_path`

### Widget

- `image_preview_swipes_to_next`
- `image_preview_double_tap_zoom`
- `video_preview_seek_updates_range`
- `audio_preview_shows_lock_screen_metadata`（mock MediaSession）

### 集成

mock RangeHttpClient，验证：拖动到 80% → 收到 Range bytes=N- → 播放位置正确

## 8. Acceptance criteria

- [ ] AC-5：视频从 30s 拖到 60s 无卡顿
- [ ] 图片全屏横滑流畅
- [ ] 音频锁屏可控制
- [ ] 网络断开时显示重试按钮

## 9. Risks / Notes

- `video_player` 在 iOS 上对 HTTPS 自签证书支持有限；沿用现有 `event.certFingerprint` 信任机制
- `just_audio` 在 Android 上需要 `FOREGROUND_SERVICE` 权限；沿用 T-013 框架
- 大图加载用 `cacheWidth/cacheHeight` 限制内存

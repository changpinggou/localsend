# T-009: 移动端文件下载到本地

> Phase: P1 — MVP
> Priority: P0
> Estimate: 2d
> Dependencies: T-003、T-008
> Spec: REQUIREMENTS.md §3.3.2 F-C-7、§5.2、§7 AC-5
> Owner: Client

## 1. Background

MVP 必须让移动端能把挂载端的文件保存到本地。下载需要走挂载端的 `/api/localsend/v2/fs/download?path=...` Range 端点，并支持：

- iOS：保存到相册 / 保存到 Files
- Android：保存到下载目录 / 通过 SAF 选目录
- macOS：保存到下载目录 / 用户指定目录

## 2. Goal

- 在文件列表/网格点击文件 → 弹出底部 sheet（iOS）/侧栏（macOS）
- 选项：`保存到相册` / `保存到 Files` / `仅预览`（预览是 T-023 范围，本工单只到下载）
- 大文件走后台上传/下载（`flutter_foreground_task` 沿用 T-013）
- 下载支持 Range 拖动（虽是下载而非播放，但移动端读取流程需要先 `HEAD` 拿到 size）

## 3. Scope

### In scope
- 下载请求 client（带 Range、Retry、Cancel token）
- 移动端保存 API 包装
- 后台任务（T-013 范围）
- 单测 / widget test

### Out of scope
- 媒体预览（→ T-023）
- 后台上传 worker 框架（→ T-013）

## 4. Files to create / modify

| Path | Change |
|------|--------|
| `packages/localsend_isolates/lib/src/task/fs_download_task.dart` | new |
| `packages/localsend_isolates/lib/src/isolate/child/fs_download_isolate.dart` | new |
| `packages/localsend_isolates/lib/src/isolate/parent/actions.dart` | modify：加 `FsDownloadAction` |
| `app/lib/provider/network/fs/fs_download_provider.dart` | new |
| `app/lib/util/save_to_gallery.dart` | new（沿用 `gal`） |
| `app/lib/util/save_to_files.dart` | new（`file_selector`） |
| `app/lib/pages/remote_browser/widgets/file_action_sheet.dart` | new |
| `app/lib/pages/remote_browser/remote_browser_page.dart` | modify：点击文件弹出 sheet |
| `app/assets/i18n/strings_en.i18n.json` | 加 key |
| `app/assets/i18n/strings_zh.i18n.json` | 加 key |

## 5. Design

### 5.1 Download task

```dart
class FsDownloadRequest {
  final String peerFingerprint;
  final String path;
  final int? rangeStart;     // null = full
  final int? rangeEnd;
  final String sessionId;    // 关联 UI 进度
}

class FsDownloadEvent {
  final String sessionId;
  final int transferred;
  final int? total;          // null = 未知
  final String? error;
  final String? savedLocalPath;  // 完成时
}
```

通过 FRB 调 `rust_lib_localsend_app::fs::download(...)`，Rust 端走 `reqwest` 流式下载（AGENTS.md 已说明 server 用 Rust，client 也走 Rust 复用 TLS 配置）。

### 5.2 保存到相册

- iOS：先存到临时目录 → `gal.SaveImageToAlbum`
- Android：先存到 cache → `gal.SaveImageToAlbum`
- 视频 / 文档：拒绝"保存到相册"，提示走 Files

### 5.3 保存到 Files

- iOS：UIDocumentPickerViewController（`file_selector` 已声明在 `app/pubspec.yaml`）
- Android：ACTION_CREATE_DOCUMENT（`file_selector`）
- macOS：NSSavePanel（`file_selector`）

## 6. UI / Interaction

```
┌────────────────────────┐
│ IMG_0001.jpg           │
├────────────────────────┤
│ 保存到相册              │ ← 按钮（仅 image/*）
│ 保存到 Files           │
│ 仅预览                  │ ← 跳转 T-023（v1 显示 "即将推出"）
│ 取消                    │
└────────────────────────┘
```

## 7. Test plan

### 单元

- `fs_download_provider_emits_progress`
- `fs_download_provider_handles_cancel`
- `save_to_gallery_rejects_video`
- `file_action_sheet_shows_only_image_options_for_image`

### 集成

mock FRB 通道，验证：点击文件 → 弹 sheet → 选保存到 Files → mock 完成事件 → 状态更新。

## 8. Acceptance criteria

- [ ] 图片保存到相册成功（手动验证 iOS + Android）
- [ ] 任意文件保存到 Files 成功
- [ ] 取消时连接立即关闭，状态变 cancelled
- [ ] 进度条随 transferred/total 更新
- [ ] 大文件（≥ 100 MB）下载中途不爆内存

## 9. Risks / Notes

- 不要把 FRB channel 阻塞在主线程；event 走 isolate 流
- 保存到相册的 `gal` 在 Android 上需要权限，沿用现有 `permission_handler` 框架
- 进度事件频率限制：建议每 200ms 一次，避免 UI rebuild 过频

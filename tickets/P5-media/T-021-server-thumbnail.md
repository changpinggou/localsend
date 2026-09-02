# T-021: Server 缩略图端点

> Phase: P5 — Media
> Priority: P0
> Estimate: 3d
> Dependencies: T-003
> Spec: REQUIREMENTS.md §3.2.4 F-S-11/12、§7 AC-6
> Owner: Server

## 1. Background

直接拉 20MB 原始 JPEG 渲染列表会卡顿。服务端在 GET /thumbnail 把图缩到 128×128 编码为 WebP，v1 不做视频缩略图（用占位图）。

## 2. Goal

- `GET /api/localsend/v2/fs/thumbnail?path=&w=&h=` 端点
- 用 `image` crate 解码（jpg/png/webp/bmp/gif）+ `webp` crate 编码
- macOS 上用 `ImageIO` 解码 HEIC
- 缩放用 Lanczos3
- EXIF orientation 自动校正
- 缓存：内存 LRU（key = (path, w, h)），可关
- size 上限：`thumbnail_max_dim` 默认 200，超过立即 400

## 3. Scope

### In scope
- 端点
- 解码（4 种常见 + HEIC macOS）
- 编码 WebP
- LRU 缓存
- size 限制

### Out of scope
- 视频缩略图（→ 后续 v2 引入 ffmpeg）
- RAW 缩略图（DNG / CR2）→ 返回 415 placeholder
- 持久化缓存

## 4. Files to create / modify

| Path | Change |
|------|--------|
| `packages/core/src/fs/thumbnail.rs` | new |
| `packages/core/src/fs/rest.rs` | extend：handle_thumbnail |
| `packages/core/Cargo.toml` | 加 `image` (Lanczos3 + webp), `webp`, `lru` 已有 |
| `packages/core/src/fs/tests/thumbnail_test.rs` | new |
| `packages/core/src/fs/tests/fixtures/sample.jpg` | new（小测试图） |

## 5. Design

### 5.1 端点

```rust
#[derive(Deserialize)]
struct ThumbnailParams {
    path: String,
    #[serde(default = "default_thumb_w")]
    w: u32,        // 128
    #[serde(default = "default_thumb_h")]
    h: u32,        // 128
}

async fn handle_thumbnail(
    State(state): State<Arc<FsState>>,
    Query(p): Query<ThumbnailParams>,
) -> Result<Response, FsError>;
```

### 5.2 解码

```rust
pub fn decode_image(path: &Path) -> Result<DynamicImage, ThumbnailError> {
    let ext = path.extension().and_then(|s| s.to_str()).unwrap_or("");
    match ext.to_ascii_lowercase().as_str() {
        "jpg" | "jpeg" | "png" | "bmp" | "gif" | "webp" => {
            image::open(path).map_err(Into::into)
        }
        #[cfg(target_os = "macos")]
        "heic" | "heif" => decode_heic_imageio(path),
        "dng" | "cr2" | "nef" | "arw" => Err(ThumbnailError::Unsupported),
        _ => Err(ThumbnailError::Unsupported),
    }
}
```

### 5.3 缩放与编码

```rust
pub fn make_thumbnail(img: DynamicImage, w: u32, h: u32) -> Vec<u8> {
    let resized = img.resize(w, h, image::imageops::Lanczos3);
    let rgba = resized.to_rgba8();
    let encoder = webp::Encoder::from_rgba(rgba.as_raw(), rgba.width(), rgba.height());
    let memory = encoder.encode(75.0);
    memory.to_vec()
}
```

### 5.4 LRU 缓存

```rust
pub struct ThumbnailCache {
    inner: Mutex<LruCache<(PathBuf, u32, u32), Arc<Vec<u8>>>>,
    max_bytes: usize,
}
```

- key = `(canonical_path, w, h)`
- value = `Arc<Vec<u8>>` 编码后 WebP
- 缓存大小 = 100 MB（可配）
- 命中返回 `Content-Type: image/webp` + `Cache-Control: public, max-age=3600`

### 5.5 EXIF orientation

读取 EXIF 0x0112 tag，应用旋转后再缩放。`image::open` 不自动处理，所以需要先用 `kamadak-exif` 读 tag。

## 6. UI / Interaction

不在本工单。

## 7. Test plan

### 单元

- `thumbnail_decodes_jpeg`
- `thumbnail_decodes_png`
- `thumbnail_decodes_heic_macos`
- `thumbnail_resizes_to_requested_dim`
- `thumbnail_rejects_dim_over_limit`
- `thumbnail_cache_hit`
- `thumbnail_cache_eviction`
- `thumbnail_returns_unsupported_for_dng`
- `thumbnail_corrects_exif_orientation`（用含 EXIF 的 fixture）

### 性能

- 1000 次请求平均 ≤ 150 ms（AC-6）；缓存命中 ≤ 5 ms

## 8. Acceptance criteria

- [ ] 4 种常见格式解码 + 缩放 + WebP 编码
- [ ] macOS HEIC 解码
- [ ] LRU 缓存命中
- [ ] size 超过 200 立即 400
- [ ] 不支持格式返回 415 + placeholder
- [ ] 性能 AC-6

## 9. Risks / Notes

- `webp` crate 与 `image` crate 版本需兼容；固定版本
- HEIC 用 ImageIO 走 `CoreGraphics` FFI，注意内存释放
- 缓存放在 `FsState` 内，单进程；多进程挂载端场景不在 v1
- 不缓存的扩展名（`dng` 等）也走相同路径，placeholder 也要缓存

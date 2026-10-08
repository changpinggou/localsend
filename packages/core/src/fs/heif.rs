//! System-framework decoding for HEIC / AVIF images.
//!
//! The `image` crate (jpeg/png/webp features only) cannot decode Apple's
//! HEIC container (HEVC intra-frame coding — patent-encumbered, no Rust
//! decoder worth its dependency tree). On macOS the system ImageIO
//! framework decodes it natively, so `generate_thumbnail` falls back to
//! [`decode_heif`] when the bytes look like a HEIF container and the
//! crate decoder failed.
//!
//! [`CGImageSourceCreateThumbnailAtIndex`] does the heavy lifting: it
//! decodes straight to a small image (`kCGImageSourceThumbnailMaxPixelSize`)
//! and applies the EXIF orientation (`kCGImageSourceCreateThumbnailWithTransform`),
//! so portrait iPhone photos come out upright. The raw FFI keeps the
//! dependency tree unchanged — the frameworks are linked via `#[link]`
//! attributes, no crate is added.
//!
//! On Windows the bundled libheif + libde265 decode HEIC natively (see
//! [`libheif::decode_via_libheif`], raw C FFI — same no-crate policy; the
//! static libraries are compiled from the vendored `support/submodules/`
//! checkouts by `build.rs`, so no Microsoft Store "HEIF Image Extensions"
//! / HEVC codec is needed). It decodes the file's embedded thumbnail item
//! — a single small HEVC frame instead of the full tile grid — and applies
//! the container's `irot`/`imir` transformations itself, so portrait
//! iPhone photos come out upright.
//!
//! Anything libheif cannot handle (AVIF without an AV1 decoder, or a
//! corrupt container) falls back to the Windows Imaging Component (see
//! [`wic::decode_via_wic`], raw COM FFI): a memory `IStream` feeds
//! `IWICBitmapDecoder`, an optional `IWICBitmapScaler` caps the long edge
//! before pixels are allocated, an `IWICFormatConverter` normalizes to
//! 32bpp RGBA, and the EXIF orientation is read from the frame's metadata
//! query reader and applied to the pixel buffer in Rust
//! ([`apply_exif_orientation`]) — unlike ImageIO, Microsoft's HEIF decoder
//! does not bake it into the pixels. That path still needs the store
//! codecs; its error says so when they are missing.
//!
//! On other targets [`decode_heif`] always fails and the caller keeps
//! the placeholder-icon behaviour.

/// Detects a HEIF/AVIF container by ISO-BMFF magic bytes.
///
/// Layout: 4-byte box size, `"ftyp"`, 4-byte major brand. iPhone photos
/// use `heic`/`heix`/`mif1` (with a HEVC item); AVIF uses `avif`/`avis`.
pub(crate) fn is_heif_container(bytes: &[u8]) -> bool {
    bytes.len() >= 12
        && &bytes[4..8] == b"ftyp"
        && matches!(
            &bytes[8..12],
            b"heic"
                | b"heix"
                | b"hevc"
                | b"hevx"
                | b"heim"
                | b"heis"
                | b"hevm"
                | b"hevs"
                | b"mif1"
                | b"msf1"
                | b"avif"
                | b"avis"
        )
}

/// Decodes a HEIF/AVIF image to a [`image::DynamicImage`], downscaled so
/// the long edge is at most `max_dim` (orientation already applied).
///
/// Errors carry a human-readable message; the caller turns them into a
/// `400` like any other undecodable image.
#[cfg_attr(not(any(target_os = "macos", target_os = "windows")), allow(unused_variables))]
pub(crate) fn decode_heif(bytes: &[u8], max_dim: u32) -> Result<image::DynamicImage, String> {
    #[cfg(target_os = "macos")]
    {
        decode_via_imageio(bytes, max_dim)
    }
    #[cfg(target_os = "windows")]
    {
        // libheif/libde265 handles iPhone-style HEIC without any store
        // codec; WIC stays as the fallback for what it cannot decode
        // (AVIF, containers libheif rejects).
        decode_via_libheif(bytes, max_dim).or_else(|libheif_error| {
            tracing::debug!(
                event = "fs.heif.libheif.fallback",
                error = %libheif_error,
                "libheif decode failed; falling back to WIC"
            );
            decode_via_wic(bytes, max_dim)
        })
    }
    #[cfg(not(any(target_os = "macos", target_os = "windows")))]
    {
        Err("HEIF/AVIF decoding is only supported on macOS and Windows".into())
    }
}

#[cfg(target_os = "macos")]
mod imageio {
    use std::os::raw::c_void;

    // Opaque CF/CG types — only ever passed around as pointers.
    type CFAllocatorRef = *const c_void;
    type CFStringRef = *const c_void;
    type CFBooleanRef = *const c_void;
    type CFNumberRef = *const c_void;
    type CFDictionaryRef = *const c_void;
    type CFMutableDictionaryRef = *mut c_void;
    type CGDataProviderRef = *const c_void;
    type CGImageSourceRef = *const c_void;
    type CGImageRef = *const c_void;
    type CGColorSpaceRef = *const c_void;
    type CGContextRef = *mut c_void;

    /// `kCFNumberIntType` — the value passed to `CFNumberCreate` is `c_int`.
    const K_CF_NUMBER_INT_TYPE: isize = 9;
    /// `kCGImageAlphaPremultipliedLast`.
    const K_CG_IMAGE_ALPHA_PREMULTIPLIED_LAST: u32 = 1;
    /// `kCGBitmapByteOrder32Big` — forces RGBA byte order on either endianness.
    const K_CG_BITMAP_BYTE_ORDER_32_BIG: u32 = 4 << 12;

    #[repr(C)]
    struct CGPoint {
        x: f64,
        y: f64,
    }

    #[repr(C)]
    struct CGSize {
        width: f64,
        height: f64,
    }

    #[repr(C)]
    struct CGRect {
        origin: CGPoint,
        size: CGSize,
    }

    /// Layout of `CFDictionaryKeyCallBacks` (CFIndex = isize, four fn
    /// pointers). We only pass pointers to the framework-provided statics.
    #[repr(C)]
    struct CFDictionaryKeyCallBacks {
        version: isize,
        retain: *const c_void,
        release: *const c_void,
        copy_description: *const c_void,
        equal: *const c_void,
        hash: *const c_void,
    }

    type CFDictionaryValueCallBacks = CFDictionaryKeyCallBacks;

    #[link(name = "CoreFoundation", kind = "framework")]
    extern "C" {
        static kCFBooleanTrue: CFBooleanRef;
        static kCFTypeDictionaryKeyCallBacks: CFDictionaryKeyCallBacks;
        static kCFTypeDictionaryValueCallBacks: CFDictionaryValueCallBacks;

        fn CFDictionaryCreateMutable(
            allocator: CFAllocatorRef,
            capacity: isize,
            key_callbacks: *const CFDictionaryKeyCallBacks,
            value_callbacks: *const CFDictionaryValueCallBacks,
        ) -> CFMutableDictionaryRef;
        fn CFDictionarySetValue(dict: CFMutableDictionaryRef, key: *const c_void, value: *const c_void);
        fn CFNumberCreate(allocator: CFAllocatorRef, number_type: isize, value_ptr: *const c_void) -> CFNumberRef;
        fn CFRelease(cf: *const c_void);
    }

    #[link(name = "ImageIO", kind = "framework")]
    extern "C" {
        static kCGImageSourceCreateThumbnailFromImageAlways: CFStringRef;
        static kCGImageSourceCreateThumbnailWithTransform: CFStringRef;
        static kCGImageSourceThumbnailMaxPixelSize: CFStringRef;

        fn CGImageSourceCreateWithDataProvider(provider: CGDataProviderRef, options: CFDictionaryRef)
            -> CGImageSourceRef;
        fn CGImageSourceCreateThumbnailAtIndex(source: CGImageSourceRef, index: usize, options: CFDictionaryRef)
            -> CGImageRef;
    }

    #[link(name = "CoreGraphics", kind = "framework")]
    extern "C" {
        fn CGDataProviderCreateWithData(
            info: *mut c_void,
            data: *const c_void,
            size: isize,
            release_data: *const c_void,
        ) -> CGDataProviderRef;
        fn CGImageGetWidth(image: CGImageRef) -> usize;
        fn CGImageGetHeight(image: CGImageRef) -> usize;
        fn CGColorSpaceCreateDeviceRGB() -> CGColorSpaceRef;
        fn CGBitmapContextCreate(
            data: *mut c_void,
            width: usize,
            height: usize,
            bits_per_component: usize,
            bytes_per_row: usize,
            space: CGColorSpaceRef,
            bitmap_info: u32,
        ) -> CGContextRef;
        fn CGContextDrawImage(context: CGContextRef, rect: CGRect, image: CGImageRef);
        fn CGBitmapContextGetData(context: CGContextRef) -> *mut c_void;
        fn CGBitmapContextGetBytesPerRow(context: CGContextRef) -> usize;
    }

    /// Decode via `CGImageSourceCreateThumbnailAtIndex` + a bitmap-context
    /// blit. Every acquired CF/CG object is released on the single exit
    /// path; the `Err` returns before an object is acquired stay leak-free
    /// by construction.
    pub(super) fn decode_via_imageio(bytes: &[u8], max_dim: u32) -> Result<image::DynamicImage, String> {
        if bytes.len() > i32::MAX as usize {
            return Err("HEIF file too large".into());
        }
        tracing::debug!(
            event = "fs.heif.imageio.entry",
            len = bytes.len(),
            max_dim,
            "decoding HEIF via system ImageIO"
        );

        unsafe {
            // `release_data` is NULL: the provider must not outlive `bytes`,
            // which holds for the whole function.
            let provider = CGDataProviderCreateWithData(
                std::ptr::null_mut(),
                bytes.as_ptr() as *const c_void,
                bytes.len() as isize,
                std::ptr::null(),
            );
            if provider.is_null() {
                return Err("CGDataProviderCreateWithData failed".into());
            }

            let options = CFDictionaryCreateMutable(
                std::ptr::null(),
                3,
                &kCFTypeDictionaryKeyCallBacks,
                &kCFTypeDictionaryValueCallBacks,
            );
            let max_pixel_size: i32 = max_dim.min(i32::MAX as u32) as i32;
            let pixel_size_number = CFNumberCreate(
                std::ptr::null(),
                K_CF_NUMBER_INT_TYPE,
                &max_pixel_size as *const i32 as *const c_void,
            );
            let decoded = if options.is_null() || pixel_size_number.is_null() {
                None
            } else {
                CFDictionarySetValue(
                    options,
                    kCGImageSourceCreateThumbnailFromImageAlways as *const c_void,
                    kCFBooleanTrue as *const c_void,
                );
                CFDictionarySetValue(
                    options,
                    kCGImageSourceCreateThumbnailWithTransform as *const c_void,
                    kCFBooleanTrue as *const c_void,
                );
                CFDictionarySetValue(
                    options,
                    kCGImageSourceThumbnailMaxPixelSize as *const c_void,
                    pixel_size_number as *const c_void,
                );

                let source = CGImageSourceCreateWithDataProvider(provider, options);
                if source.is_null() {
                    None
                } else {
                    let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options);
                    CFRelease(source);
                    if image.is_null() {
                        None
                    } else {
                        Some(image)
                    }
                }
            };

            CFRelease(pixel_size_number);
            CFRelease(options);
            CFRelease(provider);

            let cg_image = decoded.ok_or_else(|| "ImageIO failed to decode HEIF image".to_string())?;

            let result = render_cg_image(cg_image);
            CFRelease(cg_image);
            result
        }
    }

    /// Blits a `CGImage` into an RGBA8888 bitmap context and copies the
    /// pixels into a `RgbaImage`. Row stride may exceed `width * 4`
    /// (padding), so rows are copied individually.
    unsafe fn render_cg_image(cg_image: CGImageRef) -> Result<image::DynamicImage, String> {
        let width = CGImageGetWidth(cg_image);
        let height = CGImageGetHeight(cg_image);
        if width == 0 || height == 0 || width > 100_000 || height > 100_000 {
            return Err(format!("implausible HEIF dimensions: {width}x{height}"));
        }

        let color_space = CGColorSpaceCreateDeviceRGB();
        if color_space.is_null() {
            return Err("CGColorSpaceCreateDeviceRGB failed".into());
        }

        let context = CGBitmapContextCreate(
            std::ptr::null_mut(),
            width,
            height,
            8,
            width * 4,
            color_space,
            K_CG_BITMAP_BYTE_ORDER_32_BIG | K_CG_IMAGE_ALPHA_PREMULTIPLIED_LAST,
        );
        CFRelease(color_space);
        if context.is_null() {
            return Err("CGBitmapContextCreate failed".into());
        }

        CGContextDrawImage(
            context,
            CGRect {
                origin: CGPoint { x: 0.0, y: 0.0 },
                size: CGSize {
                    width: width as f64,
                    height: height as f64,
                },
            },
            cg_image,
        );

        let stride = CGBitmapContextGetBytesPerRow(context);
        let base = CGBitmapContextGetData(context) as *const u8;
        let mut pixels = Vec::with_capacity(width * height * 4);
        if base.is_null() {
            CFRelease(context);
            return Err("CGBitmapContextGetData failed".into());
        }
        for row in 0..height {
            pixels.extend_from_slice(std::slice::from_raw_parts(base.add(row * stride), width * 4));
        }
        CFRelease(context);

        image::RgbaImage::from_raw(width as u32, height as u32, pixels)
            .map(image::DynamicImage::ImageRgba8)
            .ok_or_else(|| "HEIF pixel buffer size mismatch".into())
    }
}

#[cfg(target_os = "macos")]
use imageio::decode_via_imageio;
#[cfg(target_os = "windows")]
use libheif::decode_via_libheif;
#[cfg(target_os = "windows")]
use wic::decode_via_wic;

/// Applies the EXIF orientation (tag 274, values 1–8) to an RGBA buffer.
///
/// Each *output* pixel is filled from the *stored* pixel it originates
/// from (`sample`); for the 90° rotations (5–8) the stored width/height
/// are the pre-transform ones and swap in the output. macOS bakes the
/// orientation into the pixels inside ImageIO
/// (`kCGImageSourceCreateThumbnailWithTransform`), so this only runs on
/// the Windows WIC path — plus unit tests everywhere.
#[cfg(any(target_os = "windows", test))]
fn apply_exif_orientation(img: image::RgbaImage, orientation: u16) -> image::RgbaImage {
    let (sw, sh) = (img.width(), img.height());
    // The arms return different closure types — coerce to fn pointers.
    let (dw, dh, sample): (u32, u32, fn(u32, u32, u32, u32) -> (u32, u32)) = match orientation {
        2 => (sw, sh, |x: u32, y: u32, w: u32, _: u32| (w - 1 - x, y)),
        3 => (sw, sh, |x: u32, y: u32, w: u32, h: u32| (w - 1 - x, h - 1 - y)),
        4 => (sw, sh, |x: u32, y: u32, _: u32, h: u32| (x, h - 1 - y)),
        5 => (sh, sw, |x: u32, y: u32, _: u32, _: u32| (y, x)),
        6 => (sh, sw, |x: u32, y: u32, _: u32, h: u32| (y, h - 1 - x)),
        7 => (sh, sw, |x: u32, y: u32, w: u32, h: u32| (w - 1 - y, h - 1 - x)),
        8 => (sh, sw, |x: u32, y: u32, w: u32, _: u32| (w - 1 - y, x)),
        // 1 = identity; anything else is corrupt metadata → keep as stored.
        _ => return img,
    };
    let raw = img.into_raw();
    let mut out = vec![0u8; dw as usize * dh as usize * 4];
    for y in 0..dh {
        for x in 0..dw {
            let (sx, sy) = sample(x, y, sw, sh);
            let src = ((sy * sw + sx) * 4) as usize;
            let dst = ((y * dw + x) * 4) as usize;
            out[dst..dst + 4].copy_from_slice(&raw[src..src + 4]);
        }
    }
    image::RgbaImage::from_raw(dw, dh, out).expect("orientation output buffer size mismatch")
}

/// Long-edge cap for the WIC path: integer ceil-scaling that never
/// produces a zero edge and never upscales.
#[cfg(any(target_os = "windows", test))]
fn fit(width: u32, height: u32, max_dim: u32) -> (u32, u32) {
    let long = width.max(height);
    if long == 0 || max_dim == 0 || long <= max_dim {
        return (width, height);
    }
    // ceil(v * max_dim / long) in integers — no float drift, no MSRV risk.
    let scale = |v: u32| (((v as u64 * max_dim as u64) + long as u64 - 1) / long as u64) as u32;
    (scale(width).max(1), scale(height).max(1))
}

/// HEIC decoding via the bundled libheif + libde265, driven through raw C
/// FFI (the `imageio` / `wic` approach: no Rust wrapper crate; the static
/// libraries are compiled from the vendored `support/submodules/` checkouts
/// by `build.rs`).
///
/// Decoding prefers the file's embedded thumbnail item (Apple's "reduced
/// codec image": one small HEVC frame, decodes in ~10 ms, instead of the
/// full 40+ tile grid of the primary image) and falls back to the primary
/// image when there is no thumbnail or the thumbnail itself fails.
/// `irot`/`imir` transformations are applied by libheif when the decode
/// options are NULL, so portrait iPhone photos come out upright without
/// manual EXIF handling — the WIC path's [`apply_exif_orientation`] is not
/// needed here.
#[cfg(target_os = "windows")]
mod libheif {
    use std::ffi::CStr;
    use std::os::raw::{c_char, c_int, c_void};
    use std::sync::OnceLock;

    /// `heif_colorspace_RGB` — request an RGB-family output.
    const HEIF_COLORSPACE_RGB: c_int = 1;
    /// `heif_chroma_interleaved_RGBA` — packed 8-bit RGBA output.
    const HEIF_CHROMA_INTERLEAVED_RGBA: c_int = 11;
    /// `heif_channel_interleaved` — the single plane of an interleaved image.
    const HEIF_CHANNEL_INTERLEAVED: c_int = 10;
    const HEIF_ERROR_OK: c_int = 0;

    /// Layout of libheif's `heif_error` return struct: an error code, a
    /// sub code, and a NUL-terminated message pointing into libheif-owned
    /// static storage (valid until the next call).
    #[repr(C)]
    struct HeifError {
        code: c_int,
        subcode: c_int,
        message: *const c_char,
    }

    #[link(name = "heif")]
    extern "C" {
        fn heif_init(config: *const c_void) -> HeifError;
        fn heif_context_alloc() -> *mut c_void;
        fn heif_context_free(context: *mut c_void);
        /// Keeps a reference into `mem` instead of copying — the buffer
        /// must outlive the context, which [`decode_via_libheif`] honours
        /// by freeing the context before its `&[u8]` borrow ends.
        fn heif_context_read_from_memory_without_copy(
            context: *mut c_void,
            mem: *const c_void,
            size: usize,
            reading_options: *const c_void,
        ) -> HeifError;
        fn heif_context_get_primary_image_handle(context: *mut c_void, out: *mut *mut c_void) -> HeifError;
        fn heif_image_handle_get_width(handle: *mut c_void) -> c_int;
        fn heif_image_handle_get_height(handle: *mut c_void) -> c_int;
        fn heif_image_handle_get_number_of_thumbnails(handle: *mut c_void) -> c_int;
        /// Takes a caller-allocated array and returns how many item IDs
        /// were written (not an index-based accessor).
        fn heif_image_handle_get_list_of_thumbnail_IDs(handle: *mut c_void, ids: *mut u32, count: c_int) -> c_int;
        /// Note: the second parameter is a thumbnail *item ID* from
        /// [`heif_image_handle_get_list_of_thumbnail_IDs`], not an index.
        fn heif_image_handle_get_thumbnail(main_image_handle: *mut c_void, thumbnail_id: u32, out: *mut *mut c_void) -> HeifError;
        /// With `options = NULL`, container transformations (`irot` /
        /// `imir`) are applied to the decoded pixels.
        fn heif_decode_image(
            in_handle: *mut c_void,
            out_img: *mut *mut c_void,
            colorspace: c_int,
            chroma: c_int,
            decoding_options: *const c_void,
        ) -> HeifError;
        fn heif_image_get_width(image: *mut c_void, channel: c_int) -> c_int;
        fn heif_image_get_height(image: *mut c_void, channel: c_int) -> c_int;
        fn heif_image_get_plane_readonly(image: *mut c_void, channel: c_int, out_stride: *mut c_int) -> *const u8;
        fn heif_image_release(image: *mut c_void);
        fn heif_image_handle_release(handle: *mut c_void);
    }

    /// Releases a `heif_image_handle` on every exit path.
    struct HandleGuard(*mut c_void);

    impl HandleGuard {
        fn null() -> Self {
            HandleGuard(std::ptr::null_mut())
        }

        /// Runs an FFI call that fills `out` with a new handle; the
        /// handle is released when the guard drops, even on later errors.
        fn acquire(
            call: impl FnOnce(*mut *mut c_void) -> HeifError,
            what: &str,
        ) -> Result<Self, String> {
            let mut handle = std::ptr::null_mut();
            check(call(&mut handle), what)?;
            Ok(HandleGuard(handle))
        }
    }

    impl Drop for HandleGuard {
        fn drop(&mut self) {
            if !self.0.is_null() {
                unsafe { heif_image_handle_release(self.0) }
            }
        }
    }

    /// Releases a `heif_image` on every exit path.
    struct ImageGuard(*mut c_void);

    impl ImageGuard {
        fn null() -> Self {
            ImageGuard(std::ptr::null_mut())
        }
    }

    impl Drop for ImageGuard {
        fn drop(&mut self) {
            if !self.0.is_null() {
                unsafe { heif_image_release(self.0) }
            }
        }
    }

    fn check(error: HeifError, what: &str) -> Result<(), String> {
        if error.code == HEIF_ERROR_OK {
            Ok(())
        } else {
            Err(message_of(&error, what))
        }
    }

    fn message_of(error: &HeifError, what: &str) -> String {
        let detail = if error.message.is_null() {
            String::new()
        } else {
            unsafe { CStr::from_ptr(error.message).to_string_lossy().into_owned() }
        };
        if detail.is_empty() {
            format!("{what} failed")
        } else {
            format!("{what}: {detail}")
        }
    }

    /// `heif_init` ref-counts global decoder state; initialize it once per
    /// process and keep it for the process lifetime — the server keeps
    /// decoding thumbnails, so there is no point tearing it down.
    fn ensure_init() -> Result<(), String> {
        static INIT: OnceLock<Result<(), String>> = OnceLock::new();
        INIT.get_or_init(|| check(unsafe { heif_init(std::ptr::null()) }, "heif_init"))
            .clone()
    }

    /// Decode via libheif: context → bytes → primary handle → thumbnail
    /// handle (preferred) → RGB/RGBA decode → tightly packed RGBA buffer.
    pub(super) fn decode_via_libheif(bytes: &[u8], max_dim: u32) -> Result<image::DynamicImage, String> {
        ensure_init()?;
        if bytes.is_empty() {
            return Err("empty HEIF payload".into());
        }
        if bytes.len() > i32::MAX as usize {
            return Err("HEIF file too large".into());
        }
        tracing::debug!(
            event = "fs.heif.libheif.entry",
            len = bytes.len(),
            max_dim,
            "decoding HEIF via bundled libheif/libde265"
        );

        unsafe {
            let context = heif_context_alloc();
            if context.is_null() {
                return Err("heif_context_alloc failed".into());
            }
            // Free the context before `bytes`' borrow ends — the context
            // holds a reference into it (`*_without_copy`).
            let result = decode_with_context(context, bytes);
            heif_context_free(context);
            result
        }
    }

    /// The buffer behind `bytes` must outlive `context` (see
    /// [`decode_via_libheif`]).
    unsafe fn decode_with_context(context: *mut c_void, bytes: &[u8]) -> Result<image::DynamicImage, String> {
        check(
            heif_context_read_from_memory_without_copy(context, bytes.as_ptr().cast(), bytes.len(), std::ptr::null()),
            "heif_context_read_from_memory_without_copy",
        )?;

        let primary = HandleGuard::acquire(
            |out| heif_context_get_primary_image_handle(context, out),
            "heif_context_get_primary_image_handle",
        )?;
        let (primary_width, primary_height) =
            (heif_image_handle_get_width(primary.0), heif_image_handle_get_height(primary.0));

        // Prefer the embedded thumbnail item: one small HEVC frame beats
        // decoding the 48-megapixel tile grid and downscaling afterwards.
        let mut thumbnail = HandleGuard::null();
        if heif_image_handle_get_number_of_thumbnails(primary.0) > 0 {
            let mut ids = [0u32; 4];
            let count =
                heif_image_handle_get_list_of_thumbnail_IDs(primary.0, ids.as_mut_ptr(), ids.len() as c_int).max(0) as usize;
            if count > 0 {
                // A broken thumbnail must not fail the whole decode —
                // retry with the primary image below.
                thumbnail = HandleGuard::acquire(
                    |out| heif_image_handle_get_thumbnail(primary.0, ids[0], out),
                    "heif_image_handle_get_thumbnail",
                )
                .inspect_err(|error| {
                    tracing::warn!(
                        event = "fs.heif.libheif.thumbnail",
                        item_id = ids[0],
                        error = %error,
                        "thumbnail handle failed; decoding the primary image instead"
                    );
                })
                .unwrap_or_else(|_| HandleGuard::null());
            }
        }

        let target = if thumbnail.0.is_null() { &primary } else { &thumbnail };
        let mut image = ImageGuard::null();
        check(
            heif_decode_image(
                target.0,
                &mut image.0,
                HEIF_COLORSPACE_RGB,
                HEIF_CHROMA_INTERLEAVED_RGBA,
                std::ptr::null(),
            ),
            "heif_decode_image",
        )?;

        let width = heif_image_get_width(image.0, HEIF_CHANNEL_INTERLEAVED);
        let height = heif_image_get_height(image.0, HEIF_CHANNEL_INTERLEAVED);
        if width <= 0 || height <= 0 || width > 100_000 || height > 100_000 {
            return Err(format!("implausible HEIF dimensions: {width}x{height}"));
        }
        let mut stride = 0;
        let plane = heif_image_get_plane_readonly(image.0, HEIF_CHANNEL_INTERLEAVED, &mut stride);
        if plane.is_null() || stride < width * 4 {
            return Err("libheif returned an empty RGBA plane".into());
        }

        // Rows are stride-padded — repack them tightly for RgbaImage.
        let mut pixels = Vec::with_capacity(width as usize * height as usize * 4);
        for row in 0..height as usize {
            let start = plane.add(row * stride as usize);
            pixels.extend_from_slice(std::slice::from_raw_parts(start, width as usize * 4));
        }
        tracing::debug!(
            event = "fs.heif.libheif.decoded",
            primary_width,
            primary_height,
            width,
            height,
            embedded_thumbnail = !thumbnail.0.is_null(),
            "libheif decode finished"
        );
        image::RgbaImage::from_raw(width as u32, height as u32, pixels)
            .map(image::DynamicImage::ImageRgba8)
            .ok_or_else(|| "HEIF pixel buffer size mismatch".into())
    }
}

/// Windows Imaging Component decoding, driven through raw COM FFI (the
/// macOS approach: system framework, zero crate dependencies).
///
/// Every vtable slot index below was transcribed from `wincodec.h` (via
/// the faithful winapi 0.3.9 RIDL macros) — a wrong slot calls a
/// different method with different arguments and crashes, so positions
/// are spelled out in comments. Slots we don't call are `usize`
/// placeholders that exist only to keep the offsets right.
#[cfg(target_os = "windows")]
mod wic {
    use super::{apply_exif_orientation, fit};
    use std::os::raw::c_void;

    type Hresult = i32;
    type ReleaseFn = unsafe extern "system" fn(*mut c_void) -> u32;

    const COINIT_MULTITHREADED: u32 = 0;
    const S_OK: Hresult = 0;
    const S_FALSE: Hresult = 1;
    /// COM is already up with a different apartment model — WIC works in
    /// both, so we just skip our own `CoUninitialize` in that case.
    const RPC_E_CHANGED_MODE: Hresult = 0x8001_0106u32 as i32;
    const CLSCTX_INPROC_SERVER: u32 = 1;
    const GMEM_MOVEABLE: u32 = 0x0002;
    const WIC_DECODE_METADATA_CACHE_ON_DEMAND: u32 = 0;
    /// Enum order: NearestNeighbor=0, Linear=1, Cubic=2, **Fant=3**.
    const WIC_BITMAP_INTERPOLATION_MODE_FANT: u32 = 3;
    const WIC_BITMAP_DITHER_TYPE_NONE: u32 = 0;
    const WIC_BITMAP_PALETTE_TYPE_CUSTOM: u32 = 0;
    /// No codec claims this container — the "install HEIF extensions" case.
    const WINCODEC_ERR_COMPONENTNOTFOUND: Hresult = 0x8898_2F07u32 as i32;
    /// WIC's HEVC/AV1 decoders are Media Foundation transcoders: decoder
    /// *creation* succeeds even without the store codec, and the failure
    /// only surfaces from `CopyPixels` with this Media Foundation
    /// missing-codec code (observed on every HEIC request on a Windows
    /// machine without "HEVC Video Extensions").
    const MF_E_CODEC_MISSING: Hresult = 0xC00D_5212u32 as i32;
    const VT_I2: u16 = 2;
    const VT_I4: u16 = 3;
    const VT_UI2: u16 = 18;
    const VT_UI4: u16 = 19;

    #[allow(dead_code)]
    #[repr(C)]
    #[derive(Clone, Copy)]
    struct Guid {
        data1: u32,
        data2: u16,
        data3: u16,
        data4: [u8; 8],
    }

    // GUIDs transcribed from wincodec.h. The non-"2" factory works from
    // Windows 7 on; WICImagingFactory2 only adds Win8.1+ APIs we skip.
    const CLSID_WIC_IMAGING_FACTORY: Guid = Guid {
        data1: 0xcacaf262,
        data2: 0x9370,
        data3: 0x4615,
        data4: [0xa1, 0x3b, 0x9f, 0x55, 0x39, 0xda, 0x4c, 0x0a],
    };
    const IID_WIC_IMAGING_FACTORY: Guid = Guid {
        data1: 0xec5ec8a9,
        data2: 0xc395,
        data3: 0x4314,
        data4: [0x9c, 0x77, 0x54, 0xd7, 0xa9, 0x35, 0xff, 0x70],
    };
    const GUID_WIC_PIXEL_FORMAT_32BPP_RGBA: Guid = Guid {
        data1: 0xf5c7ad2d,
        data2: 0x6a8d,
        data3: 0x43dd,
        data4: [0xa7, 0xa8, 0xa2, 0x99, 0x35, 0x26, 0x1a, 0xe9],
    };

    /// `PROPVARIANT` — only the scalar payload matters here
    /// (`GetMetadataByName` on the EXIF orientation yields one of
    /// VT_I2/I4/UI2/UI4); the layout is 24 bytes: vartype, 3 reserved
    /// words, then the union.
    #[allow(dead_code)]
    #[repr(C)]
    struct PropVariant {
        vt: u16,
        _reserved: [u16; 3],
        value: [u8; 16],
    }

    /// The three `IUnknown` slots every COM vtable starts with. Slot 2 is
    /// the only one we ever call — `Release` on the raw interface pointer.
    #[allow(dead_code)]
    #[repr(C)]
    struct ComBase {
        _query_interface: usize, // 0
        _add_ref: usize,         // 1
        release: ReleaseFn,      // 2
    }

    /// `IWICImagingFactory` (slots after the IUnknown base):
    /// 3 CreateDecoderFromFilename, **4 CreateDecoderFromStream**,
    /// 5 CreateDecoderFromFileHandle, 6 CreateComponentInfo,
    /// 7 CreateDecoder, 8 CreateEncoder, 9 CreatePalette,
    /// **10 CreateFormatConverter**, **11 CreateBitmapScaler**.
    #[allow(dead_code)]
    #[repr(C)]
    struct FactoryVtbl {
        base: ComBase,
        _create_decoder_from_filename: usize, // 3
        create_decoder_from_stream: unsafe extern "system" fn(
            this: *mut c_void,
            stream: *mut c_void,
            vendor: *const Guid,
            metadata_options: u32,
            decoder: *mut *mut c_void,
        ) -> Hresult, // 4
        _create_decoder_from_file_handle: usize, // 5
        _create_component_info: usize,           // 6
        _create_decoder: usize,                  // 7
        _create_encoder: usize,                  // 8
        _create_palette: usize,                  // 9
        create_format_converter:
            unsafe extern "system" fn(this: *mut c_void, converter: *mut *mut c_void) -> Hresult, // 10
        create_bitmap_scaler:
            unsafe extern "system" fn(this: *mut c_void, scaler: *mut *mut c_void) -> Hresult, // 11
    }

    /// `IWICBitmapDecoder` — **`GetFrame` is the LAST method (slot 13)**,
    /// after GetFrameCount (12); calling slot 8 here would invoke
    /// GetMetadataQueryReader instead.
    #[allow(dead_code)]
    #[repr(C)]
    struct DecoderVtbl {
        base: ComBase,
        _query_capability: usize,       // 3
        _initialize: usize,             // 4
        _get_container_format: usize,   // 5
        _get_decoder_info: usize,       // 6
        _copy_palette: usize,           // 7
        _get_metadata_query_reader: usize, // 8
        _get_preview: usize,            // 9
        _get_color_contexts: usize,     // 10
        _get_thumbnail: usize,          // 11
        _get_frame_count: usize,        // 12
        get_frame:
            unsafe extern "system" fn(this: *mut c_void, index: u32, frame: *mut *mut c_void) -> Hresult, // 13
    }

    /// `IWICBitmapFrameDecode` — inherits `IWICBitmapSource` (3–7), then
    /// GetMetadataQueryReader at 8.
    #[allow(dead_code)]
    #[repr(C)]
    struct FrameDecodeVtbl {
        base: ComBase,
        get_size: unsafe extern "system" fn(this: *mut c_void, width: *mut u32, height: *mut u32) -> Hresult, // 3
        _get_pixel_format: usize,           // 4
        _get_resolution: usize,             // 5
        _copy_palette: usize,               // 6
        _copy_pixels: usize,                // 7
        get_metadata_query_reader:
            unsafe extern "system" fn(this: *mut c_void, reader: *mut *mut c_void) -> Hresult, // 8
    }

    /// `IWICBitmapScaler` — inherits 3–7, then
    /// `Initialize(pISource, uiWidth, uiHeight, mode)` at 8.
    #[allow(dead_code)]
    #[repr(C)]
    struct ScalerVtbl {
        base: ComBase,
        _get_size: usize,       // 3
        _get_pixel_format: usize, // 4
        _get_resolution: usize, // 5
        _copy_palette: usize,   // 6
        _copy_pixels: usize,    // 7
        initialize: unsafe extern "system" fn(
            this: *mut c_void,
            source: *mut c_void,
            width: u32,
            height: u32,
            mode: u32,
        ) -> Hresult, // 8
    }

    /// `IWICFormatConverter` — inherits 3–7 (we call GetSize/CopyPixels on
    /// the converter directly), then its own `Initialize` at 8.
    #[allow(dead_code)]
    #[repr(C)]
    struct ConverterVtbl {
        base: ComBase,
        get_size: unsafe extern "system" fn(this: *mut c_void, width: *mut u32, height: *mut u32) -> Hresult, // 3
        _get_pixel_format: usize, // 4
        _get_resolution: usize,   // 5
        _copy_palette: usize,     // 6
        copy_pixels: unsafe extern "system" fn(
            this: *mut c_void,
            rect: *const c_void, // WICRect, NULL = whole image
            stride: u32,
            buffer_size: u32,
            buffer: *mut u8,
        ) -> Hresult, // 7
        initialize: unsafe extern "system" fn(
            this: *mut c_void,
            source: *mut c_void,
            dst_format: *const Guid,
            dither: u32,
            palette: *const c_void,
            alpha_threshold_percent: f64,
            palette_translate: u32,
        ) -> Hresult, // 8
    }

    /// `IWICMetadataQueryReader` — 3 GetContainerFormat, 4 GetLocation,
    /// **5 GetMetadataByName**, 6 GetEnumerator.
    #[allow(dead_code)]
    #[repr(C)]
    struct QueryReaderVtbl {
        base: ComBase,
        _get_container_format: usize, // 3
        _get_location: usize,         // 4
        get_metadata_by_name:
            unsafe extern "system" fn(this: *mut c_void, name: *const u16, value: *mut PropVariant) -> Hresult, // 5
    }

    #[link(name = "ole32")]
    extern "system" {
        fn CoInitializeEx(reserved: *mut c_void, model: u32) -> Hresult;
        fn CoUninitialize();
        fn CoCreateInstance(
            clsid: *const Guid,
            outer: *mut c_void,
            cls_context: u32,
            iid: *const Guid,
            out: *mut *mut c_void,
        ) -> Hresult;
        fn PropVariantClear(value: *mut PropVariant) -> Hresult;
        fn CreateStreamOnHGlobal(global: *mut c_void, delete_on_release: i32, out: *mut *mut c_void) -> Hresult;
    }

    #[link(name = "kernel32")]
    extern "system" {
        fn GlobalAlloc(flags: u32, bytes: usize) -> *mut c_void;
        fn GlobalFree(block: *mut c_void) -> *mut c_void;
        fn GlobalLock(block: *mut c_void) -> *mut c_void;
        fn GlobalUnlock(block: *mut c_void) -> i32;
    }

    fn failed(hr: Hresult) -> bool {
        hr < 0
    }

    fn describe(hr: Hresult, what: &str) -> String {
        format!("{what} failed: 0x{hr:08X}")
    }

    fn wide(s: &str) -> Vec<u16> {
        s.encode_utf16().chain(std::iter::once(0)).collect()
    }

    /// Balances a successful `CoInitializeEx` with `CoUninitialize`.
    struct ComApartment {
        owns_init: bool,
    }

    impl Drop for ComApartment {
        fn drop(&mut self) {
            if self.owns_init {
                unsafe { CoUninitialize() }
            }
        }
    }

    /// Releases every COM object created during the decode, in reverse
    /// order, on the single exit path. Objects are released through
    /// vtable slot 2 (`IUnknown::Release`).
    #[derive(Default)]
    struct ComScope {
        objs: Vec<*mut c_void>,
    }

    impl ComScope {
        fn track(&mut self, obj: *mut c_void) {
            if !obj.is_null() {
                self.objs.push(obj);
            }
        }
    }

    impl Drop for ComScope {
        fn drop(&mut self) {
            for obj in self.objs.iter().rev() {
                unsafe {
                    let vtbl = &**(*obj as *mut *const ComBase);
                    (vtbl.release)(*obj);
                }
            }
        }
    }

    /// EXIF orientation (tag 274, 1–8) from the frame's metadata. Both
    /// query-path spellings appear in the wild for HEIF containers. Any
    /// miss degrades to `1` (sensor orientation) — a rotated thumbnail is
    /// much better than a failed decode.
    fn read_orientation(frame: *mut c_void) -> u16 {
        unsafe {
            let frame_vtbl = &**(frame as *mut *const FrameDecodeVtbl);
            let mut reader = std::ptr::null_mut();
            if failed((frame_vtbl.get_metadata_query_reader)(frame, &mut reader)) {
                return 1;
            }
            let reader_vtbl = &**(reader as *mut *const QueryReaderVtbl);
            let mut orientation = 0u16;
            for path in ["/app1/ifd/exif/{ushort=274}", "/ifd/exif/{ushort=274}"] {
                let mut value = PropVariant { vt: 0, _reserved: [0; 3], value: [0; 16] };
                let hr = (reader_vtbl.get_metadata_by_name)(reader, wide(path).as_ptr(), &mut value);
                if !failed(hr) {
                    tracing::debug!(
                        event = "fs.heif.wic.orientation",
                        query = %path,
                        vt = value.vt,
                        "EXIF orientation metadata found"
                    );
                    orientation = match value.vt {
                        VT_I2 => i16::from_le_bytes([value.value[0], value.value[1]]).max(0) as u16,
                        VT_I4 => i32::from_le_bytes(value.value[..4].try_into().unwrap()).max(0) as u16,
                        VT_UI2 => u16::from_le_bytes([value.value[0], value.value[1]]),
                        VT_UI4 => u32::from_le_bytes(value.value[..4].try_into().unwrap()).min(u16::MAX as u32) as u16,
                        _ => 0,
                    };
                }
                PropVariantClear(&mut value);
                if orientation != 0 {
                    break;
                }
            }
            (reader_vtbl.base.release)(reader);
            if (1..=8).contains(&orientation) { orientation } else { 1 }
        }
    }

    /// Decode via WIC: `CoCreateInstance(factory)` → memory `IStream` →
    /// decoder → frame → (scaler, when the long edge exceeds `max_dim`) →
    /// format converter (32bpp RGBA) → `CopyPixels`, then the EXIF
    /// orientation applied in Rust. Every created COM object is tracked
    /// in one scope and released on the way out; the `HGLOBAL` backing
    /// the stream is owned by the stream (`fDeleteOnRelease`).
    pub(super) fn decode_via_wic(bytes: &[u8], max_dim: u32) -> Result<image::DynamicImage, String> {
        if bytes.is_empty() {
            return Err("empty HEIF payload".into());
        }
        if bytes.len() > i32::MAX as usize {
            return Err("HEIF file too large".into());
        }
        tracing::debug!(
            event = "fs.heif.wic.entry",
            len = bytes.len(),
            max_dim,
            "decoding HEIF via Windows Imaging Component"
        );

        let init_hr = unsafe { CoInitializeEx(std::ptr::null_mut(), COINIT_MULTITHREADED) };
        if failed(init_hr) && init_hr != RPC_E_CHANGED_MODE {
            return Err(describe(init_hr, "CoInitializeEx"));
        }
        let _apartment = ComApartment { owns_init: init_hr == S_OK || init_hr == S_FALSE };
        let mut scope = ComScope::default();

        unsafe {
            let mut factory = std::ptr::null_mut();
            let hr = CoCreateInstance(
                &CLSID_WIC_IMAGING_FACTORY,
                std::ptr::null_mut(),
                CLSCTX_INPROC_SERVER,
                &IID_WIC_IMAGING_FACTORY,
                &mut factory,
            );
            if failed(hr) {
                return Err(describe(hr, "CoCreateInstance(WICImagingFactory)"));
            }
            scope.track(factory);
            let factory_vtbl = &**(factory as *mut *const FactoryVtbl);
            tracing::debug!(event = "fs.heif.wic.factory", "WIC imaging factory created");

            // Copy the bytes into a moveable HGLOBAL; the IStream takes
            // ownership of it (`fDeleteOnRelease = TRUE`), so failure
            // paths before that point free it ourselves.
            let global = GlobalAlloc(GMEM_MOVEABLE, bytes.len());
            if global.is_null() {
                return Err("GlobalAlloc failed".into());
            }
            let dst = GlobalLock(global);
            if dst.is_null() {
                GlobalFree(global);
                return Err("GlobalLock failed".into());
            }
            std::ptr::copy_nonoverlapping(bytes.as_ptr(), dst as *mut u8, bytes.len());
            GlobalUnlock(global);

            let mut stream = std::ptr::null_mut();
            let hr = CreateStreamOnHGlobal(global, 1, &mut stream);
            if failed(hr) {
                GlobalFree(global);
                return Err(describe(hr, "CreateStreamOnHGlobal"));
            }
            scope.track(stream);

            let mut decoder = std::ptr::null_mut();
            let hr = (factory_vtbl.create_decoder_from_stream)(
                factory,
                stream,
                std::ptr::null(),
                WIC_DECODE_METADATA_CACHE_ON_DEMAND,
                &mut decoder,
            );
            if hr == WINCODEC_ERR_COMPONENTNOTFOUND {
                return Err(
                    "no WIC codec for this HEIF/AVIF container — install \"HEIF Image Extensions\" and HEVC support from the Microsoft Store"
                        .into(),
                );
            }
            if failed(hr) {
                return Err(describe(hr, "IWICImagingFactory::CreateDecoderFromStream"));
            }
            scope.track(decoder);
            let decoder_vtbl = &**(decoder as *mut *const DecoderVtbl);
            tracing::debug!(event = "fs.heif.wic.decoder", "WIC decoder created for HEIF stream");

            let mut frame = std::ptr::null_mut();
            let hr = (decoder_vtbl.get_frame)(decoder, 0, &mut frame);
            if failed(hr) {
                return Err(describe(hr, "IWICBitmapDecoder::GetFrame"));
            }
            scope.track(frame);
            let frame_vtbl = &**(frame as *mut *const FrameDecodeVtbl);

            let (mut source_w, mut source_h) = (0u32, 0u32);
            let hr = (frame_vtbl.get_size)(frame, &mut source_w, &mut source_h);
            if failed(hr) {
                return Err(describe(hr, "IWICBitmapFrameDecode::GetSize"));
            }
            if source_w == 0 || source_h == 0 || source_w > 100_000 || source_h > 100_000 {
                return Err(format!("implausible HEIF dimensions: {source_w}x{source_h}"));
            }
            tracing::debug!(
                event = "fs.heif.wic.frame",
                width = source_w,
                height = source_h,
                max_dim,
                "frame acquired"
            );

            // Downscale through a scaler when the photo exceeds the cap —
            // the scaler streams rows, so the full-size original is never
            // allocated (mirrors ImageIO's maxPixelSize behaviour).
            let mut source = frame;
            let (target_w, target_h) = fit(source_w, source_h, max_dim);
            if target_w != source_w || target_h != source_h {
                tracing::debug!(
                    event = "fs.heif.wic.scaler",
                    from = %(format!("{source_w}x{source_h}")),
                    to = %(format!("{target_w}x{target_h}")),
                    "scaling down via IWICBitmapScaler"
                );
                let mut scaler = std::ptr::null_mut();
                let hr = (factory_vtbl.create_bitmap_scaler)(factory, &mut scaler);
                if failed(hr) {
                    return Err(describe(hr, "IWICImagingFactory::CreateBitmapScaler"));
                }
                scope.track(scaler);
                let scaler_vtbl = &**(scaler as *mut *const ScalerVtbl);
                let hr = (scaler_vtbl.initialize)(scaler, frame, target_w, target_h, WIC_BITMAP_INTERPOLATION_MODE_FANT);
                if failed(hr) {
                    return Err(describe(hr, "IWICBitmapScaler::Initialize"));
                }
                source = scaler;
            }

            // WIC decodes to its native pixel format; the converter is
            // the one step that actually touches pixels, normalizing to
            // RGBA8 (alpha-threshold 0, no palette).
            let mut converter = std::ptr::null_mut();
            let hr = (factory_vtbl.create_format_converter)(factory, &mut converter);
            if failed(hr) {
                return Err(describe(hr, "IWICImagingFactory::CreateFormatConverter"));
            }
            scope.track(converter);
            let converter_vtbl = &**(converter as *mut *const ConverterVtbl);
            let hr = (converter_vtbl.initialize)(
                converter,
                source,
                &GUID_WIC_PIXEL_FORMAT_32BPP_RGBA,
                WIC_BITMAP_DITHER_TYPE_NONE,
                std::ptr::null(),
                0.0,
                WIC_BITMAP_PALETTE_TYPE_CUSTOM,
            );
            if failed(hr) {
                return Err(describe(hr, "IWICFormatConverter::Initialize"));
            }

            let (mut width, mut height) = (0u32, 0u32);
            let hr = (converter_vtbl.get_size)(converter, &mut width, &mut height);
            if failed(hr) {
                return Err(describe(hr, "IWICFormatConverter::GetSize"));
            }
            if width == 0 || height == 0 {
                return Err(format!("implausible HEIF dimensions: {width}x{height}"));
            }
            // fit() guarantees both edges ≤ max_dim; a converter that
            // disagrees would make CopyPixels allocate unboundedly.
            if max_dim > 0 && width as u64 * height as u64 > max_dim as u64 * max_dim as u64 {
                return Err(format!("WIC produced {width}x{height}, exceeding the {max_dim}px thumbnail cap"));
            }

            let stride = width as usize * 4;
            let mut pixels = vec![0u8; stride * height as usize];
            let hr = (converter_vtbl.copy_pixels)(
                converter,
                std::ptr::null(),
                stride as u32,
                pixels.len() as u32,
                pixels.as_mut_ptr(),
            );
            if failed(hr) {
                if hr == MF_E_CODEC_MISSING {
                    return Err(
                        "the codec for this HEIF/AVIF image (HEVC or AV1) is not installed — install \"HEIF Image Extensions\" and \"AV1 Video Extension\" from the Microsoft Store"
                            .into(),
                    );
                }
                return Err(describe(hr, "IWICBitmapSource::CopyPixels"));
            }

            let orientation = read_orientation(frame);
            tracing::debug!(
                event = "fs.heif.wic.decoded",
                width,
                height,
                orientation,
                "WIC pixel copy finished"
            );

            image::RgbaImage::from_raw(width, height, pixels)
                .map(|img| image::DynamicImage::ImageRgba8(apply_exif_orientation(img, orientation)))
                .ok_or_else(|| "HEIF pixel buffer size mismatch".into())
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Converts a PNG to HEIC with the stock `sips` tool. Returns `None`
    /// when the conversion fails for any reason (tool missing, format
    /// unsupported) so the test degrades to a skip instead of a failure.
    #[cfg(target_os = "macos")]
    fn png_to_heic(png_path: &std::path::Path, heic_path: &std::path::Path) -> Option<()> {
        let output = std::process::Command::new("sips")
            .arg("-s")
            .arg("format")
            .arg("heic")
            .arg(png_path)
            .arg("--out")
            .arg(heic_path)
            .output()
            .ok()?;
        if !output.status.success() {
            return None;
        }
        Some(())
    }

    #[test]
    fn exif_orientation_matches_exif_spec() {
        // 2x3 stored buffer, every pixel unique: pixel = (x, y, 7, 255).
        let mut pixels = Vec::new();
        for y in 0..3u8 {
            for x in 0..2u8 {
                pixels.extend_from_slice(&[x, y, 7, 255]);
            }
        }
        let img = image::RgbaImage::from_raw(2, 3, pixels).unwrap();
        let pixel_at = |img: &image::RgbaImage, x: u32, y: u32| img.get_pixel(x, y).0;

        // 6 = 90° CW: stored top-left ends up top-right, dims swap.
        let out = apply_exif_orientation(img.clone(), 6);
        assert_eq!(out.dimensions(), (3, 2));
        assert_eq!(pixel_at(&out, 2, 0), [0, 0, 7, 255]); // stored (0, 0)
        assert_eq!(pixel_at(&out, 2, 1), [1, 0, 7, 255]); // stored (1, 0)
        assert_eq!(pixel_at(&out, 0, 0), [0, 2, 7, 255]); // stored (0, 2) — bottom-left → top-left

        // 3 = 180°: mirrored both ways, dims kept.
        let out = apply_exif_orientation(img.clone(), 3);
        assert_eq!(out.dimensions(), (2, 3));
        assert_eq!(pixel_at(&out, 1, 2), [0, 0, 7, 255]); // stored (0, 0)

        // 5 = transpose: out(x, y) = stored(y, x).
        let out = apply_exif_orientation(img.clone(), 5);
        assert_eq!(out.dimensions(), (3, 2));
        assert_eq!(pixel_at(&out, 2, 1), [1, 2, 7, 255]); // stored (1, 2)

        // 2 = horizontal mirror.
        let out = apply_exif_orientation(img.clone(), 2);
        assert_eq!(out.dimensions(), (2, 3));
        assert_eq!(pixel_at(&out, 1, 0), [0, 0, 7, 255]); // stored (0, 0)

        // Identity and corrupt metadata keep the buffer untouched.
        for orientation in [1u16, 0, 9] {
            let out = apply_exif_orientation(img.clone(), orientation);
            assert_eq!(out.dimensions(), (2, 3));
            assert_eq!(out.as_raw(), img.as_raw(), "orientation {orientation} must be identity");
        }
    }

    #[test]
    fn thumbnail_fit_caps_long_edge() {
        assert_eq!(fit(4032, 3024, 200), (200, 150)); // iPhone landscape, exact division
        assert_eq!(fit(3024, 4032, 200), (150, 200)); // portrait
        assert_eq!(fit(100, 100, 200), (100, 100)); // no upscale
        assert_eq!(fit(50, 400, 8), (1, 8)); // ceil rounding, never a zero edge
        assert_eq!(fit(0, 0, 200), (0, 0)); // guarded upstream, but must not divide by zero
    }

    #[test]
    fn detects_heic_magic_bytes() {
        // Minimal ISO-BMFF header: size + ftyp + major brand.
        let mut header = vec![0, 0, 0, 24];
        header.extend_from_slice(b"ftyp");
        for brand in ["heic", "heix", "mif1", "avif"] {
            let mut bytes = header.clone();
            bytes.extend_from_slice(brand.as_bytes());
            assert!(is_heif_container(&bytes), "{brand} should be detected");
        }
        // ISO-BMFF but an mp4 video brand, not a still-image container.
        let mut mp4 = header.clone();
        mp4.extend_from_slice(b"isom");
        assert!(!is_heif_container(&mp4), "mp4 brand is not HEIF");
        // 'ftyp' at the wrong offset is not a HEIF magic.
        let mut misplaced = Vec::new();
        misplaced.extend_from_slice(b"ftyp");
        misplaced.extend_from_slice(b"heic");
        assert!(!is_heif_container(&misplaced), "'ftyp' at offset 0 is not HEIF");
        assert!(!is_heif_container(b"short"));
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn decodes_heic_via_system_frameworks() {
        let mut dir = std::env::temp_dir();
        let pid = std::process::id();
        let nanos = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0);
        dir.push(format!("localsend_heif_test_{pid}_{nanos}"));
        std::fs::create_dir_all(&dir).unwrap();

        // 64x64 RGB PNG with a gradient — big enough that sips produces a
        // real HEIC and the thumbnail path actually resamples.
        let png_path = dir.join("in.png");
        let heic_path = dir.join("out.heic");
        let mut pixels = Vec::with_capacity(64 * 64 * 3);
        for y in 0..64u8 {
            for x in 0..64u8 {
                pixels.extend_from_slice(&[x * 4, y * 4, 128]);
            }
        }
        image::DynamicImage::ImageRgb8(image::RgbImage::from_raw(64, 64, pixels).unwrap())
            .write_to(&mut std::io::BufWriter::new(std::fs::File::create(&png_path).unwrap()), image::ImageFormat::Png)
            .unwrap();

        if png_to_heic(&png_path, &heic_path).is_none() {
            eprintln!("sips could not produce a HEIC — skipping");
            std::fs::remove_dir_all(&dir).ok();
            return;
        }

        let bytes = std::fs::read(&heic_path).unwrap();
        assert!(is_heif_container(&bytes), "sips output should carry HEIF magic");

        let img = decode_heif(&bytes, 32).expect("system decode should succeed");
        assert!(img.width() <= 32 && img.height() <= 32, "long edge must be capped at 32");

        std::fs::remove_dir_all(&dir).ok();
    }
}

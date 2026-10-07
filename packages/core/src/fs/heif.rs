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
//! On non-macOS targets [`decode_heif`] always fails and the caller keeps
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
#[cfg_attr(not(target_os = "macos"), allow(unused_variables))]
pub(crate) fn decode_heif(bytes: &[u8], max_dim: u32) -> Result<image::DynamicImage, String> {
    #[cfg(target_os = "macos")]
    {
        decode_via_imageio(bytes, max_dim)
    }
    #[cfg(not(target_os = "macos"))]
    {
        Err("HEIF/AVIF decoding is only supported on macOS".into())
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

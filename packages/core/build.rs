//! Build script: compiles the vendored libheif + libde265 submodules as
//! static libraries for the Windows target, so HEIC thumbnails decode
//! without the Microsoft Store "HEIF Image Extensions" / HEVC codec.
//!
//! macOS decodes HEIC through the system ImageIO framework (see
//! `src/fs/heif.rs`), so this script returns immediately everywhere else.
//!
//! The invocation mirrors the out-of-tree rehearsal that was validated
//! against a real iPhone HEIC before this file was written:
//!
//! 1. libde265 — static, no SDL demo player, installed into a private
//!    prefix (`$OUT_DIR/de265-install`) because its CMake generates
//!    `de265-version.h` / `config.h` into the *build* tree while the
//!    public headers live in the *source* tree; the install merges them.
//! 2. libheif — static, plugin loading off (decoders link directly), all
//!    other codecs (x265, dav1d, aom, openjpeg, …) off; libde265 is wired
//!    in by pre-setting the `LIBDE265_INCLUDE_DIR` / `LIBDE265_LIBRARY`
//!    cache variables, which `cmake/Modules/FindLIBDE265.cmake` honours
//!    before trying pkg-config (absent in MSVC environments).
//!
//! Requires CMake on PATH (e.g. `choco install cmake` or the CMake tools
//! shipping with Visual Studio with "add to PATH" selected). The flags
//! for codecs that do not exist in a given libheif version are unused
//! cache variables — harmless, so a submodule bump cannot break this
//! script.
use std::env;
use std::fs;
use std::path::{Path, PathBuf};

fn main() {
    if env::var("CARGO_CFG_TARGET_OS").as_deref() != Ok("windows") {
        return;
    }

    let manifest_dir = PathBuf::from(env::var("CARGO_MANIFEST_DIR").expect("CARGO_MANIFEST_DIR"));
    let submodules = manifest_dir.join("../../support/submodules");
    let de265_src = submodules.join("libde265");
    let heif_src = submodules.join("libheif");
    println!("cargo:rerun-if-changed={}", de265_src.display());
    println!("cargo:rerun-if-changed={}", heif_src.display());

    // Fail with instructions instead of a cryptic CMake error when the
    // submodule checkouts are missing.
    for name in ["libde265", "libheif"] {
        let src = submodules.join(name);
        if !src.join("CMakeLists.txt").is_file() {
            panic!(
                "support/submodules/{name} is not checked out (looked at {}) — \
                 run `git submodule update --init --recursive` and rebuild",
                src.display()
            );
        }
    }

    // Always build the C++ in Release: a Debug build would use the /MDd
    // debug CRT, which does not match the CRT rustc links.
    let out_dir = PathBuf::from(env::var("OUT_DIR").expect("OUT_DIR"));
    let de265_install = out_dir.join("de265-install");
    let msvc = env::var("CARGO_CFG_TARGET_ENV").as_deref() == Ok("msvc");
    let lib_ext = if msvc { "lib" } else { "a" };

    cmake::Config::new(&de265_src)
        .profile("Release")
        .define("BUILD_SHARED_LIBS", "OFF")
        // SDL is only needed for the dec265 demo player.
        .define("ENABLE_SDL", "OFF")
        .define("CMAKE_INSTALL_PREFIX", &de265_install)
        .build_target("install")
        .build();

    // libde265 names its import library with a "lib" prefix on MSVC. Probe
    // the install tree instead of hardcoding one name.
    let de265_static = probe_static_lib(&[
        de265_install.join("lib").join(format!("libde265.{lib_ext}")),
        de265_install.join("lib").join(format!("de265.{lib_ext}")),
    ]);

    let heif_build = cmake::Config::new(&heif_src)
        .profile("Release")
        .define("BUILD_SHARED_LIBS", "OFF")
        // Decoders link directly into libheif instead of being dlopened —
        // static libraries cannot be loaded as plugins.
        .define("ENABLE_PLUGIN_LOADING", "OFF")
        .define("WITH_LIBDE265", "ON")
        // Pre-setting the Find-module cache variables bypasses its
        // pkg-config lookup, which has no MSVC counterpart.
        .define("LIBDE265_INCLUDE_DIR", de265_install.join("include"))
        .define("LIBDE265_LIBRARY", &de265_static)
        // libde265 is consumed statically here, but its headers declare
        // LIBDE265_API as __declspec(dllimport) on Windows unless
        // LIBDE265_STATIC_BUILD is defined. libde265 only defines that for
        // its own targets, and neither its installed config package nor
        // libheif's FindLIBDE265 module propagates it, so inject it through
        // a project hook — CMAKE_CXX_FLAGS cannot be used because cargokit
        // populates it from the environment and must not be clobbered.
        .define(
            "CMAKE_PROJECT_libheif_INCLUDE",
            write_de265_static_define(&out_dir),
        )
        // Every other codec/driver: off, we only want HEVC decoding.
        .define("WITH_X265", "OFF")
        .define("WITH_KVAZAAR", "OFF")
        .define("WITH_UVG266", "OFF")
        .define("WITH_VVDEC", "OFF")
        .define("WITH_VVENC", "OFF")
        .define("WITH_X264", "OFF")
        .define("WITH_OpenH264_DECODER", "OFF")
        .define("WITH_DAV1D", "OFF")
        .define("WITH_AOM_DECODER", "OFF")
        .define("WITH_AOM_ENCODER", "OFF")
        .define("WITH_SvtEnc", "OFF")
        .define("WITH_RAV1E", "OFF")
        .define("WITH_JPEG_DECODER", "OFF")
        .define("WITH_JPEG_ENCODER", "OFF")
        .define("WITH_OpenJPEG_DECODER", "OFF")
        .define("WITH_OpenJPEG_ENCODER", "OFF")
        .define("WITH_FFMPEG_DECODER", "OFF")
        .define("WITH_OPENJPH_ENCODER", "OFF")
        .define("WITH_UNCOMPRESSED_CODEC", "OFF")
        .define("WITH_WEBCODECS", "OFF")
        .define("WITH_LIBSHARPYUV", "OFF")
        .define("WITH_EXAMPLES", "OFF")
        .define("WITH_EXAMPLE_HEIF_THUMB", "OFF")
        .define("WITH_EXAMPLE_HEIF_VIEW", "OFF")
        .define("WITH_GDK_PIXBUF", "OFF")
        .define("BUILD_TESTING", "OFF")
        .define("BUILD_DOCUMENTATION", "OFF")
        .build();

    // cmake-rs defaults the install prefix of libheif to OUT_DIR, so the
    // install tree lands in <OUT_DIR>/lib; the build tree fallbacks cover
    // configurations where the install step did not run.
    let heif_static = probe_static_lib(&[
        out_dir.join("lib").join(format!("heif.{lib_ext}")),
        out_dir.join("lib").join(format!("libheif.{lib_ext}")),
        heif_build.join("libheif").join(format!("heif.{lib_ext}")),
        heif_build.join("libheif").join("Release").join(format!("heif.{lib_ext}")),
    ]);

    println!("cargo:rustc-link-search=native={}", heif_static.parent().expect("heif parent").display());
    println!("cargo:rustc-link-search=native={}", de265_static.parent().expect("de265 parent").display());
    println!("cargo:rustc-link-lib=static=heif");
    println!(
        "cargo:rustc-link-lib=static={}",
        if msvc { "libde265" } else { "de265" }
    );

    // libheif and libde265 are C++; the MSVC linker needs the C++ standard
    // library, which rustc does not pull in on its own.
    if msvc {
        let crt_static = env::var("CARGO_CFG_TARGET_FEATURE")
            .map(|features| features.split(',').any(|f| f == "crt-static"))
            .unwrap_or(false);
        println!("cargo:rustc-link-lib={}", if crt_static { "libcpmt" } else { "msvcprt" });
    }
}

/// Writes the CMake snippet that makes libheif compile against the *static*
/// libde265 (see the `CMAKE_PROJECT_libheif_INCLUDE` define above) and
/// returns its path.
fn write_de265_static_define(out_dir: &Path) -> PathBuf {
    let file = out_dir.join("de265-static-build.cmake");
    fs::write(&file, "add_compile_definitions(LIBDE265_STATIC_BUILD)\n").expect("write de265-static-build.cmake");
    file
}

/// Returns the first candidate that exists, so the build script survives the
/// layout differences between CMake generators (single- vs multi-config) and
/// install steps. Panics with all probed paths otherwise, which beats a
/// linker error about a missing library.
fn probe_static_lib(candidates: &[PathBuf]) -> PathBuf {
    candidates
        .iter()
        .find(|candidate| candidate.is_file())
        .cloned()
        .unwrap_or_else(|| {
            panic!(
                "could not locate the built static library, looked at:\n{}",
                candidates.iter().map(|p| format!("  {}", p.display())).collect::<Vec<_>>().join("\n")
            )
        })
}

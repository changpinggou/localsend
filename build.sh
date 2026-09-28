#!/bin/bash
# LocalSend 多平台编译脚本
# 用法: ./build.sh [ios|windows|macos|all]

set -e

PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
IOS_DEVICE="070CB1E9-E96A-4269-8EB8-A18B4CD27A74"  # iPhone 17 Pro Simulator

build_ios() {
    echo "=== Building iOS ==="
    cd "$PROJECT_ROOT/app"
    fvm flutter pub get
    fvm flutter run -d "$IOS_DEVICE"
}

build_windows() {
    echo "=== Building Windows ==="
    cd "$PROJECT_ROOT/app"
    fvm flutter pub get
    fvm flutter run -d windows
}

build_macos() {
    echo "=== Building macOS ==="
    cd "$PROJECT_ROOT/app"
    fvm flutter pub get
    fvm flutter run -d macos
}

build_rust_core() {
    echo "=== Checking Rust core ==="
    cd "$PROJECT_ROOT"
    cargo check --features full -p localsend
}

build_rust_isolate() {
    echo "=== Checking Rust isolate ==="
    cd "$PROJECT_ROOT/packages/localsend_isolates"
    cargo check
}

# 默认行为：编译所有平台
case "${1:-all}" in
    ios)
        build_rust_core
        build_rust_isolate
        build_ios
        ;;
    windows)
        build_rust_core
        build_rust_isolate
        build_windows
        ;;
    macos)
        build_rust_core
        build_rust_isolate
        build_macos
        ;;
    rust)
        build_rust_core
        build_rust_isolate
        ;;
    all)
        build_rust_core
        build_rust_isolate
        build_ios
        ;;
    *)
        echo "用法: $0 [ios|windows|macos|rust|all]"
        echo "  ios     - 编译并运行 iOS 模拟器"
        echo "  windows - 编译并运行 Windows"
        echo "  macos   - 编译并运行 macOS"
        echo "  rust    - 仅检查 Rust 代码编译"
        echo "  all     - 编译 Rust + iOS（默认）"
        exit 1
        ;;
esac

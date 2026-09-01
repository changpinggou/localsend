# LocalSend 项目环境搭建与编译技术指南

> 适用版本：`v1.18.2+64`（以 `app/pubspec.yaml` 为准）
> 适用源码：`https://github.com/changpinggou/localsend`
> 阅读对象：第一次接触本仓库、需要在本地拉起开发环境、编译、运行或出包的工程师

---

## 1. 项目结构速览

LocalSend 是一个**多语言 monorepo**：

| 路径                                | 说明                                                                                                                                      |
|-------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------|
| `app/`                              | Flutter 应用 `localsend_app`，UI、Provider、持久化、平台通道                                                                              |
| `packages/localsend_isolates/`      | Dart isolate 层 + `flutter_rust_bridge`（FRB）绑定，含 `rust/`（Flutter 插件 crate `rust_lib_localsend_app`）和 `rust_builder/`（cargokit） |
| `packages/core/`                    | Rust crate `localsend`：协议、HTTP server/client、加密、组播、WebRTC。**不**依赖 Flutter                                                   |
| `packages/typed_isolates/`          | 包装 `Isolate` 的小工具包，独立发布                                                                                                       |
| `server/`                           | Axum WebSocket 信令服务器（`/v1/ws`），WebRTC 使用，独立部署                                                                              |
| `cli/`                              | Rust CLI `localsend-cli`：基于 `packages/core` 的交互式终端客户端（v2 HTTP + 组播）                                                        |
| `support/scripts/`                  | 出包脚本（per-platform builds、MSIX、Inno Setup、FOSS 裁剪）                                                                              |
| `support/submodules/flutter`        | Git submodule 形式的 Flutter SDK（CI/F-Droid 可复现构建用）                                                                               |

**两个工作区，根目录统一管理：**

- **Rust 工作区**（根 `Cargo.toml`）：成员 `cli`、`packages/core`、`packages/localsend_isolates/rust`、`server`；共享 `Cargo.lock`、`target/`、`[profile.*]`。
- **Dart 工作区**（根 `pubspec.yaml`）：成员 `app`、`packages/localsend_isolates`、`packages/typed_isolates`；共享 `pubspec.lock`、`.dart_tool/`。

依赖方向：

```
app  →  localsend_isolates  →  (typed_isolates,  rust_lib_localsend_app  →  localsend core)
```

> ⚠️ `app` 只依赖 `localsend_isolates`，**不**直接依赖 `flutter_rust_bridge`、`typed_isolates` 或插件 crate。

---

## 2. 工具链要求

### 2.1 必需版本（硬编码，缺一不可）

| 工具              | 版本                            | 锁定位置                                                                                       |
|-------------------|---------------------------------|------------------------------------------------------------------------------------------------|
| Flutter           | `3.41.9`                        | `.fvmrc`、`app/pubspec.yaml` (`^3.41.0`)、`.github/workflows/ci.yml`、`support/submodules/flutter` |
| Dart SDK          | `^3.11.0`                       | 根 `pubspec.yaml` 与 `app/pubspec.yaml`                                                        |
| Rust              | `1.97.1`（含 clippy）           | 根 `rust-toolchain.toml` 与 `packages/localsend_isolates/rust-toolchain.toml`                  |
| Rust Android 目标 | `aarch64/armv7/x86_64-linux-android` | `packages/localsend_isolates/rust-toolchain.toml` 中的 `targets`                                |

> ⚠️ **必须使用 `fvm flutter` / `fvm dart`，不要直接用全局的 `flutter` / `dart`**——系统级工具链与 `.fvmrc` 锁定的版本不一致时构建会失败。仓库内的 `AGENTS.md` 与 `CLAUDE.md` 都明确强调这一点。

### 2.2 操作系统

- Linux：x86_64 / arm64（出 AppImage、deb、tar、rpm）
- macOS：11 Big Sur 及以上（DMG、App Store）
- Windows：10 及以上（ZIP、EXE、MSIX）
- Android：5.0 及以上（APK、AAB）
- iOS：12.0 及以上（IPA）

### 2.3 平台依赖

| 平台  | 系统包（最小集）                                                                                            |
|-------|-------------------------------------------------------------------------------------------------------------|
| Linux | `curl clang cmake libgtk-3-dev ninja-build libayatana-appindicator3-dev libfuse2`（AppImage 还需要 `appimage-builder`）|
| macOS | Xcode 命令行工具 + CocoaPods                                                                                 |
| Windows | Visual Studio 2022（C++ 桌面工作负载）+ Windows 10 SDK；MSIX 需 `makepri.exe` 与 `makeappx.exe`；EXE 需 Inno Setup |
| Android | OpenJDK 11（部分脚本写 17 也可）、Android SDK（`platforms;android-33`、`platform-tools`）、`sdkmanager` 许可全签 |
| iOS   | Xcode + CocoaPods；签名需 Apple Developer 账号                                                                |

### 2.4 其它建议安装

- `git`（含 submodule 支持）
- `fvm`（推荐 `pub global activate fvm` 或 `brew install fvm`）
- `flutter_rust_bridge_codegen`（**仅**在改 `packages/localsend_isolates/rust/src/api/*.rs` 时需要）
- `appimage-builder`（仅出 AppImage 时需要）
- `d2`（仅重画依赖图时需要）

---

## 3. 首次克隆与环境初始化

### 3.1 克隆仓库

```bash
git clone https://github.com/changpinggou/localsend.git
cd localsend

# 拉取 flutter 子模块（仓库内 `support/submodules/flutter`，用于 CI/可复现构建）
git submodule update --init --recursive
```

> 若你打算只用本机 `fvm` 管理的 Flutter，子模块可以**不**初始化（`AGENTS.md` 提示在普通开发机上通常无需子模块）。F-Droid 流水线等**可复现构建**才必须用它。

### 3.2 安装 Flutter 版本（通过 fvm）

```bash
# 安装 fvm（任选其一）
brew install fvm                     # macOS / Linuxbrew
pub global activate fvm              # 通用

# 安装仓库锁定的版本（首次需要下载）
fvm install 3.41.9
fvm global 3.41.9                    # 设为默认，或在仓库内自动读取 .fvmrc
```

验证：

```bash
fvm flutter --version
# 期望：Flutter 3.41.9 • channel stable • Dart 3.11.x
```

### 3.3 安装 Rust 工具链

```bash
# 通过 rustup（推荐）
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# rust-toolchain.toml 会自动拉取 1.97.1 + clippy，但 Android 目标不会自动装：
rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android
```

验证：

```bash
cargo --version
rustc --version
# 期望：cargo 1.97.1 / rustc 1.97.1
```

### 3.4 安装 Android 工具链（仅 Android 出包需要）

```bash
# Debian/Ubuntu
sudo apt install openjdk-11-jdk
sdkmanager "platform-tools" "platforms;android-33"
yes | sdkmanager --licenses
```

`ANDROID_HOME` / `ANDROID_SDK_ROOT` 指向 SDK 根目录；`PATH` 加上 `platform-tools`。

### 3.5 安装 iOS 工具链（仅 macOS + iOS 出包需要）

```bash
xcode-select --install
sudo gem install cocoapods
```

---

## 4. 拉取依赖与代码生成

> 所有 `fvm flutter` / `fvm dart` 命令都应在 `app/` 目录内执行。仓库根目录的 `pubspec.yaml` 只是工作区声明，不直接构建。

### 4.1 一次性拉依赖

```bash
cd app
fvm flutter pub get

# cargokit 的 build_tool 也需要独立拉依赖（CI 同样跑）
cd ../packages/localsend_isolates/rust_builder/cargokit/build_tool
fvm flutter pub get
cd ../../../../app
```

> 三个 Dart package 在同一 pub 工作区里，从 `app/` 执行 `pub get` 通常就够了。改 `packages/localsend_isolates` 的模型后再单独跑它的 `pub get` + `build_runner`。

### 4.2 代码生成（必须）

LocalSend 用了一整套 Dart 端的代码生成器，**必须按顺序执行**：

```bash
cd app

# (1) dart_mappable + freezed + flutter_gen + mockito
fvm dart run build_runner build

# (2) slang 国际化（slang_build_runner 在 build.yaml 中禁用，所以单独跑）
fvm dart run slang

# (3) FRB（仅当你修改了 packages/localsend_isolates/rust/src/api/*.rs 时才需要）
cd ../packages/localsend_isolates
flutter_rust_bridge_codegen generate
cd ../../app
```

常见问题：

- 生成器以 80 列重排 `app/test/mocks.mocks.dart` 是 FRB 的副作用——把它从 diff 里排除或 `fvm dart format` 回 150 列。
- CI 在 `format` 阶段会先 `rm -rf lib/gen`，然后再 format；本地不需要手动删除。
- `frb_generated.rs` 永远不会被 rustfmt 干净——CI 的 `cargo fmt --check` 被故意略过。

---

## 5. 本地运行

```bash
cd app
fvm flutter run                    # 默认连到第一个可用设备/模拟器
fvm flutter run -d macos           # 指定平台
```

支持的 host 平台：`android`、`ios`、`macos`、`windows`、`linux`、`web`（其中 `web` 仅用于打包 H5 下载页，浏览端走核心 `Web Send` 流程）。

---

## 6. 静态检查与测试（CI 一致命令）

```bash
cd app

# 格式（150 列）
fvm dart format --set-exit-if-changed lib test

# 静态分析
fvm flutter analyze

# 单元测试
fvm flutter test
fvm flutter test test/unit/util/security_helper_test.dart   # 单文件
fvm flutter test --plain-name 'some test name'              # 单测试

# isolates 子包测试
cd ../packages/localsend_isolates
fvm flutter test
```

Rust 侧（必须在仓库根执行，因为是工作区）：

```bash
# core：必须开 --features full（否则会因为可选依赖导致的条件编译失败）
cd packages/core
cargo test --features full
cargo clippy --features full --all-targets
cd ../..

# 信令 server
cargo test --package server

# 插件 crate + CLI
cargo check --package rust_lib_localsend_app --package localsend-cli
```

> ⚠️ `packages/core` 的模块是无条件声明、依赖却是可选的，所以**裸 `cargo check`/`cargo build` 会报错**——这是已存在的历史行为，不是回归。务必带 `--features full`。

---

## 7. 平台出包

> 出包命令都在 **`app/`** 目录里执行；具体脚本参考 `support/scripts/`。

### 7.1 Android

```bash
cd app
fvm flutter build apk            # APK
fvm flutter build appbundle      # AAB（Google Play）
```

> Release 签名：在 `android/app/build.gradle` 里给 `buildTypes.release` 指定 `signingConfig`，否则用 `signingConfigs.debug` 占位。F-Droid 流水线走的是 `support/scripts/compile_android_apk.sh`，它会从 `submodules/flutter` 取 Flutter 以保证可复现。

### 7.2 iOS

```bash
cd app
fvm flutter build ipa
# 或 App Store 专用
sh support/scripts/compile_mac_appstore.sh
```

### 7.3 macOS

```bash
cd app
fvm flutter build macos
# 出 DMG 安装包
sh support/scripts/compile_mac_dmg.sh
```

### 7.4 Windows

```bash
cd app
fvm flutter build windows                                     # 原始 zip
fvm flutter pub run msix:create                                # 本地 MSIX
fvm flutter pub run msix:create --store                       # Store MSIX
# 出 EXE 安装包（Inno Setup）
pwsh support/scripts/compile_windows_exe.ps1
```

需要先安装 Inno Setup（`iscc` 在 `PATH` 里），脚本默认从 `D:\inno` 读 payload。

### 7.5 Linux

```bash
cd app
fvm flutter build linux                            # 原始 bundle
sh support/scripts/compile_linux_appimage.sh       # AppImage
```

Snap 出包不在本仓库内，参见 `https://github.com/localsend/snap`。

### 7.6 Web（仅浏览器下载页）

`web/` 目录用于打包 H5 端的 `Web Send` 页面，资源由 Rust 端从 `packages/core/assets/web/` 嵌入。

---

## 8. CLI（`localsend-cli`）的单独构建

CLI 完全独立于 Flutter，**只需要 Rust**：

```bash
cd cli
cargo build --release
./target/release/localsend-cli --help

# 出 macOS CLI（已签名 + universal）
sh support/scripts/compile_mac_cli.sh
```

主要功能：

- `localsend-cli send <files...>`：向已发现设备发送（支持按 alias 或 `--to <ip>` 直接打）
- 接收方基于 v2 HTTP（`discovery` + `http` feature）
- 多文件 / 目录递归上传，空目录不上传

---

## 9. 信令服务器（`server/`）

```bash
# 本地
cd server
cargo run --release
# 默认监听 0.0.0.0:3000，路径 /v1/ws
```

Docker（从**仓库根**构建，CI 镜像同款）：

```bash
docker build -f server/Dockerfile -t localsend-signaling .
docker run --rm -p 3000:3000 localsend-signaling
```

镜像基于 `rust:1.97` 编译，最终基于 `debian:bookworm` 运行（`server/Dockerfile`）。

---

## 10. 常见坑位速查

| 现象                                                                              | 原因                                                                                            | 解决                                                                                          |
|-----------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------|
| `flutter` 提示 `Because localsend_app requires Flutter SDK version ^3.41.0...`   | 全局 Flutter 与 `.fvmrc` 不匹配                                                                | 用 `fvm flutter`；或 `fvm install 3.41.9` 后 `fvm global 3.41.9`                              |
| `cargo check` 在 `packages/core` 报 `unresolved import hyper/...`                 | 没用 `--features full`，可选依赖未启用                                                        | 加 `--features full`（模块是无条件声明的）                                                    |
| `dart format` 改了 `app/test/mocks.mocks.dart`                                   | FRB 把 80 列格式写回 mocks 文件                                                                | `fvm dart format test/mocks.mocks.dart`（150 列），或提交前 `git checkout --` 该文件          |
| `flutter build apk` 卡在 `cargo build`，提示找不到 `aarch64-linux-android` 等目标  | 插件 crate 的 `rust-toolchain.toml` 声明的 targets 没装                                       | `rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android`        |
| iOS pod install 失败                                                               | Flutter 切换过版本、Podfile.lock 过期                                                          | `cd ios && pod repo update && pod install --repo-update`                                      |
| `app/lib/gen/` 总是冲突                                                           | build_runner / slang 重新生成                                                                  | 一般直接提交生成产物即可；CI 在 format 阶段会 `rm -rf lib/gen` 再 format                        |
| `flutter_rust_bridge_codegen generate` 改了非 `lib/rust` 目录                     | 配置文件仅作用在 `packages/localsend_isolates` 内                                              | 在该子包内执行；`flutter_rust_bridge.yaml` 中 `dart_output: lib/rust`                          |
| `F-Droid` 流水线下构建时间戳漂移                                                  | `build.yaml` 中 `timestamp: false` 是故意保留的                                                | 不要打开 `timestamp: true`                                                                    |
| 局域网看不到对方设备                                                                | 路由器开了 AP 隔离 / Windows 网络为「公用」/ macOS 没授 Local Network 权限                       | 见 `README.md` 的 Troubleshooting 表                                                          |

---

## 11. 一份可拷贝的「最小可用」流程

把下面这段在干净的 macOS / Linux 机器上跑通，就能 `flutter run`：

```bash
# 0. 准备：git、curl、Xcode CLT（macOS）/ build-essential（Linux）
xcode-select --install                                                       # macOS only
sudo apt install build-essential curl git                                     # Linux only

# 1. Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source "$HOME/.cargo/env"
rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android   # 仅 Android 出包

# 2. fvm + Flutter
brew install fvm                                                              # 或 pub global activate fvm
fvm install 3.41.9

# 3. 拉代码
git clone https://github.com/changpinggou/localsend.git
cd localsend
git submodule update --init --recursive                                      # 可选：CI/可复现构建才需要

# 4. 拉依赖 + 代码生成
cd app
fvm flutter pub get
fvm dart run build_runner build
fvm dart run slang

# 5. 运行
fvm flutter run
```

跑通以上五步后，再按 §7 选择目标平台出包，按 §6 跑测试即可。

---

## 12. 参考资料

- 仓库根：`AGENTS.md`、`CLAUDE.md`、`CONTRIBUTING.md`、`CODE_SIGNING.md`、`README.md`
- 协议规范：<https://github.com/localsend/protocol>
- fvm 文档：<https://fvm.app>
- flutter_rust_bridge 文档：<https://cjycode.com/flutter_rust_bridge/>
- 项目主页：<https://localsend.org>
- 中文 README：`support/readme/README_ZH.md`

> 文档维护提示：升级 Flutter / Rust 时**同时**改 `.fvmrc`、`app/pubspec.yaml`、`.github/workflows/ci.yml`、`support/submodules/flutter` 子模块指针、根与插件两处 `rust-toolchain.toml`——CI 的 `packaging` 阶段不会放过任何不一致。

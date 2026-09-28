# LocalSend macOS 本地编译指南

本文档记录在 macOS 上从源码编译 `LocalSend.app` 的完整步骤，覆盖首次环境准备、代理配置、常见问题处理。

## 1. 环境准备

### 1.1 Flutter（通过 fvm 锁定版本）

本仓库把 Flutter 版本 pin 在 `.fvmrc`（当前为 `3.41.9`），**必须使用 fvm 调用**，不要直接用系统 Flutter。

```bash
# 一次性：通过系统 dart 安装 fvm
dart pub global activate fvm

# 把 ~/.pub-cache/bin 加入 PATH（建议写进 ~/.zshrc）
export PATH="$HOME/.pub-cache/bin:$PATH"

# 首次：安装并切换到 .fvmrc 指定的版本
fvm install
fvm use
```

### 1.2 Rust 工具链（cargokit 构建 `rust_lib_localsend_app` 需要）

```bash
# 安装 rustup
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain stable

# 项目要求精确的 1.97.1（在 packages/localsend_isolates/rust_builder/cargokit 中 pin 定）
# 首次构建 cargokit 会自动 `rustup target install aarch64-apple-darwin`；只需提前装好工具链本体：
rustup toolchain install 1.97.1

# 验证
rustup run 1.97.1 cargo --version   # 应输出 cargo 1.97.1 ...
```

### 1.3 CocoaPods（iOS / macOS 插件需要 ≥ 1.16.2）

```bash
sudo gem install cocoapods
```

### 1.4 Mac Development 签名证书

Xcode 项目 `app/macos/Runner.xcodeproj` 使用 team ID `NH5788MG66` 自动签名。首次编译前需在"钥匙串访问"中配置 Apple Developer 账号的 Mac Development 证书 + 对应私钥。

> 仅调试：可临时把 `CODE_SIGN_IDENTITY` 改为 `-` 并关闭 `CODE_SIGNING_REQUIRED`，但产物在别的机器无法启动。

## 2. 网络 / 代理

本仓库 `app/pubspec.yaml` 含 3 个 git 依赖（`device_apps` / `flutter-plugins` / `permission_handler_windows_noop`），`flutter pub get` 必须能访问 `github.com`。Rust 编译阶段 crates.io 走 HTTPS。

如果 `github.com` 直连超时（常见现象：`Recv failure: Operation timed out`），需开启代理：

```bash
# 读取系统代理端口（以本机为例：127.0.0.1:6789）
# 可通过 系统设置 → 网络 → Wi-Fi → 详细信息 → 代理 查看
export http_proxy=http://127.0.0.1:6789
export https_proxy=http://127.0.0.1:6789
export all_proxy=socks5://127.0.0.1:6789
export no_proxy=localhost,127.0.0.1
```

## 3. 编译命令（最终可执行版本）

```bash
# 1. 环境
export PATH="$HOME/.cargo/bin:$HOME/.pub-cache/bin:$PATH"
export http_proxy=http://127.0.0.1:6789
export https_proxy=http://127.0.0.1:6789
export all_proxy=socks5://127.0.0.1:6789
export no_proxy=localhost,127.0.0.1

# 2. 解析 Dart 依赖
cd /Users/changping/Documents/localsend/localsend/app
fvm flutter pub get

# 3. 编译 Release macOS app
fvm flutter build macos
```

产物位置：

```
app/build/macos/Build/Products/Release/LocalSend.app   # 155.4 MB
```

启动：

```bash
open app/build/macos/Build/Products/Release/LocalSend.app
```

## 4. 常用变体

| 场景 | 命令 |
|---|---|
| Debug 构建（启动快、含调试符号） | `fvm flutter build macos --debug` |
| Profile 构建（性能分析） | `fvm flutter build macos --profile` |
| 仅编译 Rust 层验证 | `cd packages/core && cargo build --features full` |
| 跑全量测试 | `fvm flutter test && cargo test --features full`（在 `packages/core`） |
| 清理产物后重编 | `fvm flutter clean && fvm flutter build macos` |

## 5. 常见问题排查

| 现象 | 处理 |
|---|---|
| `command not found: fvm` | 把 `~/.pub-cache/bin` 加入 PATH |
| `fatal: unable to access 'https://github.com/.../': Recv failure: Operation timed out` | 设置 4 个代理环境变量（见 §2） |
| `rustup not found in PATH` | 安装 rustup（见 §1.2） |
| `error: Directory not empty (os error 66)` 发生在 `rustup toolchain install 1.97.1` | `rustup toolchain uninstall 1.97.1 && rm -rf ~/.rustup/tmp/*` 后重装 |
| `the 'cargo' binary ... is not applicable to the '1.97.1-...' toolchain` | 重装时不要加 `--profile minimal`，或显式 `rustup component add cargo --toolchain 1.97.1` |
| `No signing certificate "Mac Development" found` | 安装 Apple Developer Mac Development 证书到钥匙串 |
| `warning: pointer is missing a nullability type specifier` 等 photo_manager 警告 | 可忽略，不影响运行 |

## 6. 版本号同步

发布新版本时，`AGENTS.md` 规定以下 5 处版本号必须一致：

- `app/pubspec.yaml`
- `cli/Cargo.toml`
- `support/scripts/compile_windows_exe-inno.iss`
- `support/build/appimage/AppImageBuilder_*.yml`
- `support/build/msix/content/AppxManifest.xml`

CI `packaging` 阶段会强制比较，不一致直接红。

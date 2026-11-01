# 构建与运行

## 通用

建议 Flutter 3.47.8 stable、Dart 3.13.7。先执行 `flutter doctor -v`、`flutter pub get`。应用 ID 在 Android、iOS、macOS 和 Linux 工程中均为 `xyz.ctspace.forum`，Windows 同样设置了 AppUserModelID。

| 平台 | 工程最低版本 | 构建宿主机 |
| --- | --- | --- |
| Android | API 26 / Android 8 | Linux、Windows、macOS，JDK 21、Android SDK |
| iOS | iOS 15 | macOS、Xcode、CocoaPods |
| macOS | macOS 12 | macOS、Xcode、CocoaPods |
| Windows | Windows 10 | Windows、Visual Studio「使用 C++ 的桌面开发」 |
| Linux | Ubuntu 22.04 或兼容发行版 | Linux、GTK 3、libsecret、C++ 工具链 |

最低版本是工程配置，未等同于所有设备的实机测试结论。

```bash
flutter analyze
flutter test
flutter build apk --release --split-per-abi
flutter build ios --release --no-codesign
flutter build macos --release
flutter build windows --release
flutter build linux --release
```

## Linux

Ubuntu 构建依赖：

```bash
sudo apt-get update
sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libsecret-1-dev
flutter build linux --release
./build/linux/x64/release/bundle/forum
```

登录使用 libsecret，桌面会话应有 Secret Service，例如 GNOME Keyring 或支持 Secret Service 的 KDE Wallet。缺少密钥环时仍可浏览公开内容，登录会明确提示系统安全存储不可用，不回退为明文保存令牌。

发布时分发整个 `bundle/`，包括 `data/` 和 `lib/`，不能只复制 `forum`。可以打包为：

```bash
tar -C build/linux/x64/release/bundle -czf ctspace-linux-x64.tar.gz .
```

包内附有 `.desktop` 和 `data/xyz.ctspace.forum.png`。安装桌面入口时，将 `.desktop` 中的 `Exec` 改成可执行文件绝对路径，`Icon` 改成图标绝对路径，或将相应文件安装到系统标准位置。

## Android

`flutter build apk --debug` 可生成本地测试 APK。`--release` 默认使用开发签名，配置正式签名后才适合发行。

在 `android/key.properties` 填写以下字段，该文件及密钥文件已被 Git 忽略：

```properties
storeFile=/absolute/path/to/release.jks
storePassword=YOUR_STORE_PASSWORD
keyAlias=YOUR_KEY_ALIAS
keyPassword=YOUR_KEY_PASSWORD
```

工程会自动使用上述签名。首次构建需要下载 Gradle、Android 插件、NDK 和依赖，网络较慢时耗时较长。仓库使用 Gradle bin 分发，避免额外下载文档和源码。

## iOS / macOS

插件支持 Swift Package Manager 与必要的 CocoaPods 回退。已配置 Podfile、最低系统版本、macOS 网络/用户选取文件沙箱权限及 iOS Keychain 能力。

macOS 使用系统的传统 Keychain 保存本应用令牌，不要求跨应用钥匙串共享。iOS 需要在 Xcode 中选择自己的 Development Team，正式 IPA、TestFlight 或 App Store 发行还需要相应签名与配置文件。`--no-codesign` 的产物不能直接安装到 iPhone。

应用内网页由 WebKit 提供。macOS 的文件选择和保存使用用户选择文件权限，不依赖全磁盘权限。

## Windows

```powershell
flutter build windows --release
.\build\windows\x64\runner\Release\forum.exe
```

分发整个 Release 目录，并确保目标系统有相应 Visual C++ Runtime。Windows 的补充网页交给系统浏览器。

## 图标与许可证

五端图标由现有站点标识生成，Android 包含 adaptive icon。需要重新生成时：

```bash
python3 -m pip install Pillow
python3 tool/generate_icons.py
```

Noto Sans SC 字体完整打包以确保五端中文显示，许可为 SIL OFL 1.1。应用代码为 Apache 2.0，两者均在应用开源许可页登记。

## 测试服务和只读冒烟

`API_BASE_URL` 可指向实现相同协议的测试服务；不支持运行时切换，避免不同站点的令牌混用。

```bash
flutter run -d linux --dart-define=API_BASE_URL=https://test.example/api
flutter build linux --release --dart-define=READ_ONLY_SMOKE=true
```

`READ_ONLY_SMOKE=true` 仅关闭前台 presence heartbeat，适用于游客导航的只读冒烟。它不会禁用用户主动点击的发布、支付或消息操作，也不应被当作全局只读开关。

## GitHub Actions 手动打包

[自动检查](../.github/workflows/flutter.yml) 仅运行格式、分析和测试。[五端打包](../.github/workflows/build.yml) **仅允许手动运行**，没有 push、PR、定时或其他触发器。

推送到 GitHub 后，打开 Actions →「手动构建五端安装包」→ Run workflow。每个平台独立构建，完成后在该次运行的 Artifacts 下载，所有文件保留 **3 天**。

| 产物名 | 内容 |
| --- | --- |
| ctspace-android-apk | 按 ABI 拆分的 Release APK；未配置正式密钥时使用开发签名 |
| ctspace-ios-unsigned-ipa | `ctspace-ios-unsigned.ipa`，内部为 `Payload/Runner.app`，构建使用 `--no-codesign` |
| ctspace-macos | 包含完整 `.app` 的 ZIP |
| ctspace-windows-x64 | 包含 EXE、DLL 与 data 的 ZIP |
| ctspace-linux-x64 | 完整运行目录的 tar.gz |

iOS IPA 需要自行签名后才能安装到真机；工作流不自动发布或上传应用商店。

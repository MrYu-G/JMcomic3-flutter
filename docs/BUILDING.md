# 构建与测试

当前支持本地发布 Android ARM64 / ARM32 和 Windows x64。命令从仓库根目录运行。

## 固定环境

| 工具 | 当前发布使用的版本 |
| --- | --- |
| Flutter / Dart | 3.50.1 / 3.14.0，见 `.fvmrc` |
| Android SDK / Gradle / AGP / Kotlin | compile SDK 37 / 9.5.0 / 9.3.1 / 2.4.20 |
| Rust | 1.98.0，MSVC 工具链 |
| Android NDK | 25.2.9519653，与 `android/app/build.gradle` 一致 |
| Java | JDK 21；Android 编译目标为 Java 17 |
| cargo-ndk | 4.1.2 |
| Windows C++ | Visual Studio Build Tools 2022 / MSVC 14.44 |

本机环境脚本从当前仓库位置查找 `_flutter/flutter`、`toolchains/` 和 `_cache/`。
后端 crate 由 `scripts/build_common.ps1` 统一解析：优先使用 `-RustBackendDir`，其次
使用 `RUST_BACKEND_RUST_DIR`，否则选择 `rust-backend/rust` 或同级
`../jmcomic3-rust-backend/rust` 中唯一存在的检出。两者同时存在时必须显式选择。
这些本地工具目录已忽略；换机器时需要自行准备同版本工具链。
`enter_build_env.ps1` 不是自动安装器。
它的 `-Target Windows` 只加载 Windows 所需工具，不要求 Android SDK/NDK 或 Java；
Windows 构建包装脚本自动选择此目标。默认 `All` 保持完整环境检查，`Android` 用于
Android 工具链。CMake/Ninja 优先使用独立工具目录，其次使用 Visual Studio 自带版本。
执行前确认 `_flutter/flutter/bin/flutter --version` 与 `.fvmrc` 一致；切换 SDK 后重新运行
`flutter pub get --enforce-lockfile`。分析和测试可以直接使用这个 SDK，不必加载完整发布环境。
`window_manager` 0.7 使用 nativeapi 的 C++ native assets；Windows 上的 widget/unit 测试
也需要可用的 MSVC 编译器、Windows SDK 及其头文件和库，只有 Flutter SDK 不再足够。

发布时 Rust 后端使用 `ci/backend.commit.txt` 的固定 SHA；可以检出到 `rust-backend/`
或使用已有同级后端仓库。脚本不会复制源码或自动切换提交。
如果已有后端检出，先检查未提交改动，再切换版本；不要覆盖本地修改。

```powershell
git clone https://github.com/MrYu-G/jmcomic3-rust-backend.git rust-backend
git -C rust-backend checkout --detach (Get-Content ci/backend.commit.txt).Trim()
. .\scripts\enter_build_env.ps1
.\scripts\verify_build_env.ps1
flutter pub get --enforce-lockfile
```

后端仓库访问权限由 GitHub 账号决定。Windows 需要 Developer Mode 以创建 Flutter
插件软链接。Android 发布需要已有的 `android/key.properties` 和 keystore；参考
`android/key.properties.example`，密钥和口令不得提交。

## 测试

```powershell
. .\scripts\enter_build_env.ps1
flutter analyze --no-pub --no-fatal-infos lib test integration_test test_driver
flutter test --no-pub --concurrency=1
cargo test --locked --manifest-path (Join-Path $env:RUST_BACKEND_RUST_DIR 'Cargo.toml') -- --test-threads=1
```

使用已选中的后端（包括同级目录）时，Cargo 清单路径为
`Join-Path $env:RUST_BACKEND_RUST_DIR 'Cargo.toml'`。原生构建包装脚本和
`verify_build_env.ps1` 均接受 `-RustBackendDir <crate路径>`；也可以先设置该环境变量。

分析必须没有 error / warning；现有风格和弃用 info 单独记录。Android 真机或模拟器
回归见 [integration_test/README.md](../integration_test/README.md)。测试使用合成数据，
在线服务和账号功能需要另外验收。

响应缓存与桥接解码也提供独立的纯 Dart 回归入口，不需要启动原生资产构建：

```powershell
.\_flutter\flutter\bin\cache\dart-sdk\bin\dart.exe --packages=.dart_tool/package_config.json test/bridge_core_check.dart
.\scripts\test_packaging_helpers.ps1
```

前者覆盖缓存失效竞争、请求合并、错误重试及历史标量/信封格式；后者使用合成目录和
归档检查构建路径与包内容验证。这些检查不能替代 MethodChannel、控件、设备或原生
安装包验收。代码归属见 [CODE_STRUCTURE.md](CODE_STRUCTURE.md)。

## Android

完整重建 Rust JNI 和两种架构的 APK：

```powershell
.\scripts\build_android.ps1
```

该脚本用 PowerShell 中已加载的工具链构建 Rust，通过现有同步脚本校验 ELF 和哈希，
然后复用 `build_android_release_split.ps1` 的发布流程；不再要求 Git Bash 或强制嵌套
后端路径。它生成并同步 `librust.so`，随后构建 ABI split APK。已有经验证的 JNI 后，生成
混淆发布 APK 和 AAB：

```powershell
. .\scripts\enter_build_env.ps1
.\scripts\build_android_release_split.ps1
```

可用 `-ApkOnly` 或 `-AabOnly` 选择格式。发布版默认启用 R8、资源压缩、Dart 混淆和
外置调试符号；保留每版符号以还原崩溃堆栈。`-DebugSign` 只用于本地测试安装。

产物在 `build/app/outputs/flutter-apk/` 和 `build/app/outputs/bundle/release/`。
项目与 Gradle 使用默认的 `build/` 目录，发布脚本的 `OutputName` 用于归档目录；
默认符号路径为 `build/<OutputName>/symbols/android/`。`OutputName` 只接受单级目录名。
每个 APK 只能包含其目标 ABI 的
`librust.so`、`libflutter.so`、`libapp.so`，发布前校验签名和包内版本。
ABI split APK 的实际 versionCode 带架构前缀，不能仅用 `pubspec.yaml` 的 build number
推断；更新时同时比较包内 versionCode。

两个 Android 发布入口都执行包内容检查：ABI 必须与请求一致，每个 ABI 必须含必需的
Rust/Flutter/AOT 库，不得同时含 Cargo 原名 Rust 库或重复 ZIP 条目。单 ABI AAB 也按
请求过滤 JNI；模拟器库保留在源码树，不进入 ARM 发布包。签名步骤只处理本次请求的
APK 文件，不扫描并签署旧构建产物。App 自有资产显式声明为 `lib/assets/version.txt`
及登录页复用的 `android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png`。
检查命令只读取归档并打印实际包大小、native 压缩前后字节数及 App 资产字节数：

```powershell
.\scripts\verify_android_package.ps1 -PackagePath build/app/outputs/flutter-apk/app-arm64-v8a-release.apk -ExpectedAbi arm64-v8a
.\scripts\test_packaging_helpers.ps1
```

检查脚本不验证代码运行、签名身份或 native 源码版本；这些仍按发布步骤单独验证。
Android 包检查还会审查归档内的源码、凭据、测试输出和调试符号文件名。Windows ZIP
及最终上传的其他归档使用同一检查：

```powershell
.\scripts\verify_release_archive.ps1 -PackagePath dist/<版本>/Jmcomic3-windows-x64-<版本>.zip
```

这些检查只读归档，不删除或重写安装包、签名、原生库或 Flutter 资产。私钥和后端源码
仍保存在各自受保护的位置，正常构建通过本地路径加载；上传检查不要求把它们加入 Git。
没有原生构建时，只能确认脚本和合成归档检查的行为，不能据此推断安装包大小或平台
兼容性。截图、测试日志与任务记录保存在被忽略的本地输出目录，不上传到 GitHub。

## Windows

```powershell
.\scripts\build_windows.ps1
```

脚本构建 Rust 静态库、准备 `windows/rust.h` 与 `windows/rust.lib`，再编译 Flutter。
静态库不提交。完整分发 `build/windows/x64/runner/Release/` 中的 EXE、DLL 和 `data`
目录，不可只复制 EXE。
安装规则包含 Flutter build hooks 生成的原生资产；例如 `cnativeapi.dll` 必须随 EXE
一起分发。打包时核对本次 `build/windows/x64/install_manifest.txt` 与 EXE，避免把旧
构建残留、源码或调试符号放入 ZIP，并运行归档检查。

## 已知环境边界

Flutter 与第三方包升级后，需要重新验证 Android 和 Windows 原生构建。
`permission_handler` 13 要求 compile SDK 37；最低 Android API 为 24，目标 API 仍跟随
Flutter（当前为 36）。Gradle 的 `android.newDsl=false` 和 `android.builtInKotlin=false`
与 Flutter 3.50 模板一致，由 Flutter 为需要的模块应用 Kotlin 插件。
Rust JNI 的 NDK 暂保留 25.2.9519653；发布前必须重建 JNI / native assets 并实测 APK，
不能将旧版本原生库的运行结果当作新依赖的验证结果。
本仓库没有 iOS、macOS、Linux、鸿蒙的平台工程，本次不提供这些平台的构建流程。

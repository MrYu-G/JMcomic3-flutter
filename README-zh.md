# JMComic3 Flutter

[![版本](https://img.shields.io/github/v/release/MrYu-G/JMcomic3-flutter)](https://github.com/MrYu-G/JMcomic3-flutter/releases/latest)

简体中文 · [English](README.md)

JMComic3 是使用 Flutter 构建界面、内嵌 Rust 后端的漫画阅读器。本仓库维护 Flutter
应用、Android / Windows 平台入口、测试和本地发布工具。当前稳定版为 **v1.7.43+72**。

## 下载与安装

从 [GitHub Releases](https://github.com/MrYu-G/JMcomic3-flutter/releases/latest)
下载本地构建的发布包。

| 文件 | 用途 |
| --- | --- |
| `Jmcomic3-arm64-v8a-*.apk` | 适用于大多数当前 Android 设备 |
| `Jmcomic3-armeabi-v7a-*.apk` | 适用于需要 32 位 ARM 的 Android 设备 |
| `Jmcomic3-universal-*.apk` | 同时包含 ARM64 与 ARM32，体积更大，不确定架构时使用 |
| `Jmcomic3-windows-x64-*.zip` | 完整解压后运行 `jmcomic3.exe` |
| `SHA256SUMS.txt` / `build-info.json` | 校验下载文件并查看源码、工具链及验证信息 |

- **Windows：** 压缩包中的 EXE、DLL 与 `data` 目录需要一起保留。程序未进行代码签名，
  部分系统需要安装 Visual C++ 运行库。
- **Android：** v1.7.43+72 启用新的签名密钥，无法覆盖安装 v1.7.26+55 及更早版本。
  请先备份数据（导出下载或 WebDAV 同步），卸载旧版后再安装。
- **平台范围：** 正式发布和验证的平台为 **Android ARM64 / ARM32 与 Windows x64**；
  其他平台不在本版本的发布范围内。

## 主要功能

- 漫画浏览、搜索、分类、详情、彩色标签和章节目录。
- 收藏、阅读历史、每周必看与评论。
- 普通连续、自由缩放连续、单页和双页阅读，支持阅读方向切换与实际可见页进度保存。
- 离线章节阅读、下载管理、导入导出与 WebDAV 同步。
- 响应式导航、主题、语言和网络线路配置。

版本更新内容见 [CHANGELOG.md](CHANGELOG.md)。

### 开发中的改进

当前源码包含可信更新、可配置阅读预加载、会话恢复、收藏资料夹修复以及重做的导入与
缓存管理界面。这些变更仍在验证中，不包含在上述稳定版安装包中。

- 更新直接使用官方 GitHub 仓库，首页通知和关于页显示完整日志；安装包通过大小和
  SHA-256 校验后才能保存。保存后打开 APK，或完整解压 Windows ZIP 安装。
- 阅读设置可独立选择预加载数量（关闭、1、2、4、6 页）和方向（向前、向后、双向），
  默认前后各 2 页。阅读图片使用临时缓存，下载文件继续支持离线阅读。
- 下载目录设置用于新建任务；下载页显示实际完整路径，长按或右键任务可暂停、继续。
  现有任务保留原来的存储位置。
- 图片缓存按 UTC 日期显示文件数量与空间占用，可多选或全选日期清理，并保留下载文件。
- 个人中心、书库管理、更新和阅读器控件减少重复留白，图标对应实际操作，保留大字体
  换行与 48 像素触控目标。

## 开发与维护

Flutter 版本由 [.fvmrc](.fvmrc) 固定。Rust 后端位于独立的
[jmcomic3-rust-backend](https://github.com/MrYu-G/jmcomic3-rust-backend)
仓库，访问需要相应权限；发布使用的提交记录在
[ci/backend.commit.txt](ci/backend.commit.txt)。后端检出目录、工具链、签名密钥和
构建产物不提交到本仓库。

### 仓库结构

| 路径 | 内容 |
| --- | --- |
| `lib/` | 应用代码：页面、阅读器、桥接调用、设置与本地化 |
| `android/`、`windows/` | 平台入口与原生桥接调用 |
| `test/`、`integration_test/`、`test_driver/` | 单元与控件测试、Android 设备回归 |
| `third_party/` | 内置的 `zoomable_positioned_list` 及本地补丁 |
| `scripts/`、`ci/`、`docs/` | 本地构建工具、版本与后端固定记录、构建和发布规范 |

### 常用检查

使用固定版本的 Flutter SDK，从仓库根目录运行：

```powershell
flutter pub get --enforce-lockfile
flutter analyze --no-pub --no-fatal-infos lib test integration_test test_driver
flutter test --no-pub --concurrency=1
```

Android 与 Windows 构建还需要本地工具链和后端检出，步骤见下方的构建文档。
当前窗口管理依赖使用原生资产，Windows 控件测试也需要 MSVC 和 Windows SDK。

### 文档

- [代码职责与维护](docs/CODE_STRUCTURE.md)
- [构建与测试](docs/BUILDING.md)
- [分支、PR 与发布规范](docs/RELEASING.md)
- [Android 阅读器回归](integration_test/README.md)

## 引用与致谢

- [ComicSparks/jasmine](https://github.com/ComicSparks/jasmine)：Flutter 阅读器结构
  和阅读交互参考，固定参考提交为
  [`e514be1`](https://github.com/ComicSparks/jasmine/commit/e514be163ec39a6f9e0d2799580d132324e23470)。
- [hect0x7/JMComic-Crawler-Python](https://github.com/hect0x7/JMComic-Crawler-Python)：
  独立 Rust 后端的移动端 API 协议、请求签名与请求头、登录和域名回退参考；
  本应用没有将该 Python 项目作为运行时依赖。
- `zoomable_positioned_list` 1.1.0：内置的连续阅读组件，保留上游版权和许可证，
  本地补丁见 [PATCHES.md](third_party/zoomable_positioned_list/PATCHES.md)。

详细引用范围和第三方声明见 [REFERENCES.md](REFERENCES.md)。相关项目名称及版权
归各自作者所有，本项目独立维护。

## 使用约定

应用访问第三方服务，服务可用性取决于外部站点。请在遵守当地规定和内容权利的前提下
用于个人学习。沿用原项目的禁止商用、禁止转发内容资产约定；第三方组件继续适用
各自许可证。

# JMComic3 Flutter

[![Release](https://img.shields.io/github/v/release/MrYu-G/JMcomic3-flutter)](https://github.com/MrYu-G/JMcomic3-flutter/releases/latest)

[简体中文](README-zh.md) · English

JMComic3 is a Flutter comic reader with an embedded Rust backend. This
repository maintains the Flutter app, the Android and Windows runners, tests,
and local release tools. The stable release is **v1.7.45+74**.

## Download and Install

Get locally built packages from
[GitHub Releases](https://github.com/MrYu-G/JMcomic3-flutter/releases/latest).

| File | Use |
| --- | --- |
| `Jmcomic3-arm64-v8a-*.apk` | Most current Android devices |
| `Jmcomic3-armeabi-v7a-*.apk` | Android devices that require 32-bit ARM |
| `Jmcomic3-universal-*.apk` | Contains both ARM64 and ARM32; larger, for when the ABI is unknown |
| `Jmcomic3-windows-x64-*.zip` | Extract the entire archive and run `jmcomic3.exe` |
| `SHA256SUMS.txt` / `build-info.json` | Verify downloads and review source, toolchain, and verification records |

- **Windows.** Keep the executable, DLLs, and `data` directory together. The
  executable is not code signed; some systems require the Visual C++ runtime.
- **Android.** v1.7.43+72 uses a new signing key and cannot be installed over
  v1.7.26+55 or earlier. Back up your data first (export downloads or WebDAV
  sync), uninstall the old version, then install this one.
- **Platforms.** The released and verified targets are **Android ARM64/ARM32
  and Windows x64**. Other platforms are not part of this release.

## Features

- Browsing, search, categories, comic details, colored tags, and chapter lists.
- Favorites, reading history, weekly selections, and comments.
- Continuous, zoomable continuous, single-page, and double-page reading, with
  reading direction switching and progress saved from the visible page.
- Offline chapters, download management, import/export, and WebDAV sync.
- Responsive navigation, themes, locales, and network route settings.

Release changes are recorded in [CHANGELOG.md](CHANGELOG.md).

### Upcoming Improvements

The current source includes a trusted updater, configurable reader preloading,
session recovery, folder fixes, and redesigned import/cache controls. These
changes are under validation and are not included in the stable package above.

- Updates use the official GitHub repository directly. Full notes appear on the
  home notification and About page; downloaded packages must pass size and
  SHA-256 checks before they can be saved. Open the saved APK or extract the
  complete Windows ZIP to install it.
- Reader settings independently select preload count (off, 1, 2, 4, or 6 pages)
  and direction (forward, backward, or both). The default is two pages in each
  direction. Reader images are temporary; downloads remain available offline.
- Download settings apply the chosen directory to new tasks. The download page
  shows the effective path; long-press or right-click a task to pause or resume.
  Existing tasks retain their original location.
- Image-cache settings show UTC calendar dates, file counts, and storage usage.
  Select dates or select all to clear cached images while retaining downloads.
- Compact profile, library, update, and reader controls reduce excess spacing,
  use action-specific icons, and retain large-text wrapping and 48-pixel targets.

## Development and Maintenance

Flutter is pinned by [.fvmrc](.fvmrc). The Rust backend is maintained in the
separate
[jmcomic3-rust-backend](https://github.com/MrYu-G/jmcomic3-rust-backend)
repository, which requires access permission; the revision used for a release
is pinned in [ci/backend.commit.txt](ci/backend.commit.txt). Backend checkouts,
toolchains, signing keys, and build outputs are not committed to this
repository.

### Repository Layout

| Path | Content |
| --- | --- |
| `lib/` | Application code: screens, reader, bridge calls, settings, and localization |
| `android/`, `windows/` | Platform runners and native bridge callers |
| `test/`, `integration_test/`, `test_driver/` | Unit and widget tests, and the Android device regression |
| `third_party/` | Vendored `zoomable_positioned_list` with its local patch |
| `scripts/`, `ci/`, `docs/` | Local build tools, version and backend pins, and build/release procedures |

### Common Checks

Run these from the repository root with the pinned Flutter SDK:

```powershell
flutter pub get --enforce-lockfile
flutter analyze --no-pub --no-fatal-infos lib test integration_test test_driver
flutter test --no-pub --concurrency=1
```

Android and Windows builds additionally need the local toolchain and a backend
checkout; follow the build document below.
With the current window-management dependency, Windows widget tests also need
MSVC and the Windows SDK for native assets.

### Documentation

- [Code ownership and maintenance](docs/CODE_STRUCTURE.md)
- [Build and test instructions](docs/BUILDING.md)
- [Branch, PR, and release procedure](docs/RELEASING.md)
- [Android reader regression](integration_test/README.md)

## References and Acknowledgments

- [ComicSparks/jasmine](https://github.com/ComicSparks/jasmine): Flutter reader
  structure and reading interaction reference, pinned to
  [`e514be1`](https://github.com/ComicSparks/jasmine/commit/e514be163ec39a6f9e0d2799580d132324e23470).
- [hect0x7/JMComic-Crawler-Python](https://github.com/hect0x7/JMComic-Crawler-Python):
  mobile API protocol, request signing and headers, login, and domain fallback
  reference for the Rust backend. This app does not use that Python project as
  a runtime dependency.
- `zoomable_positioned_list` 1.1.0: vendored continuous reader component. The
  upstream copyright and licenses are retained, and the local patch is recorded
  in [PATCHES.md](third_party/zoomable_positioned_list/PATCHES.md).

[REFERENCES.md](REFERENCES.md) records the detailed reference scope and
third-party notices. Upstream names and copyrights belong to their authors.
This project is independently maintained.

## Terms of Use

The app accesses third-party services whose availability depends on external
sites. Use it for personal study in accordance with local rules and content
rights. The policy inherited from the original project prohibits commercial use
and redistribution of content assets. Third-party components retain their own
license terms.

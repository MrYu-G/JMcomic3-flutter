import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'image_decode_targets.dart';
import 'image_files.dart';
import 'log.dart';
import 'reader_image_session.dart';

class PageImageProvider extends ImageProvider<PageImageProvider> {
  final int id;
  final String imageName;
  final double scale;

  /// Optional source-page identity.  The transport still uses [imageName],
  /// but the source index keeps two malformed/legacy entries with the same
  /// name from sharing a Flutter image-cache key.
  final int? pageIndex;

  /// Optional codec target in physical pixels.  This is deliberately a
  /// property of the Flutter provider only: the file resolved by
  /// [resolvePageImagePath] is still the canonical, fully decrypted image.
  final int? cacheWidth;
  final int? cacheHeight;

  /// Optional already-resolved canonical path, used by offline readers and
  /// tests.  It is never a network URL and is validated for existence before
  /// handing bytes to the codec.
  final String? localPath;

  /// When true, a missing [localPath] is a hard local-only failure.  This is
  /// used by the opt-in offline owner so metadata-only pages never silently
  /// fall back to an online bridge request.
  final bool localOnly;

  final ReaderImageSession? readerSession;

  PageImageProvider(
    this.id,
    this.imageName, {
    this.scale = 1.0,
    int? pageIndex,
    int? cacheWidth,
    int? cacheHeight,
    String? localPath,
    this.localOnly = false,
    this.readerSession,
  }) : pageIndex = _normalizePageIndex(pageIndex),
       cacheWidth = normalizeImageDecodeTarget(cacheWidth),
       cacheHeight = normalizeImageDecodeTarget(cacheHeight),
       localPath = normalizeLocalImagePath(localPath);

  Future<String> _pathForKey(PageImageProvider key) => resolvePageImagePath(
    key.id,
    key.imageName,
    localPath: key.localPath,
    localOnly: key.localOnly,
    readerSession: key.readerSession,
  );

  @override
  ImageStreamCompleter loadBuffer(
    PageImageProvider key,
    DecoderBufferCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsyncWithBuffer(key, decode),
      scale: key.scale,
    );
  }

  /// Direct codec hook for deterministic fixture tests. Production callers
  /// should resolve the provider through the Image widget so Flutter's image cache and
  /// lifecycle remain in charge.
  @visibleForTesting
  Future<ui.Codec> loadCodecForTest() => _loadAsyncWithImage(
    this,
    PaintingBinding.instance.instantiateImageCodecWithSize,
  );

  @override
  ImageStreamCompleter loadImage(
    PageImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsyncWithImage(key, decode),
      scale: key.scale,
    );
  }

  @override
  Future<PageImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<PageImageProvider>(this);
  }

  Future<ui.Codec> _loadAsyncWithBuffer(
    PageImageProvider key,
    DecoderBufferCallback decode,
  ) => _withSession(() => _decodeWithBuffer(key, decode));

  Future<T> _withSession<T>(Future<T> Function() operation) async {
    try {
      return await (readerSession?.run(operation) ?? operation());
    } finally {
      if (readerSession?.closed == true) {
        // A codec may finish after its widget was disposed. Remove the pending
        // image-cache listener before it can retain that late decoded frame.
        imageCache.evict(this, includeLive: true);
      }
    }
  }

  Future<ui.Codec> _decodeWithBuffer(
    PageImageProvider key,
    DecoderBufferCallback decode,
  ) async {
    assert(key == this);
    final bytes = await File(await _pathForKey(key)).readAsBytes();
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final width = key.cacheWidth;
    final height = key.cacheHeight;
    if (width == null && height == null) {
      return decode(buffer);
    }
    try {
      return await decode(
        buffer,
        cacheWidth: width,
        cacheHeight: height,
        allowUpscaling: false,
      );
    } catch (_) {
      // A decoder/plugin may reject a target-size request even though the
      // canonical image is valid. Retry the same canonical bytes without a
      // target so an optimization failure cannot turn into a page failure.
      final fallbackBuffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      return decode(fallbackBuffer);
    }
  }

  Future<ui.Codec> _loadAsyncWithImage(
    PageImageProvider key,
    ImageDecoderCallback decode,
  ) => _withSession(() => _decodeWithImage(key, decode));

  Future<ui.Codec> _decodeWithImage(
    PageImageProvider key,
    ImageDecoderCallback decode,
  ) async {
    assert(key == this);
    final bytes = await File(await _pathForKey(key)).readAsBytes();
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final width = key.cacheWidth;
    final height = key.cacheHeight;
    if (width == null && height == null) {
      return decode(buffer);
    }
    try {
      return await decode(
        buffer,
        getTargetSize: (int intrinsicWidth, int intrinsicHeight) {
          // Never request an upscale. The codec still owns aspect-ratio
          // fitting; bounding each supplied dimension by the source keeps a
          // large viewport/DPR from creating a pointless larger bitmap.
          final requestedWidth = width;
          final requestedHeight = height;
          final boundedWidth = requestedWidth == null
              ? null
              : math.min(requestedWidth, intrinsicWidth);
          final boundedHeight = requestedHeight == null
              ? null
              : math.min(requestedHeight, intrinsicHeight);
          return ui.TargetImageSize(width: boundedWidth, height: boundedHeight);
        },
      );
    } catch (_) {
      final fallbackBuffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      return decode(fallbackBuffer);
    }
  }

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) return false;
    final PageImageProvider typedOther = other as PageImageProvider;
    return id == typedOther.id &&
        imageName == typedOther.imageName &&
        scale == typedOther.scale &&
        pageIndex == typedOther.pageIndex &&
        cacheWidth == typedOther.cacheWidth &&
        cacheHeight == typedOther.cacheHeight &&
        localPath == typedOther.localPath &&
        localOnly == typedOther.localOnly &&
        readerSession == typedOther.readerSession;
  }

  @override
  int get hashCode => Object.hash(
    id,
    imageName,
    scale,
    pageIndex,
    cacheWidth,
    cacheHeight,
    localPath,
    localOnly,
    readerSession,
  );

  @override
  String toString() =>
      '$runtimeType('
      ' id: ${describeIdentity(id)},'
      ' imageName: ${describeIdentity(imageName)},'
      ' scale: $scale,'
      ' pageIndex: $pageIndex,'
      ' cacheWidth: $cacheWidth,'
      ' cacheHeight: $cacheHeight,'
      ' localPath: ${localPath == null ? '<cache>' : describeIdentity(localPath)},'
      ' localOnly: $localOnly'
      ')';
}

int? _normalizePageIndex(int? value) =>
    value != null && value >= 0 ? value : null;

final Map<String, Set<Object>> _pageImageDecodeKeys = {};
const _pageImageDecodeKeyLimit = 800;

String _pageImageCacheKey(int id, String imageName) => '$id/$imageName';

void recordPageImageDecodeKey(
  int id,
  String imageName,
  ImageProvider provider,
) {
  // Track every concrete provider variant so page eviction releases exactly
  // the decoded images painted by continuous, paired and offline readers.
  unawaited(
    provider
        .obtainKey(ImageConfiguration.empty)
        .then<void>((key) {
          final pageKey = _pageImageCacheKey(id, imageName);
          if (!_pageImageDecodeKeys.containsKey(pageKey) &&
              _pageImageDecodeKeys.length >= _pageImageDecodeKeyLimit) {
            final oldKeys = _pageImageDecodeKeys.remove(
              _pageImageDecodeKeys.keys.first,
            )!;
            for (final oldKey in oldKeys) {
              imageCache.evict(oldKey, includeLive: false);
            }
          }
          final keys = _pageImageDecodeKeys.putIfAbsent(
            pageKey,
            () => <Object>{},
          );
          // 尺寸刷新及横竖屏切换会产生多个解码版本，保留有限版本防止登记表增长。
          if (!keys.contains(key) && keys.length >= 4) {
            final oldKey = keys.first;
            keys.remove(oldKey);
            imageCache.evict(oldKey, includeLive: false);
          }
          keys.add(key);
        })
        .catchError((Object error, StackTrace stackTrace) {
          debugPrient("record page decode key failed: $error\n$stackTrace");
        }),
  );
}

/// 淘汰单页的路径、尺寸及解码缓存，保留仍在屏幕上的活动图片。
void evictPageImageMemoryCache(
  int id,
  String imageName, {
  bool includeLive = false,
}) {
  evictPageImageFileCaches(id, imageName);
  evictPageImageDecodeCache(id, imageName, includeLive: includeLive);
}

/// 仅淘汰 Flutter 解码缓存，覆盖相册页图和长条阅读器的文件/缩放缓存键。
void evictPageImageDecodeCache(
  int id,
  String imageName, {
  bool includeLive = false,
}) {
  // 翻页期间保留仍在树上的图片；阅读器销毁时才允许释放 live stream。
  imageCache.evict(PageImageProvider(id, imageName), includeLive: includeLive);
  final keys = _pageImageDecodeKeys.remove(_pageImageCacheKey(id, imageName));
  if (keys != null) {
    for (final key in keys) {
      imageCache.evict(key, includeLive: includeLive);
    }
  }
}

/// 清空图片路径、尺寸和已登记的页图解码缓存，用于磁盘缓存清理后的内存同步。
void clearAllImageMemoryCaches() {
  clearImageFileCaches();
  for (final keys in _pageImageDecodeKeys.values) {
    for (final key in keys) {
      imageCache.evict(key, includeLive: false);
    }
  }
  _pageImageDecodeKeys.clear();
  // Also release Flutter-managed live streams. The path/size maps above do
  // not own those streams, and leaving them live can keep deleted local files
  // open after a reader route has been replaced.
  imageCache.clearLiveImages();
  imageCache.clear();
}

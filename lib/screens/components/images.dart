import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:jmcomic3/screens/components/file_actions.dart';
import 'package:jmcomic3/basic/image_decode_targets.dart';
import 'package:jmcomic3/basic/image_files.dart';
import 'package:jmcomic3/basic/page_image_provider.dart';
import 'package:jmcomic3/basic/log.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/components/types.dart';

import '../file_photo_view_screen.dart';
import 'dialogs.dart';

/// Covers and avatars share path/retry state; their frame and fit stay caller-owned.
class JM3x4Cover extends StatelessWidget {
  const JM3x4Cover({
    super.key,
    required this.comicId,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.longPressMenuItems,
  });
  final int comicId;
  final double? width;
  final double? height;
  final BoxFit fit;
  final List<LongPressMenuItem>? longPressMenuItems;

  @override
  Widget build(BuildContext context) => _RemoteImage(
    identity: ('cover3x4', comicId),
    loadPath: (refresh) => cachedJm3x4CoverPath(comicId, forceRefresh: refresh),
    width: width,
    height: height,
    fit: fit,
    longPressMenuItems: longPressMenuItems,
    preserveSourceAspectRatio: true,
  );
}

class JMSquareCover extends StatelessWidget {
  const JMSquareCover({
    super.key,
    required this.comicId,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.longPressMenuItems,
  });
  final int comicId;
  final double? width;
  final double? height;
  final BoxFit fit;
  final List<LongPressMenuItem>? longPressMenuItems;

  @override
  Widget build(BuildContext context) => _RemoteImage(
    identity: ('coverSquare', comicId),
    loadPath: (refresh) =>
        cachedJmSquareCoverPath(comicId, forceRefresh: refresh),
    width: width,
    height: height,
    fit: fit,
    longPressMenuItems: longPressMenuItems,
    preserveSourceAspectRatio: true,
  );
}

class JMPhotoImage extends StatelessWidget {
  const JMPhotoImage({
    super.key,
    required this.photoName,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  });
  final String photoName;
  final double? width;
  final double? height;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) => _RemoteImage(
    identity: ('photo', photoName),
    loadPath: (refresh) => cachedPhotoPath(photoName, forceRefresh: refresh),
    width: width,
    height: height,
    fit: fit,
  );
}

class _RemoteImage extends StatefulWidget {
  const _RemoteImage({
    required this.identity,
    required this.loadPath,
    this.width,
    this.height,
    required this.fit,
    this.longPressMenuItems,
    this.preserveSourceAspectRatio = false,
  });
  final Object identity;
  final Future<String> Function(bool forceRefresh) loadPath;
  final double? width;
  final double? height;
  final BoxFit fit;
  final List<LongPressMenuItem>? longPressMenuItems;
  final bool preserveSourceAspectRatio;

  @override
  State<_RemoteImage> createState() => _RemoteImageState();
}

class _RemoteImageState extends State<_RemoteImage> {
  late Future<String> _future;
  int _autoRetryCount = 0;
  bool _autoRetryQueued = false;

  @override
  void initState() {
    super.initState();
    _future = widget.loadPath(false);
  }

  @override
  void didUpdateWidget(covariant _RemoteImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity != widget.identity) {
      _autoRetryCount = 0;
      _autoRetryQueued = false;
      _future = widget.loadPath(false);
    }
  }

  void _reload() {
    if (!mounted) return;
    setState(() => _future = widget.loadPath(true));
  }

  void _autoRetryOnDecodeError() {
    if (_autoRetryCount >= 1 || _autoRetryQueued) return;
    _autoRetryQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoRetryQueued = false;
      if (!mounted) return;
      _autoRetryCount++;
      _reload();
    });
  }

  @override
  Widget build(BuildContext context) => _pathFutureImage(
    context,
    _future,
    widget.width,
    widget.height,
    fit: widget.fit,
    longPressMenuItems: widget.longPressMenuItems,
    preserveSourceAspectRatio: widget.preserveSourceAspectRatio,
    onReload: _reload,
    onDecodeError: _autoRetryOnDecodeError,
  );
}

class JMPageImage extends StatefulWidget {
  final int id;
  final String imageName;

  /// Stable source-page identity for duplicate image names.
  final int? pageIndex;

  /// Optional path already validated by the offline availability contract.
  /// When present, no network/bridge lookup is performed.
  final String? localPath;

  /// Prevents a metadata-only offline page from falling back to the network.
  final bool localOnly;

  /// Reader pages are scaled at paint time, not distorted into codec buckets.
  final bool preserveSourceAspectRatio;
  final double? width;
  final double? height;
  final Function(Size size)? onTrueSize;

  /// The reader supplies its preload provider so visible and warmed images
  /// share one Flutter cache key, including session and offline identity.
  final PageImageProvider? provider;

  const JMPageImage(
    this.id,
    this.imageName, {
    Key? key,
    this.pageIndex,
    this.localPath,
    this.localOnly = false,
    this.preserveSourceAspectRatio = false,
    this.width,
    this.height,
    this.provider,
    this.onTrueSize,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() => _JMPageImageState();
}

class _JMPageImageState extends State<JMPageImage> {
  late Future<String> _future;
  int _generation = 0;
  int _autoRetryCount = 0;
  bool _autoRetryQueued = false;

  @override
  void initState() {
    super.initState();
    _future = _init();
  }

  @override
  void didUpdateWidget(covariant JMPageImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id ||
        oldWidget.imageName != widget.imageName ||
        oldWidget.pageIndex != widget.pageIndex ||
        oldWidget.localOnly != widget.localOnly ||
        oldWidget.localPath != widget.localPath ||
        oldWidget.provider != widget.provider) {
      _generation++;
      _autoRetryCount = 0;
      _autoRetryQueued = false;
      _future = _init();
    }
  }

  Future<String> _init({bool forceRefresh = false}) {
    final session = widget.provider?.readerSession;
    return session?.run(() => _resolvePath(forceRefresh: forceRefresh)) ??
        _resolvePath(forceRefresh: forceRefresh);
  }

  Future<String> _resolvePath({bool forceRefresh = false}) async {
    final generation = _generation;
    final id = widget.id;
    final imageName = widget.imageName;
    final pageIndex = widget.pageIndex;
    final localOnly = widget.localOnly;
    final onTrueSize = widget.onTrueSize;
    final suppliedPath = widget.localPath?.trim();
    final path = await resolvePageImagePath(
      id,
      imageName,
      localPath: suppliedPath,
      localOnly: localOnly,
      forceRefresh: forceRefresh,
      readerSession: widget.provider?.readerSession,
    );
    // A newer widget/reload may have replaced this request while the path was
    // loading. Do not start a force-refresh size lookup from the stale
    // request, since it could evict the newer size Future for the same key.
    if (!mounted ||
        generation != _generation ||
        widget.id != id ||
        widget.imageName != imageName ||
        widget.pageIndex != pageIndex ||
        widget.localOnly != localOnly ||
        widget.localPath?.trim() != suppliedPath) {
      return path;
    }
    if (onTrueSize != null) {
      Future<void> measure() async {
        final size = await cachedPageImageTrueSize(
          id,
          imageName,
          path,
          forceRefresh: forceRefresh,
        );
        if (mounted &&
            generation == _generation &&
            widget.id == id &&
            widget.imageName == imageName &&
            widget.pageIndex == pageIndex &&
            widget.localOnly == localOnly &&
            widget.localPath?.trim() == suppliedPath) {
          onTrueSize(size);
        }
      }

      // Dimensions refine layout independently. A slow/failed metadata query
      // must never keep valid image bytes behind a loading placeholder.
      final session = widget.provider?.readerSession;
      unawaited(
        (session?.run(measure) ?? measure()).catchError((
          Object error,
          StackTrace stack,
        ) {
          debugPrient('image dimensions unavailable: ${error.runtimeType}');
        }),
      );
    }
    return path;
  }

  void _reload() {
    evictPageImageMemoryCache(widget.id, widget.imageName);
    _generation++;
    if (!mounted) {
      return;
    }
    setState(() {
      _future = _init(forceRefresh: true);
    });
  }

  void _autoRetryOnDecodeError() {
    if (_autoRetryCount >= 1 || _autoRetryQueued) {
      return;
    }
    _autoRetryQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoRetryQueued = false;
      if (!mounted) {
        return;
      }
      _autoRetryCount++;
      _reload();
    });
  }

  @override
  Widget build(BuildContext context) {
    // 按 future 状态渲染图片
    return _pathFutureImage(
      context,
      _future,
      widget.width,
      widget.height,
      offlineOnly: widget.localOnly,
      preserveSourceAspectRatio: widget.preserveSourceAspectRatio,
      imageProvider: widget.provider,
      onReload: _reload,
      onDecodeError: _autoRetryOnDecodeError,
      onImageProvider: (provider) =>
          recordPageImageDecodeKey(widget.id, widget.imageName, provider),
    );
  }
}

Widget _pathFutureImage(
  BuildContext context,
  Future<String> future,
  double? width,
  double? height, {
  BoxFit fit = BoxFit.cover,
  List<LongPressMenuItem>? longPressMenuItems,
  VoidCallback? onReload,
  VoidCallback? onDecodeError,
  ValueChanged<ImageProvider>? onImageProvider,
  ImageProvider? imageProvider,
  bool offlineOnly = false,
  bool preserveSourceAspectRatio = false,
}) {
  // 使用 FutureBuilder 渲染加载/错误/成功状态
  return FutureBuilder<String>(
    future: future,
    builder: (BuildContext context, AsyncSnapshot<String> snapshot) {
      if (snapshot.connectionState == ConnectionState.done &&
          snapshot.hasError) {
        debugPrient("image load failed: ${snapshot.error.runtimeType}");
        debugPrient("image load stack: ${snapshot.stackTrace?.runtimeType}");
        if (offlineOnly) {
          return _buildOfflineImageUnavailable(
            context,
            width,
            height,
            onReload: onReload,
          );
        }
        return buildError(
          context,
          width,
          height,
          longPressMenuItems: longPressMenuItems,
          onReload: onReload,
        );
      }
      // 检查是否完成
      if (snapshot.connectionState == ConnectionState.done &&
          snapshot.hasData &&
          snapshot.data!.trim().isNotEmpty) {
        return _buildFile(
          context,
          snapshot.data!,
          width,
          height,
          fit: fit,
          longPressMenuItems: longPressMenuItems,
          onReload: onReload,
          onDecodeError: onDecodeError,
          onImageProvider: onImageProvider,
          preserveSourceAspectRatio: preserveSourceAspectRatio,
          imageProvider: imageProvider,
        );
      }
      if (snapshot.connectionState == ConnectionState.done) {
        debugPrient("image load failed: invalid result");
        if (offlineOnly) {
          return _buildOfflineImageUnavailable(
            context,
            width,
            height,
            onReload: onReload,
          );
        }
        return buildError(
          context,
          width,
          height,
          longPressMenuItems: longPressMenuItems,
          onReload: onReload,
        );
      }
      // 其他状态（waiting/active/none）显示加载状态
      return _buildLoading(
        context,
        width,
        height,
        longPressMenuItems: longPressMenuItems,
      );
    },
  );
}

/// A distinct state for an offline page whose metadata exists but whose
/// validated local file is missing or unreadable. Keeping this separate from
/// the generic network error makes the recovery action clear and prevents a
/// user from assuming that toggling network settings will fix the page.
Widget _buildOfflineImageUnavailable(
  BuildContext context,
  double? width,
  double? height, {
  VoidCallback? onReload,
}) {
  final content = SizedBox(
    width: width,
    height: height,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: (width != null && height != null)
                  ? math.min(width, height).clamp(24.0, 56.0).toDouble()
                  : 32,
              color: Colors.grey,
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.tr(
                '离线图片不可用，请重新下载',
                en: 'Offline image unavailable; download again',
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    ),
  );
  if (onReload == null) {
    return content;
  }
  return GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onReload,
    child: content,
  );
}

// 通用方法

Widget buildError(
  BuildContext context,
  double? width,
  double? height, {
  List<LongPressMenuItem>? longPressMenuItems,
  VoidCallback? onReload,
}) {
  final size = width != null && height != null
      ? math.min(width, height).clamp(24.0, 48.0).toDouble()
      : 32.0;
  final error = SizedBox(
    width: width,
    height: height,
    child: Center(
      child: Icon(Icons.error_outline, size: size, color: Colors.grey),
    ),
  );
  if (onReload != null ||
      (longPressMenuItems != null && longPressMenuItems.isNotEmpty)) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onReload,
      onLongPress: () async {
        final reloadText = context.l10n.tr('重新加载', en: 'Reload');
        List<String> menuItems = [];
        if (onReload != null) {
          menuItems.add(reloadText);
        }
        if (longPressMenuItems != null && longPressMenuItems.isNotEmpty) {
          menuItems.addAll(longPressMenuItems.map((e) => e.title));
        }
        if (menuItems.isEmpty) return;

        String? choose = await chooseListDialog(
          context,
          title: context.l10n.choose,
          values: menuItems,
        );
        if (choose == reloadText && onReload != null) {
          onReload();
        } else {
          for (var item in longPressMenuItems ?? []) {
            if (item.title == choose) {
              item.onChoose();
              break;
            }
          }
        }
      },
      child: error,
    );
  }
  return error;
}

Widget _buildLoading(
  BuildContext context,
  double? width,
  double? height, {
  List<LongPressMenuItem>? longPressMenuItems,
}) {
  final size = width != null && height != null
      ? math.min(width, height).clamp(24.0, 72.0).toDouble()
      : 32.0;
  final loading = SizedBox(
    width: width,
    height: height,
    child: Center(
      child: Icon(
        Icons.downloading,
        size: size,
        color: Colors.grey.withAlpha(150),
      ),
    ),
  );
  if (longPressMenuItems != null && longPressMenuItems.isNotEmpty) {
    return GestureDetector(
      onLongPress: () async {
        String? choose = await chooseListDialog(
          context,
          title: context.l10n.choose,
          values: longPressMenuItems.map((e) => e.title).toList(),
        );
        for (var item in longPressMenuItems) {
          if (item.title == choose) {
            item.onChoose();
            break;
          }
        }
      },
      child: loading,
    );
  }
  return loading;
}

Widget _buildFile(
  BuildContext context,
  String file,
  double? width,
  double? height, {
  BoxFit fit = BoxFit.cover,
  List<LongPressMenuItem>? longPressMenuItems,
  VoidCallback? onReload,
  VoidCallback? onDecodeError,
  ValueChanged<ImageProvider>? onImageProvider,
  ImageProvider? imageProvider,
  bool preserveSourceAspectRatio = false,
}) {
  final devicePixelRatio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
  final cacheWidth = imageDecodeTargetExtent(width, devicePixelRatio);
  final cacheHeight = imageDecodeTargetExtent(height, devicePixelRatio);
  // Cover frames and padding are independent of the source image ratio.
  // Preserve the decoded cover pixels, then let BoxFit scale and crop them.
  // Exact width/height decode targets would distort the image before painting.
  final source = FileImage(File(file));
  final provider =
      imageProvider ??
      (preserveSourceAspectRatio
          ? source
          : ResizeImage.resizeIfNeeded(cacheWidth, cacheHeight, source));
  onImageProvider?.call(provider);
  final image = Image(
    image: provider,
    width: width,
    height: height,
    errorBuilder: (a, b, c) {
      debugPrient("image decode failed: ${b.runtimeType}");
      debugPrient("image decode stack: ${c.runtimeType}");
      onDecodeError?.call();
      return buildError(
        context,
        width,
        height,
        longPressMenuItems: longPressMenuItems,
        onReload: onReload,
      );
    },
    fit: fit,
  );
  return GestureDetector(
    onLongPress: () async {
      final previewText = context.l10n.tr('预览图片', en: 'Preview image');
      final saveToGalleryText = context.l10n.tr(
        '保存图片到相册',
        en: 'Save image to gallery',
      );
      final saveToFileText = context.l10n.tr(
        '保存图片到文件',
        en: 'Save image to file',
      );
      String? choose = await chooseListDialog(
        context,
        title: context.l10n.choose,
        values: [
          previewText,
          ...Platform.isAndroid || Platform.isIOS ? [saveToGalleryText] : [],
          ...!Platform.isIOS ? [saveToFileText] : [],
          ...longPressMenuItems?.map((e) => e.title) ?? [],
        ],
      );
      if (!context.mounted) return;
      if (choose == previewText) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (context) => FilePhotoViewScreen(file)),
        );
      } else if (choose == saveToGalleryText) {
        saveImageFileToGallery(context, file);
      } else if (choose == saveToFileText) {
        saveImageFileToFile(context, file);
      } else {
        for (var item in longPressMenuItems ?? []) {
          if (item.title == choose) {
            item.onChoose();
            break;
          }
        }
      }
    },
    child: image,
  );
}

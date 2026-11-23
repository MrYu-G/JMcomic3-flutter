import 'dart:io';
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'methods.dart';
import 'reader_image_queue.dart';
import 'reader_image_session.dart';

const _pageImagePathCacheLimit = 800;
const _pageImageTrueSizeCacheLimit = 800;
const _coverPathCacheLimit = 400;
const _photoPathCacheLimit = 400;

String? normalizeLocalImagePath(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

final Map<int, Future<String>> _jm3x4CoverPathFutureCache = {};
final Map<int, Future<String>> _jmSquareCoverPathFutureCache = {};
final Map<String, Future<String>> _photoPathFutureCache = {};
final Map<String, Future<String>> _pageImagePathFutureCache = {};
final Map<String, Future<Size>> _pageImageTrueSizeFutureCache = {};
var _readerImageQueue = ReaderImageQueue();

/// A widget test that ends with a gated page request leaves that operation
/// pending forever, which would permanently occupy a slot of the process-wide
/// queue and starve every later test.
@visibleForTesting
void resetReaderImageQueueForTest() {
  _readerImageQueue = ReaderImageQueue();
}

String _pageImageCacheKey(int id, String imageName, {String? path}) {
  final normalizedPath = normalizeLocalImagePath(path);
  return normalizedPath == null
      ? "$id/$imageName"
      : "$id/$imageName|$normalizedPath";
}

T _putCacheWithLimit<K, T>(Map<K, T> cache, K key, T value, int limit) {
  if (!cache.containsKey(key) && cache.length >= limit) {
    cache.remove(cache.keys.first);
  }
  cache[key] = value;
  return value;
}

Future<String> _cachePathFuture<K>({
  required Map<K, Future<String>> cache,
  required K key,
  required Future<String> Function() loader,
  required int limit,
}) {
  final cached = cache[key];
  if (cached != null) {
    return cached;
  }
  Future<String>? currentFuture;
  currentFuture = Future<String>.sync(loader)
      .then((path) async {
        final normalized = path.trim();
        if (normalized.isEmpty) {
          throw StateError("empty image path");
        }
        return _validateImagePath(normalized, 'image file unavailable');
      })
      .catchError((Object error, StackTrace stackTrace) {
        // A forced refresh may have replaced this Future while the old request
        // was still in flight. Only evict when the cache still points at the
        // failing Future; otherwise an old failure could remove the new value.
        if (identical(cache[key], currentFuture)) {
          cache.remove(key);
        }
        Error.throwWithStackTrace(error, stackTrace);
      });
  return _putCacheWithLimit(cache, key, currentFuture, limit);
}

Future<String> cachedJm3x4CoverPath(int comicId, {bool forceRefresh = false}) {
  if (forceRefresh) {
    _jm3x4CoverPathFutureCache.remove(comicId);
  }
  return _cachePathFuture(
    cache: _jm3x4CoverPathFutureCache,
    key: comicId,
    loader: () => methods.jm3x4Cover(comicId),
    limit: _coverPathCacheLimit,
  );
}

Future<String> cachedJmSquareCoverPath(
  int comicId, {
  bool forceRefresh = false,
}) {
  if (forceRefresh) {
    _jmSquareCoverPathFutureCache.remove(comicId);
  }
  return _cachePathFuture(
    cache: _jmSquareCoverPathFutureCache,
    key: comicId,
    loader: () => methods.jmSquareCover(comicId),
    limit: _coverPathCacheLimit,
  );
}

Future<String> cachedPhotoPath(String photoName, {bool forceRefresh = false}) {
  if (forceRefresh) {
    _photoPathFutureCache.remove(photoName);
  }
  return _cachePathFuture(
    cache: _photoPathFutureCache,
    key: photoName,
    loader: () => methods.jmPhotoImage(photoName),
    limit: _photoPathCacheLimit,
  );
}

/// Resolve online and offline pages through one local-only contract. The
/// returned path always refers to canonical bytes, before Flutter decoding.
Future<String> resolvePageImagePath(
  int id,
  String imageName, {
  String? localPath,
  bool localOnly = false,
  bool forceRefresh = false,
  ReaderImageSession? readerSession,
}) async {
  final supplied = normalizeLocalImagePath(localPath);
  if (supplied != null)
    return _validateImagePath(supplied, 'local image unavailable');
  if (localOnly) throw StateError('local image unavailable');
  return _cachedPageImagePath(
    id,
    imageName,
    forceRefresh: forceRefresh,
    readerSession: readerSession,
  );
}

Future<String> _cachedPageImagePath(
  int id,
  String imageName, {
  bool forceRefresh = false,
  ReaderImageSession? readerSession,
}) {
  final key =
      _pageImageCacheKey(id, imageName) +
      (readerSession == null ? '' : '|session:${readerSession.cacheIdentity}');
  if (forceRefresh) {
    _pageImagePathFutureCache.remove(key);
  }
  return _cachePathFuture(
    cache: _pageImagePathFutureCache,
    key: key,
    loader: () => _readerImageQueue.run(
      () async => methods.jmPageImage(
        id,
        imageName,
        readerSession: readerSession == null ? null : await readerSession.token,
      ),
    ),
    limit: _pageImagePathCacheLimit,
  );
}

Future<Size> cachedPageImageTrueSize(
  int id,
  String imageName,
  String path, {
  bool forceRefresh = false,
}) async {
  final key = _pageImageCacheKey(id, imageName, path: path);
  if (forceRefresh) {
    _pageImageTrueSizeFutureCache.remove(key);
  }
  final cached = _pageImageTrueSizeFutureCache[key];
  if (cached != null) {
    return cached;
  }
  Future<Size>? currentFuture;
  currentFuture = Future<ImageSize>.sync(() => methods.imageSize(path))
      .then((imageSize) {
        if (imageSize.w <= 0 || imageSize.h <= 0) {
          // A successful bridge response with zero/negative dimensions is still a
          // malformed image contract. Do not let it poison the true-size cache or
          // make a list reader construct a zero-sized page.
          throw const FormatException('invalid image dimensions');
        }
        return Size(imageSize.w.toDouble(), imageSize.h.toDouble());
      })
      .catchError((Object error, StackTrace stackTrace) {
        if (identical(_pageImageTrueSizeFutureCache[key], currentFuture)) {
          _pageImageTrueSizeFutureCache.remove(key);
        }
        Error.throwWithStackTrace(error, stackTrace);
      });
  // 阅读器同一页可能被预加载、当前页和双页模式同时请求尺寸；缓存 Future 可以合并并发桥接调用。
  return _putCacheWithLimit(
    _pageImageTrueSizeFutureCache,
    key,
    currentFuture,
    _pageImageTrueSizeCacheLimit,
  );
}

/// Drop path/size lookups without modifying canonical image files on disk.
void evictPageImageFileCaches(int id, String imageName) {
  final key = _pageImageCacheKey(id, imageName);
  _pageImagePathFutureCache.removeWhere(
    (cacheKey, _) => cacheKey == key || cacheKey.startsWith('$key|'),
  );
  // True-size entries include the resolved canonical path. Evict all variants
  // for this logical page so a migrated/offline file cannot reuse stale
  // dimensions from the previous path.
  final prefix = '$key|';
  _pageImageTrueSizeFutureCache.removeWhere(
    (cacheKey, _) => cacheKey == key || cacheKey.startsWith(prefix),
  );
}

Future<String> _validateImagePath(
  String path,
  String unavailableMessage,
) async {
  final file = File(path);
  try {
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file || stat.size <= 0) {
      throw const FileSystemException('image file unavailable');
    }
  } catch (_) {
    // Preserve the local/online classification without exposing file paths.
    throw StateError(unavailableMessage);
  }
  return path;
}

/// Forget path/dimension results after persistent disk-cache cleanup.
void clearImageFileCaches() {
  _jm3x4CoverPathFutureCache.clear();
  _jmSquareCoverPathFutureCache.clear();
  _photoPathFutureCache.clear();
  _pageImagePathFutureCache.clear();
  _pageImageTrueSizeFutureCache.clear();
}

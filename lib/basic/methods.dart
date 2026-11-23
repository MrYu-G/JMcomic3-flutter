import 'dart:convert';
import 'dart:io';

import 'image_cache_stats.dart';
import 'bridge/method_channel_transport.dart';
import 'bridge/response_cache.dart';

import 'package:flutter/services.dart';
import 'package:jmcomic3/basic/log.dart';

import 'method_response_decoder.dart';
import 'entities.dart';
import 'page_image_batch.dart';

export 'page_image_batch.dart';

export 'entities.dart';

const methods = Methods._();

class Methods {
  const Methods._();

  static const _transport = MethodChannelTransport();
  static final _categoriesCache = ResponseCache(
    ttl: const Duration(minutes: 10),
  );
  static final _comicsCache = ResponseCache(ttl: const Duration(minutes: 5));
  static final _albumCache = ResponseCache(ttl: const Duration(minutes: 10));
  static final _coverCache = ResponseCache(ttl: const Duration(minutes: 30));
  static const _defaultCategoriesCacheKey = '__default__';
  static const _downloadThreadMin = 1;

  Future<String> _invoke(String method, dynamic params) =>
      _transport.invoke(method, params);

  void _clearResponseCaches() {
    _categoriesCache.clear();
    _comicsCache.clear();
    _albumCache.clear();
    _coverCache.clear();
  }

  void _evictAlbumCache(int comicId) =>
      _albumCache.removeWhere((key) => key.startsWith('$comicId|'));

  Future init() {
    return _invoke("init_dart", "");
  }

  Future<Map<String, String>> configLinks() async {
    return decodeStringMapResponse(
      await _invoke("config_links", ""),
      "config_links",
    );
  }

  Future<String> loadProperty(String propertyKey) {
    return _invoke("load_property", propertyKey);
  }

  Future<ComicsResponse> comics(String slug, SortBy sortBy, int page) async {
    final normalizedSlug = slug.trim();
    final cacheKey = "$normalizedSlug|${sortBy.value}|$page";
    final rsp = await _comicsCache.load(
      cacheKey,
      () => _invoke("comics", {
        "categories_slug": normalizedSlug,
        "sort_by": sortBy.value,
        "page": page,
      }),
      allowStaleOnError: true,
    );
    return decodeEntityResponse(rsp, "comics", ComicsResponse.fromJson);
  }

  Future<ComicsResponse> comicSearch(
    String searchQuery,
    SortBy sortBy,
    int page,
  ) async {
    final rsp = await _invoke("comic_search", {
      "search_query": searchQuery,
      "sort_by": sortBy.value,
      "page": page,
    });
    return decodeEntityResponse(rsp, "comic_search", ComicsResponse.fromJson);
  }

  Future<ComicsResponse> pageViewLog(int page) async {
    final rsp = await _invoke("page_view_log", page);
    return decodeEntityResponse(rsp, "page_view_log", ComicsResponse.fromJson);
  }

  Future<dynamic> deleteViewLogByComicId(int comicId) async {
    final rsp = await _invoke("delete_view_log_by_comic_id", comicId);
    return rsp;
  }

  Future<CategoriesResponse> categories() async {
    final rsp = await _categoriesCache.load(
      _defaultCategoriesCacheKey,
      () => _invoke("categories", ""),
      allowStaleOnError: true,
    );
    return decodeEntityResponse(rsp, "categories", CategoriesResponse.fromJson);
  }

  Future saveImageFileToGallery(String path) {
    return _transport.invokePlatform("saveImageFileToGallery", path);
  }

  Future saveProperty(String key, String v) {
    return _invoke("save_property", {"k": key, "v": v});
  }

  Future<AlbumResponse> album(int id, {bool ignoreViewLog = false}) async {
    final cacheKey = "$id|$ignoreViewLog";
    final rsp = await _albumCache.load(
      cacheKey,
      () => _invoke("album", {"id": id, "ignore_view_log": ignoreViewLog}),
      allowStaleOnError: true,
    );
    return decodeEntityResponse(rsp, "album", AlbumResponse.fromJson);
  }

  Future<ChapterResponse> chapter(int id) async {
    return decodeEntityResponse(
      await _invoke("chapter", id),
      "chapter",
      ChapterResponse.fromJson,
    );
  }

  Future<CommentPage> forum(String? mode, int? aid, int? uid, int page) async {
    return decodeEntityResponse(
      await _invoke("forum", {
        "mode": mode,
        "aid": aid,
        "uid": uid,
        "page": page,
      }),
      "forum",
      CommentPage.fromJson,
    );
  }

  Future<Favorite> favorites(int folderId, int page, String o) async {
    return decodeEntityResponse(
      await _invoke("favorites", {"folder_id": folderId, "page": page, "o": o}),
      "favorites",
      Favorite.fromJson,
    );
  }

  Future<Favorite> favorite() async {
    return decodeEntityResponse(
      await _invoke("favorite", ""),
      "favorite",
      Favorite.fromJson,
    );
  }

  Future<ActionResponse> setFavorite(int aid) async {
    final rsp = await _invoke("set_favorite", aid);
    _evictAlbumCache(aid);
    return decodeEntityResponse(rsp, "set_favorite", ActionResponse.fromJson);
  }

  Future createFavoriteFolder(String name) async {
    return _invoke("create_favorite_folder", name);
  }

  Future deleteFavoriteFolder(int folderId) async {
    return _invoke("delete_favorite_folder", folderId);
  }

  Future comicFavoriteFolderMove(int comicId, int folderId) async {
    return _invoke("comic_favorite_folder_move", [comicId, folderId]);
  }

  Future renameFavoriteFolder(int folderId, String name) async {
    return _invoke("rename_favorite_folder", ["$folderId", name]);
  }

  Future<GamePage> games(int page) async {
    return decodeEntityResponse(
      await _invoke("games", page),
      "games",
      GamePage.fromJson,
    );
  }

  Future updateViewLog(int id, int lastViewChapterId, int lastViewPage) {
    return _invoke("update_view_log", {
      "id": id,
      "last_view_chapter_id": lastViewChapterId,
      "last_view_page": lastViewPage,
    });
  }

  Future<ViewLog?> findViewLog(int id) async {
    return decodeNullableEntityResponse(
      await _invoke("find_view_log", id),
      "find_view_log",
      ViewLog.fromJson,
    );
  }

  Future cleanAllCache() async {
    final rsp = await _invoke("clean_all_cache", "params");
    _clearResponseCaches();
    return rsp;
  }

  Future<List<ImageCacheDay>> imageCacheStats() async {
    final rows = decodeMapListResponse(
      await _invoke('image_cache_stats', ''),
      'image_cache_stats',
    );
    return rows.map(ImageCacheDay.fromJson).toList(growable: false);
  }

  Future<void> cleanImageCacheDates(List<String> dates) async {
    if (dates.isEmpty) return;
    await _invoke('clean_image_cache_dates', {'dates': dates});
    _clearResponseCaches();
  }

  Future<String> jm3x4Cover(int comicId) {
    return _coverCache.load(
      "3x4|$comicId",
      () => _invoke("jm_3x4_cover", comicId),
      allowStaleOnError: true,
    );
  }

  Future<String> jmSquareCover(int comicId) {
    return _coverCache.load(
      "square|$comicId",
      () => _invoke("jm_square_cover", comicId),
      allowStaleOnError: true,
    );
  }

  Future<String> beginReaderSession() => _invoke('begin_reader_session', '');

  Future<void> endReaderSession(String token) async {
    await _invoke('end_reader_session', token);
  }

  Future<String> jmPageImage(
    int id,
    String imageName, {
    String? readerSession,
  }) {
    return _invoke("jm_page_image", {
      "id": id,
      "image_name": imageName,
      if (readerSession != null) "reader_session": readerSession,
    });
  }

  /// Batch page fetch adapter. Backend support is opt-in; failed/malformed
  /// batches transparently fall back to the existing single-page API.
  Future<List<JmPageImageBatchItem>> jmPageImageBatch(
    List<JmPageImageRequest> pages, {
    bool enabled = false,
  }) async {
    Future<List<JmPageImageBatchItem>> fallback() async {
      final output = <JmPageImageBatchItem>[];
      for (var offset = 0; offset < pages.length; offset += 4) {
        final chunk = pages.sublist(
          offset,
          (offset + 4).clamp(0, pages.length),
        );
        output.addAll(
          await Future.wait(
            chunk.map((p) async {
              try {
                return JmPageImageBatchItem(
                  id: p.id,
                  path: await jmPageImage(
                    p.id,
                    p.imageName,
                    readerSession: p.readerSession,
                  ),
                );
              } catch (e) {
                return JmPageImageBatchItem(
                  id: p.id,
                  error: JmPageImageBatchItem.safeErrorCode(e),
                );
              }
            }),
          ),
        );
      }
      return output;
    }

    if (!enabled || pages.isEmpty) return fallback();
    try {
      final output = <JmPageImageBatchItem>[];
      for (var offset = 0; offset < pages.length; offset += 16) {
        final chunk = pages.sublist(
          offset,
          (offset + 16).clamp(0, pages.length),
        );
        final raw = await _invoke("jm_page_image_batch", {
          "pages": chunk.map((p) => p.toJson()).toList(),
        });
        final decoded = jsonDecode(raw);
        if (decoded is! Map ||
            decoded["version"] != 1 ||
            decoded["items"] is! List) {
          return await fallback();
        }
        // Parse every element strictly.  Filtering non-map values would let a
        // malformed response appear valid when the remaining item count still
        // happened to match the request.
        final items = (decoded["items"] as List)
            .map(JmPageImageBatchItem.fromJson)
            .toList(growable: false);
        if (items.length != chunk.length ||
            !List.generate(
              items.length,
              (i) => items[i].id == chunk[i].id,
            ).every((v) => v)) {
          return await fallback();
        }
        output.addAll(items);
      }
      return output;
    } catch (_) {
      return fallback();
    }
  }

  Future<String> jmPhotoImage(String imageName) {
    return _invoke("jm_photo_image", imageName);
  }

  Future<ImageSize> imageSize(String path) async {
    return decodeEntityResponse(
      await _invoke("image_size", path),
      "image_size",
      ImageSize.fromJson,
    );
  }

  Future<String> loadApiHost() {
    return _invoke("load_api_host", "");
  }

  Future<List<String>> loadApiHostList() async {
    return decodeStringListResponse(
      await _invoke("load_api_host_list", ""),
      "load_api_host_list",
      dedupe: true,
    );
  }

  Future<List<String>> refreshApiHostList() async {
    return decodeStringListResponse(
      await _invoke("refresh_api_host_list", ""),
      "refresh_api_host_list",
      dedupe: true,
    );
  }

  Future<String> loadCdnHost() {
    return _invoke("load_cdn_host", "");
  }

  Future saveApiHost(String choose) async {
    _clearResponseCaches();
    try {
      return await _invoke("save_api_host", choose);
    } finally {
      _clearResponseCaches();
    }
  }

  Future saveCdnHost(String choose) async {
    _clearResponseCaches();
    try {
      return await _invoke("save_cdn_host", choose);
    } finally {
      _clearResponseCaches();
    }
  }

  Future<PreLoginResponse> preLogin() async {
    return decodeEntityResponse(
      await _invoke("pre_login", ""),
      "pre_login",
      PreLoginResponse.fromJson,
    );
  }

  Future<SelfInfo> login(String username, String password) async {
    final rsp = await _invoke("login", {
      "username": username,
      "password": password,
    });
    _clearResponseCaches();
    return decodeEntityResponse(rsp, "login", SelfInfo.fromJson);
  }

  Future logout() async {
    await _invoke("logout", {});
    _clearResponseCaches();
  }

  Future<CommentResponse> comment(int aid, String comment) async {
    return decodeEntityResponse(
      await _invoke("comment", {"aid": aid, "comment": comment}),
      "comment",
      CommentResponse.fromJson,
    );
  }

  Future<CommentResponse> childComment(
    int aid,
    String comment,
    int? commentId,
  ) async {
    return decodeEntityResponse(
      await _invoke("child_comment", {
        "aid": aid,
        "comment": comment,
        "comment_id": commentId,
      }),
      "child_comment",
      CommentResponse.fromJson,
    );
  }

  Future<String> loadUsername() {
    return _invoke("load_username", "");
  }

  Future<String> loadLastLoginUsername() {
    return _invoke("loadLastLoginUsername", "");
  }

  Future<String> loadPassword() {
    return _invoke("load_password", "");
  }

  Future clearViewLog() {
    return _invoke("clear_view_log", "");
  }

  Future<List<SearchHistory>> lastSearchHistories(int count) async {
    if (count <= 0) {
      // 调用方用 0 表示不展示搜索历史；直接在 Dart 侧短路，避免一次无意义桥接调用。
      return const <SearchHistory>[];
    }
    return decodeEntityListResponse(
      await _invoke("last_search_histories", "$count"),
      "last_search_histories",
      SearchHistory.fromJson,
    );
  }

  /// Download list
  Future<List<DownloadAlbum>> allDownloads() async {
    return decodeEntityListResponse(
      await _invoke("all_downloads", ""),
      "all_downloads",
      DownloadAlbum.fromJson,
    );
  }

  Future<void> pauseDownload(int id) async {
    await _invoke('pause_download', id);
  }

  Future<void> resumeDownload(int id) async {
    await _invoke('resume_download', id);
  }

  Future<DownloadAlbum?> downloadAlbumById(int id) async {
    // 下载详情页轮询只需要摘要字段；后端单项接口复用 all_downloads 的 wire 形状。
    return decodeNullableEntityResponse(
      await _invoke("download_album_by_id", "$id"),
      "download_album_by_id",
      DownloadAlbum.fromJson,
    );
  }

  /// Find download item
  Future<DownloadCreate?> downloadById(int id) async {
    return decodeNullableEntityResponse(
      await _invoke("download_by_id", "$id"),
      "download_by_id",
      DownloadCreate.fromJson,
    );
  }

  /// Create download task
  Future<dynamic> createDownload(DownloadCreate create) async {
    return _invoke("create_download", create);
  }

  /// Download image list
  Future<List<DlImage>> dlImageByChapterId(int id) async {
    return decodeEntityListResponse(
      await _invoke("dl_image_by_chapter_id", "$id"),
      "dl_image_by_chapter_id",
      DlImage.fromJson,
    );
  }

  /// Optional, read-only local availability probe. Older backends may not
  /// implement it; callers must treat errors/unknown payloads as unavailable.
  Future<List<DlImage>> dlImageLocalAvailability(int id) async {
    try {
      final raw = await _invoke("dl_image_local_availability", "$id");
      return decodeEntityListResponse(
        raw,
        "dl_image_local_availability",
        DlImage.fromJson,
      );
    } catch (_) {
      return const <DlImage>[];
    }
  }

  Future<dynamic> deleteDownload(int id) async {
    return _invoke("delete_download", id);
  }

  Future<dynamic> renewAllDownloads() async {
    return _invoke("renew_all_downloads", "");
  }

  /// Get Android refresh modes
  Future<List<String>> loadAndroidModes() async {
    try {
      final raw = await _transport.invokePlatform("androidGetModes");
      return decodeStringListValue(raw, "androidGetModes", dedupe: true);
    } on PlatformException catch (e, s) {
      // 刷新率模式只影响设置页展示；通道异常时降级为空列表，避免应用初始化被阻断。
      debugPrient(
        "androidGetModes fallback []: ${e.runtimeType}/${s.runtimeType}",
      );
      return const <String>[];
    }
  }

  /// Set Android refresh mode
  Future setAndroidMode(String androidDisplayMode) {
    final normalizedMode = androidDisplayMode.trim();
    return _transport.invokePlatform("androidSetMode", {
      "mode": normalizedMode,
    });
  }

  /// Get Android SDK version
  Future<int> androidGetVersion() async {
    if (Platform.isAndroid) {
      return await _transport.invokePlatform("androidGetVersion", {});
    }
    return 0;
  }

  Future export_jm_jpegs(List<int> idList, String path, bool deleteExported) {
    return _invoke("export_jm_jpegs", {
      "comic_id": idList,
      "dir": path,
      "delete_exported": deleteExported,
    });
  }

  Future export_jm_zip(List<int> idList, String path, bool deleteExported) {
    return _invoke("export_jm_zip", {
      "comic_id": idList,
      "dir": path,
      "delete_exported": deleteExported,
    });
  }

  Future export_jm_zip_single(
    int id,
    String folder,
    String? rename,
    bool deleteExported,
  ) {
    return _invoke("export_jm_zip_single", {
      "id": id,
      "folder": folder,
      "rename": rename,
      "delete_exported": deleteExported,
    });
  }

  Future export_jm_jpegs_zip_single(
    int id,
    String folder,
    String? rename,
    bool deleteExported,
  ) {
    return _invoke("export_jm_jpegs_zip_single", {
      "id": id,
      "folder": folder,
      "rename": rename,
      "delete_exported": deleteExported,
    });
  }

  Future export_jm_jmi(List<int> idList, String path, bool deleteExported) {
    return _invoke("export_jm_jmi", {
      "comic_id": idList,
      "dir": path,
      "delete_exported": deleteExported,
    });
  }

  Future export_jm_jmi_single(
    int id,
    String folder,
    String? rename,
    bool deleteExported,
  ) {
    return _invoke("export_jm_jmi_single", {
      "id": id,
      "folder": folder,
      "rename": rename,
      "delete_exported": deleteExported,
    });
  }

  Future export_cbzs_zip_single(
    int id,
    String folder,
    String? rename,
    bool deleteExported,
  ) {
    return _invoke("export_cbzs_zip_single", {
      "id": id,
      "folder": folder,
      "rename": rename,
      "delete_exported": deleteExported,
    });
  }

  Future export_jm_pdf(int id, String folder, bool deleteExported) {
    return _invoke("export_jm_pdf", {
      "comic_id": [id],
      "dir": folder,
      "delete_exported": deleteExported,
    });
  }

  Future export_jm_pdf2(int id, String folder, bool deleteExported) {
    return _invoke("export_jm_pdf2", {
      "comic_id": [id],
      "dir": folder,
      "delete_exported": deleteExported,
    });
  }

  Future export_jm_epub(List<int> idList, String path, bool deleteExported) {
    return _invoke("export_jm_epub", {
      "comic_id": idList,
      "dir": path,
      "delete_exported": deleteExported,
    });
  }

  Future export_jm_epub_single(
    int id,
    String folder,
    String? rename,
    bool deleteExported,
  ) {
    return _invoke("export_jm_epub_single", {
      "id": id,
      "folder": folder,
      "rename": rename,
      "delete_exported": deleteExported,
    });
  }

  Future import_jm_zip(String path) {
    debugPrient('[import] type=zip pathProvided=${path.isNotEmpty}');
    return _invoke("import_jm_zip", path);
  }

  Future import_jm_jmi(String path) {
    debugPrient('[import] type=jmi pathProvided=${path.isNotEmpty}');
    return _invoke("import_jm_jmi", path);
  }

  Future import_jm_dir(String path) {
    debugPrient('[import] type=dir pathProvided=${path.isNotEmpty}');
    return _invoke("import_jm_dir", path);
  }

  Future<IsPro> isPro() async {
    return decodeEntityResponse(
      await _invoke("is_pro", ""),
      "is_pro",
      IsPro.fromJson,
    );
  }

  Future<ProInfoAll> proInfoAll() async {
    return decodeEntityResponse(
      await _invoke("pro_info_all", ""),
      "pro_info_all",
      ProInfoAll.fromJson,
    );
  }

  Future reloadPro() {
    return _invoke("reload_pro", "");
  }

  Future inputCdKey(String cdKey) {
    return _invoke("input_cd_key", cdKey);
  }

  Future checkPat(String accessKey) {
    return _invoke("check_pat", accessKey);
  }

  Future bindPatAccount(String accessKey, String username) {
    return _invoke(
      "bind_pat",
      jsonEncode({"access_key": accessKey, "username": username}),
    );
  }

  Future reloadPatAccount() {
    return _invoke("reload_pat_account", "");
  }

  Future clearPat() {
    return _invoke("clear_pat", "");
  }

  Future<int> load_download_thread() async {
    // 线程上下限由后端统一维护；前端只解析稳定的标量响应并提供桥接故障回退值。
    return decodeBackendInt(
      await _invoke("load_download_thread", ""),
      fallback: _downloadThreadMin,
    );
  }

  Future set_download_thread(int count) {
    // 线程范围只在后端归一化，避免前后端维护两套容易漂移的边界常量。
    return _invoke("set_download_thread", "$count");
  }

  Future clearAllSearchLog() {
    return _invoke("clear_all_search_log", "");
  }

  Future clearASearchLog(String log) {
    return _invoke("clear_a_search_log", log);
  }

  Future setProxy(String url) async {
    _clearResponseCaches();
    try {
      return await _invoke("set_proxy", url);
    } finally {
      _clearResponseCaches();
    }
  }

  Future<String> getProxy() {
    return _invoke("get_proxy", "");
  }

  Future webDavSync(dynamic params) {
    return _invoke("sync_webdav", params);
  }

  Future<String> iosGetDocumentDir() async {
    return await _transport.invokePlatform("iosGetDocumentDir");
  }

  Future<String> androidDefaultExportsDir() async {
    return await _transport.invokePlatform("androidDefaultExportsDir");
  }

  Future<String> getDownloadAndExportTo() async {
    return await _invoke("get_download_and_export_to", "");
  }

  Future<String> getEffectiveDownloadDir() =>
      _invoke('get_effective_download_dir', '');

  Future<String> getHomeDir() async {
    return await _invoke("getHomeDir", "");
  }

  Future setDownloadAndExportTo(String path) async {
    return await _invoke("set_download_and_export_to", path);
  }

  Future<int> ping(String idx) async {
    debugPrient("PING API $idx");
    return decodeBackendInt(await _invoke("ping_server", idx), fallback: 0);
  }

  Future<int> pingCdn(String idx) async {
    debugPrient("PING CDN $idx");
    return decodeBackendInt(await _invoke("ping_cdn", idx), fallback: 0);
  }

  Future mkdirs(String path) {
    return _invoke("mkdirs", path);
  }

  Future androidMkdirs(String path) async {
    return await _transport.invokePlatform("androidMkdirs", path);
  }

  Future<String> picturesDir() async {
    return await _transport.invokePlatform("picturesDir");
  }

  Future<String> copyPictureToFolder(String folder, String path) async {
    return await _invoke("copyPictureToFolder", {
      "folder": folder,
      "path": path,
    });
  }

  Future<String> getProServerName() async {
    try {
      final name = await _invoke("get_pro_server_name", "");
      if (name == "HK" || name == "US") {
        return name;
      }
    } catch (e, s) {
      debugPrient(
        "get_pro_server_name fallback HK: ${e.runtimeType}/${s.runtimeType}",
      );
    }
    return "HK";
  }

  Future setProServerName(String serverName) async {
    try {
      return await _invoke("set_pro_server_name", serverName);
    } catch (e, s) {
      debugPrient(
        "set_pro_server_name ignored: ${e.runtimeType}/${s.runtimeType}",
      );
      return "";
    }
  }

  Future<bool> verifyAuthentication() async {
    return await _transport.invokePlatform("verifyAuthentication");
  }

  Future<String> daily(int uid) {
    return _invoke("daily", uid);
  }

  Future<WeekData> week(int page) async {
    return decodeEntityResponse(
      await _invoke("week", {"page": page}),
      "week",
      WeekData.fromJson,
    );
  }

  Future<WeekFilterResponse> weekFilter(
    String categoryId,
    String typeId,
    int page,
  ) async {
    return decodeEntityResponse(
      await _invoke("week_filter", {
        "category_id": categoryId,
        "type_id": typeId,
        "page": page,
      }),
      "week_filter",
      WeekFilterResponse.fromJson,
    );
  }
}

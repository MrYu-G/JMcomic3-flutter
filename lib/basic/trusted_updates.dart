import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const updateRepository = 'MrYu-G/JMcomic3-flutter';
const officialReleasePage = 'https://github.com/$updateRepository/releases/';
const latestReleaseApi =
    'https://api.github.com/repos/$updateRepository/releases/latest';

class AppVersion implements Comparable<AppVersion> {
  AppVersion._(this.parts);

  final List<int> parts;
  static final pattern = RegExp(r'^v(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?$');

  static AppVersion? parse(String value) {
    final match = pattern.firstMatch(value);
    if (match == null) return null;
    final parts = <int>[];
    for (var i = 1; i <= 4; i++) {
      final part = int.tryParse(match.group(i) ?? '0');
      if (part == null) return null;
      parts.add(part);
    }
    return AppVersion._(parts);
  }

  @override
  int compareTo(AppVersion other) {
    for (var i = 0; i < parts.length; i++) {
      final comparison = parts[i].compareTo(other.parts[i]);
      if (comparison != 0) return comparison;
    }
    return 0;
  }
}

bool _httpsHost(Uri uri, String host) =>
    uri.scheme == 'https' &&
    uri.host == host &&
    uri.userInfo.isEmpty &&
    uri.port == 443 &&
    !uri.hasFragment;

bool _repositoryPath(Uri uri, String host, List<String> suffix) {
  final prefix = host == 'api.github.com' ? ['repos'] : <String>[];
  final expected = [...prefix, ...updateRepository.split('/'), ...suffix];
  final actual = uri.pathSegments;
  return _httpsHost(uri, host) &&
      !uri.hasQuery &&
      actual.length == expected.length &&
      List.generate(
        expected.length,
        (i) => actual[i] == expected[i],
      ).every((match) => match);
}

class UpdateAsset {
  UpdateAsset._(this.name, this.url, this.size, this.sha256Hex);

  final String name;
  final Uri url;
  final int size;
  final String sha256Hex;

  static UpdateAsset? parse(Object? value, String tag) {
    if (value is! Map) return null;
    final name = value['name'];
    final size = value['size'];
    final digest = value['digest'];
    final url = Uri.tryParse(value['browser_download_url']?.toString() ?? '');
    if (name is! String ||
        size is! int ||
        size <= 0 ||
        digest is! String ||
        !RegExp(r'^sha256:[a-fA-F0-9]{64}$').hasMatch(digest) ||
        url == null ||
        !_repositoryPath(url, 'github.com', [
          'releases',
          'download',
          tag,
          name,
        ])) {
      return null;
    }
    // Only release packages for the supported targets are offered as updates.
    final names = [
      'Jmcomic3-arm64-v8a-$tag.apk',
      'Jmcomic3-armeabi-v7a-$tag.apk',
      'Jmcomic3-windows-x64-$tag.zip',
    ];
    if (!names.contains(name)) return null;
    return UpdateAsset._(name, url, size, digest.substring(7).toLowerCase());
  }
}

class TrustedRelease {
  TrustedRelease._(this.tag, this.body, this.assets, this.json);

  final String tag;
  final String body;
  final List<UpdateAsset> assets;
  final Map<String, dynamic> json;

  static TrustedRelease parse(Object? data) {
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Invalid release response');
    }
    final tag = data['tag_name'];
    final id = data['id'];
    final body = data['body'];
    final api = Uri.tryParse(data['url']?.toString() ?? '');
    final page = Uri.tryParse(data['html_url']?.toString() ?? '');
    if (tag is! String ||
        AppVersion.parse(tag) == null ||
        id is! int ||
        id <= 0 ||
        data['draft'] != false ||
        data['prerelease'] != false ||
        (body != null && body is! String) ||
        api == null ||
        page == null ||
        !_repositoryPath(api, 'api.github.com', ['releases', '$id']) ||
        !_repositoryPath(page, 'github.com', ['releases', 'tag', tag])) {
      throw const FormatException('Release identity could not be verified');
    }
    final rawAssets = data['assets'];
    if (rawAssets is! List) {
      throw const FormatException('Invalid release assets');
    }
    final assets = rawAssets
        .map((asset) => UpdateAsset.parse(asset, tag))
        .whereType<UpdateAsset>()
        .toList(growable: false);
    return TrustedRelease._(tag, body as String? ?? '', assets, data);
  }

  bool isNewerThan(String current) {
    final installed = AppVersion.parse(current);
    return installed != null && AppVersion.parse(tag)!.compareTo(installed) > 0;
  }
}

/// Metadata never passes through a content mirror or a native generic HTTP
/// route. Its HTTPS origin is the trust anchor for release identity and digest.
class TrustedUpdateClient {
  TrustedUpdateClient({HttpClient? client}) : _client = client ?? HttpClient() {
    _client.connectionTimeout = const Duration(seconds: 10);
    _client.idleTimeout = const Duration(seconds: 30);
    _client.userAgent = 'JMcomic3-Updater';
  }

  final HttpClient _client;

  Future<TrustedRelease> latest() async {
    final request = await _client
        .getUrl(Uri.parse(latestReleaseApi))
        .timeout(const Duration(seconds: 12));
    request.followRedirects = false;
    request.headers.set('Accept', 'application/vnd.github+json');
    request.headers.set('X-GitHub-Api-Version', '2022-11-28');
    final response = await request.close().timeout(const Duration(seconds: 15));
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>().timeout(const Duration(seconds: 15));
      throw HttpException('Update check returned HTTP ${response.statusCode}');
    }
    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 15))) {
      if (bytes.length + chunk.length > 4 * 1024 * 1024) {
        throw const FormatException('Release response is too large');
      }
      bytes.addAll(chunk);
    }
    return TrustedRelease.parse(jsonDecode(utf8.decode(bytes)));
  }

  void close() => _client.close(force: true);
}

enum UpdateDownloadPhase { downloading, verifying, ready }

class UpdateDownloadProgress {
  const UpdateDownloadProgress(this.phase, this.received, this.total);

  final UpdateDownloadPhase phase;
  final int received;
  final int total;
  double get fraction => total == 0 ? 0 : (received / total).clamp(0, 1);
}

class UpdateDownloadCancelled implements Exception {}

class UpdateDownloader {
  UpdateDownloader({HttpClient? client}) : _client = client ?? HttpClient() {
    _client.connectionTimeout = const Duration(seconds: 15);
    _client.autoUncompress = false;
  }

  final HttpClient _client;
  bool _cancelled = false;

  void cancel() {
    _cancelled = true;
    _client.close(force: true);
  }

  void _checkCancelled() {
    if (_cancelled) throw UpdateDownloadCancelled();
  }

  static bool allowedRedirect(Uri uri) =>
      _httpsHost(uri, 'release-assets.githubusercontent.com') ||
      _httpsHost(uri, 'objects.githubusercontent.com');

  /// Caller owns the returned temporary directory after success. Until then,
  /// errors/cancellation remove the partial file and its task-owned directory.
  Future<File> download(
    UpdateAsset asset,
    void Function(UpdateDownloadProgress) onProgress,
  ) async {
    final directory = await Directory.systemTemp.createTemp('jmcomic3-update-');
    final partial = File('${directory.path}/${asset.name}.part');
    IOSink? sink;
    var succeeded = false;
    try {
      var uri = asset.url;
      HttpClientResponse? response;
      for (var redirects = 0; redirects <= 3; redirects++) {
        _checkCancelled();
        final request = await _client
            .getUrl(uri)
            .timeout(const Duration(seconds: 15));
        request.followRedirects = false;
        request.headers.set('Accept-Encoding', 'identity');
        response = await request.close().timeout(const Duration(seconds: 20));
        if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          await response.drain<void>().timeout(const Duration(seconds: 15));
          if (location == null) throw const HttpException('Missing redirect');
          uri = uri.resolve(location);
          if (!allowedRedirect(uri) || redirects == 3) {
            throw const HttpException('Untrusted update download redirect');
          }
          continue;
        }
        break;
      }
      if (response == null || response.statusCode != HttpStatus.ok) {
        throw const HttpException('Update package download failed');
      }
      if (response.contentLength >= 0 && response.contentLength != asset.size) {
        throw const FormatException('Update package size mismatch');
      }
      sink = partial.openWrite();
      var received = 0;
      onProgress(
        UpdateDownloadProgress(UpdateDownloadPhase.downloading, 0, asset.size),
      );
      // addStream observes asynchronous disk errors and applies backpressure
      // while the network is still producing data.
      await sink.addStream(
        response.timeout(const Duration(seconds: 30)).map((chunk) {
          _checkCancelled();
          received += chunk.length;
          if (received > asset.size) {
            throw const FormatException('Update package exceeds expected size');
          }
          onProgress(
            UpdateDownloadProgress(
              UpdateDownloadPhase.downloading,
              received,
              asset.size,
            ),
          );
          return chunk;
        }),
      );
      await sink.flush();
      await sink.close();
      sink = null;
      _checkCancelled();
      if (received != asset.size) {
        throw const FormatException('Incomplete update package');
      }
      onProgress(
        UpdateDownloadProgress(
          UpdateDownloadPhase.verifying,
          received,
          asset.size,
        ),
      );
      final digest = await sha256.bind(partial.openRead()).first;
      _checkCancelled();
      if (digest.toString() != asset.sha256Hex) {
        throw const FormatException('Update package SHA-256 mismatch');
      }
      final file = await partial.rename('${directory.path}/${asset.name}');
      succeeded = true;
      onProgress(
        UpdateDownloadProgress(UpdateDownloadPhase.ready, received, asset.size),
      );
      return file;
    } catch (_) {
      if (_cancelled) throw UpdateDownloadCancelled();
      rethrow;
    } finally {
      // Closing a failed disk write can itself throw. Preserve the original
      // failure/cancellation and still release the socket and partial package.
      try {
        await sink?.close();
      } catch (_) {
        // The write/flush failure is already propagated by the main operation.
      } finally {
        _client.close(force: true);
        if (!succeeded) {
          try {
            if (await directory.exists())
              await directory.delete(recursive: true);
          } catch (_) {
            // A locked file must not hide the original download failure.
          }
        }
      }
    }
  }
}

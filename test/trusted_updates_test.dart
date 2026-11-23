import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/basic/trusted_updates.dart';
import 'package:jmcomic3/configs/versions.dart';

Map<String, dynamic> releaseFixture({
  String tag = 'v1.7.27+56',
  List<int> bytes = const [1, 2, 3],
}) => {
  'id': 123,
  'tag_name': tag,
  'name': 'An arbitrary display title is not a version',
  'url': 'https://api.github.com/repos/$updateRepository/releases/123',
  'html_url':
      'https://github.com/$updateRepository/releases/tag/${Uri.encodeComponent(tag)}',
  'draft': false,
  'prerelease': false,
  'body': '# Full notes\n\nFirst paragraph.\n\nLast paragraph.',
  'assets': [
    {
      'name': 'Jmcomic3-windows-x64-$tag.zip',
      'size': bytes.length,
      'digest': 'sha256:${sha256.convert(bytes)}',
      'browser_download_url':
          'https://github.com/$updateRepository/releases/download/${Uri.encodeComponent(tag)}/${Uri.encodeComponent('Jmcomic3-windows-x64-$tag.zip')}',
    },
  ],
};

class _Headers extends Fake implements HttpHeaders {
  final values = <String, String>{};
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) =>
      values[name.toLowerCase()] = '$value';
  @override
  String? value(String name) => values[name.toLowerCase()];
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(
    this.chunks, {
    this.statusCode = 200,
    this.contentLength = -1,
    String? location,
  }) {
    if (location != null) headers.set('location', location);
  }
  final List<List<int>> chunks;
  @override
  final int statusCode;
  @override
  final int contentLength;
  @override
  final _Headers headers = _Headers();
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.fromIterable(chunks).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Request extends Fake implements HttpClientRequest {
  _Request(this.response);
  final _Response response;
  @override
  bool followRedirects = true;
  @override
  final HttpHeaders headers = _Headers();
  @override
  Future<HttpClientResponse> close() async => response;
}

class _Client extends Fake implements HttpClient {
  _Client(this.respond);
  final _Response Function(Uri) respond;
  final requests = <Uri>[];
  final nativeRequests = <_Request>[];
  bool closed = false;
  @override
  Duration? connectionTimeout;
  @override
  Duration idleTimeout = Duration.zero;
  @override
  String? userAgent;
  @override
  bool autoUncompress = true;
  @override
  Future<HttpClientRequest> getUrl(Uri uri) async {
    requests.add(uri);
    final request = _Request(respond(uri));
    nativeRequests.add(request);
    return request;
  }

  @override
  void close({bool force = false}) => closed = true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('release identity and numeric progression are required', () {
    final release = TrustedRelease.parse(releaseFixture());
    expect(release.body, contains('Last paragraph.'));
    expect(release.isNewerThan('v1.7.26+55'), isTrue);
    expect(release.isNewerThan('v1.7.27+56'), isFalse);
    expect(release.isNewerThan('v1.7.28+1'), isFalse);
    expect(release.isNewerThan('dirty'), isFalse);
    expect(
      AppVersion.parse('v1.10.0')!.compareTo(AppVersion.parse('v1.9.99+500')!),
      greaterThan(0),
    );
    for (final tag in [
      'fake-update',
      'v1.2',
      'v1.2.3-beta',
      'v1.2.3\n',
      'v-1.2.3',
    ]) {
      expect(AppVersion.parse(tag), isNull, reason: tag);
      expect(
        () => TrustedRelease.parse(releaseFixture(tag: tag)),
        throwsFormatException,
      );
    }
  });

  test('repository substrings, redirects, old owners and mismatched tags cannot establish trust', () {
    for (final page in [
      'https://attacker.invalid/?next=https://github.com/$updateRepository/releases/tag/v1.7.27%2B56',
      'https://github.com.attacker.invalid/$updateRepository/releases/tag/v1.7.27%2B56',
      'https://github.com@attacker.invalid/$updateRepository/releases/tag/v1.7.27%2B56',
      'https://attacker@github.com/$updateRepository/releases/tag/v1.7.27%2B56',
      'http://github.com/$updateRepository/releases/tag/v1.7.27%2B56',
      'https://github.com/MrYu-JMComic/JMcomic3-flutter/releases/tag/v1.7.27%2B56',
      'https://github.com/$updateRepository/releases/tag/v9.9.9',
      'https://github.com/$updateRepository/releases/tag/v1.7.27%2B56?next=other',
      'https://github.com/$updateRepository/releases/tag/v1.7.27%2B56#other',
    ]) {
      expect(
        () => TrustedRelease.parse(releaseFixture()..['html_url'] = page),
        throwsFormatException,
        reason: page,
      );
    }
    for (final changes in [
      {'url': 'https://api.github.com/repos/other/repo/releases/123'},
      {'id': 124},
      {'draft': true},
      {'prerelease': true},
      {'assets': null},
    ]) {
      expect(
        () => TrustedRelease.parse(releaseFixture()..addAll(changes)),
        throwsFormatException,
      );
    }
  });

  test(
    'packages require matching official tag/name, size and trusted digest',
    () {
      final json = releaseFixture();
      final original = (json['assets'] as List).single as Map<String, dynamic>;
      for (final change in [
        {'digest': null},
        {'digest': 'sha256:bad'},
        {'size': 0},
        {
          'browser_download_url':
              'https://ghproxy.com/${original['browser_download_url']}',
        },
        {'name': '../update.apk'},
        {'name': 'novel-reader.apk'},
      ]) {
        final modified = Map<String, dynamic>.from(original)..addAll(change);
        expect(
          TrustedRelease.parse({
            ...json,
            'assets': [modified],
          }).assets,
          isEmpty,
        );
      }
    },
  );

  test(
    'metadata uses only direct GitHub API and never follows redirects',
    () async {
      final client = _Client(
        (_) => _Response([utf8.encode(jsonEncode(releaseFixture()))]),
      );
      final updater = TrustedUpdateClient(client: client);
      expect((await updater.latest()).tag, 'v1.7.27+56');
      expect(client.requests, [Uri.parse(latestReleaseApi)]);
      expect(client.nativeRequests.single.followRedirects, isFalse);
      updater.close();
      expect(client.closed, isTrue);
      final redirect = _Client(
        (_) => _Response(
          [],
          statusCode: 302,
          location: 'https://attacker.invalid',
        ),
      );
      await expectLater(
        TrustedUpdateClient(client: redirect).latest(),
        throwsA(isA<HttpException>()),
      );
      expect(redirect.requests, hasLength(1));
    },
  );

  test(
    'download permits GitHub CDN redirect then verifies bytes before ready',
    () async {
      final asset = TrustedRelease.parse(releaseFixture()).assets.single;
      final client = _Client(
        (uri) => uri.host == 'github.com'
            ? _Response(
                [],
                statusCode: 302,
                location: 'https://release-assets.githubusercontent.com/github-production-release-asset/test?signature=synthetic',
              )
            : _Response([
                [1],
                [2, 3],
              ], contentLength: 3),
      );
      final events = <UpdateDownloadProgress>[];
      final file = await UpdateDownloader(client: client)
          .download(asset, events.add);
      try {
        expect(await file.readAsBytes(), [1, 2, 3]);
        expect(events.last.phase, UpdateDownloadPhase.ready);
        expect(
          events.map((event) => event.phase),
          contains(UpdateDownloadPhase.verifying),
        );
        expect(
          client.nativeRequests.every((request) => !request.followRedirects),
          isTrue,
        );
        expect(client.closed, isTrue);
      } finally {
        await file.parent.delete(recursive: true);
      }
    },
  );

  test(
    'hijacked, truncated, oversized and corrupt downloads never become ready',
    () async {
      final asset = TrustedRelease.parse(releaseFixture()).assets.single;
      for (final response in [
        _Response(
          [],
          statusCode: 302,
          location: 'https://attacker.invalid/file',
        ),
        _Response(
          [],
          statusCode: 302,
          location: 'http://release-assets.githubusercontent.com/file',
        ),
        _Response([
          [1, 2],
        ]),
        _Response([
          [1, 2, 3, 4],
        ]),
        _Response([
          [9, 9, 9],
        ]),
        _Response([
          [1, 2, 3],
        ], contentLength: 4),
      ]) {
        final events = <UpdateDownloadProgress>[];
        final client = _Client((_) => response);
        await expectLater(
          UpdateDownloader(client: client).download(asset, events.add),
          throwsA(isA<Exception>()),
        );
        expect(
          events.where((event) => event.phase == UpdateDownloadPhase.ready),
          isEmpty,
        );
        expect(client.closed, isTrue);
      }
    },
  );

  test('cancelling a download prevents readiness', () async {
    final asset = TrustedRelease.parse(releaseFixture()).assets.single;
    final downloader = UpdateDownloader(
      client: _Client(
        (_) => _Response([
          [1],
          [2],
          [3],
        ]),
      ),
    );
    await expectLater(
      downloader.download(asset, (progress) {
        if (progress.received == 1) downloader.cancel();
      }),
      throwsA(isA<UpdateDownloadCancelled>()),
    );
  });

  test(
    'startup discards old untrusted caches and invalid verified envelopes',
    () async {
      final properties = {
        'latestVersionNameCache': 'v99.0.0',
        'latestVersionInfoCache': 'Download a novel app',
        'latestVersionRepoCache': updateRepository,
        'verifiedGithubReleaseCacheV1': jsonEncode({
          'repository': 'attacker/repo',
          'release': releaseFixture(),
        }),
      };
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('methods'), (
            call,
          ) async {
            final request = jsonDecode(call.arguments as String) as Map;
            if (request['method'] == 'load_property') {
              return jsonEncode({
                'error_message': '',
                'response_data': properties[request['params']] ?? '',
              });
            }
            if (request['method'] == 'save_property') {
              final params = jsonDecode(request['params'] as String) as Map;
              properties[params['k'] as String] = params['v'] as String;
              return jsonEncode({'error_message': '', 'response_data': ''});
            }
            throw StateError('Unexpected native method');
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(const MethodChannel('methods'), null),
      );
      await initVersion();
      expect(latestVersion, isNull);
      expect(latestVersionInfo(), isNull);
      expect(properties.values.every((value) => value.isEmpty), isTrue);
      expect(latestDownloadUrl(), officialReleasePage);
    },
  );
}

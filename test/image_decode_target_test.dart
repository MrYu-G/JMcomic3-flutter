import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/basic/image_decode_targets.dart';
import 'package:jmcomic3/basic/page_image_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('decode target is bounded to stable buckets', () {
    expect(imageDecodeTargetExtent(100, 1), 256);
    expect(imageDecodeTargetExtent(500, 1), 512);
    expect(imageDecodeTargetExtent(900, 2), 2048);
    expect(imageDecodeTargetExtent(null, 2), isNull);
    expect(imageDecodeTargetExtent(0, 2), isNull);
    expect(imageDecodeTargetExtent(10000, 4), 4096);
    expect(imageDecodeTargetExtent(double.infinity, 1), isNull);
    expect(imageDecodeTargetExtent(100, double.nan), isNull);
  });

  test('page provider key includes bounded codec targets', () {
    final small = PageImageProvider(
      1,
      'page.jpg',
      cacheWidth: 100,
      cacheHeight: 200,
    );
    final same = PageImageProvider(
      1,
      'page.jpg',
      cacheWidth: 101,
      cacheHeight: 201,
    );
    final different = PageImageProvider(
      1,
      'page.jpg',
      cacheWidth: 500,
      cacheHeight: 200,
    );

    expect(small.cacheWidth, 256);
    expect(small.cacheHeight, 256);
    expect(small, same);
    expect(small, isNot(different));
    expect(small.hashCode, same.hashCode);
  });

  test('duplicate source pages keep distinct provider identities', () {
    final first = PageImageProvider(
      1,
      'same.jpg',
      pageIndex: 0,
      cacheWidth: 400,
    );
    final second = PageImageProvider(
      1,
      'same.jpg',
      pageIndex: 1,
      cacheWidth: 400,
    );

    expect(first, isNot(second));
    expect(first.hashCode, isNot(second.hashCode));
  });

  test(
    'local-only provider rejects missing availability without bridge call',
    () async {
      final provider = PageImageProvider(1, 'missing.jpg', localOnly: true);

      await expectLater(
        provider.loadCodecForTest(),
        throwsA(isA<StateError>()),
      );
    },
  );

  test('local-only provider treats blank local path as unavailable', () async {
    final provider = PageImageProvider(
      2,
      'blank.jpg',
      localPath: '   ',
      localOnly: true,
    );

    expect(provider.localPath, isNull);
    await expectLater(provider.loadCodecForTest(), throwsA(isA<StateError>()));
  });
}

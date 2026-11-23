import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/basic/page_image_provider.dart';

import 'synthetic_png.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'target codec produces bounded pixels from a canonical fixture',
    () async {
      final directory = await Directory.systemTemp.createTemp('jm3-codec-');
      addTearDown(() => directory.delete(recursive: true));
      final fixture = File('${directory.path}/page.png');
      await writeSyntheticPng(fixture, width: 421, height: 751);
      final provider = PageImageProvider(
        9001,
        'fixture.png',
        localPath: fixture.path,
        cacheWidth: 256,
      );
      final codec = await provider.loadCodecForTest();
      addTearDown(codec.dispose);
      final frame = await codec.getNextFrame();
      addTearDown(frame.image.dispose);

      // The synthetic source is 421x751. Target decoding must reduce the bitmap while
      // retaining its aspect ratio; no scrambled/network bytes are involved in
      // this step.
      expect(frame.image.width, 256);
      expect(frame.image.height, 456);
      expect(frame.image.height / frame.image.width, closeTo(751 / 421, 0.03));
    },
  );
}

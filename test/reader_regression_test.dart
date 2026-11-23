import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_view/photo_view.dart';
import 'package:jmcomic3/basic/image_files.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/configs/no_animation.dart';
import 'package:jmcomic3/configs/reader_controller_type.dart';
import 'package:jmcomic3/configs/reader_direction.dart';
import 'package:jmcomic3/configs/reader_preload.dart';
import 'package:jmcomic3/configs/reader_slider_position.dart';
import 'package:jmcomic3/configs/reader_type.dart';
import 'package:jmcomic3/configs/two_page_direction.dart';
import 'package:jmcomic3/configs/volume_key_control.dart';
import 'package:jmcomic3/configs/theme.dart' as app_theme;
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/comic_reader_screen.dart';
import 'package:jmcomic3/screens/components/images.dart';
import 'package:jmcomic3/basic/page_image_provider.dart';
import 'package:zoomable_positioned_list/zoomable_positioned_list.dart'
    as zoomable;

Future<void> Function(String name, WidgetTester tester)? readerCheckpoint;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  final heights = <int>[64, 384, 128, 512, 96, 320, 64, 384, 64, 128];
  final paths = <String>[];
  final viewLogs = <int>[];
  final imageRequests = <String>[];
  Completer<void>? imageGate;
  var direction = ReaderDirection.leftToRight;
  var controlMode = ReaderControllerType.controller;
  var sliderPosition = ReaderSliderPosition.bottom;
  var configuredType = ReaderType.webtoon;
  var preloadCount = 2;

  setUpAll(() async {
    directory = Directory(
      Platform.isAndroid
          ? '${Directory.systemTemp.path}/jm-reader-rewrite-fixtures'
          : 'build/checks/reader-performance/fixtures',
    );
    await directory.create(recursive: true);
    for (var index = 0; index < heights.length; index++) {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        Rect.fromLTWH(0, 0, 64, heights[index].toDouble()),
        Paint()..color = Colors.primaries[index],
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(64, heights[index]);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final path = '${directory.path}/page_$index.png';
      await File(path).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
      picture.dispose();
      paths.add(path);
    }
  });

  setUp(() {
    clearAllImageMemoryCaches();
    resetReaderImageQueueForTest();
    imageCache.clear();
    imageCache.clearLiveImages();
    viewLogs.clear();
    imageRequests.clear();
    imageGate = null;
    controlMode = ReaderControllerType.controller;
    sliderPosition = ReaderSliderPosition.bottom;
    preloadCount = 2;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('methods'), (call) async {
          if (call.method == 'device_status') {
            return {'battery_level': 85, 'charging': false, 'network': 'wifi'};
          }
          final payload =
              jsonDecode(call.arguments as String) as Map<String, dynamic>;
          final name = payload['method'];
          final params = payload['params'] as String;
          var response = '';
          if (name == 'load_property') {
            response = switch (params) {
              'reader_controller_type' => controlMode.toString(),
              'readerDirection' => direction.toString(),
              'reader_slider_position' => sliderPosition.toString(),
              'readerType' => configuredType.toString(),
              'readerPreloadCount' => '$preloadCount',
              _ => '',
            };
          } else if (name == 'begin_reader_session') {
            response = 'fixture-reader-session';
          } else if (name == 'end_reader_session') {
            response = '';
          } else if (name == 'jm_page_image') {
            final imageName =
                (jsonDecode(params) as Map<String, dynamic>)['image_name']
                    as String;
            imageRequests.add(imageName);
            if (imageName == '0.png' && imageGate != null) {
              await imageGate!.future;
            }
            response =
                paths[int.parse(imageName.split('.').first) % paths.length];
          } else if (name == 'image_size') {
            final index = paths.indexOf(params);
            response = jsonEncode({'w': 64, 'h': heights[index]});
          } else if (name == 'update_view_log') {
            viewLogs.add(
              (jsonDecode(params) as Map<String, dynamic>)['last_view_page']
                  as int,
            );
          } else {
            throw StateError('Unexpected reader method: $name');
          }
          return jsonEncode({'error_message': '', 'response_data': response});
        });
  });
  tearDown(() async {
    if (imageGate != null && !imageGate!.isCompleted) imageGate!.complete();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('methods'), null);
  });

  Future<GlobalKey> mountReader(
    WidgetTester tester,
    ReaderType type,
    ReaderDirection readDirection, {
    int pageCount = 10,
    int startIndex = 0,
    ThemeData? theme,
    double textScale = 1,
    MediaQueryData Function(MediaQueryData)? mediaQueryOverride,
    ValueChanged<int>? onUnmount,
  }) async {
    direction = readDirection;
    configuredType = type;
    await initReaderType();
    await initReaderControllerType();
    await initReaderDirection();
    await initReaderPreload();
    await initReaderSliderPosition();
    await initNoAnimation();
    await initVolumeKeyControl();
    await initTwoPageDirection();
    final key = GlobalKey();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      clearAllImageMemoryCaches();
    });
    await tester.pumpWidget(
      _UnmountProbe(
        onDeactivate: () {
          if (key.currentState != null) {
            onUnmount?.call(comicReaderProgressForTest(key).current);
          }
        },
        child: RepaintBoundary(
          key: const ValueKey('reader-regression-surface'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: theme,
            localizationsDelegates: const [AppLocalizations.delegate],
            builder: (context, child) {
              final data = MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(textScale));
              return MediaQuery(
                data: mediaQueryOverride?.call(data) ?? data,
                child: child!,
              );
            },
            home: Scaffold(
              body: buildComicReaderForTest(
                key: key,
                chapter: ChapterResponse(
                  id: 81234,
                  series: [],
                  tags: '',
                  name: 'Reader regression',
                  images: List.generate(pageCount, (index) => '$index.png'),
                  seriesId: 81234,
                  isFavorite: false,
                  liked: false,
                ),
                readerType: type,
                direction: readDirection,
                startIndex: startIndex,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pumpAndSettle();
    return key;
  }

  Future<void> doubleTap(WidgetTester tester, Offset point) async {
    await tester.tapAt(point);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(point);
    await tester.pumpAndSettle();
  }

  Finder firstPage() => find.byKey(const ValueKey('reader-page-81234-0'));

  testWidgets('disabled preload requests only the active gallery page', (
    tester,
  ) async {
    preloadCount = 0;
    await mountReader(
      tester,
      ReaderType.gallery,
      ReaderDirection.leftToRight,
      startIndex: 4,
    );
    expect(imageRequests, ['4.png']);
  });

  testWidgets(
    'default preload warms two pages before and after the active page',
    (tester) async {
      await mountReader(
        tester,
        ReaderType.gallery,
        ReaderDirection.rightToLeft,
        startIndex: 4,
      );
      await tester.runAsync(() async {
        for (
          var attempt = 0;
          attempt < 50 && imageRequests.length < 5;
          attempt++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          await tester.pump();
        }
      });
      expect(
        imageRequests,
        unorderedEquals(['4.png', '5.png', '3.png', '6.png', '2.png']),
      );
    },
  );

  testWidgets('continuous progress uses largest visible area after scrolling', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final key = await mountReader(
      tester,
      ReaderType.webtoon,
      ReaderDirection.topToBottom,
    );
    final viewport = tester.getRect(
      find.byType(zoomable.ZoomablePositionedList),
    );
    await tester.timedDragFrom(
      viewport.center,
      const Offset(0, -150),
      const Duration(milliseconds: 500),
    );
    await tester.pumpAndSettle();
    final firstVisible = tester.getRect(firstPage()).intersect(viewport);
    final nextVisible = tester
        .getRect(find.byKey(const ValueKey('reader-page-81234-1')))
        .intersect(viewport);
    expect(firstVisible.height, greaterThan(0));
    expect(
      nextVisible.width * nextVisible.height,
      greaterThan(firstVisible.width * firstVisible.height),
    );
    expect(comicReaderProgressForTest(key).current, 1);
  });

  testWidgets(
    'mouse wheel releases restored progress without a pointer click',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });
      final key = await mountReader(
        tester,
        ReaderType.webtoon,
        ReaderDirection.topToBottom,
        startIndex: 1,
      );
      final viewport = tester.getRect(
        find.byType(zoomable.ZoomablePositionedList),
      );
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: viewport.center,
          scrollDelta: const Offset(0, 2500),
        ),
      );
      await tester.pumpAndSettle();
      expect(comicReaderProgressForTest(key).current, greaterThan(1));
    },
  );

  for (final total in [10, 100]) {
    for (final textScale in [1.0, 2.0]) {
      testWidgets(
        'page counter keeps slider stable from ${total - 1} to $total at ${textScale}x',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(393, 852);
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });
          preloadCount = 0;
          final key = await mountReader(
            tester,
            ReaderType.gallery,
            ReaderDirection.leftToRight,
            pageCount: total,
            startIndex: total - 2,
            textScale: textScale,
          );
          final sliderFinder = find.byKey(
            const ValueKey('reader-progress-slider'),
          );
          final counterFinder = find.byKey(
            const ValueKey('reader-page-counter'),
          );
          final originalSlider = tester.getRect(sliderFinder);
          final originalCounter = tester.getRect(counterFinder);
          final valueFinder = find.byKey(
            const ValueKey('reader-page-counter-value'),
          );
          expect(tester.widget<Text>(valueFinder).data, '${total - 1}/$total');
          expect(originalSlider.height, closeTo(48, .1));

          jumpComicReaderForTest(key, total - 1, animation: false);
          await tester.pumpAndSettle();

          expect(tester.widget<Text>(valueFinder).data, '$total/$total');
          expect(tester.getRect(sliderFinder), originalSlider);
          expect(tester.getRect(counterFinder), originalCounter);
          expect(
            tester
                .getRect(find.byKey(const ValueKey('reader-bottom-controls')))
                .height,
            closeTo(48, .1),
          );
          expect(tester.takeException(), isNull);
          await readerCheckpoint?.call(
            'reader-counter-$total-${textScale}x',
            tester,
          );
        },
      );
    }
  }

  testWidgets('page counter reserves bold and spaced text in reverse reading', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    preloadCount = 0;
    final key = await mountReader(
      tester,
      ReaderType.gallery,
      ReaderDirection.rightToLeft,
      pageCount: 100,
      startIndex: 98,
      textScale: 2,
      mediaQueryOverride: (data) => data
          .copyWith(boldText: true)
          .applyTextStyleOverrides(
            lineHeightScaleFactorOverride: data.lineHeightScaleFactorOverride,
            letterSpacingOverride: 3,
            wordSpacingOverride: data.wordSpacingOverride,
            paragraphSpacingOverride: data.paragraphSpacingOverride,
          ),
    );
    final sliderFinder = find.byKey(const ValueKey('reader-progress-slider'));
    final counterFinder = find.byKey(const ValueKey('reader-page-counter'));
    final valueFinder = find.byKey(const ValueKey('reader-page-counter-value'));
    final originalSlider = tester.getRect(sliderFinder);
    final originalCounter = tester.getRect(counterFinder);
    expect(tester.widget<Text>(valueFinder).data, '99/100');

    jumpComicReaderForTest(key, 99, animation: false);
    await tester.pumpAndSettle();

    expect(tester.widget<Text>(valueFinder).data, '100/100');
    expect(tester.getRect(sliderFinder), originalSlider);
    expect(tester.getRect(counterFinder), originalCounter);
    final richTextFinder = find.descendant(
      of: valueFinder,
      matching: find.byType(RichText),
    );
    final text = tester.widget<RichText>(richTextFinder).text;
    expect(text.style!.fontWeight, FontWeight.bold);
    expect(text.style!.letterSpacing, 3);
    final paragraph = tester.renderObject<RenderParagraph>(richTextFinder);
    expect(
      paragraph.getMaxIntrinsicWidth(double.infinity),
      lessThanOrEqualTo(originalCounter.width + .01),
    );
    expect(originalSlider.height, closeTo(48, .1));
    expect(tester.takeException(), isNull);
    await readerCheckpoint?.call('reader-counter-accessibility', tester);
  });

  for (final layout in [
    (
      name: 'portrait',
      viewport: const Size(393, 852),
      insets: const FakeViewPadding(),
      textScale: 1.0,
      checkpointSuffix: '',
    ),
    (
      name: 'portrait insets and large text',
      viewport: const Size(393, 852),
      insets: const FakeViewPadding(top: 24, bottom: 24),
      textScale: 2.0,
      checkpointSuffix: '-large-text',
    ),
    (
      name: 'landscape insets and large text',
      viewport: const Size(852, 393),
      insets: const FakeViewPadding(left: 32, right: 32, bottom: 24),
      textScale: 2.0,
      checkpointSuffix: '-landscape',
    ),
  ]) {
    testWidgets('pending reader bottom controls stay compact ${layout.name}', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = layout.viewport;
      tester.view.padding = layout.insets;
      tester.view.viewPadding = layout.insets;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.view.resetPadding();
        tester.view.resetViewPadding();
      });
      imageGate = Completer<void>();
      preloadCount = 0;
      await mountReader(
        tester,
        ReaderType.webToonFreeZoom,
        ReaderDirection.topToBottom,
        textScale: layout.textScale,
      );
      final barFinder = find.byKey(const ValueKey('reader-bottom-controls'));
      final sliderFinder = find.byKey(const ValueKey('reader-progress-slider'));
      final viewportFinder = find.byType(zoomable.ZoomablePositionedList);

      void expectCompactControls() {
        final viewport = tester.getRect(viewportFinder);
        final bar = tester.getRect(barFinder);
        final slider = tester.getRect(sliderFinder);
        expect(bar.bottom, closeTo(layout.viewport.height, .1));
        expect(bar.height, closeTo(48 + layout.insets.bottom, .1));
        expect(viewport.bottom, closeTo(bar.bottom, .1));
        expect(slider.height, closeTo(48, .1));
        expect(slider.center.dy, closeTo(bar.top + 24, .1));
        expect(slider.left, greaterThanOrEqualTo(layout.insets.left + 48));
        expect(
          slider.right,
          lessThanOrEqualTo(layout.viewport.width - layout.insets.right - 48),
        );
        expect(find.byTooltip('Reader settings').hitTestable(), findsOneWidget);
        expect(find.byTooltip('Chapters').hitTestable(), findsOneWidget);
        expect(tester.getRect(find.byType(AppBar)).bottom, lessThan(bar.top));
        expect(tester.takeException(), isNull);
      }

      final placeholder = find.descendant(
        of: firstPage(),
        matching: find.byIcon(Icons.downloading),
      );
      expect(placeholder, findsOneWidget);
      expect(tester.getSize(placeholder), const Size.square(72));
      expect(tester.getSize(firstPage()), tester.getSize(viewportFinder));
      expectCompactControls();
      await readerCheckpoint?.call(
        'pending-reader-bottom-controls${layout.checkpointSuffix}',
        tester,
      );

      imageGate!.complete();
      final imageFinder = find.descendant(
        of: firstPage(),
        matching: find.byType(RawImage),
      );
      for (var attempt = 0; attempt < 100; attempt++) {
        await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
        if (imageFinder.evaluate().isNotEmpty &&
            tester.widget<RawImage>(imageFinder.first).image != null) {
          break;
        }
      }
      await tester.pumpAndSettle();
      expect(tester.widget<RawImage>(imageFinder.first).image, isNotNull);
      expect(placeholder, findsNothing);
      expectCompactControls();
      await readerCheckpoint?.call(
        'loaded-reader-bottom-controls${layout.checkpointSuffix}',
        tester,
      );
    });
  }

  for (final side in [ReaderSliderPosition.left, ReaderSliderPosition.right]) {
    testWidgets('pending reader keeps $side slider at the viewport edge', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(393, 852);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      sliderPosition = side;
      imageGate = Completer<void>();
      preloadCount = 0;
      await mountReader(
        tester,
        ReaderType.webToonFreeZoom,
        ReaderDirection.topToBottom,
      );
      expect(
        find.byKey(const ValueKey('reader-bottom-controls')),
        findsNothing,
      );
      final slider = tester.getRect(
        find.ancestor(
          of: find.byKey(const ValueKey('reader-progress-slider')),
          matching: find.byType(RotatedBox),
        ),
      );
      final viewport = tester.getRect(
        find.byType(zoomable.ZoomablePositionedList),
      );
      expect(slider.width, closeTo(48, .1));
      expect(slider.height, closeTo(300, .1));
      expect(slider.center.dy, closeTo(viewport.center.dy, .1));
      expect(
        side == ReaderSliderPosition.left ? slider.left : slider.right,
        closeTo(
          side == ReaderSliderPosition.left ? viewport.left : viewport.right,
          .1,
        ),
      );
      expect(find.byTooltip('Reader settings').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final textScale in [1.0, 2.0]) {
    testWidgets(
      'compact reader settings retain preload controls at ${textScale}x',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(393, 852);
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        imageGate = Completer<void>();
        preloadCount = 0;
        await mountReader(
          tester,
          ReaderType.webtoon,
          ReaderDirection.topToBottom,
          textScale: textScale,
        );
        await tester.tap(find.byTooltip('Reader settings'));
        await tester.pumpAndSettle();
        final settings = find.byType(ListView);
        final icons = [
          Icons.crop_sharp,
          Icons.view_day_outlined,
          Icons.control_camera_outlined,
          Icons.straighten_sharp,
        ];
        final iconRects = [
          for (final icon in icons) tester.getRect(find.byIcon(icon)),
        ];
        for (final rect in iconRects) {
          expect(rect.top, closeTo(iconRects.first.top, .1));
        }
        expect(
          find.descendant(of: settings, matching: find.byType(OutlinedButton)),
          findsNothing,
        );
        await readerCheckpoint?.call(
          'compact-reader-settings-${textScale}x',
          tester,
        );
        await tester.tap(find.byIcon(Icons.crop_sharp));
        await tester.pumpAndSettle();
        expect(find.text('Choose reader direction'), findsOneWidget);
        Navigator.of(tester.element(find.byType(SimpleDialog))).pop();
        await tester.pumpAndSettle();
        final pagesTile = find.text('Preload pages per direction');
        await tester.ensureVisible(pagesTile);
        await tester.tap(pagesTile);
        await tester.pumpAndSettle();
        expect(find.byType(SimpleDialog), findsOneWidget);
        Navigator.of(tester.element(find.byType(SimpleDialog))).pop();
        await tester.pumpAndSettle();
        final directionTile = find.text('Preload direction');
        await tester.ensureVisible(directionTile);
        await tester.tap(directionTile);
        await tester.pumpAndSettle();
        expect(find.byType(SimpleDialog), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final dark in [false, true]) {
    testWidgets(
      'bottom controls blend over pages with a small draggable dot ${dark ? 'dark' : 'light'}',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 844);
        tester.view.padding = const FakeViewPadding(bottom: 24);
        tester.view.viewPadding = const FakeViewPadding(bottom: 24);
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.view.resetPadding();
          tester.view.resetViewPadding();
        });
        if (!Platform.isAndroid &&
            Platform.environment['LAYOUT_SCREENSHOTS'] == '1') {
          await tester.runAsync(() async {
            final font = await File('C:/Windows/Fonts/segoeui.ttf')
                .readAsBytes();
            await (FontLoader(
              'Roboto',
            )..addFont(Future.value(ByteData.sublistView(font)))).load();
            final icons = await File(
              '_flutter/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            ).readAsBytes();
            await (FontLoader(
              'MaterialIcons',
            )..addFont(Future.value(ByteData.sublistView(icons)))).load();
          });
        }
        final key = await mountReader(
          tester,
          ReaderType.webToonFreeZoom,
          ReaderDirection.topToBottom,
          startIndex: 1,
          theme: dark ? app_theme.darkTheme : app_theme.lightTheme,
        );
        await tester.runAsync(() async {
          for (var attempt = 0; attempt < 100; attempt++) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
            await tester.pump();
            final image = find.descendant(
              of: find.byKey(const ValueKey('reader-page-81234-1')),
              matching: find.byType(RawImage),
            );
            if (image.evaluate().isNotEmpty &&
                tester.widget<RawImage>(image.first).image != null) {
              break;
            }
          }
        });
        jumpComicReaderForTest(key, 1, animation: false);
        await tester.pumpAndSettle();
        final barFinder = find.byKey(const ValueKey('reader-bottom-controls'));
        final sliderFinder = find.byKey(
          const ValueKey('reader-progress-slider'),
        );
        final sliderTheme = tester.widget<SliderTheme>(
          find
              .ancestor(of: sliderFinder, matching: find.byType(SliderTheme))
              .first,
        );
        expect(
          (sliderTheme.data.thumbShape! as RoundSliderThumbShape)
              .enabledThumbRadius,
          lessThan(10),
        );
        final viewport = tester.getRect(
          find.byType(zoomable.ZoomablePositionedList),
        );
        final bar = tester.getRect(barFinder);
        expect(viewport.bottom, closeTo(bar.bottom, .1));
        expect(bar.height, closeTo(48 + 24, .1));
        expect(tester.getSize(sliderFinder).height, closeTo(48, .1));
        expect(tester.getCenter(sliderFinder).dy, closeTo(bar.top + 24, .1));
        final fullscreenButton = find.byTooltip('Fullscreen');
        expect(
          tester.getSize(fullscreenButton).height,
          greaterThanOrEqualTo(48),
        );
        final finalChapterButton = tester.widget<IconButton>(
          find.byWidgetPredicate(
            (widget) =>
                widget is IconButton && widget.tooltip == 'Last chapter',
          ),
        );
        expect(finalChapterButton.onPressed, isNull);
        expect(
          tester.widget<Slider>(sliderFinder).semanticFormatterCallback!(1),
          'Page 2 of 10',
        );
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('reader-regression-surface')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          try {
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            if (!Platform.isAndroid) {
              await File(
                'build/checks/reader-performance/progress-${dark ? 'dark' : 'light'}.png',
              ).writeAsBytes(png!.buffer.asUint8List());
            }
            final pixels = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!.buffer.asUint8List();
            // Sample both the toolbar and the phone's bottom safe inset. Both
            // must show the real pink page underneath the translucent black.
            final expected = Color.alphaBlend(
              const Color(0x88000000),
              Colors.primaries[1],
            );
            for (final y in [bar.top + 4, bar.bottom - 4]) {
              final offset =
                  (y.floor() * image.width + (bar.left + 4).floor()) * 4;
              expect(pixels[offset], closeTo((expected.r * 255).round(), 2));
              expect(
                pixels[offset + 1],
                closeTo((expected.g * 255).round(), 2),
              );
              expect(
                pixels[offset + 2],
                closeTo((expected.b * 255).round(), 2),
              );
            }
          } finally {
            image.dispose();
          }
        });
        await readerCheckpoint?.call(
          'reader-progress-${dark ? 'dark' : 'light'}',
          tester,
        );
        final slider = tester.getRect(sliderFinder);
        // A finger can start outside the visible 14px dot but inside its
        // invisible touch area; shrinking the dot must not shrink that target.
        await tester.timedDragFrom(
          Offset(slider.left + slider.width * .2, slider.center.dy + 12),
          Offset(slider.width * .4, 0),
          const Duration(milliseconds: 250),
        );
        await tester.pumpAndSettle();
        expect(comicReaderProgressForTest(key).current, greaterThan(1));
        expect(tester.widget<Slider>(sliderFinder).value, greaterThan(1));
        tester
            .widget<zoomable.ZoomablePositionedList>(
              find.byType(zoomable.ZoomablePositionedList),
            )
            .itemScrollController!
            .jumpTo(index: 10);
        await tester.pumpAndSettle();
        final end = find.text('Finish reading');
        expect(end.hitTestable(), findsOneWidget);
        expect(
          tester.getRect(end).bottom,
          lessThan(tester.getRect(barFinder).top),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final type in [ReaderType.gallery, ReaderType.twoPageGallery]) {
    for (final readDirection in ReaderDirection.values) {
      testWidgets('$type $readDirection zoom/pan resets before paging', (
        tester,
      ) async {
        final key = await mountReader(tester, type, readDirection);
        final photo = tester.widget<PhotoView>(find.byType(PhotoView).first);
        final controller = photo.controller!;
        final rect = tester.getRect(find.byType(PhotoView).first);
        await doubleTap(tester, rect.center);
        expect(controller.scale, closeTo(2, .01));
        await readerCheckpoint?.call(
          'reader-${type.name}-${readDirection.name}-zoom',
          tester,
        );
        final before = controller.position;
        await tester.timedDragFrom(
          rect.center,
          const Offset(-80, 0),
          const Duration(milliseconds: 200),
        );
        await tester.pumpAndSettle();
        expect((controller.position.dx - before.dx).abs(), greaterThan(10));
        expect(comicReaderProgressForTest(key).current, 0);
        await doubleTap(tester, rect.center);
        expect(controller.scale, closeTo(1, .01));
        final delta = switch (readDirection) {
          ReaderDirection.leftToRight => Offset(-rect.width * .9, 0),
          ReaderDirection.rightToLeft => Offset(rect.width * .9, 0),
          ReaderDirection.topToBottom => Offset(0, -rect.height * .9),
        };
        await tester.dragFrom(rect.center, delta);
        await tester.pumpAndSettle();
        expect(
          comicReaderProgressForTest(key).current,
          type == ReaderType.twoPageGallery ? 2 : 1,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('odd final spread and restored odd source rank stay in bounds', (
    tester,
  ) async {
    final key = await mountReader(
      tester,
      ReaderType.twoPageGallery,
      ReaderDirection.rightToLeft,
      pageCount: 5,
      startIndex: 3,
    );
    expect(comicReaderProgressForTest(key).current, 2);
    jumpComicReaderForTest(key, 99, animation: false);
    await tester.pumpAndSettle();
    expect(comicReaderProgressForTest(key).current, 4);
    await readerCheckpoint?.call('reader-odd-spread-last', tester);
    controlComicReaderForTest('DOWN');
    await tester.pumpAndSettle();
    expect(comicReaderProgressForTest(key).current, 4);
    expect(tester.takeException(), isNull);
  });

  for (final readDirection in [
    ReaderDirection.leftToRight,
    ReaderDirection.rightToLeft,
    ReaderDirection.topToBottom,
  ]) {
    testWidgets(
      '$readDirection continuous zoom pans once and restores scrolling',
      (tester) async {
        final key = await mountReader(
          tester,
          ReaderType.webToonFreeZoom,
          readDirection,
        );
        final viewport = tester.getRect(
          find.byType(zoomable.ZoomablePositionedList),
        );
        final original = tester.getRect(firstPage());
        await doubleTap(tester, viewport.center);
        expect(
          tester.getRect(firstPage()).width / original.width,
          closeTo(2, .05),
        );
        await readerCheckpoint?.call(
          'reader-continuous-${readDirection.name}-zoom',
          tester,
        );
        final before = tester.getRect(firstPage());
        await tester.timedDragFrom(
          viewport.center,
          readDirection == ReaderDirection.leftToRight
              ? const Offset(-80, 0)
              : const Offset(80, 0),
          const Duration(milliseconds: 200),
        );
        await tester.pumpAndSettle();
        final delta = (tester.getRect(firstPage()).left - before.left).abs();
        expect(delta, greaterThan(10));
        expect(delta, lessThan(150));
        expect(comicReaderProgressForTest(key).current, 0);
        await doubleTap(tester, viewport.center);
        expect(
          tester.getRect(firstPage()).width / original.width,
          closeTo(1, .05),
        );
        final scroll = switch (readDirection) {
          ReaderDirection.topToBottom => Offset(
            0,
            -original.height - viewport.height / 2,
          ),
          ReaderDirection.leftToRight => Offset(
            -original.width - viewport.width / 3,
            0,
          ),
          ReaderDirection.rightToLeft => Offset(
            original.width + viewport.width / 3,
            0,
          ),
        };
        await tester.dragFrom(viewport.center, scroll);
        await tester.pumpAndSettle();
        expect(comicReaderProgressForTest(key).current, greaterThan(0));
        await readerCheckpoint?.call(
          'reader-continuous-${readDirection.name}-restored',
          tester,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'vertical pinch keeps scale and single-finger pan after handoff',
    (tester) async {
      final key = await mountReader(
        tester,
        ReaderType.webToonFreeZoom,
        ReaderDirection.topToBottom,
      );
      final rect = tester.getRect(find.byType(zoomable.ZoomablePositionedList));
      final initial = tester.getRect(firstPage());
      final distance = rect.width * .12;
      final first = await tester.createGesture(
        kind: PointerDeviceKind.touch,
        pointer: 1,
      );
      final second = await tester.createGesture(
        kind: PointerDeviceKind.touch,
        pointer: 2,
      );
      await first.down(rect.center - Offset(distance, 0));
      await second.down(rect.center + Offset(distance, 0));
      await tester.pump();
      await first.moveTo(rect.center - Offset(distance * 1.8, 0));
      await second.moveTo(rect.center + Offset(distance * 1.8, 0));
      await tester.pumpAndSettle();
      final zoomed = tester.getRect(firstPage());
      expect(zoomed.width / initial.width, greaterThan(1.1));
      await second.up();
      await tester.pump();
      final before = tester.getRect(firstPage());
      await first.moveBy(const Offset(-60, 0));
      await tester.pumpAndSettle();
      await first.up();
      final moved = tester.getRect(firstPage());
      expect(moved.width, closeTo(zoomed.width, 1));
      expect((moved.left - before.left).abs(), greaterThan(10));
      expect((moved.left - before.left).abs(), lessThan(110));
      expect(comicReaderProgressForTest(key).current, 0);
      expect(tester.takeException(), isNull);
    },
  );

  for (final mode in [
    ReaderControllerType.touchDouble,
    ReaderControllerType.touchDoubleOnceNext,
  ]) {
    testWidgets('continuous reader preserves $mode without disabling pinch', (
      tester,
    ) async {
      controlMode = mode;
      await mountReader(
        tester,
        ReaderType.webToonFreeZoom,
        ReaderDirection.topToBottom,
      );
      final before = tester.getRect(firstPage());
      expect(find.byType(AppBar), findsOneWidget);
      await doubleTap(
        tester,
        tester.getRect(find.byType(zoomable.ZoomablePositionedList)).center,
      );
      expect(find.byType(AppBar), findsNothing);
      expect(tester.getRect(firstPage()).width, closeTo(before.width, 1));
      expect(
        tester
            .widget<zoomable.ZoomablePositionedList>(
              find.byType(zoomable.ZoomablePositionedList),
            )
            .enableZoom,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final type in [
    ReaderType.gallery,
    ReaderType.webToonFreeZoom,
    ReaderType.twoPageGallery,
  ]) {
    testWidgets(
      '$type locks slider through intermediate pages and superseded jumps',
      (tester) async {
        final key = await mountReader(
          tester,
          type,
          ReaderDirection.leftToRight,
        );
        jumpComicReaderForTest(key, 8);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(comicReaderProgressForTest(key).slider, 8);
        expect(tester.widget<Slider>(find.byType(Slider)).value, 8);
        jumpComicReaderForTest(key, 4);
        await tester.pump();
        for (var tick = 0; tick < 3; tick++) {
          await tester.pump(const Duration(milliseconds: 90));
          expect(comicReaderProgressForTest(key).slider, 4);
        }
        await tester.pumpAndSettle();
        expect(comicReaderProgressForTest(key), (
          current: 4,
          slider: 4,
          jumpTarget: null,
        ));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }

  for (final type in [ReaderType.webtoon, ReaderType.webToonFreeZoom]) {
    testWidgets('$type jumps to distant varying-height pages by exact index', (
      tester,
    ) async {
      final key = await mountReader(tester, type, ReaderDirection.topToBottom);
      jumpComicReaderForTest(key, 7, animation: false);
      await tester.pumpAndSettle();
      expect(comicReaderProgressForTest(key), (
        current: 7,
        slider: 7,
        jumpTarget: null,
      ));
      jumpComicReaderForTest(key, 2);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(comicReaderProgressForTest(key).slider, 2);
      await tester.pumpAndSettle();
      expect(comicReaderProgressForTest(key).current, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }

  testWidgets('exit during an animated jump persists the actual visible page', (
    tester,
  ) async {
    int? actualAtRemoval;
    final key = await mountReader(
      tester,
      ReaderType.gallery,
      ReaderDirection.leftToRight,
      onUnmount: (page) => actualAtRemoval = page,
    );
    jumpComicReaderForTest(key, 8);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final actual = comicReaderProgressForTest(key).current;
    expect(actual, lessThan(8));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    // A real Android frame may advance between sampling and pumpWidget.
    // Capture the actual page synchronously when the reader is deactivated.
    expect(actualAtRemoval, lessThan(8));
    expect(viewLogs.last, actualAtRemoval);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'two-page controls advance and rewind complete spreads at boundaries',
    (tester) async {
      final key = await mountReader(
        tester,
        ReaderType.twoPageGallery,
        ReaderDirection.leftToRight,
      );
      controlComicReaderForTest('DOWN');
      await tester.pumpAndSettle();
      expect(comicReaderProgressForTest(key).current, 2);
      controlComicReaderForTest('UP');
      await tester.pumpAndSettle();
      expect(comicReaderProgressForTest(key).current, 0);
      controlComicReaderForTest('UP');
      await tester.pumpAndSettle();
      expect(comicReaderProgressForTest(key).current, 0);
      for (var index = 0; index < 6; index++) {
        controlComicReaderForTest('DOWN');
        await tester.pumpAndSettle();
      }
      expect(comicReaderProgressForTest(key).current, 8);
      expect(comicReaderProgressForTest(key).slider, 8);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets('two-page rapid controls retain the newest spread target', (
    tester,
  ) async {
    final key = await mountReader(
      tester,
      ReaderType.twoPageGallery,
      ReaderDirection.leftToRight,
    );
    controlComicReaderForTest('DOWN');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    controlComicReaderForTest('DOWN');
    await tester.pump();
    expect(comicReaderProgressForTest(key).slider, 4);
    await tester.pump(const Duration(milliseconds: 90));
    expect(comicReaderProgressForTest(key).slider, 4);
    controlComicReaderForTest('UP');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    controlComicReaderForTest('UP');
    await tester.pumpAndSettle();
    expect(comicReaderProgressForTest(key), (
      current: 0,
      slider: 0,
      jumpTarget: null,
    ));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets(
    'late real image completion after reader disposal is evicted and queue stops',
    (tester) async {
      imageGate = Completer<void>();
      await mountReader(
        tester,
        ReaderType.gallery,
        ReaderDirection.leftToRight,
      );
      expect(imageRequests, contains('0.png'));
      expect(imageRequests.toSet().length, imageRequests.length);
      final requestsBeforeDispose = imageRequests.toList();
      final provider = tester.widget<Image>(find.byType(Image).first).image;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        imageGate!.complete();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      // 实际文件读取与解码跨越 FakeAsync 和引擎任务，交替推进真实 I/O 与帧末监听器清理。
      for (var frame = 0; frame < 20; frame++) {
        await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      final status = imageCache.statusForKey(
        await provider.obtainKey(ImageConfiguration.empty),
      );
      expect(status.keepAlive, isFalse);
      expect(status.pending, isFalse);
      expect(imageRequests, requestsBeforeDispose);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reader keeps a page cache while mounted and releases it on exit',
    (tester) async {
      final readerKey = await mountReader(
        tester,
        ReaderType.webtoon,
        ReaderDirection.topToBottom,
      );
      final firstPage = find.byType(JMPageImage).first;
      final pageFinder = find.descendant(
        of: firstPage,
        matching: find.byType(Image),
      );
      expect(pageFinder, findsOneWidget);
      final provider = tester.widget<Image>(pageFinder).image;
      final providerKey = await provider.obtainKey(ImageConfiguration.empty);
      var status = imageCache.statusForKey(providerKey);
      expect(status.live || status.keepAlive || status.pending, isTrue);

      jumpComicReaderForTest(readerKey, 5, animation: false);
      await tester.pumpAndSettle();
      status = imageCache.statusForKey(providerKey);
      expect(status.live || status.keepAlive || status.pending, isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(imageCache.statusForKey(providerKey).keepAlive, isFalse);
      expect(imageCache.statusForKey(providerKey).live, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}

class _UnmountProbe extends StatefulWidget {
  const _UnmountProbe({required this.child, required this.onDeactivate});
  final Widget child;
  final VoidCallback onDeactivate;
  @override
  State<_UnmountProbe> createState() => _UnmountProbeState();
}

class _UnmountProbeState extends State<_UnmountProbe> {
  @override
  void deactivate() {
    widget.onDeactivate();
    super.deactivate();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

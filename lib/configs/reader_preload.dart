import 'package:flutter/material.dart';
import 'package:jmcomic3/screens/components/dialogs.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/configs/enum_property.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

enum ReaderPreloadDirection { both, forward, backward }

const readerPreloadCounts = [0, 1, 2, 4, 6];
const _countKey = 'readerPreloadCount';
const _directionKey = 'readerPreloadDirection';
int _count = 2;
ReaderPreloadDirection _direction = ReaderPreloadDirection.both;

int get currentReaderPreloadCount => _count;
ReaderPreloadDirection get currentReaderPreloadDirection => _direction;

Future<void> initReaderPreload() async {
  final count = int.tryParse(await methods.loadProperty(_countKey));
  _count = readerPreloadCounts.contains(count) ? count! : 2;
  _direction = parseEnumPropertyValue(
    await methods.loadProperty(_directionKey),
    ReaderPreloadDirection.values,
    ReaderPreloadDirection.both,
  );
}

/// Nearest pages are queued first; reading direction is expressed in source
/// page order and therefore works unchanged for right-to-left layouts.
List<int> readerPreloadPages({
  required int page,
  required int pageCount,
  required int count,
  required ReaderPreloadDirection direction,
  bool paired = false,
}) {
  if (pageCount <= 0 || count <= 0) return const [];
  final first = page.clamp(0, pageCount - 1).toInt();
  final last = paired ? (first + 1).clamp(0, pageCount - 1).toInt() : first;
  return [
    for (var distance = 1; distance <= count; distance++) ...[
      if (direction != ReaderPreloadDirection.backward &&
          last + distance < pageCount)
        last + distance,
      if (direction != ReaderPreloadDirection.forward && first - distance >= 0)
        first - distance,
    ],
  ];
}

String readerPreloadCountName(BuildContext context) => _count == 0
    ? context.l10n.tr('关闭', en: 'Off')
    : context.l10n.tr('$_count 页', en: '$_count pages');

String readerPreloadDirectionName(
  ReaderPreloadDirection direction,
  BuildContext context,
) => switch (direction) {
  ReaderPreloadDirection.both => context.l10n.tr(
    '双向（向前和向后）',
    en: 'Bidirectional (forward and backward)',
  ),
  ReaderPreloadDirection.forward => context.l10n.tr('仅向前', en: 'Forward only'),
  ReaderPreloadDirection.backward => context.l10n.tr(
    '仅向后',
    en: 'Backward only',
  ),
};

Future<void> chooseReaderPreloadCount(BuildContext context) async {
  final value = await chooseMapDialog<int>(
    context,
    title: context.l10n.tr('预加载页数（每个方向）', en: 'Preload pages per direction'),
    values: {
      for (final count in readerPreloadCounts)
        count == 0
                ? context.l10n.tr('关闭', en: 'Off')
                : context.l10n.tr('$count 页', en: '$count pages'):
            count,
    },
  );
  if (value == null) return;
  await methods.saveProperty(_countKey, '$value');
  _count = value;
}

Future<void> chooseReaderPreloadDirection(BuildContext context) async {
  final value = await chooseMapDialog<ReaderPreloadDirection>(
    context,
    title: context.l10n.tr('预加载方向', en: 'Preload direction'),
    values: {
      for (final direction in ReaderPreloadDirection.values)
        readerPreloadDirectionName(direction, context): direction,
    },
  );
  if (value == null) return;
  await methods.saveProperty(_directionKey, '$value');
  _direction = value;
}

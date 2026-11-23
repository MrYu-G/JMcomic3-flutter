part of '../comic_reader_screen.dart';

class _EpChooser extends StatefulWidget {
  final ChapterResponse chapter;
  final FutureOr Function(int, bool) onChangeEp;
  final List<Series>? series;

  const _EpChooser(this.chapter, this.onChangeEp, {this.series});

  @override
  State<StatefulWidget> createState() => _EpChooserState();
}

class _EpChooserState extends State<_EpChooser> {
  bool _selectionInFlight = false;

  Future<void> _selectChapter(int id) async {
    if (_selectionInFlight || !mounted) {
      return;
    }
    _selectionInFlight = true;
    try {
      if (mounted) {
        Navigator.of(context).pop();
      }
      await Future<void>.sync(() => widget.onChangeEp(id, false));
    } catch (error, stackTrace) {
      debugPrient(
        "chapter selection failed: ${error.runtimeType}/${stackTrace.runtimeType}",
      );
    } finally {
      _selectionInFlight = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final series = widget.series ?? widget.chapter.series;
    if (series.isEmpty) {
      return Center(
        child: Text(
          context.l10n.tr("无章节可选择", en: "No chapters available"),
          style: const TextStyle(color: Colors.white),
        ),
      );
    }

    final entries = _sortReaderSeries(series);
    final index = entries.map((e) => e.id).toList().indexOf(widget.chapter.id);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: zoomable.ZoomablePositionedList.builder(
          enableZoom: false,
          initialScrollIndex: index < 2 ? 0 : index - 2,
          itemCount: entries.length,
          itemBuilder: (context, index) {
            final entry = entries[index];
            final selected = widget.chapter.id == entry.id;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Semantics(
                selected: selected,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: selected ? Colors.white12 : null,
                    minimumSize: const Size.fromHeight(48),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    side: const BorderSide(color: Colors.white24),
                  ),
                  onPressed: _selectionInFlight
                      ? null
                      : () => unawaited(_selectChapter(entry.id)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (selected) ...[
                        const Icon(Icons.check, size: 18),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Text(
                          entry.sort +
                              (entry.name.isEmpty ? '' : ' - ${entry.name}'),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SettingPanel extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => _SettingPanelState();
}

class _SettingPanelState extends State<_SettingPanel> {
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(
        12,
        8,
        12,
        8 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      children: [
        Row(
          children: [
            _bottomIcon(
              icon: Icons.crop_sharp,
              label: context.l10n.tr('阅读方向', en: 'Reading direction'),
              title: readerDirectionName(currentReaderDirection, context),
              onPressed: () async {
                await chooseReaderDirection(context);
                if (mounted) setState(() {});
              },
            ),
            _bottomIcon(
              icon: Icons.view_day_outlined,
              label: context.l10n.tr('阅读模式', en: 'Reader mode'),
              title: readerTypeName(currentReaderType, context),
              onPressed: () async {
                await chooseReaderType(context);
                if (mounted) setState(() {});
              },
            ),
            _bottomIcon(
              icon: Icons.control_camera_outlined,
              label: context.l10n.tr('操控方式', en: 'Controls'),
              title: currentReaderControllerTypeName(context),
              onPressed: () async {
                await chooseReaderControllerType(context);
                if (mounted) setState(() {});
              },
            ),
            _bottomIcon(
              icon: Icons.straighten_sharp,
              label: context.l10n.tr('进度条位置', en: 'Slider position'),
              title: currentReaderSliderPositionName(context),
              onPressed: () async {
                await chooseReaderSliderPosition(context);
                if (mounted) setState(() {});
              },
            ),
          ],
        ),
        const SizedBox(height: 4),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          minLeadingWidth: 24,
          horizontalTitleGap: 12,
          minTileHeight: 64,
          textColor: Colors.white,
          iconColor: Colors.white,
          leading: const Icon(Icons.photo_library_outlined),
          title: Text(
            context.l10n.tr('预加载页数（每个方向）', en: 'Preload pages per direction'),
          ),
          subtitle: Text(
            readerPreloadCountName(context),
            style: const TextStyle(color: Colors.white70),
          ),
          onTap: () async {
            await chooseReaderPreloadCount(context);
            if (mounted) setState(() {});
          },
        ),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          minLeadingWidth: 24,
          horizontalTitleGap: 12,
          minTileHeight: 64,
          textColor: Colors.white,
          iconColor: Colors.white,
          leading: Icon(switch (currentReaderPreloadDirection) {
            ReaderPreloadDirection.both => Icons.swap_horiz,
            ReaderPreloadDirection.forward => Icons.redo,
            ReaderPreloadDirection.backward => Icons.undo,
          }),
          title: Text(context.l10n.tr('预加载方向', en: 'Preload direction')),
          subtitle: Text(
            readerPreloadDirectionName(currentReaderPreloadDirection, context),
            style: const TextStyle(color: Colors.white70),
          ),
          onTap: () async {
            await chooseReaderPreloadDirection(context);
            if (mounted) setState(() {});
          },
        ),
      ],
    );
  }

  Widget _bottomIcon({
    required IconData icon,
    required String label,
    required String title,
    required void Function() onPressed,
  }) {
    return Expanded(
      child: Center(
        child: IconButton(
          iconSize: max(55, 34 + MediaQuery.textScalerOf(context).scale(14)),
          tooltip: '$label: $title',
          onPressed: onPressed,
          icon: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 3),
              Icon(icon, size: 25, color: Colors.white),
              const SizedBox(height: 3),
              Text(
                title,
                style: const TextStyle(color: Colors.white, fontSize: 10),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 3),
            ],
          ),
        ),
      ),
    );
  }
}

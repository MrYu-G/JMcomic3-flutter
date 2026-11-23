import 'package:flutter/material.dart';
import 'package:jmcomic3/screens/components/file_actions.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

import 'components/comic_download_card.dart';
import 'components/content_error.dart';
import 'components/content_loading.dart';
import 'components/feedback.dart';
import 'components/right_click_pop.dart';
import 'downloads_export_shared.dart';
import 'downloads_exporting_screen.dart';
import 'incomplete_download_export_screen.dart';

class DownloadExportSelectionScreen extends StatefulWidget {
  const DownloadExportSelectionScreen.completed({super.key})
    : scope = DownloadExportScope.completed;

  const DownloadExportSelectionScreen.includingIncomplete({super.key})
    : scope = DownloadExportScope.includingIncomplete;

  final DownloadExportScope scope;

  @override
  State<DownloadExportSelectionScreen> createState() =>
      _DownloadExportSelectionScreenState();
}

class _DownloadExportSelectionScreenState
    extends State<DownloadExportSelectionScreen> {
  late Future<List<DownloadAlbum>> _downloadsFuture;
  Set<int> _selected = {};
  bool _openingExport = false;

  @override
  void initState() {
    super.initState();
    _downloadsFuture = _loadDownloads();
  }

  Future<List<DownloadAlbum>> _loadDownloads() async =>
      (await methods.allDownloads())
          .where(widget.scope.accepts)
          .toList(growable: false);

  Future<void> _refresh() async {
    final future = _loadDownloads();
    setState(() {
      _downloadsFuture = future;
    });
    try {
      final albums = await future;
      if (!mounted || !identical(_downloadsFuture, future)) return;
      setState(() => _selected = restoreSelectedIdSet(_selected, albums));
    } catch (_) {
      // The FutureBuilder presents the failure and its retry control.
    }
  }

  Future<void> _openExport() async {
    if (_openingExport) return;
    if (_selected.isEmpty) {
      defaultToast(context, context.l10n.pleaseSelectExportContent);
      return;
    }
    setState(() => _openingExport = true);
    try {
      final allowed = await androidMangeStorageRequest();
      if (!mounted) return;
      if (!allowed) {
        defaultToast(
          context,
          context.l10n.tr('申请权限被拒绝', en: 'Permission denied'),
        );
        return;
      }
      final ids = _selected.toList(growable: false);
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (context) => switch (widget.scope) {
            DownloadExportScope.completed => DownloadsExportingScreen(
              idList: ids,
            ),
            DownloadExportScope.includingIncomplete =>
              IncompleteDownloadExportScreen(idList: ids),
          },
        ),
      );
      if (mounted) await _refresh();
    } catch (error) {
      if (mounted) defaultToast(context, '$error');
    } finally {
      if (mounted) setState(() => _openingExport = false);
    }
  }

  @override
  Widget build(BuildContext context) => rightClickPop(
    context: context,
    child: FutureBuilder<List<DownloadAlbum>>(
      future: _downloadsFuture,
      builder: (context, snapshot) {
        final ready =
            snapshot.connectionState == ConnectionState.done &&
            snapshot.hasData;
        final albums = ready ? snapshot.requireData : const <DownloadAlbum>[];
        final allSelected =
            albums.isNotEmpty &&
            albums.every((album) => _selected.contains(album.id));
        return Scaffold(
          appBar: AppBar(
            title: Text(switch (widget.scope) {
              DownloadExportScope.completed => context.l10n.tr(
                '批量导出',
                en: 'Batch export',
              ),
              DownloadExportScope.includingIncomplete => context.l10n.tr(
                '批量导出(即使没有下载完)',
                en: 'Batch export (including unfinished downloads)',
              ),
            }),
            actions: [
              IconButton(
                tooltip: allSelected
                    ? context.l10n.tr('取消全选', en: 'Deselect all')
                    : context.l10n.tr('全选', en: 'Select all'),
                onPressed: !ready || albums.isEmpty || _openingExport
                    ? null
                    : () => setState(() {
                        _selected.clear();
                        if (!allSelected) {
                          _selected.addAll(albums.map((album) => album.id));
                        }
                      }),
                icon: const Icon(Icons.select_all),
              ),
              IconButton(
                tooltip: context.l10n.tr('导出所选', en: 'Export selected'),
                onPressed: ready && !_openingExport ? _openExport : null,
                icon: const Icon(Icons.file_upload_outlined),
              ),
            ],
          ),
          body: snapshot.hasError
              ? ContentError(
                  error: snapshot.error,
                  stackTrace: snapshot.stackTrace,
                  onRefresh: _refresh,
                )
              : !ready
              ? ContentLoading(
                  label: context.l10n.tr('加载中...', en: 'Loading...'),
                )
              : albums.isEmpty
              ? Center(
                  child: Text(
                    context.l10n.tr('没有可导出的下载', en: 'No downloads to export'),
                  ),
                )
              : ListView.builder(
                  itemCount: albums.length,
                  itemBuilder: (context, index) {
                    final album = albums[index];
                    final selected = _selected.contains(album.id);
                    return Semantics(
                      selected: selected,
                      button: true,
                      enabled: !_openingExport,
                      child: InkWell(
                        onTap: _openingExport
                            ? null
                            : () => setState(
                                () => toggleSelectedDownloadId(
                                  _selected,
                                  album.id,
                                ),
                              ),
                        child: Row(
                          children: [
                            Expanded(child: ComicDownloadCard(album)),
                            Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: Icon(
                                selected
                                    ? Icons.check_circle
                                    : Icons.circle_outlined,
                                color: Theme.of(context).colorScheme.secondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        );
      },
    ),
  );
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:jmcomic3/screens/components/dialogs.dart';
import 'package:jmcomic3/screens/components/feedback.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/configs/download_thread_count.dart';
import 'package:jmcomic3/configs/download_and_export_to.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/components/content_loading.dart';
import 'package:jmcomic3/screens/download_import_screen.dart';

import 'components/comic_download_card.dart';
import 'components/right_click_pop.dart';
import 'download_album_screen.dart';
import 'download_export_selection_screen.dart';

enum _DownloadsAction { export, concurrency, refresh }

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  static const _autoRefreshInterval = Duration(seconds: 2);

  bool _loading = true;
  bool _loadingDownloads = false;
  List<DownloadAlbum> _downloads = [];
  Timer? _autoRefreshTimer;
  String? _downloadDirectory;
  String? _directoryError;
  String? _loadError;

  Future<void> _loadDirectory() async {
    try {
      final directory = await methods.getEffectiveDownloadDir();
      if (!mounted) return;
      setState(() {
        _downloadDirectory = directory;
        _directoryError = null;
      });
    } catch (error) {
      if (mounted) setState(() => _directoryError = '$error');
    }
  }

  void _setState(_) {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _load({bool showLoading = false}) async {
    if (_loadingDownloads) {
      _syncAutoRefresh();
      return;
    }
    _loadingDownloads = true;
    if (showLoading && mounted) {
      setState(() {
        _loading = true;
      });
    }
    try {
      final downloads = await methods.allDownloads();
      if (!mounted) {
        return;
      }
      setState(() {
        _downloads = downloads;
        _loadError = null;
        _loading = false;
      });
    } catch (error) {
      if (mounted) setState(() => _loadError = '$error');
    } finally {
      _loadingDownloads = false;
      if (mounted) {
        if (showLoading && _loading) {
          setState(() {
            _loading = false;
          });
        }
        _syncAutoRefresh();
      }
    }
  }

  void _syncAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
    if (!_downloads.any((e) => e.shouldAutoRefreshStatus)) {
      return;
    }
    _autoRefreshTimer = Timer(_autoRefreshInterval, () {
      _load();
    });
  }

  @override
  void initState() {
    super.initState();
    downloadThreadCountEvent.subscribe(_setState);
    _load(showLoading: true);
    _loadDirectory();
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    downloadThreadCountEvent.unsubscribe(_setState);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return rightClickPop(child: buildScreen(context), context: context);
  }

  Widget buildScreen(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.downloads),
        actions: [
          importButton(),
          PopupMenuButton<_DownloadsAction>(
            tooltip: l10n.tr('更多下载操作', en: 'More download options'),
            icon: const Icon(Icons.more_vert),
            onSelected: _toolbarAction,
            itemBuilder: (context) => [
              _toolbarMenuItem(
                _DownloadsAction.export,
                Icons.ios_share,
                l10n.tr('导出下载', en: 'Export downloads'),
              ),
              _toolbarMenuItem(
                _DownloadsAction.concurrency,
                Icons.tune,
                l10n.tr(
                  '并发下载：$downloadThreadCount',
                  en: 'Concurrent downloads: $downloadThreadCount',
                ),
              ),
              _toolbarMenuItem(
                _DownloadsAction.refresh,
                Icons.refresh,
                l10n.tr('刷新下载状态', en: 'Refresh download status'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(Icons.folder_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.tr('新下载保存到', en: 'New downloads are saved to'),
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      if (_directoryError != null)
                        Text(
                          l10n.tr(
                            '无法读取下载目录：$_directoryError',
                            en: 'Could not read download directory: $_directoryError',
                          ),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        )
                      else
                        SelectableText(
                          _downloadDirectory ?? l10n.loading,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: _directoryError != null
                      ? l10n.tr('重试', en: 'Retry')
                      : l10n.tr('更改目录', en: 'Change directory'),
                  onPressed: () async {
                    if (_directoryError == null) {
                      await chooseDownloadDirectory(context);
                    }
                    if (mounted) await _loadDirectory();
                  },
                  icon: Icon(
                    _directoryError != null
                        ? Icons.refresh
                        : Icons.edit_outlined,
                  ),
                ),
              ],
            ),
          ),
          if (_loadError != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline,
                    color: Theme.of(context).colorScheme.error,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.tr('无法加载下载列表', en: 'Could not load downloads'),
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.tr('重试', en: 'Retry'),
                    onPressed: () => _load(showLoading: _downloads.isEmpty),
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading && _downloads.isEmpty) {
      return ContentLoading(label: context.l10n.loading);
    }
    if (_downloads.isEmpty && _loadError == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            context.l10n.tr(
              '暂无下载，可从漫画详情添加或导入已有备份。',
              en: 'No downloads yet. Add chapters from comic details or import a backup.',
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return _listView();
  }

  Widget _listView() {
    // 下载记录可能长期累积；列表页只构建可见卡片，避免进入页面时一次性创建全部 Widget。
    return ListView.builder(
      itemCount: _downloads.length,
      itemBuilder: (context, index) {
        final download = _downloads[index];
        return GestureDetector(
          key: Key("DOWNLOAD:${download.id}"),
          onTap: () => _openDownload(download),
          onLongPress: () => _chooseDownloadAction(download),
          onSecondaryTap: () => _chooseDownloadAction(download),
          child: ComicDownloadCard(
            download,
            onActions: download.isDeleting
                ? null
                : () => _chooseDownloadAction(download),
          ),
        );
      },
    );
  }

  Future<void> _openDownload(DownloadAlbum download) async {
    if (download.dlStatus == 3) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (BuildContext context) {
          return DownloadAlbumScreen(download);
        },
      ),
    );
    if (!mounted) {
      return;
    }
    _load();
  }

  Future<void> _chooseDownloadAction(DownloadAlbum download) async {
    final deleteLabel = context.l10n.delete;
    final pauseLabel = context.l10n.tr('暂停下载', en: 'Pause download');
    final resumeLabel = context.l10n.tr('继续下载', en: 'Resume download');
    final chooseTitle = context.l10n.choose;
    final action = await chooseListDialog(
      context,
      values: [
        if (download.isQueuedOrDownloading) pauseLabel,
        if (download.isPaused || download.isFailed) resumeLabel,
        deleteLabel,
      ],
      title: chooseTitle,
    );
    if (!mounted || action == null) {
      return;
    }
    try {
      if (action == pauseLabel) {
        await methods.pauseDownload(download.id);
      } else if (action == resumeLabel) {
        await methods.resumeDownload(download.id);
      } else if (action == deleteLabel) {
        await methods.deleteDownload(download.id);
      }
      if (mounted) await _load(showLoading: _downloads.isEmpty);
    } catch (error) {
      if (mounted) defaultToast(context, '$error');
    }
  }

  Widget importButton() {
    return IconButton(
      tooltip: context.l10n.tr('导入下载', en: 'Import downloads'),
      onPressed: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const DownloadImportScreen()),
        );
        if (!mounted) {
          return;
        }
        _load(showLoading: _downloads.isEmpty);
      },
      icon: const Icon(Icons.move_to_inbox_outlined),
    );
  }

  PopupMenuItem<_DownloadsAction> _toolbarMenuItem(
    _DownloadsAction action,
    IconData icon,
    String label,
  ) {
    return PopupMenuItem(
      value: action,
      height: 48,
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(label)),
        ],
      ),
    );
  }

  Future<void> _toolbarAction(_DownloadsAction action) async {
    try {
      switch (action) {
        case _DownloadsAction.export:
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  const DownloadExportSelectionScreen.completed(),
            ),
          );
          break;
        case _DownloadsAction.concurrency:
          await chooseDownloadThread(context);
          break;
        case _DownloadsAction.refresh:
          await methods.renewAllDownloads();
          break;
      }
      if (mounted) await _load(showLoading: _downloads.isEmpty);
    } catch (error) {
      if (mounted) defaultToast(context, '$error');
    }
  }
}

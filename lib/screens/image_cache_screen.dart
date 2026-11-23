import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/image_cache_stats.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/basic/page_image_provider.dart';

import 'components/right_click_pop.dart';

class ImageCacheScreen extends StatefulWidget {
  const ImageCacheScreen({super.key});

  @override
  State<ImageCacheScreen> createState() => _ImageCacheScreenState();
}

class _ImageCacheScreenState extends State<ImageCacheScreen> {
  List<ImageCacheDay> _days = const [];
  final Set<String> _selected = {};
  bool _loading = true;
  bool _cleaning = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final days = await methods.imageCacheStats();
      if (!mounted) return;
      setState(() {
        _days = days;
        _selected.removeWhere((date) => !days.any((day) => day.date == date));
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _cleanSelected() async {
    if (_cleaning || _loading || _selected.isEmpty) return;
    setState(() {
      _cleaning = true;
      _error = null;
    });
    try {
      await methods.cleanImageCacheDates(_selected.toList(growable: false));
      clearAllImageMemoryCaches();
      if (!mounted) return;
      _selected.clear();
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _cleaning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = Theme.of(context).colorScheme;
    final busy = _loading || _cleaning;
    final totalBytes = _days.fold<int>(0, (total, day) => total + day.bytes);
    final totalFiles = _days.fold<int>(
      0,
      (total, day) => total + day.fileCount,
    );
    final selectedBytes = _days
        .where((day) => _selected.contains(day.date))
        .fold<int>(0, (total, day) => total + day.bytes);
    return rightClickPop(
      context: context,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.tr('图片缓存', en: 'Image cache')),
          actions: [
            IconButton(
              tooltip: l10n.tr('刷新统计', en: 'Refresh statistics'),
              onPressed: busy ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: Column(
          children: [
            if (busy)
              LinearProgressIndicator(
                semanticsLabel: _cleaning
                    ? l10n.tr('正在清理…', en: 'Cleaning…')
                    : l10n.tr('加载统计中', en: 'Loading statistics'),
              ),
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Card(
                      margin: const EdgeInsets.all(12),
                      color: colors.surfaceContainerLow,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 32,
                              child: Icon(
                                Icons.storage_outlined,
                                size: 24,
                                color: colors.primary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${formatCacheBytes(totalBytes)} · ${l10n.tr('$totalFiles 个文件', en: '$totalFiles files')}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    l10n.tr(
                                      '按修改日期（UTC）选择缓存清理，已下载漫画会保留。',
                                      en: 'Select caches by modification date (UTC). Downloaded comics are kept.',
                                    ),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (_error != null)
                    SliverToBoxAdapter(
                      child: Semantics(
                        liveRegion: true,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 32,
                                    child: Icon(
                                      Icons.error_outline,
                                      color: colors.error,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      l10n.tr(
                                        '操作失败：$_error',
                                        en: 'Operation failed: $_error',
                                      ),
                                      style: TextStyle(color: colors.error),
                                    ),
                                  ),
                                ],
                              ),
                              Padding(
                                padding: const EdgeInsets.only(left: 44),
                                child: TextButton.icon(
                                  style: TextButton.styleFrom(
                                    minimumSize: const Size(48, 48),
                                  ),
                                  onPressed: busy ? null : _load,
                                  icon: const Icon(Icons.refresh, size: 20),
                                  label: Text(l10n.tr('重新加载', en: 'Reload')),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (_days.isNotEmpty)
                    SliverToBoxAdapter(
                      child: CheckboxListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                        ),
                        minTileHeight: 48,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(l10n.tr('全选', en: 'Select all')),
                        tristate: true,
                        value: _selected.isEmpty
                            ? false
                            : _selected.length == _days.length
                            ? true
                            : null,
                        onChanged: busy
                            ? null
                            : (_) => setState(() {
                                final selectAll =
                                    _selected.length != _days.length;
                                _selected.clear();
                                if (selectAll) {
                                  _selected.addAll(
                                    _days.map((day) => day.date),
                                  );
                                }
                              }),
                      ),
                    ),
                  if (_days.isEmpty && !busy && _error == null)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.photo_library_outlined,
                                size: 32,
                                color: colors.onSurfaceVariant,
                              ),
                              const SizedBox(height: 8),
                              Text(l10n.tr('没有图片缓存', en: 'No image cache')),
                            ],
                          ),
                        ),
                      ),
                    )
                  else
                    SliverList.builder(
                      itemCount: _days.length,
                      itemBuilder: (context, index) {
                        final day = _days[index];
                        return CheckboxListTile(
                          key: ValueKey('cache-date-${day.date}'),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                          ),
                          minTileHeight: 64,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text(day.date),
                          subtitle: Text(
                            '${l10n.tr('${day.fileCount} 个文件', en: '${day.fileCount} files')} · ${formatCacheBytes(day.bytes)}',
                          ),
                          value: _selected.contains(day.date),
                          onChanged: busy
                              ? null
                              : (value) => setState(() {
                                  if (value == true) {
                                    _selected.add(day.date);
                                  } else {
                                    _selected.remove(day.date);
                                  }
                                }),
                        );
                      },
                    ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  onPressed: busy || _selected.isEmpty ? null : _cleanSelected,
                  icon: const Icon(Icons.delete_outline),
                  label: Text(
                    _cleaning
                        ? l10n.tr('正在清理…', en: 'Cleaning…')
                        : l10n.tr(
                            '清理所选 ${_selected.length} 天 · ${formatCacheBytes(selectedBytes)}',
                            en: 'Clear ${_selected.length} selected days · ${formatCacheBytes(selectedBytes)}',
                          ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

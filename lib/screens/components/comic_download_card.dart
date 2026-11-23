import 'package:flutter/material.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

import '../../basic/methods.dart';
import 'images.dart';

class ComicDownloadCard extends StatelessWidget {
  final DownloadAlbum comic;
  final VoidCallback? onActions;

  const ComicDownloadCard(this.comic, {super.key, this.onActions});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = _statusText(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: JM3x4Cover(comicId: comic.id, width: 60, height: 80),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Tooltip(
                  // Hover still shows the full title; a long press belongs to the
                  // card, which opens the download actions.
                  triggerMode: TooltipTriggerMode.manual,
                  message: comic.name,
                  child: Text(
                    comic.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                if (comic.authorLabel.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    comic.authorLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_statusIcon(), size: 14, color: _statusColor()),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            status,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: _statusColor(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '${comic.dledImageCount} / ${comic.imageCount}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
                if (comic.downloadProgress != null) ...[
                  const SizedBox(height: 5),
                  _buildProgress(context),
                ],
              ],
            ),
          ),
          if (onActions != null)
            IconButton(
              tooltip: context.l10n.tr('下载操作', en: 'Download actions'),
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              onPressed: onActions,
              icon: const Icon(Icons.more_vert, size: 20),
            ),
        ],
      ),
    );
  }

  Widget _buildProgress(BuildContext context) {
    final progress = comic.downloadProgress;
    if (progress == null) {
      return Container();
    }
    final color = _statusColor();
    return ClipRRect(
      borderRadius: const BorderRadius.all(Radius.circular(3)),
      child: LinearProgressIndicator(
        value: comic.isDeleting ? null : progress,
        minHeight: 4,
        color: color,
        backgroundColor: color.withValues(alpha: .14),
      ),
    );
  }

  String _statusText(BuildContext context) {
    if (comic.isQueuedOrDownloading) {
      if (comic.dledImageCount > 0) {
        return context.l10n.tr("下载中", en: "Downloading");
      }
      return context.l10n.tr("队列中", en: "Queued");
    }
    if (comic.isDownloaded) {
      return context.l10n.tr("已下载", en: "Downloaded");
    }
    if (comic.isFailed) {
      return context.l10n.tr("已失败", en: "Failed");
    }
    if (comic.isPaused) {
      return context.l10n.tr('已暂停', en: 'Paused');
    }
    if (comic.isDeleting) {
      return context.l10n.tr("删除中", en: "Deleting");
    }
    return context.l10n.tr("未知状态", en: "Unknown status");
  }

  Color _statusColor() {
    if (comic.isQueuedOrDownloading) {
      return Colors.blue;
    }
    if (comic.isDownloaded) {
      return Colors.green;
    }
    if (comic.isFailed) {
      return Colors.red;
    }
    if (comic.isPaused) {
      return Colors.blueGrey;
    }
    if (comic.isDeleting) {
      return Colors.orange;
    }
    return Colors.grey;
  }

  IconData _statusIcon() {
    if (comic.isPaused) return Icons.pause_circle_outline;
    if (comic.isFailed) return Icons.error_outline;
    if (comic.isDeleting) return Icons.delete_outline;
    if (comic.isDownloaded) return Icons.check_circle_outline;
    if (comic.isQueuedOrDownloading) {
      return comic.dledImageCount == 0
          ? Icons.schedule
          : Icons.downloading_outlined;
    }
    return Icons.help_outline;
  }
}

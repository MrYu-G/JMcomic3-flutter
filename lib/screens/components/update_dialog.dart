import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:jmcomic3/screens/components/dialogs.dart';
import 'package:jmcomic3/screens/components/feedback.dart';
import 'package:jmcomic3/basic/trusted_updates.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

class ReleaseNotes extends StatelessWidget {
  const ReleaseNotes({super.key, required this.body});
  final String body;

  @override
  Widget build(BuildContext context) => MarkdownBody(
    data: body.trim().isEmpty ? context.l10n.updateContentUnavailable : body,
    selectable: true,
    // Release text is informational. Update navigation is through the
    // verified package controls or the fixed official releases link.
    imageBuilder: (_, __, ___) => const SizedBox.shrink(),
  );
}

class UpdateReleaseDialog extends StatelessWidget {
  const UpdateReleaseDialog({super.key, required this.release});
  final TrustedRelease release;

  @override
  Widget build(BuildContext context) => AlertDialog(
    insetPadding: EdgeInsets.symmetric(
      horizontal: MediaQuery.sizeOf(context).width < 600 ? 16 : 40,
      vertical: 24,
    ),
    titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
    contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
    actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
    title: Text(
      '${context.l10n.tr('发现新版本', en: 'Update available')} ${release.tag}',
    ),
    content: SizedBox(
      width: 600,
      child: SingleChildScrollView(child: ReleaseNotes(body: release.body)),
    ),
    actions: [
      TextButton(
        style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
        onPressed: () => Navigator.pop(context),
        child: Text(context.l10n.tr('稍后', en: 'Later')),
      ),
      FilledButton.icon(
        style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
        onPressed: () => chooseUpdatePackage(context, release),
        icon: const Icon(Icons.download_outlined),
        label: Text(context.l10n.tr('下载更新', en: 'Download update')),
      ),
    ],
  );
}

Future<void> chooseUpdatePackage(
  BuildContext context,
  TrustedRelease release,
) async {
  final assets = release.assets
      .where(
        (asset) => Platform.isAndroid
            ? asset.name.endsWith('.apk')
            : Platform.isWindows && asset.name.endsWith('.zip'),
      )
      .toList();
  if (assets.isEmpty) {
    defaultToast(
      context,
      context.l10n.tr(
        '该版本暂无可验证的安装包，请查看官方发布页',
        en: 'No verifiable package is available. See the official release page.',
      ),
    );
    return;
  }
  final asset = assets.length == 1
      ? assets.single
      : await chooseMapDialog<UpdateAsset>(
          context,
          title: context.l10n.tr('选择安装包架构', en: 'Choose package architecture'),
          values: {for (final asset in assets) asset.name: asset},
        );
  if (asset == null || !context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) =>
        UpdateDownloadDialog(version: release.tag, asset: asset),
  );
}

String _size(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

class UpdateDownloadDialog extends StatefulWidget {
  const UpdateDownloadDialog({
    super.key,
    required this.version,
    required this.asset,
    this.downloader,
  });
  final String version;
  final UpdateAsset asset;
  final UpdateDownloader? downloader;

  @override
  State<UpdateDownloadDialog> createState() => _UpdateDownloadDialogState();
}

class _UpdateDownloadDialogState extends State<UpdateDownloadDialog> {
  UpdateDownloader? _downloader;
  UpdateDownloadProgress? _progress;
  File? _file;
  bool _failed = false;
  bool _saving = false;
  String? _savedPath;
  DateTime _lastProgress = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _download();
  }

  Future<void> _download() async {
    final downloader = widget.downloader ?? UpdateDownloader();
    _downloader = downloader;
    setState(() {
      _failed = false;
      _progress = null;
    });
    try {
      final file = await downloader.download(widget.asset, (progress) {
        if (!mounted) return;
        final now = DateTime.now();
        if (progress.phase != _progress?.phase ||
            now.difference(_lastProgress).inMilliseconds >= 100) {
          _lastProgress = now;
          setState(() => _progress = progress);
        }
      });
      if (!mounted) {
        await file.parent.delete(recursive: true);
        return;
      }
      setState(() => _file = file);
    } on UpdateDownloadCancelled {
      // The downloader owns partial-file cleanup when the dialog closes.
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _save() async {
    final file = _file;
    if (file == null) return;
    setState(() => _saving = true);
    try {
      // Android uses the system document picker (SAF), which needs no broad
      // storage permission. Only bytes that passed verification reach export.
      final bytes = await file.readAsBytes();
      final uri = await FilePicker.saveFile(
        dialogTitle: context.l10n.tr('保存更新安装包', en: 'Save update package'),
        fileName: widget.asset.name,
        mimeType: widget.asset.name.endsWith('.apk')
            ? 'application/vnd.android.package-archive'
            : 'application/zip',
        bytes: bytes,
      );
      if (uri != null) {
        if (mounted) {
          setState(
            () => _savedPath = uri.scheme == 'file'
                ? uri.toFilePath()
                : uri.toString(),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        defaultToast(
          context,
          context.l10n.tr(
            '保存失败，请重试',
            en: 'Could not save the package. Please retry.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _downloader?.cancel();
    final file = _file;
    if (file != null) {
      unawaited(
        file.parent.delete(recursive: true).catchError((_) => file.parent),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _file != null;
    final verifying = _progress?.phase == UpdateDownloadPhase.verifying;
    final colors = Theme.of(context).colorScheme;
    final status = _failed
        ? context.l10n.tr(
            '下载或完整性校验失败，请重试',
            en: 'Download or integrity verification failed. Please retry.',
          )
        : _savedPath != null
        ? context.l10n.tr('安装包已保存', en: 'Package saved')
        : ready
        ? context.l10n.tr(
            'SHA-256 校验通过，可以保存安装包',
            en: 'SHA-256 verified. The package is ready to save.',
          )
        : verifying
        ? context.l10n.tr('正在校验 SHA-256…', en: 'Verifying SHA-256…')
        : context.l10n.tr('下载中…', en: 'Downloading…');
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        insetPadding: EdgeInsets.symmetric(
          horizontal: MediaQuery.sizeOf(context).width < 600 ? 16 : 40,
          vertical: 24,
        ),
        titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        title: Text(
          '${context.l10n.tr('下载更新', en: 'Download update')} ${widget.version}',
        ),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.asset.name,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: verifying ? null : _progress?.fraction ?? 0,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '${((_progress?.fraction ?? 0) * 100).toStringAsFixed(0)}%',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    Text(
                      '${_size(_progress?.received ?? 0)} / ${_size(widget.asset.size)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  context.l10n.tr(
                    '下载线路：GitHub 官方',
                    en: 'Download route: Official GitHub',
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(
                      _failed
                          ? Icons.error_outline
                          : _savedPath != null
                          ? Icons.check_circle_outline
                          : ready
                          ? Icons.verified_outlined
                          : verifying
                          ? Icons.shield_outlined
                          : Icons.downloading_outlined,
                      color: _failed ? colors.error : colors.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(status)),
                  ],
                ),
                if (_savedPath != null) ...[
                  const SizedBox(height: 12),
                  SelectableText(
                    _savedPath!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.l10n.tr(
                      'Android：打开 APK 安装。Windows：退出应用后完整解压 ZIP。',
                      en: 'Android: open the APK to install. Windows: exit the app and extract the entire ZIP.',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: Text(
              ready || _failed
                  ? context.l10n.tr('关闭', en: 'Close')
                  : context.l10n.tr('取消', en: 'Cancel'),
            ),
          ),
          if (_failed)
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
              onPressed: _download,
              icon: const Icon(Icons.refresh, size: 20),
              label: Text(context.l10n.tr('重试', en: 'Retry')),
            ),
          if (ready && _savedPath == null)
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save_alt, size: 20),
              label: Text(
                _saving
                    ? context.l10n.tr('保存中…', en: 'Saving…')
                    : context.l10n.tr('保存安装包', en: 'Save package'),
              ),
            ),
        ],
      ),
    );
  }
}

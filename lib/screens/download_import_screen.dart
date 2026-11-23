import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:filesystem_picker/filesystem_picker.dart';
import 'package:flutter/material.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

import 'package:jmcomic3/screens/components/file_actions.dart';
import '../basic/methods.dart';
import '../configs/is_pro.dart';
import 'components/right_click_pop.dart';
import 'download_import_shared.dart';

class DownloadImportScreen extends StatefulWidget {
  const DownloadImportScreen({super.key});

  @override
  State<DownloadImportScreen> createState() => _DownloadImportScreenState();
}

class _DownloadImportScreenState extends State<DownloadImportScreen> {
  bool _busy = false;
  bool _importing = false;
  bool _failed = false;
  bool _completed = false;
  String _message = '';

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_importing,
      child: rightClickPop(
        context: context,
        canPop: !_importing,
        child: Scaffold(
          appBar: AppBar(title: Text(l10n.tr('导入下载', en: 'Import downloads'))),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 840),
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  Card(
                    margin: EdgeInsets.zero,
                    color: colors.secondaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 32,
                            child: Icon(
                              Icons.restore_page_outlined,
                              color: colors.onSecondaryContainer,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l10n.tr(
                                    '把备份带回书架',
                                    en: 'Bring your backups to the library',
                                  ),
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(
                                        color: colors.onSecondaryContainer,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  l10n.tr(
                                    '导入本应用导出的 .jm.zip、.jmi 文件，或整个备份文件夹。完成后在下载列表查看，原始文件会保留。',
                                    en: 'Import .jm.zip or .jmi backups exported by this app, or an entire backup folder. Find imported comics in Downloads. Original files are kept.',
                                  ),
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: colors.onSecondaryContainer,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (!hasProAccess)
                    _notice(
                      Icons.workspace_premium_outlined,
                      l10n.tr('导入需要 Pro 权限', en: 'Import requires Pro access'),
                    ),
                  if (Platform.isAndroid)
                    _notice(
                      Icons.folder_open_outlined,
                      l10n.tr(
                        '选择备份需要文件权限。若被拒绝，请在系统设置中允许访问，或移至 Download / Documents 子文件夹后重试。',
                        en: 'File access is required. If denied, allow access in system settings or move backups into a Download / Documents subfolder and retry.',
                      ),
                    ),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth >= 600
                          ? (constraints.maxWidth - 8) / 2
                          : constraints.maxWidth;
                      return Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          SizedBox(
                            width: width,
                            child: _methodCard(
                              icon: Icons.file_open_outlined,
                              title: l10n.tr('从文件导入', en: 'Import a file'),
                              description: l10n.tr(
                                '选择一个 .jm.zip 或 .jmi 备份',
                                en: 'Choose one .jm.zip or .jmi backup',
                              ),
                              onTap: () => _import(folder: false),
                            ),
                          ),
                          SizedBox(
                            width: width,
                            child: _methodCard(
                              icon: Icons.drive_folder_upload_outlined,
                              title: l10n.tr('从文件夹导入', en: 'Import a folder'),
                              description: l10n.tr(
                                '批量导入文件夹内支持的备份文件',
                                en: 'Import supported backups from a folder',
                              ),
                              onTap: () => _import(folder: true),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  if (_message.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Semantics(
                      liveRegion: true,
                      child: Card(
                        margin: EdgeInsets.zero,
                        color: _failed
                            ? colors.errorContainer
                            : colors.surfaceContainerLow,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 32,
                                    child: Icon(
                                      _failed
                                          ? Icons.error_outline
                                          : _busy
                                          ? Icons.hourglass_top
                                          : _completed
                                          ? Icons.check_circle_outline
                                          : Icons.info_outline,
                                      color: _failed
                                          ? colors.onErrorContainer
                                          : colors.primary,
                                      size: 24,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      _message,
                                      style: TextStyle(
                                        color: _failed
                                            ? colors.onErrorContainer
                                            : colors.onSurface,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (_importing) ...[
                                const SizedBox(height: 12),
                                LinearProgressIndicator(
                                  semanticsLabel: l10n.tr(
                                    '正在导入',
                                    en: 'Importing',
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _notice(IconData icon, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 32,
          child: Icon(
            icon,
            size: 20,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    ),
  );

  Widget _methodCard({
    required IconData icon,
    required String title,
    required String description,
    required VoidCallback onTap,
  }) {
    return Card.outlined(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        button: true,
        enabled: !_busy,
        child: Tooltip(
          message: title,
          child: InkWell(
            onTap: _busy ? null : onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 72),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    SizedBox(
                      width: 32,
                      child: Icon(
                        icon,
                        size: 24,
                        color: _busy
                            ? Theme.of(context).disabledColor
                            : Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            description,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.chevron_right, size: 20),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _status(
    String message, {
    bool failed = false,
    bool importing = false,
    bool completed = false,
  }) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _failed = failed;
      _completed = completed;
      _importing = importing;
    });
  }

  Future<void> _import({required bool folder}) async {
    if (_busy) return;
    final l10n = context.l10n;
    if (!hasProAccess) {
      _status(
        l10n.tr('导入需要 Pro 权限', en: 'Import requires Pro access'),
        failed: true,
      );
      return;
    }
    setState(() => _busy = true);
    try {
      _status(l10n.tr('准备选择备份…', en: 'Preparing to choose a backup…'));
      if (!await androidMangeStorageRequest()) {
        _status(
          l10n.tr(
            '文件访问权限被拒绝。允许权限后可重试。',
            en: 'File access was denied. Allow access and try again.',
          ),
          failed: true,
        );
        return;
      }
      if (!mounted) return;
      final path = folder
          ? await chooseFolder(context)
          : await _chooseImportFilePath();
      if (!mounted) return;
      if (path == null) {
        _status(
          l10n.tr(
            '已取消选择，可重新选择备份。',
            en: 'Selection cancelled. You can choose another backup.',
          ),
        );
        return;
      }
      final kind = folder ? null : detectDownloadImportArchiveKind(path);
      if (!folder && kind == null) {
        _status(
          l10n.tr(
            '只支持 .jm.zip 和 .jmi 备份文件。',
            en: 'Only .jm.zip and .jmi backup files are supported.',
          ),
          failed: true,
        );
        return;
      }
      _status(
        l10n.tr('正在导入，请保持此页面打开…', en: 'Importing. Keep this page open…'),
        importing: true,
      );
      if (folder) {
        await methods.import_jm_dir(path);
      } else if (kind == DownloadImportArchiveKind.jmZip) {
        await methods.import_jm_zip(path);
      } else {
        await methods.import_jm_jmi(path);
      }
      _status(
        l10n.tr(
          '导入完成，可在下载列表查看。',
          en: 'Import complete. Open Downloads to view your comics.',
        ),
        completed: true,
      );
    } catch (error) {
      _status(
        l10n.tr('导入失败：$error', en: 'Import failed: $error'),
        failed: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _importing = false;
        });
      }
    }
  }

  Future<String?> _chooseImportFilePath() async {
    if (Platform.isAndroid) {
      return FilesystemPicker.open(
        title: context.l10n.tr('选择文件', en: 'Select file'),
        context: context,
        rootDirectory: Directory('/storage/emulated/0'),
        fsType: FilesystemType.file,
        folderIconColor: Theme.of(context).colorScheme.primary,
        allowedExtensions: ['.zip', '.jmi'],
        fileTileSelectMode: FileTileSelectMode.wholeTile,
      );
    }
    final file = await FilePicker.pickFile(
      dialogTitle: context.l10n.tr('选择要导入的文件', en: 'Choose file to import'),
      type: FileType.custom,
      allowedExtensions: ['zip', 'jmi'],
    );
    return file?.path;
  }
}

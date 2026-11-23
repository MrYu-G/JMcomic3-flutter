import 'package:flutter/material.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

import 'package:jmcomic3/screens/components/file_actions.dart';
import 'package:jmcomic3/screens/components/dialogs.dart';
import 'package:jmcomic3/screens/components/feedback.dart';
import '../basic/methods.dart';
import 'is_pro.dart';

String _currentDownloadAndExportTo = '';

Future<String?> initDownloadAndExportTo() async {
  _currentDownloadAndExportTo = await methods.getDownloadAndExportTo();
  return null;
}

String currentDownloadAndExportToName() => _currentDownloadAndExportTo.isEmpty
    ? 'Not set'
    : _currentDownloadAndExportTo;

String get currentDownloadAndExportTo => _currentDownloadAndExportTo;

Future<void> chooseDownloadDirectory(BuildContext context) async {
  final l10n = context.l10n;
  if (!hasProAccess) {
    defaultToast(
      context,
      l10n.tr(
        '自定义下载目录需要 Pro 权限',
        en: 'A custom download directory requires Pro access',
      ),
    );
    return;
  }
  final chooseNewLocation = l10n.tr('选择新位置', en: 'Choose new location');
  final useDefault = l10n.tr('使用默认目录', en: 'Use default directory');
  final choice = await chooseListDialog(
    context,
    values: [chooseNewLocation, useDefault],
    title: l10n.tr('新下载的保存目录', en: 'Directory for new downloads'),
  );
  if (choice == null || !context.mounted) return;
  try {
    String? path;
    if (choice == useDefault) {
      path = '';
    } else {
      if (!await androidMangeStorageRequest()) {
        if (context.mounted) {
          defaultToast(
            context,
            l10n.tr('文件访问权限被拒绝', en: 'File access was denied'),
          );
        }
        return;
      }
      if (!context.mounted) return;
      path = await chooseFolder(context);
    }
    if (path == null || !context.mounted) return;
    // Retain the existing property so historical preferences remain compatible.
    await methods.setDownloadAndExportTo(path);
    _currentDownloadAndExportTo = path;
  } catch (error) {
    if (context.mounted) {
      defaultToast(
        context,
        l10n.tr('设置目录失败：$error', en: 'Could not set directory: $error'),
      );
    }
  }
}

Widget downloadAndExportToSetting() => StatefulBuilder(
  builder: (context, setState) => ListTile(
    leading: const Icon(Icons.folder_outlined),
    title: Text(context.l10n.tr('下载目录', en: 'Download directory')),
    subtitle: Text(
      [
        _currentDownloadAndExportTo.isEmpty
            ? context.l10n.tr('使用默认目录', en: 'Using the default directory')
            : _currentDownloadAndExportTo,
        context.l10n.tr(
          '仅影响新下载，现有下载保留原位置。',
          en: 'Applies to new downloads. Existing downloads keep their location.',
        ),
      ].join('\n'),
    ),
    onTap: () async {
      await chooseDownloadDirectory(context);
      if (context.mounted) setState(() {});
    },
  ),
);

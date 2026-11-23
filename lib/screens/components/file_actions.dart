import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

import 'package:jmcomic3/configs/android_version.dart';
import 'package:jmcomic3/basic/methods.dart';

import 'feedback.dart';

Future<bool> androidGalleryPermissionRequest() async {
  if (Platform.isAndroid && androidVersion < 33) {
    return await (Permission.storage.request()).isGranted;
  }
  return true;
}

Future<bool> androidMangeStorageRequest() async {
  if (Platform.isAndroid) {
    if (androidVersion < 30) {
      return await (Permission.storage.request()).isGranted;
    }
    return await (Permission.manageExternalStorage.request()).isGranted;
  }
  return true;
}

Future saveImageFileToGallery(BuildContext context, String path) async {
  if (!await androidGalleryPermissionRequest()) {
    if (!context.mounted) return;
    throw Exception(context.l10n.tr("申请权限被拒绝", en: "Permission denied"));
  }
  if (!context.mounted) return;
  if (Platform.isIOS || Platform.isAndroid) {
    await methods.saveImageFileToGallery(path);
    if (!context.mounted) return;
    defaultToast(context, context.l10n.tr("保存成功", en: "Saved successfully"));
    return;
  }
  defaultToast(
    context,
    context.l10n.tr("暂不支持该平台", en: "Platform not supported"),
  );
}

Future saveImageFileToFile(BuildContext context, String path) async {
  if (!await androidGalleryPermissionRequest()) {
    if (!context.mounted) return;
    throw Exception(context.l10n.tr("申请权限被拒绝", en: "Permission denied"));
  }
  if (!context.mounted) return;
  String? folder;
  if (Platform.isAndroid) {
    folder = await methods.picturesDir();
  } else if (Platform.isIOS) {
    folder = await methods.iosGetDocumentDir() + "/pictures";
  } else {
    folder = await chooseFolder(context);
  }
  if (folder == null || !context.mounted) return;
  try {
    await methods.copyPictureToFolder(folder, path);
    if (!context.mounted) return;
    defaultToast(context, context.l10n.tr("保存成功", en: "Saved successfully"));
  } catch (e) {
    if (!context.mounted) return;
    defaultToast(context, context.l10n.tr("保存失败", en: "Save failed") + " : $e");
  }
}

/// 选择一个文件夹用于保存文件
Future<String?> chooseFolder(BuildContext context) async {
  // The embedded backend consumes filesystem paths, not Android SAF URIs.
  // Retain the path-returning API until the native storage contract supports SAF.
  return FilePicker.getDirectoryPath(
    dialogTitle: context.l10n.tr(
      "选择一个文件夹, 将文件保存到这里",
      en: "Choose a folder to save files",
    ),
  );
}

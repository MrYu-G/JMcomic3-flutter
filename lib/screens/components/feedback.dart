import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_styled_toast/flutter_styled_toast.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

import 'dialogs.dart';

/// 显示一个toast
void defaultToast(BuildContext context, String title) {
  showToast(
    context.l10n.tr(title),
    context: context,
    position: StyledToastPosition.center,
    animation: StyledToastAnimation.scale,
    reverseAnimation: StyledToastAnimation.fade,
    duration: const Duration(seconds: 4),
    animDuration: const Duration(seconds: 1),
    curve: Curves.elasticOut,
    reverseCurve: Curves.linear,
  );
}

Future<void> copyToClipBoard(BuildContext context, String text) async {
  try {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      defaultToast(
        context,
        context.l10n.tr('已复制到剪切板', en: 'Copied to clipboard'),
      );
    }
  } on PlatformException {
    if (context.mounted) {
      defaultToast(
        context,
        context.l10n.tr('复制失败', en: 'Could not copy to clipboard'),
      );
    }
  }
}

Future<void> confirmCopy(BuildContext context, String content) async {
  if (await confirmDialog(
        context,
        context.l10n.tr('复制', en: 'Copy'),
        content,
      ) &&
      context.mounted) {
    await copyToClipBoard(context, content);
  }
}

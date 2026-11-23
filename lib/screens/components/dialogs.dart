import 'package:flutter/material.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

Future<String?> displayTextInputDialog(
  BuildContext context, {
  String? title,
  String src = '',
  String? hint,
  String? desc,
  bool isPasswd = false,
}) => showDialog<String>(
  context: context,
  builder: (_) => _TextInputDialog(
    title: title,
    initialValue: src,
    hint: hint,
    description: desc,
    obscure: isPasswd,
  ),
);

class _TextInputDialog extends StatefulWidget {
  const _TextInputDialog({
    this.title,
    required this.initialValue,
    this.hint,
    this.description,
    required this.obscure,
  });
  final String? title;
  final String initialValue;
  final String? hint;
  final String? description;
  final bool obscure;

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  // Each route owns its controller, including the dismissal animation. Nested
  // dialogs cannot overwrite another prompt or retain its sensitive input.
  late final _controller = TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: widget.title == null ? null : Text(l10n.tr(widget.title!)),
      content: SingleChildScrollView(
        child: ListBody(
          children: [
            TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: widget.hint == null ? null : l10n.tr(widget.hint!),
              ),
              obscureText: widget.obscure,
              obscuringCharacter: '\u2022',
            ),
            if (widget.description != null)
              Padding(
                padding: const EdgeInsets.only(top: 20, bottom: 10),
                child: Text(
                  l10n.tr(widget.description!),
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).textTheme.bodyMedium?.color
                        ?.withValues(alpha: .5),
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        MaterialButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.tr('取消', en: 'Cancel')),
        ),
        MaterialButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: Text(l10n.confirm),
        ),
      ],
    );
  }
}

Future<T?> chooseListDialog<T>(
  BuildContext context, {
  required List<T> values,
  required String title,
  String? tips,
}) async {
  final l10n = context.l10n;
  return showDialog<T>(
    context: context,
    builder: (BuildContext context) {
      return SimpleDialog(
        title: Text(l10n.tr(title)),
        children: [
          ...values.map(
            (e) => SimpleDialogOption(
              onPressed: () {
                Navigator.of(context).pop(e);
              },
              child: Text(l10n.tr('$e')),
            ),
          ),
          ...tips != null
              ? [
                  Container(
                    padding: const EdgeInsets.fromLTRB(15, 5, 15, 15),
                    child: Text(l10n.tr(tips)),
                  ),
                ]
              : [],
        ],
      );
    },
  );
}

Future<T?> chooseMapDialog<T>(
  BuildContext buildContext, {
  required String title,
  required Map<String, T> values,
}) async {
  final l10n = buildContext.l10n;
  return await showDialog<T>(
    context: buildContext,
    builder: (BuildContext context) {
      return SimpleDialog(
        title: Text(l10n.tr(title)),
        children: values.entries
            .map(
              (e) => SimpleDialogOption(
                child: Text(l10n.tr(e.key)),
                onPressed: () {
                  Navigator.of(context).pop(e.value);
                },
              ),
            )
            .toList(),
      );
    },
  );
}

/// 显示一个确认框, 用户关闭弹窗以及选择否都会返回false, 仅当用户选择确定时返回true
Future<bool> confirmDialog(
  BuildContext context,
  String title,
  String content,
) async {
  final l10n = context.l10n;
  return await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.tr(title)),
          content: new SingleChildScrollView(
            child: new ListBody(children: <Widget>[new Text(l10n.tr(content))]),
          ),
          actions: <Widget>[
            new MaterialButton(
              child: new Text(l10n.tr('取消', en: 'Cancel')),
              onPressed: () {
                Navigator.of(context).pop(false);
              },
            ),
            new MaterialButton(
              child: new Text(l10n.confirm),
              onPressed: () {
                Navigator.of(context).pop(true);
              },
            ),
          ],
        ),
      ) ??
      false;
}

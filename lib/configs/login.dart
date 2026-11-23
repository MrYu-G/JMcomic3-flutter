import 'package:event/event.dart';
import 'package:flutter/material.dart';
import 'package:jmcomic3/screens/components/login_agreement.dart';
import 'package:jmcomic3/screens/components/dialogs.dart';
import 'package:jmcomic3/screens/components/feedback.dart';
import 'package:jmcomic3/screens/components/login_form.dart';
import 'package:jmcomic3/basic/log.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/configs/bool_property.dart';
import 'package:jmcomic3/configs/is_pro.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

enum LoginStatus { notSet, logging, loginField, loginSuccess, guest }

late SelfInfo _selfInfo;
LoginStatus _status = LoginStatus.notSet;
String _loginMessage = "";
const _guestModePropertyName = "guest_mode";
bool _guestMode = false;
final Event _event = Event();

SelfInfo get selfInfo => _selfInfo;

Event get loginEvent => _event;

LoginStatus get loginStatus => _status;

String get loginMessage => _loginMessage;

bool get hasJwtAccess => _status == LoginStatus.loginSuccess;

bool get isGuestMode => _status == LoginStatus.guest;

set _loginState(LoginStatus value) {
  _status = value;
  _event.broadcast();
}

String _loginFailureMessage(AppLocalizations l10n, Object error) {
  // Older native libraries can include the complete response in their errors.
  // Classify it locally, but only return our own text to the UI and debug log.
  final detail = '$error'.toLowerCase();
  if (error is FormatException ||
      error is TypeError ||
      detail.contains('jm response') ||
      detail.contains('parse json') ||
      detail.contains('decode response') ||
      detail.contains('decrypt') ||
      detail.contains('invalid response')) {
    return l10n.tr(
      '登录服务返回了异常数据 请稍后重试或更新应用',
      en: 'The sign-in service returned invalid data Retry later or update the app',
    );
  }
  if (RegExp(r'''\b(?:status|code)["']?\s*[:=]?\s*["']?(401|403)\b''')
          .hasMatch(detail) ||
      detail.contains('invalid username') ||
      detail.contains('invalid password') ||
      detail.contains('incorrect password') ||
      detail.contains('账号或密码') ||
      detail.contains('帳號或密碼')) {
    return l10n.tr(
      '账号或密码不正确 请检查后重试',
      en: 'Incorrect account or password Check your details and retry',
    );
  }
  if (detail.contains('timeout') ||
      detail.contains('timed out') ||
      detail.contains('connection') ||
      detail.contains('connect') ||
      detail.contains('network') ||
      detail.contains('socket') ||
      detail.contains('dns') ||
      detail.contains('error sending request') ||
      RegExp(r'\bstatus\s*[:=]?\s*5\d\d\b').hasMatch(detail)) {
    return l10n.tr(
      '无法连接登录服务 请检查网络或切换线路后重试',
      en: 'Unable to reach the sign-in service Check your connection or switch routes',
    );
  }
  return l10n.tr('登录失败 请稍后重试', en: 'Sign-in failed Please try again later');
}

Future initLogin(BuildContext context) async {
  final l10n = context.l10n;
  _loginMessage = '';
  try {
    _guestMode = parseBoolPropertyValue(
      await methods.loadProperty(_guestModePropertyName),
      fallback: false,
    );
    _loginState = LoginStatus.logging;
    final preLogin = await methods.preLogin();
    if (!preLogin.preSet) {
      _loginState = _guestMode ? LoginStatus.guest : LoginStatus.notSet;
    } else if (preLogin.preLogin) {
      _guestMode = false;
      await methods.saveProperty(_guestModePropertyName, "false");
      _selfInfo = preLogin.selfInfo!;
      _loginState = LoginStatus.loginSuccess;
      fav(context);
    } else {
      _loginMessage = _loginFailureMessage(l10n, preLogin.message ?? '');
      _loginState = _guestMode ? LoginStatus.guest : LoginStatus.loginField;
    }
  } catch (e) {
    _loginMessage = _loginFailureMessage(l10n, e);
    debugPrient('Pre-login failed: $_loginMessage');
    _loginState = _guestMode ? LoginStatus.guest : LoginStatus.loginField;
  } finally {
    reloadIsPro();
  }
}

List<FavoriteFolderItem> favData = [];

Future<void> _performFolderAction(
  BuildContext context,
  Future<dynamic> Function() action,
  String success,
) async {
  try {
    await action();
    // Refresh only after the server accepted the operation, so the next menu
    // never uses a removed/renamed folder from the previous session snapshot.
    favData = (await methods.favorite()).folderList;
    if (context.mounted) defaultToast(context, success);
  } catch (error) {
    if (context.mounted) defaultToast(context, '$error');
  }
}

Widget createFavoriteFolderItemTile(BuildContext context) {
  return ListTile(
    title: Text(context.l10n.tr("创建收藏文件夹", en: "Create favorites folder")),
    onTap: () async {
      if (!await ensureJwtAccess(
        context,
        feature: context.l10n.tr("创建收藏夹", en: "Create favorites folder"),
      )) {
        return;
      }
      var name = await displayTextInputDialog(
        context,
        title: context.l10n.tr("创建收藏文件夹", en: "Create favorites folder"),
        hint: context.l10n.tr("文件夹名称", en: "Folder name"),
      );
      if (name == null || !context.mounted) {
        return;
      }
      if (name.trim().isEmpty) return;
      await _performFolderAction(
        context,
        () => methods.createFavoriteFolder(name.trim()),
        context.l10n.tr('创建成功', en: 'Created successfully'),
      );
    },
  );
}

Widget deleteFavoriteFolderItemTile(BuildContext context) {
  return ListTile(
    title: Text(context.l10n.tr("删除收藏文件夹", en: "Delete favorites folder")),
    onTap: () async {
      if (!await ensureJwtAccess(
        context,
        feature: context.l10n.tr("删除收藏夹", en: "Delete favorites folder"),
      )) {
        return;
      }
      if (!context.mounted) return;
      if (!await fav(context) || !context.mounted) return;
      var j = favData.map((i) {
        return MapEntry(i.name, i.fid);
      }).toList();
      j.add(MapEntry(context.l10n.tr("默认 / 不删除", en: "Default / Keep"), 0));
      var v = await chooseMapDialog<int>(
        context,
        title: context.l10n.tr("删除资料夹", en: "Delete folder"),
        values: Map.fromEntries(j),
      );
      if (v != null && v != 0 && context.mounted) {
        await _performFolderAction(
          context,
          () => methods.deleteFavoriteFolder(v),
          context.l10n.tr('删除成功', en: 'Deleted successfully'),
        );
      }
    },
  );
}

Widget renameFavoriteFolderItemTile(BuildContext context) {
  return ListTile(
    title: Text(context.l10n.tr("重命名收藏文件夹", en: "Rename favorites folder")),
    onTap: () async {
      if (!await ensureJwtAccess(
        context,
        feature: context.l10n.tr("重命名收藏夹", en: "Rename favorites folder"),
      )) {
        return;
      }
      if (!context.mounted) return;
      if (!await fav(context) || !context.mounted) return;
      var j = favData.map((i) {
        return MapEntry(i.name, i.fid);
      }).toList();
      j.add(MapEntry(context.l10n.tr("默认 / 不重命名", en: "Default / Keep"), 0));
      var v = await chooseMapDialog<int>(
        context,
        title: context.l10n.tr("重命名资料夹", en: "Rename folder"),
        values: Map.fromEntries(j),
      );
      if (v != null && v != 0 && context.mounted) {
        var name = await displayTextInputDialog(
          context,
          title: context.l10n.tr("重命名收藏文件夹", en: "Rename favorites folder"),
          hint: context.l10n.tr("文件夹名称", en: "Folder name"),
        );
        if (name == null || !context.mounted) {
          return;
        }
        if (name.trim().isEmpty) return;
        await _performFolderAction(
          context,
          () => methods.renameFavoriteFolder(v, name.trim()),
          context.l10n.tr('重命名成功', en: 'Renamed successfully'),
        );
      }
    },
  );
}

Future<bool> fav(BuildContext buildContext) async {
  try {
    favData = (await methods.favorite()).folderList;
    return true;
  } catch (e, st) {
    debugPrient("$e\n$st");
    if (buildContext.mounted) defaultToast(buildContext, "$e");
    return false;
  }
}

Future login(String username, String password, BuildContext context) async {
  final l10n = context.l10n;
  _loginMessage = '';
  try {
    _loginState = LoginStatus.logging;
    final selfInfo = await methods.login(username, password);
    _guestMode = false;
    await methods.saveProperty(_guestModePropertyName, "false");
    _selfInfo = selfInfo;
    _loginState = LoginStatus.loginSuccess;
    fav(context);
  } catch (e) {
    _loginMessage = _loginFailureMessage(l10n, e);
    debugPrient('Login failed: $_loginMessage');
    _loginState = LoginStatus.loginField;
  }
}

Future<void> enterGuestMode() async {
  _guestMode = true;
  await methods.saveProperty(_guestModePropertyName, "true");
  _loginMessage = "";
  _loginState = LoginStatus.guest;
}

Future<bool> ensureJwtAccess(BuildContext context, {String? feature}) async {
  if (hasJwtAccess) {
    return true;
  }
  final shouldLogin = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) {
      final l10n = context.l10n;
      final targetFeature = feature ?? l10n.tr("该功能", en: "This feature");
      return AlertDialog(
        title: Text(l10n.tr("登录提醒", en: "Login required")),
        content: Text(
          isGuestMode
              ? l10n.tr(
                  "当前是游客模式，$targetFeature 需要登录后才能使用。",
                  en: "Guest mode is active. $targetFeature requires login.",
                )
              : l10n.tr(
                  "$targetFeature 需要登录后才能使用。",
                  en: "$targetFeature requires login.",
                ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(false);
            },
            child: Text(l10n.tr("取消", en: "Cancel")),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(true);
            },
            child: Text(l10n.tr("去登录", en: "Go login")),
          ),
        ],
      );
    },
  );
  if (shouldLogin == true) {
    await loginDialog(context);
  }
  return hasJwtAccess;
}

Future loginDialog(BuildContext context) async {
  await showDialog(
    context: context,
    builder: (BuildContext context) {
      return _LoginDialog();
    },
  );
}

class _LoginDialog extends StatefulWidget {
  @override
  State<_LoginDialog> createState() => _LoginDialogState();
}

class _LoginDialogState extends State<_LoginDialog> {
  late Future<(String, String)> _credentials = _loadCredentials();
  bool _busy = false;

  Future<(String, String)> _loadCredentials() async {
    final username = await methods.loadUsername();
    final password = await methods.loadPassword();
    return (username, password);
  }

  Future<String?> _submit(String username, String password) async {
    await login(username, password, context);
    if (!mounted) return null;
    if (loginStatus != LoginStatus.loginSuccess) {
      return loginMessage.isEmpty ? context.l10n.loginFailed : loginMessage;
    }
    await reloadIsPro();
    // Callers such as ensureJwtAccess must observe the completed authentication.
    if (mounted) Navigator.of(context).pop();
    return null;
  }

  Future<void> _guest() async {
    await enterGuestMode();
    await reloadIsPro();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(l10n.login, style: theme.textTheme.titleLarge),
                  ),
                  IconButton(
                    tooltip: l10n.tr('关闭', en: 'Close'),
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FutureBuilder<(String, String)>(
                future: _credentials,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Center(
                        child: CircularProgressIndicator(
                          semanticsLabel: l10n.tr(
                            '加载账号',
                            en: 'Loading account',
                          ),
                        ),
                      ),
                    );
                  }
                  if (snapshot.hasError) {
                    return Column(
                      children: [
                        Text(
                          l10n.tr(
                            '无法读取已保存的账号',
                            en: 'Unable to load the saved account',
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          alignment: WrapAlignment.center,
                          children: [
                            TextButton.icon(
                              onPressed: () => setState(() {
                                _credentials = _loadCredentials();
                              }),
                              icon: const Icon(Icons.refresh_rounded),
                              label: Text(l10n.tr('重试', en: 'Retry')),
                            ),
                            TextButton(
                              onPressed: () => setState(() {
                                _credentials = Future.value(('', ''));
                              }),
                              child: Text(
                                l10n.tr('手动登录', en: 'Enter manually'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  }
                  final (username, password) = snapshot.requireData;
                  return LoginForm(
                    initialUsername: username,
                    initialPassword: password,
                    onLogin: _submit,
                    onGuest: _guest,
                    onBusyChanged: (value) => setState(() => _busy = value),
                    agreement: const LoginAgreementHint(
                      padding: EdgeInsets.zero,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

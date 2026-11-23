import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/app_links.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

import '../configs/versions.dart';
import '../configs/is_pro.dart';
import '../configs/login.dart';
import '../configs/network_api_host.dart';
import '../configs/network_cdn_host.dart';
import 'app_screen.dart';
import 'components/login_agreement.dart';
import 'components/login_form.dart';
import 'components/recommend_links_panel.dart';

const firstLoginScreen = FirstLoginScreen();

class FirstLoginScreen extends StatefulWidget {
  const FirstLoginScreen({super.key});

  @override
  State<FirstLoginScreen> createState() => _FirstLoginScreenState();
}

class _FirstLoginScreenState extends State<FirstLoginScreen> {
  bool _busy = false;
  int _onClickVersion = 0;

  void _versionAction() {
    if (++_onClickVersion >= 7) {
      openUrl(
        String.fromCharCodes(
          base64Decode('aHR0cHM6Ly9qbWNvbWljMS5yb2Nrcy9zaWdudXA='),
        ),
      );
    }
  }

  void _openApp() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const AppScreen()),
    );
  }

  Future<String?> _login(String username, String password) async {
    await login(username, password, context);
    if (!mounted) return null;
    if (loginStatus != LoginStatus.loginSuccess) {
      return loginMessage.isEmpty ? context.l10n.loginFailed : loginMessage;
    }
    await reloadIsPro();
    _openApp();
    return null;
  }

  Future<void> _continueAsGuest() async {
    await enterGuestMode();
    await reloadIsPro();
    _openApp();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final appIcon = Image.asset(
      'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png',
      key: const ValueKey('login-app-icon'),
      width: 72,
      height: 72,
      excludeFromSemantics: true,
    );
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 600;
            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.symmetric(
                horizontal: wide ? 32 : 24,
                vertical: 24,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: (constraints.maxHeight - 48).clamp(
                    0,
                    double.infinity,
                  ),
                ),
                child: Align(
                  alignment: const Alignment(0, -0.16),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Column(
                      key: const ValueKey('login-page-content'),
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: theme.brightness == Brightness.dark
                              ? ColorFiltered(
                                  colorFilter: const ColorFilter.matrix([
                                    -1,
                                    0,
                                    0,
                                    0,
                                    255,
                                    0,
                                    -1,
                                    0,
                                    0,
                                    255,
                                    0,
                                    0,
                                    -1,
                                    0,
                                    255,
                                    0,
                                    0,
                                    0,
                                    1,
                                    0,
                                  ]),
                                  child: appIcon,
                                )
                              : appIcon,
                        ),
                        const SizedBox(height: 18),
                        Text(
                          l10n.tr('登录 JMComic3', en: 'Sign in to JMComic3'),
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 24),
                        LoginForm(
                          onLogin: _login,
                          onGuest: _continueAsGuest,
                          onBusyChanged: (value) =>
                              setState(() => _busy = value),
                          agreement: const LoginAgreementHint(
                            padding: EdgeInsets.zero,
                          ),
                        ),
                        const SizedBox(height: 24),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(color: colors.outlineVariant),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: ExpansionTile(
                            key: const PageStorageKey('login-connections'),
                            enabled: !_busy,
                            shape: const Border(),
                            collapsedShape: const Border(),
                            leading: const Icon(
                              Icons.alt_route_rounded,
                              size: 22,
                            ),
                            title: Text(
                              l10n.tr('连接设置', en: 'Connection settings'),
                              style: theme.textTheme.titleSmall,
                            ),
                            subtitle: Text(
                              l10n.tr(
                                '设置 API 和图片线路',
                                en: 'Choose API and image routes',
                              ),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                            tilePadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 2,
                            ),
                            children: [
                              ExcludeFocus(
                                excluding: _busy,
                                child: IgnorePointer(
                                  ignoring: _busy,
                                  child: apiHostSetting(),
                                ),
                              ),
                              ExcludeFocus(
                                excluding: _busy,
                                child: IgnorePointer(
                                  ignoring: _busy,
                                  child: cdnHostSetting(),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const RecommendLinksPanel(),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.center,
                          child: TextButton(
                            onPressed: _busy ? null : _versionAction,
                            child: Text(
                              currentVersion(),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

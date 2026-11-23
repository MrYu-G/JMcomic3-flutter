import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

/// Shared sign-in presentation. Callers retain authentication and navigation;
/// returning an error message keeps the form open for another attempt.
class LoginForm extends StatefulWidget {
  const LoginForm({
    super.key,
    required this.onLogin,
    required this.onGuest,
    required this.agreement,
    this.initialUsername = '',
    this.initialPassword = '',
    this.onBusyChanged,
  });

  final Future<String?> Function(String username, String password) onLogin;
  final Future<void> Function() onGuest;
  final Widget agreement;
  final String initialUsername;
  final String initialPassword;
  final ValueChanged<bool>? onBusyChanged;

  @override
  State<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<LoginForm> {
  final _formKey = GlobalKey<FormState>();
  late final _username = TextEditingController(text: widget.initialUsername);
  late final _password = TextEditingController(text: widget.initialPassword);
  final _passwordFocus = FocusNode();
  bool _obscure = true;
  bool _busy = false;
  bool _guestRequest = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit({bool guest = false}) async {
    if (_busy || (!guest && !_formKey.currentState!.validate())) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _guestRequest = guest;
      _error = null;
    });
    widget.onBusyChanged?.call(true);
    try {
      String? error;
      if (guest) {
        await widget.onGuest();
      } else {
        // Password whitespace is significant; never normalize it.
        error = await widget.onLogin(_username.text.trim(), _password.text);
      }
      if (!mounted) return;
      if (error == null && !guest) TextInput.finishAutofillContext();
      setState(() => _error = error);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _error = context.l10n.tr(
          '暂时无法连接 请检查网络后重试',
          en: 'Unable to connect Check your connection and retry',
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        widget.onBusyChanged?.call(false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final buttonStyle = ButtonStyle(
      visualDensity: VisualDensity.standard,
      minimumSize: const WidgetStatePropertyAll(Size.fromHeight(48)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
    return PopScope(
      canPop: !_busy,
      child: AutofillGroup(
        onDisposeAction: AutofillContextAction.cancel,
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const ValueKey('login-account'),
                controller: _username,
                enabled: !_busy,
                autofillHints: const [AutofillHints.username],
                textInputAction: TextInputAction.next,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: l10n.account,
                  prefixIcon: const Icon(Icons.person_outline_rounded),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 18,
                  ),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? l10n.inputAccount
                    : null,
                onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
              ),
              const SizedBox(height: 14),
              TextFormField(
                key: const ValueKey('login-password'),
                controller: _password,
                focusNode: _passwordFocus,
                enabled: !_busy,
                obscureText: _obscure,
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.done,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: l10n.password,
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    tooltip: _obscure
                        ? l10n.tr('显示密码', en: 'Show password')
                        : l10n.tr('隐藏密码', en: 'Hide password'),
                    onPressed: _busy
                        ? null
                        : () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 18,
                  ),
                ),
                validator: (value) =>
                    value == null || value.isEmpty ? l10n.inputPassword : null,
                onFieldSubmitted: (_) => _submit(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colors.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          size: 20,
                          color: colors.onErrorContainer,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _error!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colors.onErrorContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton.icon(
                key: const ValueKey('login-submit'),
                style: buttonStyle,
                onPressed: _busy ? null : () => _submit(),
                icon: _busy && !_guestRequest
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.login_rounded, size: 20),
                label: Text(
                  _busy && !_guestRequest
                      ? l10n.tr('正在登录…', en: 'Signing in')
                      : l10n.login,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                key: const ValueKey('login-guest'),
                style: buttonStyle,
                onPressed: _busy ? null : () => _submit(guest: true),
                icon: _busy && _guestRequest
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.explore_outlined, size: 20),
                label: Text(
                  _busy && _guestRequest
                      ? l10n.tr('正在进入', en: 'Opening')
                      : l10n.tr('以游客身份继续', en: 'Continue as guest'),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                l10n.tr(
                  '游客可浏览内容 收藏和评论需登录',
                  en: 'Guests can browse Favorites and comments require login',
                ),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              // A new route during authentication would steal the caller's
              // completion navigation (for example, closing the terms sheet).
              ExcludeFocus(
                excluding: _busy,
                child: IgnorePointer(ignoring: _busy, child: widget.agreement),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

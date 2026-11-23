import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/configs/login.dart' as login_config;
import 'package:jmcomic3/configs/theme.dart' as app_theme;
import 'package:jmcomic3/configs/versions.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/components/login_agreement.dart';
import 'package:jmcomic3/screens/components/login_form.dart';
import 'package:jmcomic3/screens/first_login_screen.dart';

const _channel = MethodChannel('methods');
const _preview = ValueKey('login-layout-preview');
const _accountKey = ValueKey('login-account');
const _passwordKey = ValueKey('login-password');
const _submitKey = ValueKey('login-submit');
const _guestKey = ValueKey('login-guest');
const _openDialogKey = ValueKey('open-login-dialog');
const _invalidCredentialsMessage =
    'Incorrect account or password Check your details and retry';
const _connectionMessage =
    'Unable to reach the sign-in service Check your connection or switch routes';
const _invalidDataMessage =
    'The sign-in service returned invalid data Retry later or update the app';
const _rawLoginRejection =
    'jm request `https://example.invalid/login?token=private-response-marker` '
    'returned status 401: {"code":401,"data":[],"errorMsg":"invalid username/password"}';
final _screenshots = Platform.environment['LAYOUT_SCREENSHOTS'] == '1';

/// Native integration can capture the same asserted states without changing
/// production widgets or allowing this suite to write outside its output root.
Future<void> Function(String name, WidgetTester tester)? loginCheckpoint;

class _BackendFixture {
  final requests = <Map<String, dynamic>>[];
  final properties = <String, String>{'checkVersionPeriod': '-1'};
  String savedUsername = 'saved-reader';
  String savedPassword = ' synthetic password ';
  bool failLogin = false;
  String loginError = 'jm request returned status 401';
  String? loginRawResponse;
  String? preLoginError;
  String? preLoginRawResponse;
  String preLoginMessage = '';
  bool failGuest = false;
  bool failHydration = false;
  Completer<void>? hydrationGate;
  Completer<void>? loginGate;
  Completer<void>? guestGate;

  List<Map<String, dynamic>> calls(String method) =>
      requests.where((request) => request['method'] == method).toList();

  Future<String> handle(MethodCall call) async {
    if (call.method != 'invoke') {
      throw StateError('Unexpected platform call: ${call.method}');
    }
    final request = Map<String, dynamic>.from(
      jsonDecode(call.arguments as String) as Map,
    );
    requests.add(request);
    final method = request['method'];
    final params = request['params'] as String;
    Object response;
    switch (method) {
      case 'load_username':
      case 'load_password':
        await hydrationGate?.future;
        if (failHydration) {
          return _envelope('', error: 'Saved login unavailable');
        }
        response = method == 'load_username' ? savedUsername : savedPassword;
        break;
      case 'login':
        await loginGate?.future;
        if (loginRawResponse != null) return loginRawResponse!;
        if (failLogin) return _envelope('', error: loginError);
        response = {
          'uid': 42,
          'username': 'synthetic-reader',
          'email': 'reader@example.invalid',
          'emailverified': 'yes',
          'photo': '?v=0?v=',
          'fname': '',
          'gender': '',
          'message': '',
          'coin': 0,
          'album_favorites': 0,
          's': '',
          'level_name': '',
          'level': 1,
          'nextLevelExp': 1,
          'exp': '0',
          'expPercent': 0.0,
          'badges': <String>[],
          'album_favorites_max': 100,
        };
        break;
      case 'pre_login':
        if (preLoginRawResponse != null) return preLoginRawResponse!;
        if (preLoginError != null) return _envelope('', error: preLoginError!);
        response = {
          'pre_set': true,
          'pre_login': false,
          'self_info': null,
          'message': preLoginMessage,
        };
        break;
      case 'save_property':
        final values = jsonDecode(params) as Map;
        if (values['k'] == 'guest_mode' && values['v'] == 'true') {
          await guestGate?.future;
          if (failGuest) {
            return _envelope('', error: 'Fixture guest unavailable');
          }
        }
        properties[values['k'] as String] = values['v'] as String;
        response = '';
        break;
      case 'load_property':
        response = properties[params] ?? '';
        break;
      case 'favorite':
        response = {'total': 0, 'count': 0, 'list': [], 'folder_list': []};
        break;
      case 'pro_info_all':
        response = {
          'pro_info_af': {'is_pro': true, 'expire': 4102444800},
          'pro_info_pat': {'is_pro': true},
        };
        break;
      default:
        throw StateError('Unexpected backend operation: $method');
    }
    return _envelope(response);
  }
}

String _envelope(Object response, {String error = ''}) => jsonEncode({
  'error_message': error,
  'response_data': response is String ? response : jsonEncode(response),
});

Widget _app(
  Widget screen, {
  bool dark = false,
  double textScale = 1,
  String language = 'en',
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: app_theme.lightTheme,
  darkTheme: app_theme.darkTheme,
  themeMode: dark ? ThemeMode.dark : ThemeMode.light,
  locale: Locale(language),
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context)
        .copyWith(textScaler: TextScaler.linear(textScale)),
    child: RepaintBoundary(key: _preview, child: child!),
  ),
  home: screen,
);

Widget _form({
  required Future<String?> Function(String, String) onLogin,
  Future<void> Function()? onGuest,
  ValueChanged<bool>? onBusyChanged,
  String username = '',
  String password = '',
}) => Scaffold(
  body: SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: LoginForm(
      initialUsername: username,
      initialPassword: password,
      onLogin: onLogin,
      onGuest: onGuest ?? () async {},
      onBusyChanged: onBusyChanged,
      agreement: const LoginAgreementHint(padding: EdgeInsets.zero),
    ),
  ),
);

Widget _dialogHost({VoidCallback? onClosed}) => Scaffold(
  body: Builder(
    builder: (context) => Center(
      child: FilledButton(
        key: _openDialogKey,
        onPressed: () async {
          await login_config.loginDialog(context);
          onClosed?.call();
        },
        child: const Text('Open sign-in'),
      ),
    ),
  ),
);

Future<_BackendFixture> _prepare(
  WidgetTester tester, {
  Size size = const Size(393, 852),
}) async {
  // The integration runner creates its binding before this suite. Register
  // synthetic input after the per-test reset rather than replacing that binding
  // or allowing native IME notifications to race the injected editing values.
  final ownsTextInput = !tester.testTextInput.isRegistered;
  if (ownsTextInput) tester.testTextInput.register();
  final fixture = _BackendFixture();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(_channel, fixture.handle);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() async {
    try {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    } finally {
      if (ownsTextInput) tester.testTextInput.unregister();
      messenger.setMockMethodCallHandler(_channel, null);
      tester.view.resetViewInsets();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  });
  await login_config.enterGuestMode();
  await tester.runAsync(initVersion);
  fixture.requests.clear();
  return fixture;
}

EditableText _editable(WidgetTester tester, Key key) =>
    tester.widget<EditableText>(
      find.descendant(of: find.byKey(key), matching: find.byType(EditableText)),
    );

Future<void> _enter(
  WidgetTester tester,
  String username,
  String password,
) async {
  await tester.enterText(find.byKey(_accountKey), username);
  await tester.enterText(find.byKey(_passwordKey), password);
}

Future<void> _tap(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.tap(find.byKey(key));
  await tester.pump();
}

Future<void> _openDialog(WidgetTester tester) async {
  await _tap(tester, _openDialogKey);
  // A pending hydration request intentionally keeps a progress indicator alive.
  await tester.pump(const Duration(milliseconds: 300));
}

void _expectEnabled(WidgetTester tester, bool enabled) {
  expect(
    tester.widget<FilledButton>(find.byKey(_submitKey)).onPressed != null,
    enabled,
  );
  expect(
    tester.widget<OutlinedButton>(find.byKey(_guestKey)).onPressed != null,
    enabled,
  );
  expect(
    tester.widget<TextFormField>(find.byKey(_accountKey)).enabled,
    enabled,
  );
  expect(
    tester.widget<TextFormField>(find.byKey(_passwordKey)).enabled,
    enabled,
  );
}

Future<void> _checkpoint(WidgetTester tester, String name) async {
  expect(tester.takeException(), isNull);
  await loginCheckpoint?.call(name, tester);
  if (!_screenshots) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_preview),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/checks/login-layout/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(
        bytes!.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
    } finally {
      image.dispose();
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('empty account and password validate without submitting', (
    tester,
  ) async {
    await _prepare(tester);
    var calls = 0;
    await tester.pumpWidget(
      _app(
        _form(
          onLogin: (_, _) async {
            calls++;
            return null;
          },
        ),
      ),
    );
    await _tap(tester, _submitKey);
    expect(find.text('Enter account'), findsOneWidget);
    expect(find.text('Enter password'), findsOneWidget);
    expect(calls, 0);
    await tester.enterText(find.byKey(_accountKey), '   ');
    await _tap(tester, _submitKey);
    expect(calls, 0);
    _expectEnabled(tester, true);
    await _checkpoint(tester, 'form-empty-validation');
  });

  testWidgets(
    'password visibility is labelled and submission preserves whitespace',
    (tester) async {
      await _prepare(tester);
      final semantics = tester.ensureSemantics();
      try {
        final submitted = <(String, String)>[];
        await tester.pumpWidget(
          _app(
            _form(
              onLogin: (username, password) async {
                submitted.add((username, password));
                return null;
              },
            ),
          ),
        );
        await _enter(tester, '  synthetic-reader  ', ' pass word ');
        expect(_editable(tester, _passwordKey).obscureText, isTrue);
        expect(
          tester
              .getSemantics(find.byTooltip('Show password'))
              .getSemanticsData()
              .tooltip,
          'Show password',
        );
        await tester.tap(find.byTooltip('Show password'));
        await tester.pump();
        expect(_editable(tester, _passwordKey).obscureText, isFalse);
        expect(
          tester
              .getSemantics(find.byTooltip('Hide password'))
              .getSemanticsData()
              .tooltip,
          'Hide password',
        );
        expect(_editable(tester, _passwordKey).controller.text, ' pass word ');
        await tester.tap(find.byTooltip('Hide password'));
        await _tap(tester, _submitKey);
        // Native input/focus updates settle after the completed submission.
        // Start the next edit only once the fields are enabled again.
        await tester.pumpAndSettle();
        _expectEnabled(tester, true);
        expect(submitted, [('synthetic-reader', ' pass word ')]);
        await tester.enterText(find.byKey(_passwordKey), '   ');
        await tester.pumpAndSettle();
        expect(_editable(tester, _passwordKey).controller.text, '   ');
        await _tap(tester, _submitKey);
        await tester.pumpAndSettle();
        expect(submitted, [
          ('synthetic-reader', ' pass word '),
          ('synthetic-reader', '   '),
        ]);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('keyboard next focuses password and done submits once', (
    tester,
  ) async {
    await _prepare(tester);
    var calls = 0;
    await tester.pumpWidget(
      _app(
        _form(
          onLogin: (_, _) async {
            calls++;
            return null;
          },
        ),
      ),
    );
    await tester.enterText(find.byKey(_accountKey), 'synthetic-reader');
    expect(
      _editable(tester, _accountKey).textInputAction,
      TextInputAction.next,
    );
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();
    expect(_editable(tester, _passwordKey).focusNode.hasFocus, isTrue);
    await tester.enterText(find.byKey(_passwordKey), 'synthetic-pass');
    expect(
      _editable(tester, _passwordKey).textInputAction,
      TextInputAction.done,
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(calls, 1);
  });

  testWidgets(
    'busy form coalesces submissions and retains fields after rejection for retry',
    (tester) async {
      await _prepare(tester);
      final pending = Completer<String?>();
      final busy = <bool>[];
      var calls = 0;
      await tester.pumpWidget(
        _app(
          _form(
            onLogin: (_, _) {
              calls++;
              return calls == 1 ? pending.future : Future.value(null);
            },
            onBusyChanged: busy.add,
          ),
        ),
      );
      await _enter(tester, 'synthetic-reader', ' synthetic-pass ');
      final submit = tester
          .widget<FilledButton>(find.byKey(_submitKey))
          .onPressed!;
      submit();
      submit();
      await tester.pump();
      expect(calls, 1);
      _expectEnabled(tester, false);
      expect(find.text('Signing in'), findsOneWidget);
      await _checkpoint(tester, 'form-signing-in');
      pending.complete('Synthetic rejection. Please retry.');
      await tester.pumpAndSettle();
      _expectEnabled(tester, true);
      expect(
        _editable(tester, _accountKey).controller.text,
        'synthetic-reader',
      );
      expect(
        _editable(tester, _passwordKey).controller.text,
        ' synthetic-pass ',
      );
      expect(find.text('Synthetic rejection. Please retry.'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics && widget.properties.liveRegion == true,
        ),
        findsOneWidget,
      );
      await _checkpoint(tester, 'form-rejected');
      await _tap(tester, _submitKey);
      expect(calls, 2);
      expect(find.text('Synthetic rejection. Please retry.'), findsNothing);
      expect(busy, [true, false, true, false]);
    },
  );

  testWidgets('guest failure restores actions and retry needs no credentials', (
    tester,
  ) async {
    await _prepare(tester);
    final pending = Completer<void>();
    var guestCalls = 0;
    var loginCalls = 0;
    await tester.pumpWidget(
      _app(
        _form(
          onLogin: (_, _) async {
            loginCalls++;
            return null;
          },
          onGuest: () {
            guestCalls++;
            return guestCalls == 1 ? pending.future : Future.value();
          },
        ),
      ),
    );
    await _tap(tester, _guestKey);
    _expectEnabled(tester, false);
    expect(find.text('Opening'), findsOneWidget);
    pending.completeError(StateError('synthetic network failure'));
    await tester.pumpAndSettle();
    expect(
      find.text('Unable to connect Check your connection and retry'),
      findsOneWidget,
    );
    _expectEnabled(tester, true);
    await _tap(tester, _guestKey);
    expect(guestCalls, 2);
    expect(loginCalls, 0);
    expect(find.text('Enter account'), findsNothing);
    expect(find.text('Enter password'), findsNothing);
  });

  for (final guest in [false, true]) {
    testWidgets(
      'disposing during pending ${guest ? 'guest' : 'login'} ignores late completion',
      (tester) async {
        await _prepare(tester);
        final pending = Completer<String?>();
        final busy = <bool>[];
        await tester.pumpWidget(
          _app(
            _form(
              username: 'synthetic-reader',
              password: 'synthetic-pass',
              onLogin: (_, _) => pending.future,
              onGuest: () async {
                await pending.future;
              },
              onBusyChanged: busy.add,
            ),
          ),
        );
        await _tap(tester, guest ? _guestKey : _submitKey);
        await tester.pumpWidget(const SizedBox.shrink());
        pending.completeError(StateError('late synthetic failure'));
        await tester.pump();
        expect(busy, [true]);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('dialog hydrates saved fields after a visible loading state', (
    tester,
  ) async {
    final fixture = await _prepare(tester);
    fixture.hydrationGate = Completer<void>();
    await tester.pumpWidget(_app(_dialogHost()));
    await _openDialog(tester);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(LoginForm), findsNothing);
    await _checkpoint(tester, 'dialog-loading');
    fixture.hydrationGate!.complete();
    await tester.pumpAndSettle();
    expect(
      _editable(tester, _accountKey).controller.text,
      fixture.savedUsername,
    );
    expect(
      _editable(tester, _passwordKey).controller.text,
      fixture.savedPassword,
    );
    expect(_editable(tester, _passwordKey).obscureText, isTrue);
    await _checkpoint(tester, 'dialog-saved-login');
  });

  testWidgets(
    'closing dialog before hydration ignores the late saved credentials',
    (tester) async {
      final fixture = await _prepare(tester);
      fixture.hydrationGate = Completer<void>();
      var closed = false;
      await tester.pumpWidget(_app(_dialogHost(onClosed: () => closed = true)));
      await _openDialog(tester);
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      navigator.pop();
      await tester.pumpAndSettle();
      expect(closed, isTrue);
      fixture.hydrationGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(LoginForm), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'dialog future waits for successful authentication and retry keeps credentials',
    (tester) async {
      final fixture = await _prepare(tester);
      fixture.loginGate = Completer<void>();
      fixture.failLogin = true;
      var closed = false;
      login_config.LoginStatus? statusAtClose;
      await tester.pumpWidget(
        _app(
          _dialogHost(
            onClosed: () {
              closed = true;
              statusAtClose = login_config.loginStatus;
            },
          ),
        ),
      );
      await _openDialog(tester);
      await tester.pumpAndSettle();
      await _enter(tester, '  synthetic-reader  ', ' synthetic-pass ');
      await _tap(tester, _submitKey);
      expect(closed, isFalse);
      expect(login_config.loginStatus, login_config.LoginStatus.logging);
      _expectEnabled(tester, false);
      final request =
          jsonDecode(fixture.calls('login').single['params'] as String) as Map;
      expect(request, {
        'username': 'synthetic-reader',
        'password': ' synthetic-pass ',
      });
      fixture.loginGate!.complete();
      await tester.pumpAndSettle();
      expect(closed, isFalse);
      expect(find.text(_invalidCredentialsMessage), findsOneWidget);
      expect(
        _editable(tester, _passwordKey).controller.text,
        ' synthetic-pass ',
      );
      _expectEnabled(tester, true);
      fixture.failLogin = false;
      fixture.loginGate = Completer<void>();
      await _tap(tester, _submitKey);
      expect(closed, isFalse);
      fixture.loginGate!.complete();
      await tester.pumpAndSettle();
      expect(closed, isTrue);
      expect(statusAtClose, login_config.LoginStatus.loginSuccess);
      expect(fixture.calls('login'), hasLength(2));
      expect(fixture.properties['guest_mode'], 'false');
      expect(find.byType(LoginForm), findsNothing);
    },
  );

  for (final manual in [false, true]) {
    testWidgets(
      'saved account load failure supports ${manual ? 'manual entry' : 'retry'}',
      (tester) async {
        final fixture = await _prepare(tester);
        fixture.failHydration = true;
        await tester.pumpWidget(_app(_dialogHost()));
        await _openDialog(tester);
        await tester.pumpAndSettle();
        expect(find.text('Unable to load the saved account'), findsOneWidget);
        expect(find.byType(LoginForm), findsNothing);
        await _checkpoint(
          tester,
          'dialog-hydration-failure-${manual ? 'manual' : 'retry'}',
        );
        fixture.failHydration = false;
        await tester.tap(find.text(manual ? 'Enter manually' : 'Retry'));
        await tester.pumpAndSettle();
        expect(
          _editable(tester, _accountKey).controller.text,
          manual ? '' : fixture.savedUsername,
        );
        expect(
          _editable(tester, _passwordKey).controller.text,
          manual ? '' : fixture.savedPassword,
        );
        _expectEnabled(tester, true);
        expect(fixture.calls('load_username'), hasLength(manual ? 1 : 2));
      },
    );
  }

  testWidgets(
    'dialog guest failure remains open and retry waits for saved guest mode',
    (tester) async {
      final fixture = await _prepare(tester);
      fixture.guestGate = Completer<void>();
      fixture.failGuest = true;
      var closed = false;
      await tester.pumpWidget(_app(_dialogHost(onClosed: () => closed = true)));
      await _openDialog(tester);
      await tester.pumpAndSettle();
      await _tap(tester, _guestKey);
      expect(closed, isFalse);
      _expectEnabled(tester, false);
      fixture.guestGate!.complete();
      await tester.pumpAndSettle();
      expect(closed, isFalse);
      _expectEnabled(tester, true);
      expect(
        find.text('Unable to connect Check your connection and retry'),
        findsOneWidget,
      );
      fixture.failGuest = false;
      fixture.guestGate = Completer<void>();
      await _tap(tester, _guestKey);
      expect(closed, isFalse);
      fixture.guestGate!.complete();
      await tester.pumpAndSettle();
      expect(closed, isTrue);
      expect(login_config.loginStatus, login_config.LoginStatus.guest);
      expect(fixture.properties['guest_mode'], 'true');
      expect(fixture.calls('login'), isEmpty);
    },
  );

  testWidgets(
    'busy dialog blocks terms pointer and keyboard navigation until authentication completes',
    (tester) async {
      final fixture = await _prepare(tester);
      fixture.loginGate = Completer<void>();
      var closed = false;
      await tester.pumpWidget(_app(_dialogHost(onClosed: () => closed = true)));
      await _openDialog(tester);
      await tester.pumpAndSettle();
      await _tap(tester, _submitKey);
      final terms = find.text('Terms of use');
      await tester.ensureVisible(terms);
      await tester.tapAt(tester.getCenter(terms));
      await tester.pump();
      expect(find.text('Terms of use'), findsOneWidget);
      final termsFocus = Focus.of(tester.element(terms));
      expect(termsFocus.canRequestFocus, isFalse);
      termsFocus.requestFocus();
      await tester.pump();
      expect(termsFocus.hasFocus, isFalse);
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.close_rounded),
            )
            .onPressed,
        isNull,
      );
      await tester
          .state<NavigatorState>(find.byType(Navigator).first)
          .maybePop();
      await tester.pump();
      expect(closed, isFalse);
      expect(find.byType(LoginForm), findsOneWidget);
      fixture.loginGate!.complete();
      await tester.pumpAndSettle();
      expect(closed, isTrue);
      expect(find.byType(LoginForm), findsNothing);
    },
  );

  testWidgets(
    'first login reports backend failure without navigating or dropping fields',
    (tester) async {
      final fixture = await _prepare(tester);
      fixture.failLogin = true;
      await tester.pumpWidget(_app(const FirstLoginScreen()));
      await _enter(tester, 'synthetic-reader', ' synthetic-pass ');
      await _tap(tester, _submitKey);
      await tester.pumpAndSettle();
      expect(find.byType(FirstLoginScreen), findsOneWidget);
      expect(find.text(_invalidCredentialsMessage), findsOneWidget);
      expect(
        _editable(tester, _passwordKey).controller.text,
        ' synthetic-pass ',
      );
      _expectEnabled(tester, true);
      await _checkpoint(tester, 'first-login-rejected');
    },
  );

  testWidgets('first login guest failure leaves a usable form', (tester) async {
    final fixture = await _prepare(tester);
    fixture.failGuest = true;
    await tester.pumpWidget(_app(const FirstLoginScreen()));
    await _tap(tester, _guestKey);
    await tester.pumpAndSettle();
    expect(find.byType(FirstLoginScreen), findsOneWidget);
    expect(
      find.text('Unable to connect Check your connection and retry'),
      findsOneWidget,
    );
    _expectEnabled(tester, true);
    expect(fixture.calls('login'), isEmpty);
  });

  final loginFailures = [
    (
      name: 'upstream 401 response',
      error: _rawLoginRejection,
      raw: null,
      language: 'en',
      message: _invalidCredentialsMessage,
    ),
    (
      name: 'localized upstream 403',
      error: 'jm request returned status 403',
      raw: null,
      language: 'zh',
      message: '账号或密码不正确 请检查后重试',
    ),
    (
      name: 'network timeout',
      error: 'error sending request for url https://example.invalid/private-response-marker timed out',
      raw: null,
      language: 'en',
      message: _connectionMessage,
    ),
    (
      name: 'malformed raw response',
      error: '',
      raw: '{"private-response-marker":',
      language: 'en',
      message: _invalidDataMessage,
    ),
    (
      name: 'malformed decrypted response',
      error: 'parse decrypted jm data failed: private-response-marker',
      raw: null,
      language: 'en',
      message: _invalidDataMessage,
    ),
    (
      name: 'unknown backend error',
      error: 'Unexpected failure private-response-marker',
      raw: null,
      language: 'en',
      message: 'Sign-in failed Please try again later',
    ),
  ];
  for (final failure in loginFailures) {
    testWidgets('manual login sanitizes ${failure.name} in UI and logs', (
      tester,
    ) async {
      final fixture = await _prepare(tester);
      fixture.failLogin = true;
      fixture.loginError = failure.error;
      fixture.loginRawResponse = failure.raw;
      await tester.pumpWidget(
        _app(const FirstLoginScreen(), language: failure.language),
      );
      final debugMessages = <String>[];
      final oldDebugPrint = debugPrint;
      debugPrint = (message, {wrapWidth}) {
        if (message != null) debugMessages.add(message);
      };
      try {
        await _enter(tester, 'synthetic-reader', 'synthetic-pass');
        await _tap(tester, _submitKey);
        await tester.pumpAndSettle();
      } finally {
        debugPrint = oldDebugPrint;
      }
      expect(find.text(failure.message), findsOneWidget);
      expect(login_config.loginMessage, failure.message);
      expect(debugMessages, ['Login failed: ${failure.message}']);
      expect(find.textContaining('private-response-marker'), findsNothing);
      expect(find.textContaining('Bad state:'), findsNothing);
      _expectEnabled(tester, true);
    });
  }

  for (final failure in [
    (
      name: 'returned upstream error',
      message: _rawLoginRejection,
      error: null,
      raw: null,
      expected: _invalidCredentialsMessage,
    ),
    (
      name: 'thrown upstream error',
      message: '',
      error: _rawLoginRejection,
      raw: null,
      expected: _invalidCredentialsMessage,
    ),
    (
      name: 'connection failure',
      message: '',
      error:
          'connection failed: https://example.invalid/private-response-marker',
      raw: null,
      expected: _connectionMessage,
    ),
    (
      name: 'malformed raw response',
      message: '',
      error: null,
      raw: '{"private-response-marker":',
      expected: _invalidDataMessage,
    ),
  ]) {
    testWidgets(
      'pre-login sanitizes ${failure.name} before notifying callers',
      (tester) async {
        final fixture = await _prepare(tester);
        fixture.properties['guest_mode'] = 'false';
        fixture.preLoginMessage = failure.message;
        fixture.preLoginError = failure.error;
        fixture.preLoginRawResponse = failure.raw;
        late BuildContext loginContext;
        await tester.pumpWidget(
          _app(
            Builder(
              builder: (context) {
                loginContext = context;
                return const SizedBox.shrink();
              },
            ),
          ),
        );
        final publishedMessages = <String>[];
        void recordFailure(_) {
          if (login_config.loginStatus == login_config.LoginStatus.loginField) {
            publishedMessages.add(login_config.loginMessage);
          }
        }

        final debugMessages = <String>[];
        final oldDebugPrint = debugPrint;
        debugPrint = (message, {wrapWidth}) {
          if (message != null) debugMessages.add(message);
        };
        login_config.loginEvent.subscribe(recordFailure);
        try {
          await login_config.initLogin(loginContext);
          await tester.pumpAndSettle();
        } finally {
          login_config.loginEvent.unsubscribe(recordFailure);
          debugPrint = oldDebugPrint;
        }
        expect(login_config.loginMessage, failure.expected);
        expect(publishedMessages, [failure.expected]);
        expect(
          debugMessages,
          failure.error == null && failure.raw == null
              ? isEmpty
              : ['Pre-login failed: ${failure.expected}'],
        );
      },
    );
  }

  final layouts = [
    (
      name: 'mobile-393-en',
      size: const Size(393, 852),
      scale: 1.0,
      dark: false,
      language: 'en',
    ),
    (
      name: 'mobile-393-zh',
      size: const Size(393, 852),
      scale: 1.0,
      dark: false,
      language: 'zh',
    ),
    (
      name: 'compact-320-large-en',
      size: const Size(320, 700),
      scale: 2.0,
      dark: false,
      language: 'en',
    ),
    (
      name: 'compact-393-large-zh',
      size: const Size(393, 852),
      scale: 2.0,
      dark: true,
      language: 'zh',
    ),
    (
      name: 'desktop-en',
      size: const Size(1280, 800),
      scale: 1.0,
      dark: true,
      language: 'en',
    ),
    (
      name: 'desktop-zh',
      size: const Size(1280, 800),
      scale: 1.0,
      dark: false,
      language: 'zh',
    ),
  ];
  for (final layout in layouts) {
    for (final dialog in [false, true]) {
      testWidgets(
        '${dialog ? 'dialog' : 'first login'} ${layout.name} fits and remains usable above keyboard',
        (tester) async {
          await _prepare(tester, size: layout.size);
          await tester.pumpWidget(
            _app(
              dialog ? _dialogHost() : const FirstLoginScreen(),
              textScale: layout.scale,
              dark: layout.dark,
              language: layout.language,
            ),
          );
          if (dialog) await _openDialog(tester);
          await tester.pumpAndSettle();
          expect(find.byType(LoginForm), findsOneWidget);
          final account = tester.getRect(find.byKey(_accountKey));
          expect(account.left, greaterThanOrEqualTo(0));
          expect(account.right, lessThanOrEqualTo(layout.size.width));
          expect(account.width, lessThanOrEqualTo(440));
          if (!dialog && layout.scale == 1) {
            expect(find.byType(AppBar), findsNothing);
            final iconFinder = find.byKey(const ValueKey('login-app-icon'));
            final icon = tester.widget<Image>(iconFinder);
            expect(icon.image, isA<AssetImage>());
            expect(
              (icon.image as AssetImage).assetName,
              'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png',
            );
            final iconRect = tester.getRect(iconFinder);
            expect(tester.getSize(iconFinder), const Size(72, 72));
            expect(iconRect.center.dx, closeTo(layout.size.width / 2, 1));
            final content = tester.getRect(
              find.byKey(const ValueKey('login-page-content')),
            );
            expect(content.center.dx, closeTo(layout.size.width / 2, 1));
            if (content.height < layout.size.height - 48) {
              final topSpace = content.top;
              final bottomSpace = layout.size.height - content.bottom;
              expect(content.center.dy, lessThan(layout.size.height / 2));
              // Keep both margins balanced while placing the content slightly
              // above center. Longer text remains free to use the scroll view.
              expect(topSpace, greaterThanOrEqualTo(24));
              expect(bottomSpace, greaterThan(topSpace));
              expect(topSpace, greaterThan(bottomSpace * 0.6));
            }
          }
          final prefix = '${dialog ? 'dialog' : 'first-login'}-${layout.name}';
          await _checkpoint(tester, prefix);
          tester.view.viewInsets = const FakeViewPadding(bottom: 280);
          await tester.pump();
          await tester.ensureVisible(find.byKey(_passwordKey));
          await tester.tap(find.byKey(_passwordKey));
          await tester.pumpAndSettle();
          await tester.enterText(find.byKey(_passwordKey), 'synthetic-pass');
          await tester.ensureVisible(find.byKey(_submitKey));
          await tester.pumpAndSettle();
          final submit = tester.getRect(find.byKey(_submitKey));
          expect(submit.top, greaterThanOrEqualTo(0));
          expect(submit.bottom, lessThanOrEqualTo(layout.size.height - 280));
          expect(submit.height, greaterThanOrEqualTo(48));
          expect(find.byKey(_submitKey).hitTestable(), findsOneWidget);
          expect(
            _editable(tester, _passwordKey).controller.text,
            'synthetic-pass',
          );
          await _checkpoint(tester, '$prefix-keyboard');
        },
      );
    }
  }
}

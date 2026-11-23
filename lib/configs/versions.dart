import 'dart:convert';

import 'package:event/event.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:jmcomic3/screens/components/dialogs.dart';
import 'package:jmcomic3/screens/components/feedback.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/basic/trusted_updates.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/components/update_dialog.dart';

import 'int_property.dart';
import 'ignore_upgrade_pop.dart';

const releasePageUrl = officialReleasePage;
const _propertyName = 'checkVersionPeriod';
const _releaseCacheKey = 'verifiedGithubReleaseCacheV1';
String _version = 'dirty';
TrustedRelease? _release;
Future<void>? _checking;
int _period = -1;
bool _display = true;
String? updateCheckError;
final versionEvent = Event<EventArgs>();

Future<void> initVersion() async {
  _release = null;
  updateCheckError = null;
  _display = true;
  try {
    _version = (await rootBundle.loadString('lib/assets/version.txt')).trim();
  } catch (_) {
    _version = 'dirty';
  }
  // The old mirror/app-config cache had no provenance. Never migrate it into
  // the trusted cache, even when its version string happens to look valid.
  for (final key in [
    'latestVersionNameCache',
    'latestVersionInfoCache',
    'latestVersionRepoCache',
  ]) {
    if ((await methods.loadProperty(key)).isNotEmpty) {
      await methods.saveProperty(key, '');
    }
  }
  final cached = await methods.loadProperty(_releaseCacheKey);
  if (cached.isNotEmpty) {
    try {
      final data = jsonDecode(cached);
      if (data is! Map || data['repository'] != updateRepository) {
        throw const FormatException('Invalid update cache');
      }
      _release = TrustedRelease.parse(data['release']);
    } catch (_) {
      await methods.saveProperty(_releaseCacheKey, '');
    }
  }
  _period = parseBoundedIntPropertyValue(
    await methods.loadProperty(_propertyName),
    fallback: 0,
    min: -1,
  );
  if (_period > 0 && DateTime.now().millisecondsSinceEpoch > _period) {
    _period = 0;
    await methods.saveProperty(_propertyName, '0');
  }
}

String currentVersion() => _version;
TrustedRelease? get latestRelease => _release;
String? get latestVersion =>
    _release?.isNewerThan(_version) == true ? _release!.tag : null;
String? get latestVersionName =>
    _release?.tag ?? (dirtyVersion() ? null : _version);
String? latestVersionInfo() => _release?.body;
String latestDownloadUrl() => releasePageUrl;
bool dirtyVersion() => AppVersion.parse(_version) == null;

Future<void> autoCheckNewVersion() async {
  if (_period == 0) await silentCheckNewVersion();
}

Future<void> silentCheckNewVersion() async {
  try {
    await _versionCheck();
  } catch (_) {
    // Background/offline checks retain only previously verified release data.
    // About shows the failure and manual checks also display a toast.
  }
}

Future<void> manualCheckNewVersion(BuildContext context) async {
  defaultToast(context, context.l10n.tr('检查更新中', en: 'Checking for updates'));
  try {
    await _versionCheck();
    if (context.mounted) {
      defaultToast(
        context,
        context.l10n.tr('检查更新成功', en: 'Update check complete'),
      );
    }
  } catch (_) {
    if (context.mounted) {
      defaultToast(
        context,
        context.l10n.tr('检查更新失败，请重试', en: 'Update check failed. Please retry.'),
      );
    }
  }
}

Future<void> _versionCheck() => _checking ??= _loadRelease().whenComplete(() {
  _checking = null;
});

Future<void> _loadRelease() async {
  if (dirtyVersion()) return;
  final client = TrustedUpdateClient();
  try {
    final release = await client.latest();
    await methods.saveProperty(
      _releaseCacheKey,
      jsonEncode({'repository': updateRepository, 'release': release.json}),
    );
    _release = release;
    updateCheckError = null;
  } catch (_) {
    updateCheckError = 'update_check_failed';
    rethrow;
  } finally {
    client.close();
    versionEvent.broadcast();
  }
}

String _periodText(BuildContext context) {
  if (_period < 0) {
    return context.l10n.tr('自动检查更新已关闭', en: 'Automatic update checks are off');
  }
  if (_period == 0) {
    return context.l10n.tr('自动检查更新已开启', en: 'Automatic update checks are on');
  }
  return '${context.l10n.tr('下次检查时间', en: 'Next check')}: ${formatDateTimeToDateTime(DateTime.fromMillisecondsSinceEpoch(_period))}';
}

Future<void> _choosePeriod(BuildContext context) async {
  final result = await chooseMapDialog<int>(
    context,
    title: context.l10n.tr('自动检查更新', en: 'Automatic update checks'),
    values: {
      context.l10n.tr('开启', en: 'On'): 0,
      context.l10n.tr('一周后', en: 'In one week'): 7,
      context.l10n.tr('一个月后', en: 'In one month'): 30,
      context.l10n.tr('一年后', en: 'In one year'): 365,
      context.l10n.tr('关闭', en: 'Off'): -1,
    },
  );
  if (result == null) return;
  _period = result <= 0
      ? result
      : DateTime.now().add(Duration(days: result)).millisecondsSinceEpoch;
  await methods.saveProperty(_propertyName, '$_period');
}

Widget autoUpdateCheckSetting() => StatefulBuilder(
  builder: (context, setState) {
    return ListTile(
      title: Text(context.l10n.tr('自动检查更新', en: 'Automatic update checks')),
      subtitle: Text(_periodText(context)),
      onTap: () async {
        await _choosePeriod(context);
        if (context.mounted) {
          setState(() {});
        }
      },
    );
  },
);

String formatDateTimeToDateTime(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

void versionPop(BuildContext context) {
  final release = _release;
  if (release == null ||
      latestVersion == null ||
      !_display ||
      currentIgnoreUpgradePop()) {
    return;
  }
  _display = false;
  showDialog<void>(
    context: context,
    builder: (context) => UpdateReleaseDialog(release: release),
  );
}

import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/app_links.dart';
import 'package:jmcomic3/configs/versions.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/components/badge.dart';

import 'components/right_click_pop.dart';
import 'components/update_dialog.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() {
    return _AboutState();
  }
}

class _AboutState extends State<AboutScreen> {
  @override
  void initState() {
    super.initState();
    versionEvent.subscribe(_refreshVersion);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final info = latestVersionInfo();
      if ((info ?? "").trim().isEmpty) {
        await silentCheckNewVersion();
        if (mounted) setState(() {});
      }
    });
  }

  void _refreshVersion(_) {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    versionEvent.unsubscribe(_refreshVersion);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return rightClickPop(child: buildScreen(context), context: context);
  }

  Widget buildScreen(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.about)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: SafeArea(
            top: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              children: [
                _buildLogo(),
                const SizedBox(height: 12),
                _buildNewestVersion(),
                if (latestVersion != null) _buildGotoGithub(),
                if (updateCheckError != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 0,
                      vertical: 8,
                    ),
                    child: Text(
                      context.l10n.tr(
                        '无法检查更新，请稍后重试。当前显示最近一次已验证的更新信息。',
                        en: 'Could not check for updates. Showing the last verified release; please retry.',
                      ),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const Divider(height: 24),
                _buildVersionText(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(
          Icons.menu_book_outlined,
          size: 32,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('JMComic3', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                context.l10n.currentVersionLabel(currentVersion()),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNewestVersion() {
    final versionText = latestVersionName ?? context.l10n.noNewVersion;
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        VersionBadged(
          child: Padding(
            padding: const EdgeInsetsDirectional.only(
              end: 16,
              top: 4,
              bottom: 4,
            ),
            child: Text('${context.l10n.latestVersion}: $versionText'),
          ),
        ),
        Tooltip(
          message: context.l10n.checkUpdate,
          child: TextButton.icon(
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            icon: const Icon(Icons.refresh, size: 20),
            label: Text(context.l10n.checkUpdate),
            onPressed: () async {
              await manualCheckNewVersion(context);
              if (mounted) setState(() {});
            },
          ),
        ),
      ],
    );
  }

  Widget _buildGotoGithub() {
    return Container(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          if (latestRelease != null)
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: () => chooseUpdatePackage(context, latestRelease!),
              icon: const Icon(Icons.download_outlined),
              label: Text(context.l10n.tr('下载更新', en: 'Download update')),
            ),
          TextButton.icon(
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: () => openUrl(releasePageUrl),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: Text(context.l10n.goToDownloadPage),
          ),
        ],
      ),
    );
  }

  Widget _buildVersionText() {
    final info = latestVersionInfo();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.l10n.updateContent,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        ReleaseNotes(
          body: info != null && info.trim().isNotEmpty
              ? info
              : context.l10n.updateContentUnavailable,
        ),
      ],
    );
  }
}

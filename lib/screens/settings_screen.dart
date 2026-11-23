import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/configs/app_font_size.dart';
import 'package:jmcomic3/configs/app_locale.dart';
import 'package:jmcomic3/configs/app_orientation.dart';
import 'package:jmcomic3/configs/network_api_host.dart';
import 'package:jmcomic3/configs/network_cdn_host.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/download_export_selection_screen.dart';

import 'package:jmcomic3/screens/components/dialogs.dart';
import 'package:jmcomic3/screens/components/login_agreement.dart';

import '../basic/web_dav_sync.dart';
import '../configs/Authentication.dart';
import '../configs/android_display_mode.dart';
import '../configs/categories_sort.dart';
import '../configs/display_jmcode.dart';
import '../configs/download_and_export_to.dart';
import '../configs/disable_recommend_content.dart';
import '../configs/export_rename.dart';
import '../configs/ignore_upgrade_pop.dart';
import '../configs/ignore_view_log.dart';
import '../configs/is_pro.dart';
import '../configs/login.dart';
import '../configs/no_animation.dart';
import '../configs/proxy.dart';
import '../configs/search_title_words.dart';
import '../configs/theme.dart';
import '../configs/two_page_direction.dart';
import '../configs/using_right_click_pop.dart';
import '../configs/versions.dart';
import '../configs/volume_key_control.dart';
import '../configs/web_dav_password.dart';
import '../configs/web_dav_sync_switch.dart';
import '../configs/web_dav_url.dart';
import '../configs/web_dav_username.dart';
import 'init_screen.dart';
import 'components/right_click_pop.dart';
import 'image_cache_screen.dart';
import 'runtime_log_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() {
    return _SettingsState();
  }
}

class _SettingsState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return rightClickPop(child: buildScreen(context), context: context);
  }

  Widget buildScreen(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settings)),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Theme(
              data: theme.copyWith(
                listTileTheme: theme.listTileTheme.copyWith(
                  minTileHeight: 48,
                  minVerticalPadding: 8,
                  minLeadingWidth: 24,
                  horizontalTitleGap: 12,
                  titleAlignment: ListTileTitleAlignment.center,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                expansionTileTheme: theme.expansionTileTheme.copyWith(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                  childrenPadding: EdgeInsets.zero,
                  shape: const Border(),
                  collapsedShape: const Border(),
                ),
                dividerTheme: theme.dividerTheme.copyWith(space: 8),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    ExpansionTile(
                      minTileHeight: 48,
                      leading: const Icon(
                        Icons.manage_accounts_outlined,
                        size: 24,
                      ),
                      title: Text(l10n.sectionUserNetwork),
                      children: [
                        apiHostSetting(),
                        cdnHostSetting(),
                        proxySetting(),
                        const Divider(),
                        createFavoriteFolderItemTile(context),
                        deleteFavoriteFolderItemTile(context),
                        renameFavoriteFolderItemTile(context),
                        const Divider(),
                        ListTile(
                          onTap: () async {
                            if (await confirmDialog(
                              context,
                              l10n.clearAccount,
                              l10n.clearAccountConfirm,
                            )) {
                              await methods.logout();
                              if (!context.mounted) return;
                              Navigator.of(context).pushAndRemoveUntil(
                                MaterialPageRoute(
                                  builder: (BuildContext context) =>
                                      const InitScreen(),
                                ),
                                (route) => false,
                              );
                            }
                          },
                          title: Text(l10n.clearAccount),
                        ),
                      ],
                    ),
                    ExpansionTile(
                      minTileHeight: 48,
                      leading: const Icon(Icons.menu_book_outlined, size: 24),
                      title: Text(l10n.sectionReading),
                      children: [
                        volumeKeyControlSetting(),
                        noAnimationSetting(),
                        twoGalleryDirectionSetting(context),
                      ],
                    ),
                    ExpansionTile(
                      minTileHeight: 48,
                      leading: const Icon(Icons.sync_outlined, size: 24),
                      title: Text(l10n.sectionSync),
                      children: [
                        webDavSyncSwitchSetting(),
                        webDavUrlSetting(),
                        webDavUserNameSetting(),
                        webDavPasswordSetting(),
                        webDavSyncClick(context),
                        webDavSyncUploadClick(context),
                        webDavSyncDownloadClick(context),
                      ],
                    ),
                    ExpansionTile(
                      minTileHeight: 48,
                      leading: const Icon(Icons.tune_outlined, size: 24),
                      title: Text(l10n.sectionSystemApp),
                      children: [
                        ListTile(
                          title: Text(l10n.tr('图片缓存', en: 'Image cache')),
                          trailing: const Icon(Icons.chevron_right, size: 20),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const ImageCacheScreen(),
                            ),
                          ),
                        ),
                        ListTile(
                          title: Text(l10n.tr('运行日志', en: 'Runtime log')),
                          trailing: const Icon(Icons.chevron_right, size: 20),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const RuntimeLogScreen(),
                            ),
                          ),
                        ),
                        disableRecommendContentSetting(),
                        userAgreementSetting(context),
                        if (hasProAccess) ...[
                          const Divider(),
                          autoUpdateCheckSetting(),
                          ignoreUpgradePopSetting(),
                        ],
                        const Divider(),
                        ignoreVewLogSetting(),
                        appOrientationWidget(),
                        const Divider(),
                        categoriesSortSetting(context),
                        themeSetting(context),
                        appLocaleSetting(context),
                        androidDisplayModeSetting(),
                        usingRightClickPopSetting(),
                        const Divider(),
                        authenticationSetting(),
                        const Divider(),
                        exportRenameSetting(),
                        downloadAndExportToSetting(),
                        displayJmcodeSetting(),
                        ListTile(
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (c) =>
                                    const DownloadExportSelectionScreen.includingIncomplete(),
                              ),
                            );
                          },
                          title: Text(l10n.exportIncomplete),
                          trailing: const Icon(Icons.chevron_right, size: 20),
                        ),
                        const Divider(),
                        searchTitleWordsSetting(),
                        ...fontSizeAdjustSettings(),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

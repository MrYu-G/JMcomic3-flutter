import 'package:flutter/material.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';

Future<void> showUserAgreementBottomSheet(BuildContext context) async {
  await showMaterialModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xAA000000),
    builder: (context) {
      return SizedBox(
        height: MediaQuery.of(context).size.height * (.6),
        child: const _LoginAgreementSheet(),
      );
    },
  );
}

Widget userAgreementSetting(BuildContext context) {
  return ListTile(
    onTap: () => showUserAgreementBottomSheet(context),
    title: Text(context.l10n.tr("用户协议", en: "User agreement")),
    subtitle: Text(
      context.l10n.tr("查看当前应用使用协议", en: "View current app agreement"),
    ),
  );
}

class LoginAgreementHint extends StatelessWidget {
  final EdgeInsetsGeometry padding;

  const LoginAgreementHint({
    super.key,
    this.padding = const EdgeInsets.fromLTRB(16, 0, 16, 8),
  });

  @override
  Widget build(BuildContext context) {
    final agreeStyle = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    final agreeLinkStyle = agreeStyle?.copyWith(
      decoration: TextDecoration.underline,
      color: Theme.of(context).colorScheme.primary,
    );
    return Padding(
      padding: padding,
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            context.l10n.tr("登录即表示您同意 ", en: "By signing in you agree to "),
            style: agreeStyle,
          ),
          InkWell(
            onTap: () => showUserAgreementBottomSheet(context),
            child: Text(
              context.l10n.tr("使用协议", en: "Terms of use"),
              style: agreeLinkStyle,
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginAgreementSheet extends StatelessWidget {
  const _LoginAgreementSheet();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final bodyStyle = textTheme.bodyMedium;
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: context.l10n.tr("关闭", en: "Close"),
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
                Expanded(
                  child: Text(
                    context.l10n.tr("使用协议", en: "Terms of use"),
                    style: textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 48),
              ],
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                children: [
                  Text(
                    context.l10n.tr(
                      "登录或继续使用本应用 即表示您已阅读并同意以下条款",
                      en: "By signing in or continuing to use this application you confirm that you have read and agree to the following terms",
                    ),
                    style: bodyStyle,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    context.l10n.tr(
                      "1 为保障服务安全与改进服务质量 服务提供方可能保存并分析您的登录 浏览 搜索及下载等操作记录 以及必要的设备与网络信息",
                      en: "1 Service providers may retain and analyze records of your sign in activity browsing searches and downloads together with necessary device and network information to maintain service security and improve service quality",
                    ),
                    style: bodyStyle,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.l10n.tr(
                      "2 您应遵守当地法律法规 不得上传或传播违法内容 不得利用本服务从事违法活动 对涉及敏感内容的信息应审慎判断 上述行为所产生的后果由您自行承担",
                      en: "2 You must comply with local laws and regulations and must not upload or distribute unlawful content or use this service for unlawful activities You should exercise due care when assessing sensitive content You are responsible for the consequences resulting from those activities",
                    ),
                    style: bodyStyle,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.l10n.tr(
                      "3 本应用所展示的信息仅供参考与交流 不构成医疗建议或诊断及治疗意见 使用相关信息所产生的后果由您自行承担",
                      en: "3 Information displayed in this application is provided solely for reference and discussion and does not constitute medical advice or guidance on diagnosis or treatment You are responsible for the consequences of using this information",
                    ),
                    style: bodyStyle,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.l10n.tr(
                      "4 本协议可能根据需要予以更新 更新后继续使用本应用 即表示您接受修订后的条款",
                      en: "4 These terms may be revised as necessary Continued use of this application after a revision indicates your acceptance of the revised terms",
                    ),
                    style: bodyStyle,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    context.l10n.tr(
                      "如您不同意上述条款 请勿登录并停止使用本应用",
                      en: "If you do not agree to these terms please refrain from signing in and discontinue use of this application",
                    ),
                    style: bodyStyle,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: MaterialButton(
                  color: Colors.orange.shade700,
                  onPressed: () => Navigator.of(context).pop(),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Text(
                      context.l10n.tr("关闭", en: "Close"),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:url_launcher/url_launcher.dart';

/// 打开web页面
Future<dynamic> openUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri != null && await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

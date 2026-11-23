import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

/// Status belongs to this mounted reader, never to a chapter-global singleton.
/// Replaced chapters get a fresh snapshot and disposed requests cannot publish.
class ReaderInfoBar extends StatefulWidget {
  const ReaderInfoBar({super.key, required this.page, required this.total});

  final int page;
  final int total;

  @override
  State<ReaderInfoBar> createState() => _ReaderInfoBarState();
}

class _ReaderInfoBarState extends State<ReaderInfoBar>
    with WidgetsBindingObserver {
  static const _channel = MethodChannel('methods');
  Timer? _timer;
  bool _loading = false;
  int? _battery;
  bool _charging = false;
  String _network = 'unknown';
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  void _start() {
    _timer?.cancel();
    unawaited(_refresh());
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _refresh());
  }

  Future<void> _refresh() async {
    if (_loading) return;
    _loading = true;
    try {
      final status = await _channel.invokeMapMethod<String, dynamic>(
        'device_status',
      );
      if (!mounted) return;
      final battery = status?['battery_level'];
      setState(() {
        _now = DateTime.now();
        _battery = battery is int && battery >= 0 && battery <= 100
            ? battery
            : null;
        _charging = status?['charging'] == true;
        _network = status?['network'] is String
            ? status!['network'] as String
            : 'unknown';
      });
    } on MissingPluginException {
      // Unsupported test/host environments retain a clear unknown state.
      if (mounted) setState(() => _now = DateTime.now());
    } on PlatformException {
      if (mounted) {
        setState(() {
          _now = DateTime.now();
          _battery = null;
          _network = 'unknown';
        });
      }
    } finally {
      _loading = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _start();
    } else {
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final networkIcon = switch (_network) {
      'wifi' => Icons.wifi,
      'mobile' => Icons.network_cell,
      'ethernet' => Icons.settings_ethernet,
      'connected' => Icons.network_check,
      'none' => Icons.signal_wifi_off,
      _ => Icons.help_outline,
    };
    final networkLabel = switch (_network) {
      'wifi' => 'Wi-Fi',
      'mobile' => context.l10n.tr('移动网络', en: 'Mobile network'),
      'ethernet' => context.l10n.tr('以太网', en: 'Ethernet'),
      'connected' => context.l10n.tr('已连接', en: 'Connected'),
      'none' => context.l10n.tr('无网络', en: 'Offline'),
      _ => context.l10n.tr('网络状态未知', en: 'Network status unknown'),
    };
    final time =
        '${_now.hour.toString().padLeft(2, '0')}:'
        '${_now.minute.toString().padLeft(2, '0')}';
    final pageText = '${widget.page}/${widget.total}';
    final batteryText = _battery == null ? '—' : '$_battery%';
    final batteryLabel = _battery == null
        ? context.l10n.tr('电量未知', en: 'Battery unknown')
        : _charging
        ? context.l10n.tr(
            '正在充电，电量 $_battery%',
            en: 'Charging, battery $_battery%',
          )
        : context.l10n.tr('电量 $_battery%', en: 'Battery $_battery%');
    final batteryIcon = _battery == null
        ? Icons.battery_unknown
        : _charging
        ? Icons.battery_charging_full
        : _battery! <= 15
        ? Icons.battery_alert
        : _battery! <= 30
        ? Icons.battery_2_bar
        : _battery! <= 50
        ? Icons.battery_3_bar
        : _battery! <= 70
        ? Icons.battery_4_bar
        : _battery! <= 90
        ? Icons.battery_5_bar
        : Icons.battery_full;
    const textStyle = TextStyle(
      color: Colors.white70,
      fontSize: 11,
      height: 1.2,
    );
    final timeAndNetwork = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(time),
        const SizedBox(width: 6),
        Icon(networkIcon, semanticLabel: networkLabel),
      ],
    );
    final battery = Semantics(
      label: batteryLabel,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(batteryIcon),
          const SizedBox(width: 2),
          Text(batteryText),
        ],
      ),
    );
    final progress = Semantics(
      label: context.l10n.tr(
        '第 ${widget.page} 页，共 ${widget.total} 页',
        en: 'Page ${widget.page} of ${widget.total}',
      ),
      excludeSemantics: true,
      child: Text(pageText, textAlign: TextAlign.center),
    );
    double textWidth(String text) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: textStyle),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    final sideWidth = (textWidth(time) + 20).clamp(
      textWidth(batteryText) + 16,
      double.infinity,
    );
    final singleRowWidth = sideWidth * 2 + textWidth(pageText) + 16;
    return ColoredBox(
      color: const Color(0x99000000),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        child: DefaultTextStyle(
          style: textStyle,
          child: IconTheme(
            data: const IconThemeData(color: Colors.white70, size: 14),
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Keep page progress truly centered; large text can use a second
                // line instead of squeezing or clipping the status groups.
                if (constraints.maxWidth < singleRowWidth) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [timeAndNetwork, battery],
                      ),
                      const SizedBox(height: 2),
                      progress,
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: timeAndNetwork,
                      ),
                    ),
                    progress,
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: battery,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

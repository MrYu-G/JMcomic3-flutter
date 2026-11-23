import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/runtime_log.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

import 'components/right_click_pop.dart';

class RuntimeLogScreen extends StatefulWidget {
  const RuntimeLogScreen({super.key});

  @override
  State<RuntimeLogScreen> createState() => _RuntimeLogScreenState();
}

class _RuntimeLogScreenState extends State<RuntimeLogScreen> {
  bool _errorsOnly = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = Theme.of(context).colorScheme;
    return rightClickPop(
      context: context,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.tr('运行日志', en: 'Runtime log')),
          actions: [
            IconButton(
              style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
              tooltip: l10n.tr('清空日志', en: 'Clear log'),
              onPressed: clearRuntimeLog,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Tooltip(
                          message: l10n.tr(
                            '仅显示失败的操作',
                            en: 'Show failed operations only',
                          ),
                          child: FilterChip(
                            materialTapTargetSize: MaterialTapTargetSize.padded,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            visualDensity: VisualDensity.standard,
                            selected: _errorsOnly,
                            showCheckmark: false,
                            avatar: Icon(
                              Icons.error_outline,
                              size: 18,
                              color: _errorsOnly
                                  ? colors.onErrorContainer
                                  : colors.error,
                            ),
                            selectedColor: colors.errorContainer,
                            labelStyle: TextStyle(
                              color: _errorsOnly
                                  ? colors.onErrorContainer
                                  : colors.onSurface,
                            ),
                            label: Text(l10n.tr('仅错误', en: 'Errors Only')),
                            onSelected: (selected) =>
                                setState(() => _errorsOnly = selected),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l10n.tr(
                            '本次运行最近 $runtimeLogCapacity 次操作 · 名称、结果与耗时',
                            en: 'Last $runtimeLogCapacity operations this session · name, result and duration',
                          ),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ValueListenableBuilder<int>(
                      valueListenable: runtimeLogRevision,
                      builder: (context, _, child) {
                        final entries = runtimeLogEntries
                            .where((entry) => !_errorsOnly || entry.failed)
                            .toList(growable: false);
                        if (entries.isEmpty) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                _errorsOnly
                                    ? l10n.tr(
                                        '没有错误日志',
                                        en: 'No errors recorded',
                                      )
                                    : l10n.tr('没有日志', en: 'No log entries'),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          );
                        }
                        return ListView.builder(
                          itemCount: entries.length,
                          itemBuilder: (context, index) {
                            final entry = entries[index];
                            final time = entry.time
                                .toIso8601String()
                                .split('T')
                                .last
                                .substring(0, 8);
                            return ListTile(
                              minVerticalPadding: 8,
                              minLeadingWidth: 24,
                              horizontalTitleGap: 12,
                              titleAlignment: ListTileTitleAlignment.center,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              leading: Icon(
                                entry.failed
                                    ? Icons.error_outline
                                    : Icons.check_circle_outline,
                                color: entry.failed
                                    ? colors.error
                                    : colors.primary,
                                size: 22,
                              ),
                              title: Text(entry.operation),
                              subtitle: Text(
                                '$time · ${entry.duration.inMilliseconds} ms · ${entry.failed ? l10n.tr('失败', en: 'Failed') : l10n.tr('成功', en: 'Succeeded')}',
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

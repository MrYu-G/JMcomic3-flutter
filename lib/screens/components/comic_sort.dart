import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/entities.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

import 'dialogs.dart';

Future<SortBy?> chooseSortBy(BuildContext context) async {
  final values = <String, SortBy>{
    sortByName(context, sortByDefault): sortByDefault,
    sortByName(context, sortByNew): sortByNew,
    sortByName(context, sortByLike): sortByLike,
    sortByName(context, sortByView): sortByView,
    sortByName(context, sortByViewDay): sortByViewDay,
    sortByName(context, sortByViewWeek): sortByViewWeek,
    sortByName(context, sortByViewMonth): sortByViewMonth,
  };
  return await chooseMapDialog(
    context,
    title: context.l10n.tr("请选择排序方式", en: "Choose sort mode"),
    values: values,
  );
}

String sortByName(BuildContext context, SortBy sortBy) {
  if (sortBy == sortByDefault) {
    return context.l10n.tr("默认", en: "Default");
  }
  if (sortBy == sortByNew) {
    return context.l10n.tr("最新", en: "Newest");
  }
  if (sortBy == sortByLike) {
    return context.l10n.tr("心", en: "Like");
  }
  if (sortBy == sortByView) {
    return context.l10n.tr("查看", en: "Views");
  }
  if (sortBy == sortByViewDay) {
    return context.l10n.tr("日榜", en: "Daily");
  }
  if (sortBy == sortByViewWeek) {
    return context.l10n.tr("周榜", en: "Weekly");
  }
  if (sortBy == sortByViewMonth) {
    return context.l10n.tr("月榜", en: "Monthly");
  }
  return context.l10n.tr(sortBy.toString());
}

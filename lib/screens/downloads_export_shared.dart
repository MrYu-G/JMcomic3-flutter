import 'package:jmcomic3/basic/entities.dart';

enum DownloadExportScope {
  completed,
  includingIncomplete;

  bool accepts(DownloadAlbum album) => switch (this) {
    completed => album.isDownloaded,
    includingIncomplete => !album.isDeleting,
  };
}

/// 批量导出页会在每个卡片构建时判断选中状态；Set 让包含判断和切换保持 O(1)。
void toggleSelectedDownloadId(Set<int> selected, int id) {
  if (!selected.add(id)) {
    selected.remove(id);
  }
}

/// 刷新下载列表后只保留仍可导出的项目，并沿用旧逻辑保留用户原本的选择顺序。
Set<int> restoreSelectedIdSet(
  Set<int> previousSelected,
  List<DownloadAlbum> latest,
) {
  final latestIds = latest.map((e) => e.id).toSet();
  return previousSelected.where(latestIds.contains).toSet();
}

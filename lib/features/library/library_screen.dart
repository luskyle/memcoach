import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/database.dart';
import '../../data/repositories/item_repository.dart';
import '../../providers.dart';
import '../../shared/empty_state.dart';
import '../../shared/ios_large_title.dart';
import '../../shared/status_chip.dart';
import 'card_edit_sheet.dart';

/// 分组内容：展示某个分组的全部成卡。
/// 搜索（全文）/ 筛选（语言、状态）/ 分组（库 + 未分类兜底）。
///
/// [active]：非活动 Tab 时 build 短路，停止构建与流监听（减少后台开销）。
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key, this.active = true});

  final bool active;

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return const SizedBox.shrink();

    final filter = ref.watch(libraryFilterProvider);
    final items = ref.watch(libraryItemsProvider);
    final collections = ref.watch(collectionsProvider);
    final links = ref.watch(itemCollectionLinksProvider);
    final stats = ref.watch(collectionStatsProvider);
    final viewMode = ref.watch(libraryViewModeProvider);

    // 标题：选中分组 → 分组名；未选（全部/搜索）→ 收藏
    final selectedName = filter.collectionId == null
        ? null
        : collections.value
            ?.where((c) => c.id == filter.collectionId)
            .map((c) => c.name)
            .firstOrNull;
    final title = selectedName ?? '卡片库';

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Row(
            children: [
              Expanded(child: IOSLargeTitle(title)),
              // 视图切换：列表 / 网格（Apple Store 卡片式）
              SegmentedButton<String>(
                style: const ButtonStyle(
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                segments: const [
                  ButtonSegment(
                    value: 'list',
                    icon: Icon(Icons.view_agenda_outlined, size: 18),
                    tooltip: '列表模式',
                  ),
                  ButtonSegment(
                    value: 'grid',
                    icon: Icon(Icons.grid_view_outlined, size: 18),
                    tooltip: '网格模式',
                  ),
                ],
                selected: {viewMode},
                onSelectionChanged: (v) async {
                  final mode = v.first;
                  ref.read(libraryViewModeProvider.notifier).state = mode;
                  await ref.read(settingsProvider).setLibraryViewMode(mode);
                },
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: '搜索卡片（全文）',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchCtrl.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchCtrl.clear();
                        ref.read(libraryFilterProvider.notifier).state =
                            filter.copyWith(search: '');
                      },
                    ),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              isDense: true,
            ),
            onChanged: (v) => ref.read(libraryFilterProvider.notifier).state =
                filter.copyWith(search: v),
          ),
        ),
        // 筛选行：状态 + 语言
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FilterChip(
                  label: '全部',
                  selected: filter.status == null,
                  onTap: () => ref.read(libraryFilterProvider.notifier).state =
                      filter.copyWith(status: null),
                ),
                _FilterChip(
                  label: '学习中',
                  selected: filter.status == 'learning',
                  onTap: () => _setStatus('learning'),
                ),
                _FilterChip(
                  label: '已掌握',
                  selected: filter.status == 'mastered',
                  onTap: () => _setStatus('mastered'),
                ),
                _FilterChip(
                  label: '冷置',
                  selected: filter.status == 'cold',
                  onTap: () => _setStatus('cold'),
                ),
                const SizedBox(width: 8),
                const VerticalDivider(),
                _FilterChip(
                  label: '日',
                  selected: filter.lang == 'ja',
                  onTap: () => _setLang('ja'),
                ),
                _FilterChip(
                  label: '英',
                  selected: filter.lang == 'en',
                  onTap: () => _setLang('en'),
                ),
                _FilterChip(
                  label: '中',
                  selected: filter.lang == 'zh',
                  onTap: () => _setLang('zh'),
                ),
              ],
            ),
          ),
        ),
        // ---- 渲染 ----
        Expanded(
          child: items.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('加载失败：$e')),
            data: (list) {
              if (list.isEmpty) {
                return EmptyState(
                  icon: Icons.collections_bookmark_outlined,
                  title: selectedName == null ? '卡片库还空着' : '「$title」还空着',
                  subtitle: '去「学习」学会新词，或从侧栏选择一个分组查看内容。',
                );
              }
              // 分组内容直接平铺展示（不再依赖展开），按视图模式渲染
              final view = _GroupedContentView(
                viewMode: viewMode,
                items: list,
                collections: collections.value ?? const [],
                links: links.value ?? const [],
                stats: stats.value ?? const {},
                onRename: _renameCollection,
                onDelete: _deleteCollection,
              );
              return RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(libraryItemsProvider);
                  ref.invalidate(collectionStatsProvider);
                },
                child: view,
              );
            },
          ),
        ),
      ],
    );
  }

  void _setStatus(String s) {
    final f = ref.read(libraryFilterProvider);
    ref.read(libraryFilterProvider.notifier).state = f.copyWith(status: s);
  }

  void _setLang(String l) {
    ref.read(libraryFilterProvider.notifier).state =
        ref.read(libraryFilterProvider).toggleLang(l);
  }

  Future<void> _renameCollection(
      BuildContext context, CollectionRow col) async {
    final ctrl = TextEditingController(text: col.name);
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('重命名分组'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: '名称'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      await ref.read(itemRepositoryProvider).renameCollection(col.id, name);
      ref.invalidate(collectionsProvider);
      ref.invalidate(collectionStatsProvider);
    }
  }

  Future<void> _deleteCollection(
      BuildContext context, CollectionRow col) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('删除分组「${col.name}」？'),
        content: const Text('条目不会被删除，会回到「未分类」。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(itemRepositoryProvider).deleteCollection(col.id);
      ref.invalidate(collectionsProvider);
      ref.invalidate(collectionStatsProvider);
    }
  }
}

/// 分组头部：名称 + 卡片数/掌握率 + 菜单（重命名/删除）。
/// 分组内容视图：按主库分组平铺展示（不依赖展开），
/// 支持列表模式 / 网格模式（Apple Store 卡片风格）。
class _GroupedContentView extends ConsumerWidget {
  const _GroupedContentView({
    required this.viewMode,
    required this.items,
    required this.collections,
    required this.links,
    required this.stats,
    required this.onRename,
    required this.onDelete,
  });

  final String viewMode;
  final List<ItemWithCard> items;
  final List<CollectionRow> collections;
  final List<ItemCollectionRow> links;
  final Map<int, ({int total, int mastered})> stats;
  final void Function(BuildContext, CollectionRow) onRename;
  final void Function(BuildContext, CollectionRow) onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return viewMode == 'grid' ? buildGrid(context) : buildList(context);
  }

  /// item → 主库分组（未关联 → 未分类兜底）。
  List<(CollectionRow, List<ItemWithCard>)> _groups() {
    final primaryOf = <int, int>{};
    for (final link in links) {
      if (link.isPrimary) primaryOf[link.itemId] = link.collectionId;
    }
    final colById = {for (final c in collections) c.id: c};
    final groups = <int, List<ItemWithCard>>{};
    final ungrouped = <ItemWithCard>[];
    for (final item in items) {
      final cid = primaryOf[item.item.id];
      final col = cid == null ? null : colById[cid];
      if (col == null) {
        ungrouped.add(item);
      } else {
        groups.putIfAbsent(col.id, () => []).add(item);
      }
    }
    final result = <(CollectionRow, List<ItemWithCard>)>[];
    for (final c in collections) {
      final gi = groups[c.id];
      if (gi != null && gi.isNotEmpty) {
        result.add((c, gi));
      }
    }
    if (ungrouped.isNotEmpty) {
      result.add((
        CollectionRow(
          id: -1,
          name: '未分类',
          parentId: null,
          ownerId: null,
          isSystem: true,
          createdAt: DateTime(0),
        ),
        ungrouped,
      ));
    }
    return result;
  }

  /// 列表模式：分组头（可操作）+ 卡片直接平铺（无展开门槛）。
  Widget buildList(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 88),
      children: [
        for (final (col, colItems) in _groups()) ...[
          _GroupHeader(
            collection: col,
            stat: stats[col.id],
            itemCount: colItems.length,
            onRename: () => onRename(context, col),
            onDelete: () => onDelete(context, col),
          ),
          for (final item in colItems) _ItemListTile(item: item),
        ],
      ],
    );
  }

  /// 网格模式：分组头 + Apple Store 风格方形卡片。
  Widget buildGrid(BuildContext context) {
    final blocks = <Widget>[];
    for (final (col, colItems) in _groups()) {
      blocks.add(
        _GroupHeader(
          collection: col,
          stat: stats[col.id],
          itemCount: colItems.length,
          onRename: () => onRename(context, col),
          onDelete: () => onDelete(context, col),
        ),
      );
      blocks.add(
        LayoutBuilder(
          builder: (ctx, cons) {
            final width = cons.maxWidth;
            final columns = width >= 1100 ? 4 : (width >= 760 ? 3 : 2);
            const spacing = 12.0;
            final cardWidth = (width - spacing * (columns - 1)) / columns;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final item in colItems)
                  SizedBox(
                    width: cardWidth,
                    height: cardWidth, // 方形卡片
                    child: _ItemGridCard(item: item),
                  ),
              ],
            );
          },
        ),
      );
      blocks.add(const SizedBox(height: 16));
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 88),
      children: blocks,
    );
  }
}

/// 分组头：名称 + 统计 + 重命名/删除菜单。
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.collection,
    required this.stat,
    required this.itemCount,
    required this.onRename,
    required this.onDelete,
  });

  final CollectionRow collection;
  final ({int total, int mastered})? stat;
  final int itemCount;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isDefault = collection.id == -1;
    final ratio = stat == null
        ? 0.0
        : (stat!.total == 0 ? 0.0 : stat!.mastered / stat!.total);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 10),
      child: Row(
        children: [
          Icon(
            isDefault ? Icons.folder_outlined : Icons.folder,
            size: 18,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              collection.name,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
          Text(
            stat == null
                ? '$itemCount 张'
                : '${stat!.total} 张 · 掌握 ${(ratio * 100).toStringAsFixed(0)}%',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(width: 4),
          PopupMenuButton<String>(
            padding: EdgeInsets.zero,
            iconSize: 18,
            onSelected: (v) => v == 'rename'
                ? onRename()
                : (v == 'delete' ? onDelete() : null),
            itemBuilder: (_) => [
              if (!isDefault)
                const PopupMenuItem(value: 'rename', child: Text('重命名')),
              if (!isDefault && !collection.isSystem)
                const PopupMenuItem(value: 'delete', child: Text('删除')),
            ],
          ),
        ],
      ),
    );
  }
}

/// 列表卡片：语言 + 正面 + 答案/来源 + 状态。
class _ItemListTile extends ConsumerWidget {
  const _ItemListTile({required this.item});

  final ItemWithCard item;

  String get _subtitle {
    final answer = item.card?.answer ?? '';
    final url = item.item.originalUrl;
    if (url == null) return answer;
    final host = Uri.tryParse(url)?.host ?? '';
    final site = host.replaceFirst(RegExp(r'^www\.'), '');
    return answer.isEmpty ? '$site · 网页' : '$answer · $site';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        leading: LanguageBadge(lang: item.item.lang),
        title: Text(
          item.card?.prompt ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
        subtitle: Text(
          _subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: StatusChip(status: item.item.status),
        onTap: () => CardEditSheet.open(context, ref, item),
      ),
    );
  }
}

/// Apple Store 风格网格卡片：大圆角、留白、语言角标 + 状态、
/// 正面大字、答案摘要、来源站点、复习间隔。
class _ItemGridCard extends ConsumerWidget {
  const _ItemGridCard({required this.item});

  final ItemWithCard item;

  String get _sourceHost {
    final url = item.item.originalUrl;
    if (url == null) return '';
    final host = Uri.tryParse(url)?.host ?? '';
    return host.replaceFirst(RegExp(r'^www\.'), '');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final card = item.card;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: InkWell(
        onTap: () => CardEditSheet.open(context, ref, item),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // 顶部：语言角标 / 卡种 + 状态徽标
              Row(
                children: [
                  LanguageBadge(lang: item.item.lang),
                  const SizedBox(width: 6),
                  Text(
                    kindLabel(card?.kind ?? 'word'),
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  StatusChip(status: item.item.status),
                ],
              ),
              const SizedBox(height: 12),
              // 正面（大字，方形卡片空间紧凑限 2 行）
              Text(
                card?.prompt ?? item.item.note ?? '',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 17,
                  height: 1.35,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              // 背面 / 摘要（1 行）
              if ((card?.answer ?? '').isNotEmpty)
                Text(
                  card!.answer,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              const SizedBox(height: 8),
              // 底部：来源 + 复习间隔
              Row(
                children: [
                  if (_sourceHost.isNotEmpty) ...[
                    Icon(Icons.language,
                        size: 12, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        _sourceHost,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  Text(
                    card != null && card.intervalDays > 0
                        ? '${card.intervalDays} 天后'
                        : '待复习',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: scheme.primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/database.dart';
import '../../data/repositories/item_repository.dart';
import '../../providers.dart';
import '../../shared/empty_state.dart';
import '../library/card_edit_sheet.dart';
import 'memory_set_browse_screen.dart';
import 'memory_set_review_screen.dart';

/// 记忆管理（记忆教练）：用户自建「记忆集」，
/// 对集合整体学习/复习/回顾。集合可拉入已有收藏。
class MemoryManagerScreen extends ConsumerWidget {
  const MemoryManagerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sets = ref.watch(memorySetsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('记忆管理'),
        actions: [
          IconButton(
            tooltip: '新建记忆集',
            icon: const Icon(Icons.add_box_outlined),
            onPressed: () => _createSet(context, ref),
          ),
        ],
      ),
      body: sets.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (list) {
          if (list.isEmpty) {
            return const Center(
              child: EmptyState(
                icon: Icons.workspaces_outline,
                title: '还没有记忆集',
                subtitle: '建一个集合（如「考证刷题」），把已有收藏拉进来，'
                    '就能对集合整体复习。',
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [for (final s in list) _SetCard(set: s)],
          );
        },
      ),
    );
  }

  Future<void> _createSet(BuildContext context, WidgetRef ref) async {
    final nameCtrl = TextEditingController();
    final purposeCtrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('新建记忆集'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(labelText: '名称'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: purposeCtrl,
              decoration: const InputDecoration(
                labelText: '用途 / 说明（可选）',
                hintText: '如：考研英语真题词 / 产品知识库',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, nameCtrl.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      final setId = await ref
          .read(memorySetRepositoryProvider)
          .create(name, purpose: purposeCtrl.text.trim());
      ref.invalidate(memorySetsProvider);
      if (context.mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MemorySetDetailScreen(setId: setId),
          ),
        );
      }
    }
  }
}

/// 记忆集卡片：名称 + 用途 + 条数 + 进入。
class _SetCard extends ConsumerWidget {
  const _SetCard({required this.set});

  final MemorySetRow set;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    // 条目数（异步加载展示）
    final count = ref.watch(_memorySetCountProvider(set.id)).valueOrNull;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.workspaces_outline, color: scheme.primary),
        ),
        title: Text(
          set.name,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          set.purpose == null || set.purpose!.isEmpty
              ? '${count ?? '…'} 条内容'
              : '${set.purpose} · ${count ?? '…'} 条',
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MemorySetDetailScreen(setId: set.id),
          ),
        ),
      ),
    );
  }
}

/// 集合条目数。
final _memorySetCountProvider =
    FutureProvider.autoDispose.family<int, int>((ref, setId) async {
  final repo = ref.watch(memorySetRepositoryProvider);
  return (await repo.itemsOf(setId)).length;
});

/// 记忆集详情：条目列表 + 拉入收藏 + 开始复习 + 浏览回顾。
class MemorySetDetailScreen extends ConsumerWidget {
  const MemorySetDetailScreen({super.key, required this.setId});

  final int setId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 无法用 watch + Future detail，用 Provider.future 组合
    final detail = ref.watch(memorySetDetailProvider(setId));
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(detail.valueOrNull?.set.name ?? '记忆集'),
        actions: [
          IconButton(
            tooltip: '添加收藏',
            icon: const Icon(Icons.playlist_add_outlined),
            onPressed: () => _addLibraryItems(context, ref),
          ),
        ],
      ),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (d) {
          final items = d.items;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 用途说明
              if (d.set.purpose != null && d.set.purpose!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                  child: Text(
                    d.set.purpose!,
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
              // 操作行：开始复习 / 浏览回顾
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed:
                            items.isEmpty ? null : () => _startReview(context),
                        icon: const Icon(Icons.style, size: 18),
                        label: const Text('开始复习'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed:
                            items.isEmpty ? null : () => _browse(context),
                        icon: const Icon(Icons.visibility_outlined, size: 18),
                        label: const Text('浏览回顾'),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // 条目列表
              Expanded(
                child: items.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            '集合还是空的。\n点右上角「添加收藏」从记忆库把卡片拉进来，'
                            '之后就能对集合整体复习。',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: items.length,
                        itemBuilder: (_, i) {
                          final it = items[i];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            elevation: 0,
                            color: scheme.surfaceContainerLow,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            child: ListTile(
                              title: Text(
                                it.card?.prompt ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600),
                              ),
                              subtitle: Text(
                                it.card?.answer ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: PopupMenuButton<String>(
                                onSelected: (v) {
                                  if (v == 'remove') {
                                    _removeItem(context, ref, it.item.id);
                                  }
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                      value: 'remove', child: Text('移出集合')),
                                ],
                              ),
                              onTap: () => CardEditSheet.open(context, ref, it),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 从记忆库批量拉入已有收藏（卡片）到集合。
  Future<void> _addLibraryItems(BuildContext context, WidgetRef ref) async {
    final libraryItems = await ref.read(libraryItemsProvider.future);
    if (!context.mounted) return;
    if (libraryItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('记忆库还是空的，先去「学习」背几张卡')),
      );
      return;
    }
    final inSetIds =
        (await ref.read(memorySetRepositoryProvider).itemsOf(setId))
            .map((it) => it.item.id)
            .toSet();
    if (!context.mounted) return;
    final candidates = libraryItems
        .where((it) => !inSetIds.contains(it.item.id))
        .toList();
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('记忆库的卡片都已在这个集合里')),
      );
      return;
    }
    final picked = <int>{};
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _LibraryPicker(
        items: candidates,
        picked: picked,
        title: '选择收藏（多选）',
      ),
    );
    if (ok != true || picked.isEmpty) return;
    if (!context.mounted) return;
    final setRepo = ref.read(memorySetRepositoryProvider);
    for (final itemId in picked) {
      await setRepo.addItem(setId, itemId);
    }
    if (!context.mounted) return;
    ref.invalidate(memorySetDetailProvider(setId));
    ref.invalidate(_memorySetCountProvider(setId));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已加入 ${picked.length} 个收藏')),
    );
  }

  void _removeItem(BuildContext context, WidgetRef ref, int itemId) {
    ref.read(memorySetRepositoryProvider).removeItem(setId, itemId);
    ref.invalidate(memorySetDetailProvider(setId));
    ref.invalidate(_memorySetCountProvider(setId));
  }

  void _startReview(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MemorySetReviewSessionScreen(setId: setId),
      ),
    );
  }

  void _browse(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MemorySetBrowseScreen(setId: setId),
      ),
    );
  }
}

/// 记忆库卡片多选弹层（拉入记忆集）。
class _LibraryPicker extends StatefulWidget {
  const _LibraryPicker({
    required this.items,
    required this.picked,
    required this.title,
  });

  final List<ItemWithCard> items;
  final Set<int> picked;
  final String title;

  @override
  State<_LibraryPicker> createState() => _LibraryPickerState();
}

class _LibraryPickerState extends State<_LibraryPicker> {
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Flexible(
              child: SizedBox(
                height: 360,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: widget.items.length,
                  itemBuilder: (_, i) {
                    final it = widget.items[i];
                    final sel = widget.picked.contains(it.item.id);
                    return CheckboxListTile(
                      dense: true,
                      value: sel,
                      title: Text(
                        it.card?.prompt ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        it.card?.answer ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          widget.picked.add(it.item.id);
                        } else {
                          widget.picked.remove(it.item.id);
                        }
                      }),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: widget.picked.isEmpty
                    ? null
                    : () => Navigator.pop(context, true),
                child: Text('加入（${widget.picked.length}）'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
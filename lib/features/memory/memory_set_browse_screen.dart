import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import '../library/card_edit_sheet.dart';

/// 记忆集浏览回顾：平铺展示集合内所有内容。
class MemorySetBrowseScreen extends ConsumerWidget {
  const MemorySetBrowseScreen({super.key, required this.setId});

  final int setId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(memorySetDetailProvider(setId));

    return Scaffold(
      appBar: AppBar(title: const Text('浏览回顾')),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (d) {
          final items = d.items;
          if (items.isEmpty) {
            return const Center(child: Text('集合还是空的'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            itemBuilder: (_, i) {
              final it = items[i];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                elevation: 0,
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  title: Text(
                    it.card?.prompt ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    it.card?.answer ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => CardEditSheet.open(context, ref, it),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

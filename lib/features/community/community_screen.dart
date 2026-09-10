import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../content/content_plugin.dart';
import '../../providers.dart';
import '../../shared/ios_large_title.dart';
import 'training_set_detail_screen.dart';

/// 社区 Tab：自由选择训练类型（翻卡/单选/填空）→ 点击进详情 → 下载训练集。
///
/// 目录来自 TrainingSetSource（当前内置，远程接口预留）。
class CommunityScreen extends ConsumerWidget {
  const CommunityScreen({super.key, this.active = true});

  final bool active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!active) return const SizedBox.shrink();

    final catalog = ref.watch(trainingSetCatalogProvider);
    final installed = ref.watch(installedTrainingSetIdsProvider);
    final installedIds = installed.valueOrNull ?? const <String>{};

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 88),
      children: [
        const IOSLargeTitle('社区'),
        const SizedBox(height: 4),
        Text(
          '挑选感兴趣的训练类型，下载训练集后在「训练」里练习',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        catalog.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('加载失败：$e'),
          data: (list) => Column(
            children: [
              for (final p in list)
                _TrainingSetCard(
                  plugin: p,
                  installed: installedIds.contains(p.id),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => TrainingSetDetailScreen(plugin: p),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 训练集卡片：图标 + 名称 + 类型标签 + 条数 + 下载状态。
class _TrainingSetCard extends StatelessWidget {
  const _TrainingSetCard({
    required this.plugin,
    required this.installed,
    required this.onTap,
  });

  final ContentPlugin plugin;
  final bool installed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, tag) = switch (plugin.kind) {
      ContentKind.flashcard => (Icons.style_outlined, '翻卡'),
      ContentKind.quiz => (Icons.quiz_outlined, '单选'),
      ContentKind.cloze => (Icons.auto_stories, '填空'),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        onTap: onTap,
        leading: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 20, color: scheme.primary),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                plugin.name,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                tag,
                style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
        subtitle: Text(
          '${plugin.description} · 共 ${plugin.items.length} 项',
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
        trailing: installed
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle, size: 18, color: scheme.primary),
                  const SizedBox(width: 4),
                  Text(
                    '已下载',
                    style: TextStyle(fontSize: 12, color: scheme.primary),
                  ),
                ],
              )
            : const Icon(Icons.chevron_right, size: 20),
      ),
    );
  }
}
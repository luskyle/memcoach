import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../content/builtin_plugins.dart';
import '../../content/content_plugin.dart';
import '../../data/dictionary/language_catalog.dart';
import '../../providers.dart';
import '../../shared/empty_state.dart';
import '../../shared/ios_large_title.dart';
import '../settings/paywall_sheet.dart';
import 'content_player_screen.dart';
import 'study_level_screen.dart';

/// 学习 Tab：按语言主动学习（新词闪卡 → 自动进入 SRS 复习队列）。
///
/// 语言包分级：日语/英语免费；韩/法/西 等需 Pro 解锁。
class StudyScreen extends ConsumerWidget {
  const StudyScreen({super.key, this.active = true});

  final bool active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!active) return const SizedBox.shrink();

    final settings = ref.watch(settingsProvider);
    final dict = ref.watch(dictionaryServiceProvider);
    final counts = dict.countsByLang();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 88),
      children: [
        const IOSLargeTitle('学习'),
        const SizedBox(height: 4),
        Text(
          '按语言主动学习新词，学会的自动进入复习队列（间隔重复）',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        for (final lang in LanguageCatalog.entries)
          _LangCard(
            info: lang,
            entryCount: counts[lang.code] ?? 0,
            unlocked:
                LanguageCatalog.unlocked(lang.code, isPro: settings.isPro),
            onTap: () {
              if (LanguageCatalog.unlocked(lang.code, isPro: settings.isPro)) {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => StudyLevelScreen(lang: lang.code),
                  ),
                );
              } else {
                PaywallSheet.show(
                    context: context, reason: '解锁语言包：${lang.name}');
              }
            },
          ),
        const SizedBox(height: 20),
        // ---- 内容插件（可扩展：翻卡 / 单选 / 填空） ----
        Text(
          '内容插件',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 8),
        FutureBuilder<List<ContentPlugin>>(
          future: ContentRegistry.builtin(),
          builder: (context, snap) {
            if (snap.hasError) {
              return Text('插件加载失败：${snap.error}');
            }
            final plugins = snap.data ?? const <ContentPlugin>[];
            return Column(
              children: [
                for (final p in plugins)
                  _PluginCard(
                    plugin: p,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ContentPlayerScreen(plugin: p),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// 内容插件卡片：图标 + 名称 + 玩法标签。
class _PluginCard extends StatelessWidget {
  const _PluginCard({required this.plugin, required this.onTap});

  final ContentPlugin plugin;
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
          width: 38,
          height: 38,
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
        trailing: Icon(
          Icons.chevron_right,
          size: 20,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _LangCard extends StatelessWidget {
  const _LangCard({
    required this.info,
    required this.entryCount,
    required this.unlocked,
    required this.onTap,
  });

  final LanguageInfo info;
  final int entryCount;
  final bool unlocked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        onTap: onTap,
        leading: Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: info.free
                ? scheme.primary.withValues(alpha: 0.12)
                : scheme.surfaceContainerHighest.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            info.badge,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: info.free ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
        ),
        title: Row(
          children: [
            Text(
              info.name,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            if (!unlocked) ...[
              const SizedBox(width: 6),
              Icon(Icons.lock, size: 14, color: scheme.onSurfaceVariant),
            ],
          ],
        ),
        subtitle: Text(
          '${info.desc} · 共 $entryCount 词${unlocked ? '' : ' · Pro 解锁'}',
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
        trailing: Icon(
          unlocked ? Icons.chevron_right : Icons.lock_outline,
          size: 20,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// 学习空态（未载入词库）。
class StudyEmptyState extends StatelessWidget {
  const StudyEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      icon: Icons.translate,
      title: '词库尚未载入',
      subtitle: '重启应用后自动载入语言包',
    );
  }
}

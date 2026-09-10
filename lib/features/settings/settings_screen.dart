import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/analytics/analytics_service.dart';
import '../../data/export/export_service.dart';
import '../../data/settings/settings_store.dart';
import '../../providers.dart';
import 'paywall_sheet.dart';

/// 设置：订阅 / 偏好 / 数据所有权 / 关于。
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quota = ref.watch(quotaProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ---- 订阅 ----
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.workspace_premium_outlined),
                  title: const Text('Memcoach Pro'),
                  subtitle: quota.when(
                    loading: () => const Text('…'),
                    error: (_, __) => const Text('升级解锁无限额度'),
                    data: (q) => Text(q.isPro
                        ? '已解锁：无限复习 · 无限卡片'
                        : '免费版：无限复习 · 卡片库 100 张'),
                  ),
                  trailing: FilledButton.tonal(
                    onPressed: () => PaywallSheet.show(
                      context: context,
                      reason: '解锁无限复习与无限卡片库',
                    ),
                    child: const Text('升级'),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.pie_chart_outline),
                  title: const Text('当前额度'),
                  subtitle: quota.when(
                    loading: () => const Text('…'),
                    error: (_, __) => const Text('—'),
                    data: (q) => Text(
                      q.isPro
                          ? '无限'
                          : '已复习 ${q.reviewsToday} 次 · '
                              '记忆库 ${q.libraryCards}/${Quota.maxLibraryCards} 张',
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // ---- 偏好 ----
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.brightness_6_outlined),
                  title: const Text('外观'),
                  subtitle: Text(_themeLabel(ref.watch(themeModeProvider))),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.system,
                        icon: Icon(Icons.brightness_auto_outlined),
                        label: Text('跟随系统'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.light,
                        icon: Icon(Icons.light_mode_outlined),
                        label: Text('浅色'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        icon: Icon(Icons.dark_mode_outlined),
                        label: Text('深色'),
                      ),
                    ],
                    selected: {ref.watch(themeModeProvider)},
                    onSelectionChanged: (v) async {
                      final mode = v.first;
                      ref.read(themeModeProvider.notifier).state = mode;
                      await ref.read(settingsProvider).setThemeMode(
                            switch (mode) {
                              ThemeMode.light => 'light',
                              ThemeMode.dark => 'dark',
                              _ => 'system',
                            },
                          );
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // ---- 数据所有权 ----
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.file_download_outlined),
                  title: const Text('导出我的卡片库'),
                  subtitle: const Text('元数据 + 复习日志 → 本地 zip（JSON 机器可读）'),
                  onTap: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    try {
                      final path = await ExportService()
                          .export(ref.read(databaseProvider));
                      ref
                          .read(analyticsProvider)
                          .track(AnalyticsEvents.exportUsed);
                      messenger.showSnackBar(
                        SnackBar(content: Text('已导出：$path')),
                      );
                    } catch (e) {
                      messenger.showSnackBar(
                        SnackBar(content: Text('导出失败：$e')),
                      );
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.shield_outlined),
                  title: const Text('隐私与数据'),
                  subtitle: const Text('数据默认只存在本机，随时可导出拿回'),
                  onTap: () => showAboutDialog(
                    context: context,
                    applicationName: 'Memcoach',
                    applicationVersion: '0.2.0',
                    children: const [
                      Text(
                        '· 复习与学习数据默认仅保存在本机\n'
                        '· 所有生成内容均可编辑、可删除\n'
                        '· 导出 / 删除即删，随时拿回数据',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Card(
            child: ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('关于 Memcoach'),
              subtitle: Text('你的记忆教练：把想记住的东西收进来，在对的时间提醒你复习。'),
            ),
          ),
        ],
      ),
    );
  }

  String _themeLabel(ThemeMode mode) => switch (mode) {
        ThemeMode.light => '浅色',
        ThemeMode.dark => '深色',
        _ => '跟随系统',
      };
}
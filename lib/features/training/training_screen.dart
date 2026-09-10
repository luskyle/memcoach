import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/dictionary/language_catalog.dart';
import '../../providers.dart';
import '../../shared/empty_state.dart';
import '../../shared/ios_large_title.dart';
import '../../shared/status_chip.dart';
import 'curve_screen.dart';
import 'review_session_screen.dart';

/// 复习页（默认落点）：今日任务 + 开始复习 + 遗忘曲线入口。
///
/// [active]：非活动 Tab 时 build 短路，停止构建与统计监听（减少后台开销）。
class ReviewScreen extends ConsumerWidget {
  const ReviewScreen({super.key, this.active = true});

  final bool active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!active) return const SizedBox.shrink();
    final overview = ref.watch(reviewOverviewProvider);
    final scheme = Theme.of(context).colorScheme;

    return overview.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('加载失败：$e')),
      data: (o) {
        if (o.due == 0 && o.masterRatio == 0) {
          // 全新用户引导
          return const EmptyState(
            icon: Icons.school_outlined,
            title: '今天还没有复习任务',
            subtitle: '去「学习」学几个新词，或先记点什么，\n它会自动安排明天的首次复习。',
          );
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            const IOSLargeTitle('今日复习'),
            if (o.backlog > 0)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0x1AFF9500), // iOS systemOrange 10% 浅底
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.hourglass_top, color: scheme.tertiary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '积压 ${o.backlog} 条：超过复习间隔没复习，曲线开始下滑',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('今日任务', style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${o.due}',
                          style: Theme.of(context)
                              .textTheme
                              .displayMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: scheme.primary,
                              ),
                        ),
                        const SizedBox(width: 8),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            '张到期卡片',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: o.due == 0
                            ? null
                            : () => _startReview(context, ref),
                        icon: const Icon(Icons.style),
                        label: Text(o.due == 0 ? '今日复习完成' : '开始复习'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    icon: Icons.check_circle_outline,
                    label: '今日已复习',
                    value: '${o.reviewedToday}',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatCard(
                    icon: Icons.workspace_premium_outlined,
                    label: '掌握率',
                    value: '${(o.masterRatio * 100).toStringAsFixed(0)}%',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // ---- 学习情况（默认页图表）----
            const _StudyProgressSection(),
            const SizedBox(height: 12),
            // ---- 复习情况（近 8 周柱状图）----
            const _ReviewChartSection(),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: Icon(Icons.show_chart, color: scheme.primary),
                title: const Text('遗忘曲线'),
                subtitle: const Text('个人复习质量 vs 理论曲线（周视图）'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CurveScreen()),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _startReview(BuildContext context, WidgetRef ref) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ReviewSessionScreen()),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: scheme.primary),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// 学习情况：各语言学习进度（学习产生的卡片 / 词库总量）。
class _StudyProgressSection extends ConsumerWidget {
  const _StudyProgressSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final learned = ref.watch(learnedByLangProvider);
    final dict = ref.watch(dictionaryServiceProvider);
    final counts = dict.countsByLang();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.school, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  '学习情况',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (learned.value == null || learned.value!.isEmpty)
              Text(
                '还没有学习记录——去「学习」从第一关开始（拼音五十音/音标起步）',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              )
            else
              for (final info in LanguageCatalog.entries)
                if ((counts[info.code] ?? 0) > 0) ...[
                  _LangProgressRow(
                    info: info,
                    learned: learned.value![info.code] ?? 0,
                    total: counts[info.code] ?? 0,
                  ),
                  const SizedBox(height: 8),
                ],
          ],
        ),
      ),
    );
  }
}

class _LangProgressRow extends StatelessWidget {
  const _LangProgressRow({
    required this.info,
    required this.learned,
    required this.total,
  });

  final LanguageInfo info;
  final int learned;
  final int total;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ratio = total == 0 ? 0.0 : (learned / total).clamp(0.0, 1.0);
    return Row(
      children: [
        LanguageBadge(lang: info.code),
        const SizedBox(width: 8),
        SizedBox(
          width: 96,
          child: Text(
            '${info.name} · $learned/$total',
            style: const TextStyle(fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              color: scheme.primary,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
        ),
      ],
    );
  }
}

/// 复习情况：近 8 周每周复习次数柱状图 + 汇总。
class _ReviewChartSection extends ConsumerWidget {
  const _ReviewChartSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final weeks = ref.watch(weeklyStatsProvider);
    final overview = ref.watch(reviewOverviewProvider);
    final total = overview.maybeWhen(
      data: (o) => o.reviewedToday,
      orElse: () => 0,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bar_chart, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  '复习情况 · 近 8 周',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 140,
              child: weeks.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(),
                ),
                error: (_, __) => const SizedBox.shrink(),
                data: (list) {
                  final hasData = list.any((w) => w.reviews > 0);
                  if (!hasData) {
                    return Center(
                      child: Text(
                        '完成几次复习后，这里显示每周复习量',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    );
                  }
                  return BarChart(
                    BarChartData(
                      maxY: (list
                                  .map((w) => w.reviews)
                                  .reduce((a, b) => a > b ? a : b) +
                              2)
                          .toDouble(),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: 1,
                        getDrawingHorizontalLine: (v) => FlLine(
                          color: scheme.outlineVariant.withValues(alpha: 0.4),
                          strokeWidth: 1,
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(),
                        rightTitles: const AxisTitles(),
                        leftTitles: const AxisTitles(),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 24,
                            interval: 1,
                            getTitlesWidget: (v, meta) {
                              final i = v.toInt();
                              if (i < 0 || i >= list.length) {
                                return const SizedBox.shrink();
                              }
                              return Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  '${list[i].weekStart.month}/${list[i].weekStart.day}',
                                  style: const TextStyle(fontSize: 8),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      barGroups: [
                        for (var i = 0; i < list.length; i++)
                          BarChartGroupData(
                            x: i,
                            barRods: [
                              BarChartRodData(
                                toY: list[i].reviews.toDouble(),
                                width: 10,
                                color: scheme.primary,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(3),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '本周已复习 $total 次 · 数据来自真实复习日志',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

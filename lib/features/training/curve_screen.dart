import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/repositories/review_repository.dart';
import '../../providers.dart';
import '../../shared/empty_state.dart';

/// 遗忘曲线：个人复习正确率 vs 理论基线（周视图）+ 复习热力图（12 周）。
class CurveScreen extends ConsumerWidget {
  const CurveScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(weeklyStatsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('遗忘曲线')),
      body: stats.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (weeks) => _buildBody(context, weeks, ref),
      ),
    );
  }

  Widget _buildBody(
      BuildContext context, List<WeeklyStat> weeks, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final withData = weeks.where((w) => w.reviews > 0).toList();

    if (withData.isEmpty) {
      return const EmptyState(
        icon: Icons.show_chart,
        title: '还没有曲线数据',
        subtitle: '完成几次复习后，这里会展示你的真实复习质量曲线。',
      );
    }

    // 保持原始周索引：无数据周留空位，线不断裂
    final spots = <FlSpot>[];
    for (var i = 0; i < weeks.length; i++) {
      if (weeks[i].reviews > 0) {
        spots.add(FlSpot(i.toDouble(), weeks[i].correctRatio * 100));
      }
    }
    final theorySpots = spots.map((s) => FlSpot(s.x, 90)).toList();

    final latest = withData.last;
    final totalReviews = weeks.fold<int>(0, (a, w) => a + w.reviews);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: _MiniStat(
                label: '本周复习',
                value: '${latest.reviews} 次',
                icon: Icons.replay,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MiniStat(
                label: '本周正确率',
                value: '${(latest.correctRatio * 100).toStringAsFixed(0)}%',
                icon: Icons.trending_up,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MiniStat(
                label: '累计复习',
                value: '$totalReviews 次',
                icon: Icons.history,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 24, 20, 16),
            child: SizedBox(
              height: 260,
              child: LineChart(
                LineChartData(
                  minY: 0,
                  maxY: 100,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: 25,
                    getDrawingHorizontalLine: (v) => FlLine(
                      color: scheme.outlineVariant.withValues(alpha: 0.4),
                      strokeWidth: 1,
                    ),
                  ),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(),
                    rightTitles: const AxisTitles(),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        interval: 25,
                        getTitlesWidget: (v, meta) => Text('${v.round()}%',
                            style: const TextStyle(fontSize: 10)),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        interval: 1,
                        getTitlesWidget: (v, meta) {
                          final idx = v.round();
                          if (idx < 0 || idx >= weeks.length) {
                            return const SizedBox.shrink();
                          }
                          // 隔周显示，避免拥挤
                          if (idx % 2 != 0 && idx != weeks.length - 1) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              DateFormat('MM/dd').format(weeks[idx].weekStart),
                              style: const TextStyle(fontSize: 10),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    // 理论基线（目标正确率 90%）
                    LineChartBarData(
                      spots: theorySpots,
                      isCurved: true,
                      curveSmoothness: 0,
                      color: scheme.outline,
                      barWidth: 2,
                      dashArray: [6, 4],
                      dotData: const FlDotData(show: false),
                    ),
                    // 个人正确率
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      curveSmoothness: 0.35,
                      color: scheme.primary,
                      barWidth: 3,
                      dotData: FlDotData(
                          show: true,
                          getDotPainter: (_, __, ___, ____) =>
                              FlDotCirclePainter(
                                radius: 3.5,
                                color: scheme.primary,
                                strokeWidth: 2,
                                strokeColor: scheme.surface,
                              )),
                      belowBarData: BarAreaData(
                        show: true,
                        color: scheme.primary.withValues(alpha: 0.08),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _LegendDot(color: scheme.primary, label: '个人正确率'),
            const SizedBox(width: 16),
            _LegendDot(color: scheme.outline, label: '理论目标（90%）'),
          ],
        ),
        const SizedBox(height: 24),
        _buildHeatmap(context, ref),
        const SizedBox(height: 8),
        Text(
          '数据全部来自真实复习日志：只展示你实际完成的复习。',
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  /// 复习热力图：GitHub 风格 12 周日历（行 = 周一~周日，列 = 周）。
  Widget _buildHeatmap(BuildContext context, WidgetRef ref) {
    final counts = ref.watch(reviewHeatmapProvider);
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.calendar_month, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  '复习热力图（近 12 周）',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 16),
            counts.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (_, __) => const SizedBox.shrink(),
              data: (byDay) => _HeatmapGrid(counts: byDay),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Column(
          children: [
            Icon(icon, size: 16, color: scheme.primary),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              label,
              style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

/// GitHub 风格复习热力图：列 = 周（近 12 周，截至本周），行 = 周一~周日。
class _HeatmapGrid extends StatelessWidget {
  const _HeatmapGrid({required this.counts});

  final Map<DateTime, int> counts;

  static const _cell = 12.0;
  static const _gap = 3.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final thisMonday = today.subtract(Duration(days: today.weekday - 1));

    // 近 12 周（旧 → 新）
    final weeks = List.generate(
      12,
      (i) => thisMonday.subtract(Duration(days: 7 * (11 - i))),
    );

    // 每月首个周列标注月份
    final monthLabels = <int, String>{};
    var lastMonth = -1;
    for (var w = 0; w < weeks.length; w++) {
      final m = weeks[w].month;
      if (m != lastMonth) {
        lastMonth = m;
        monthLabels[w] = '${weeks[w].month}月';
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 月份标注
        Row(
          children: [
            const SizedBox(width: 22), // 对齐星期标签
            for (var w = 0; w < weeks.length; w++)
              SizedBox(
                width: _cell + _gap,
                child: Text(
                  monthLabels[w] ?? '',
                  style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant),
                ),
              ),
          ],
        ),
        const SizedBox(height: 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 星期标签（一/三/五）
            Column(
              children: [
                for (final d in const ['一', '', '三', '', '五', '', ''])
                  SizedBox(
                    height: _cell + _gap,
                    width: 22,
                    child: Text(
                      d,
                      style: TextStyle(
                          fontSize: 9, color: scheme.onSurfaceVariant),
                    ),
                  ),
              ],
            ),
            for (final monday in weeks)
              Column(
                children: [
                  for (var d = 0; d < 7; d++)
                    _cellWidget(
                      scheme,
                      monday.add(Duration(days: d)),
                    ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 10),
        // 图例：少 → 多
        Row(
          children: [
            Text(
              '少',
              style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(width: 6),
            for (final level in [0, 1, 2, 3, 4])
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(right: 3),
                decoration: BoxDecoration(
                  color:
                      _levelColor(scheme, _levelOf(level == 4 ? 6 : level * 2)),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            const SizedBox(width: 3),
            Text(
              '多',
              style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ],
    );
  }

  Widget _cellWidget(ColorScheme scheme, DateTime day) {
    final count = counts[day] ?? 0;
    return Padding(
      padding: const EdgeInsets.only(right: _gap, bottom: _gap),
      child: Container(
        width: _cell,
        height: _cell,
        decoration: BoxDecoration(
          color: _levelColor(scheme, _levelOf(count)),
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }

  /// 复习量分级：0 / 1 / 2~3 / 4~5 / 6+。
  static int _levelOf(int count) {
    if (count <= 0) return 0;
    if (count == 1) return 1;
    if (count <= 3) return 2;
    if (count <= 5) return 3;
    return 4;
  }

  Color _levelColor(ColorScheme scheme, int level) {
    return switch (level) {
      0 => scheme.surfaceContainerHighest.withValues(alpha: 0.55),
      1 => scheme.primary.withValues(alpha: 0.22),
      2 => scheme.primary.withValues(alpha: 0.45),
      3 => scheme.primary.withValues(alpha: 0.7),
      _ => scheme.primary,
    };
  }
}

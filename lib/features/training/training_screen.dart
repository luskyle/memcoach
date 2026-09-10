import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/training.dart';
import '../../providers.dart';
import '../../shared/ios_large_title.dart';
import 'curve_screen.dart';
import 'training_session_screen.dart';

/// 训练页（默认落点）：头部数据 + 自评状态选择强度 + 开始训练。
///
/// 训练机制：没有正在训练中的任务时，用户先自评状态
/// （很好→Max 强度 / 一般→中等 / 很差→轻松），强度决定本轮
/// 题量、SM-2 间隔增幅、新卡 vs 复习卡比例、时长上限。
class TrainingScreen extends ConsumerWidget {
  const TrainingScreen({super.key, this.active = true});

  final bool active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!active) return const SizedBox.shrink();

    final overview = ref.watch(reviewOverviewProvider);
    final intensity = ref.watch(trainingIntensityProvider);
    final scheme = Theme.of(context).colorScheme;

    return overview.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('加载失败：$e')),
      data: (o) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 88),
          children: [
            const IOSLargeTitle('训练'),
            const SizedBox(height: 4),
            Text(
              '先自评状态，选出本轮强度，再开始训练',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            if (o.backlog > 0)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0x1AFF9500),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.hourglass_top, color: scheme.tertiary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '积压 ${o.backlog} 条：超过训练间隔没训练，记忆开始下滑',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
            _OverviewCard(
              due: o.due,
              canStart: intensity != null,
              onStart: () => _startTraining(context),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    icon: Icons.check_circle_outline,
                    label: '今日已训练',
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
            const SizedBox(height: 20),
            // ---- 自评状态 → 训练强度 ----
            Text(
              '自我评估状态',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              '没有正在训练中的任务时，先选一个贴合当下的状态',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            for (final i in TrainingIntensity.values) ...[
              _IntensityCard(
                intensity: i,
                selected: intensity == i,
                onTap: () => ref
                    .read(trainingIntensityProvider.notifier)
                    .state = i,
              ),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: Icon(Icons.show_chart, color: scheme.primary),
                title: const Text('遗忘曲线'),
                subtitle: const Text('训练质量 vs 理论曲线（周视图）'),
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

  void _startTraining(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const TrainingSessionScreen()),
    );
  }
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({
    required this.due,
    required this.canStart,
    required this.onStart,
  });

  final int due;
  final bool canStart;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('到期复习', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$due',
                  style: Theme.of(context).textTheme.displayMedium?.copyWith(
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
                onPressed: canStart ? onStart : null,
                icon: const Icon(Icons.fitness_center),
                label: Text(canStart ? '开始训练' : '先自评状态'),
              ),
            ),
          ],
        ),
      ),
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

/// 自评状态卡片：三种强度，选中高亮。
class _IntensityCard extends StatelessWidget {
  const _IntensityCard({
    required this.intensity,
    required this.selected,
    required this.onTap,
  });

  final TrainingIntensity intensity;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final preset = intensityPreset(intensity);
    final (icon, color) = switch (intensity) {
      TrainingIntensity.max => (Icons.bolt, Colors.deepOrange),
      TrainingIntensity.medium => (Icons.trending_up, scheme.primary),
      TrainingIntensity.relaxed => (Icons.spa, Colors.teal),
    };

    return Card(
      elevation: 0,
      color: selected
          ? color.withValues(alpha: 0.10)
          : scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: selected
            ? BorderSide(color: color, width: 1.4)
            : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          intensityStateLabel(intensity),
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          intensityModeLabel(intensity),
                          style: TextStyle(
                              fontSize: 12, color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${intensityDescription(intensity)} · 约 ${preset.cardCount} 张',
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                color: selected ? color : scheme.outlineVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
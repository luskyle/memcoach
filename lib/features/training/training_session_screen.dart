import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/analytics/analytics_service.dart';
import '../../data/repositories/item_repository.dart';
import '../../domain/srs/sm2.dart';
import '../../domain/training.dart';
import '../../providers.dart';
import 'curve_screen.dart';

/// 训练会话：混合「新卡（已下载训练集引入）+ 到期复习卡」，
/// 闪卡先猜后看 + 三键评级（忘了/模糊/记得）。
///
/// 强度决定本轮题量、新卡占比、SM-2 间隔增幅与时长上限。
class TrainingSessionScreen extends ConsumerStatefulWidget {
  const TrainingSessionScreen({super.key});

  @override
  ConsumerState<TrainingSessionScreen> createState() =>
      _TrainingSessionScreenState();
}

class _TrainingSessionScreenState extends ConsumerState<TrainingSessionScreen> {
  static const _groupSize = 6; // 卡片墙：一屏一组

  List<CardWithItem> _queue = const [];
  int _groupStart = 0;
  final Set<int> _groupRated = {}; // 当前组内已评级卡（组内相对下标）
  int _answered = 0;
  int _qualitySum = 0;
  late final DateTime _startedAt;
  bool _loading = true;
  bool _finished = false;

  TrainingIntensity get _intensity =>
      ref.read(trainingIntensityProvider) ?? TrainingIntensity.medium;

  IntensityPreset get _preset => intensityPreset(_intensity);

  @override
  void initState() {
    super.initState();
    _startedAt = DateTime.now();
    _load();
  }

  /// 组队：确保有足够新卡后，按强度比例取「新卡 + 到期卡」。
  Future<void> _load() async {
    final preset = _preset;
    final reviewRepo = ref.read(reviewRepositoryProvider);
    final setRepo = ref.read(trainingSetRepositoryProvider);

    // 1. 从已下载训练集补足新卡（引入即成为可训练卡片）
    var needNew = preset.newCardTarget();
    final existingNew = await reviewRepo.newCards(limit: preset.cardCount);
    needNew -= existingNew.length;
    if (needNew > 0) {
      final installedIds =
          await ref.read(trainingSetRepositoryProvider).installedIds();
      if (installedIds.isNotEmpty) {
        final catalog = await ref.read(trainingSetSourceProvider).catalog();
        for (final p in catalog) {
          if (needNew <= 0) break;
          if (!installedIds.contains(p.id)) continue;
          final imported = await setRepo.importItems(p, needNew);
          needNew -= imported;
        }
      }
    }

    // 2. 取新卡 + 到期卡，封顶 cardCount
    final newCards =
        await reviewRepo.newCards(limit: preset.newCardTarget());
    final reviewTarget =
        (preset.cardCount - newCards.length).clamp(0, preset.cardCount);
    final due = await reviewRepo.dueCards(limit: reviewTarget);

    final queue = <CardWithItem>[...newCards, ...due];
    setState(() {
      _queue = queue;
      _finished = queue.isEmpty;
      _loading = false;
    });
  }

  /// 当前组卡片（组内相对下标 0..n-1）。
  List<CardWithItem> get _group => _queue.sublist(
        _groupStart,
        (_groupStart + _groupSize).clamp(0, _queue.length),
      );

  /// 评级并落库（SM-2 更新 + 强度间隔增幅）；组内评完自动切下一组。
  Future<void> _rate(int localIndex, ReviewRating rating) async {
    final card = _queue[_groupStart + localIndex].card;
    final quality = sm2QualityFor(rating);
    ref.read(analyticsProvider).track(
      AnalyticsEvents.reviewRating,
      props: {'quality': quality},
    );
    await ref.read(reviewRepositoryProvider).reviewCard(
          cardId: card.id,
          rating: rating,
          intervalMultiplier: _preset.intervalMultiplier,
        );
    setState(() {
      _answered += 1;
      _qualitySum += quality;
      _groupRated.add(localIndex);
    });
    ref.invalidate(dueCardsProvider);
    ref.invalidate(reviewOverviewProvider);
    ref.invalidate(quotaProvider);
    if (_groupRated.length >= _group.length) {
      _nextGroup();
    }
  }

  void _nextGroup() {
    final completed = _groupStart + _groupSize >= _queue.length;
    setState(() {
      _groupStart += _groupSize;
      _groupRated.clear();
      if (completed) _finished = true;
    });
    if (completed) {
      ref.read(analyticsProvider).track(
        AnalyticsEvents.reviewSessionCompleted,
        props: {'count': _answered},
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_finished) {
      return _buildCompletion();
    }

    final group = _group;
    final progress = _queue.isEmpty ? 0.0 : _answered / _queue.length;
    final elapsed = DateTime.now().difference(_startedAt);
    final overCap = elapsed.inMinutes >= _preset.durationCapMinutes;

    return Scaffold(
      appBar: AppBar(
        title: Text('训练 · $_answered/${_queue.length}'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3),
          child: LinearProgressIndicator(
              value: progress, borderRadius: BorderRadius.circular(4)),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(
                    Icons.fitness_center,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${intensityModeLabel(_intensity)} · '
                    '上限 ${_preset.durationCapMinutes} 分钟 · '
                    '已用时 ${elapsed.inMinutes}:${(elapsed.inSeconds % 60).toString().padLeft(2, '0')}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
              if (overCap) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0x1AFF9500),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    '已达本轮时长上限，可继续练完或返回休息',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1160),
                    child: GridView.builder(
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 14,
                        crossAxisSpacing: 14,
                        childAspectRatio: 1.35,
                      ),
                      itemCount: group.length,
                      itemBuilder: (_, i) => _WallCard(
                        key: ValueKey(group[i].card.id),
                        item: group[i],
                        rated: _groupRated.contains(i),
                        onRate: (r) => _rate(i, r),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                _groupRated.length >= group.length
                    ? '本组完成，进入下一组…'
                    : '点击卡片翻面看答案，再评级：忘了 / 模糊 / 记得',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompletion() {
    final avgQuality = _answered == 0 ? 0.0 : _qualitySum / _answered;
    final summary = _answered == 0
        ? '没有可训练内容'
        : '完成 $_answered 张 · 平均评级 ${avgQuality.toStringAsFixed(1)}/5';

    if (_answered == 0) {
      // 没有可训练内容：引导去社区下载训练集
      return Scaffold(
        appBar: AppBar(automaticallyImplyLeading: false),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.explore_off, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                Text(
                  '还没有可训练的内容',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text(
                  '去「社区」下载你感兴趣的训练集，\n就能开始训练了。',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('返回'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: false),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.task_alt, size: 64, color: Colors.green),
              const SizedBox(height: 16),
              Text(
                '本轮训练完成',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(summary, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const CurveScreen()),
                  );
                },
                icon: const Icon(Icons.show_chart),
                label: const Text('查看遗忘曲线'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('返回'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 卡片墙单卡：点击翻面，背面可评级；已评级盖绿色对勾。
class _WallCard extends StatefulWidget {
  const _WallCard({
    super.key,
    required this.item,
    required this.rated,
    required this.onRate,
  });

  final CardWithItem item;
  final bool rated;
  final ValueChanged<ReviewRating> onRate;

  @override
  State<_WallCard> createState() => _WallCardState();
}

class _WallCardState extends State<_WallCard> {
  bool _flipped = false;

  @override
  void didUpdateWidget(covariant _WallCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 评级完成后回到正面，展示对勾
    if (!oldWidget.rated && widget.rated && _flipped) {
      _flipped = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedOpacity(
      opacity: widget.rated ? 0.45 : 1,
      duration: const Duration(milliseconds: 220),
      child: GestureDetector(
        onTap: widget.rated
            ? null
            : () => setState(() => _flipped = !_flipped),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_flipped) _back() else _front(),
              if (widget.rated)
                Container(
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.check_circle,
                      color: Colors.green, size: 44),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _front() {
    return Center(
      key: const ValueKey('front'),
      child: SingleChildScrollView(
        child: Text(
          widget.item.card.prompt,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _back() {
    return Column(
      key: const ValueKey('back'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Text(
              widget.item.card.answer.isEmpty ? '（无答案）' : widget.item.card.answer,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, height: 1.4),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _MiniRate(
              label: '忘了',
              icon: Icons.sentiment_very_dissatisfied,
              color: Colors.redAccent,
              onTap: () => widget.onRate(ReviewRating.forgot),
            ),
            _MiniRate(
              label: '模糊',
              icon: Icons.sentiment_neutral,
              color: Colors.amber.shade700,
              onTap: () => widget.onRate(ReviewRating.fuzzy),
            ),
            _MiniRate(
              label: '记得',
              icon: Icons.sentiment_satisfied_alt,
              color: Colors.green.shade600,
              onTap: () => widget.onRate(ReviewRating.remembered),
            ),
          ],
        ),
      ],
    );
  }
}

/// 卡片墙上的迷你评级按钮。
class _MiniRate extends StatelessWidget {
  const _MiniRate({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
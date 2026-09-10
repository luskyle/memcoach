import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/analytics/analytics_service.dart';
import '../../providers.dart';

/// 订阅墙（占位）：26 元/月、198 元/年、398 元/买断。
/// 内购接入在阶段 2（W7~10）完成，MVP 仅展示方案与免费额度对照。
class PaywallSheet extends StatelessWidget {
  const PaywallSheet({super.key, required this.reason});

  final String reason;

  static Future<void> show({
    required BuildContext context,
    required String reason,
  }) {
    // 付费墙曝光（触发时机：额度超限 / 升级入口）
    ProviderScope.containerOf(context, listen: false)
        .read(analyticsProvider)
        .track(AnalyticsEvents.paywallShown, props: {'reason': reason});
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => PaywallSheet(reason: reason),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Memcoach Pro', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            reason,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          _plan(
            context,
            name: '按月',
            price: '26 元/月',
            features: '无限训练额度 · 无限卡片',
          ),
          _plan(
            context,
            name: '按年',
            price: '198 元/年',
            features: '约 16.5 元/月，省 36%',
            recommended: true,
          ),
          _plan(
            context,
            name: '买断',
            price: '398 元',
            features: '一次购买，永久使用',
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '免费版：无限训练 · 卡片上限 100 张。\n'
              '说明：应用内购将在后续版本接入，当前为方案展示。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _plan(
    BuildContext context, {
    required String name,
    required String price,
    required String features,
    bool recommended = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          recommended ? Icons.star : Icons.workspace_premium_outlined,
          color: recommended ? scheme.tertiary : scheme.primary,
        ),
        title: Row(
          children: [
            Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
            if (recommended) ...[
              const SizedBox(width: 8),
              Text(
                '推荐',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: scheme.tertiary,
                ),
              ),
            ],
          ],
        ),
        subtitle: Text(features),
        trailing: Text(
          price,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: scheme.primary,
          ),
        ),
      ),
    );
  }
}

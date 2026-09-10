import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../data/database/database.dart';
import '../../data/repositories/item_repository.dart';
import '../../providers.dart';
import '../../shared/status_chip.dart';

/// 记忆库卡片编辑入口：点按/长按卡片打开 [CardDetailSheet]，
/// 编辑正反面 / 删除（原收件箱 item_actions 的卡片详情迁移而来）。
class CardEditSheet {
  const CardEditSheet._();

  static void open(BuildContext context, WidgetRef ref, ItemWithCard item) {
    final card = item.card;
    if (card == null) return; // 记忆库只展示已成卡条目
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => CardDetailSheet(item: item, card: card),
    );
  }
}

/// 卡片详情弹层：卡面编辑（正面/背面）、删除。
class CardDetailSheet extends ConsumerStatefulWidget {
  const CardDetailSheet({super.key, required this.item, required this.card});

  final ItemWithCard item;
  final CardRow card;

  @override
  ConsumerState<CardDetailSheet> createState() => _CardDetailSheetState();
}

class _CardDetailSheetState extends ConsumerState<CardDetailSheet> {
  late final TextEditingController _prompt;
  late final TextEditingController _answer;

  @override
  void initState() {
    super.initState();
    _prompt = TextEditingController(text: widget.card.prompt);
    _answer = TextEditingController(text: widget.card.answer);
  }

  @override
  void dispose() {
    _prompt.dispose();
    _answer.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await ref.read(itemRepositoryProvider).updateCardFields(
          widget.item.item.id,
          prompt: _prompt.text.trim(),
          answer: _answer.text.trim(),
        );
    if (mounted) {
      Navigator.of(context).pop();
      ref.invalidate(libraryItemsProvider);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已保存')));
    }
  }

  Future<void> _delete() async {
    await ref.read(itemRepositoryProvider).deleteItem(widget.item.item.id);
    if (mounted) {
      Navigator.of(context).pop();
      ref.invalidate(libraryItemsProvider);
      ref.invalidate(reviewOverviewProvider);
      ref.invalidate(quotaProvider);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已删除')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('卡片', style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                StatusChip(status: widget.item.item.status),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '间隔 ${widget.card.intervalDays} 天 · EF ${widget.card.easeFactor.toStringAsFixed(2)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            // 出处（划词收藏自动带来源页）
            if (widget.item.item.originalUrl != null ||
                widget.item.item.sourceTitle != null) ...[
              const SizedBox(height: 12),
              _SourceRow(item: widget.item.item),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _prompt,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '正面',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _answer,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: '背面 / 答案',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _delete,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('删除'),
                ),
                const Spacer(),
                FilledButton(onPressed: _save, child: const Text('保存')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 来源行：标题 + 「打开原文」。
class _SourceRow extends StatelessWidget {
  const _SourceRow({required this.item});

  final ItemRow item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final url = item.originalUrl;
    final title = item.sourceTitle;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.link, size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title ?? url ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (url != null) ...[
            const SizedBox(width: 8),
            InkWell(
              onTap: () async {
                final uri = Uri.tryParse(url);
                if (uri != null && await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              child: Text(
                '打开原文',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.systemBlue,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
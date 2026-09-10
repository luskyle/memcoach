import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../content/content_plugin.dart';
import '../../domain/poetry/poetry_puzzle.dart';
import '../../providers.dart';

/// 训练集详情：介绍 + 下载训练集 → 之后在「训练」里练习；可先试玩。
class TrainingSetDetailScreen extends ConsumerWidget {
  const TrainingSetDetailScreen({super.key, required this.plugin});

  final ContentPlugin plugin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final installedIds =
        ref.watch(installedTrainingSetIdsProvider).valueOrNull ??
            const <String>{};
    final installed = installedIds.contains(plugin.id);
    final scheme = Theme.of(context).colorScheme;
    final (icon, tag) = switch (plugin.kind) {
      ContentKind.flashcard => (Icons.style_outlined, '翻卡'),
      ContentKind.quiz => (Icons.quiz_outlined, '单选'),
      ContentKind.cloze => (Icons.auto_stories, '填空'),
    };

    return Scaffold(
      appBar: AppBar(title: Text(plugin.name)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, size: 28, color: scheme.primary),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plugin.name,
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text('类型：$tag · 共 ${plugin.items.length} 项',
                        style: TextStyle(
                            fontSize: 12, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(plugin.description,
              style: const TextStyle(fontSize: 14, height: 1.5)),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: installed
                ? null
                : () async {
                    await ref
                        .read(trainingSetRepositoryProvider)
                        .install(plugin);
                    ref.invalidate(installedTrainingSetIdsProvider);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('已下载「${plugin.name}」，去「训练」开始练习'),
                        ),
                      );
                    }
                  },
            icon: Icon(installed ? Icons.check_circle : Icons.download),
            label: Text(installed ? '已下载' : '下载训练集'),
          ),
          if (installed) ...[
            const SizedBox(height: 8),
            Text(
              '已下载：训练时会按你的强度逐步引入这些卡片',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => TrainingSetPlayScreen(plugin: plugin),
              ),
            ),
            icon: const Icon(Icons.play_circle_outline),
            label: const Text('试玩'),
          ),
        ],
      ),
    );
  }
}

/// 训练集统一播放器（试玩 / 预览）：按玩法（翻卡 / 单选 / 填空）分发渲染。
/// 逐题推进 + 进度条 + 完成页；试玩结果不入 SRS。
class TrainingSetPlayScreen extends ConsumerStatefulWidget {
  const TrainingSetPlayScreen({super.key, required this.plugin});

  final ContentPlugin plugin;

  @override
  ConsumerState<TrainingSetPlayScreen> createState() =>
      _TrainingSetPlayScreenState();
}

class _TrainingSetPlayScreenState extends ConsumerState<TrainingSetPlayScreen> {
  int _index = 0;
  int _score = 0;
  bool _flipped = false; // flashcard 翻面
  int? _selected; // quiz 已选下标
  int _clozeCorrect = 0; // cloze 本项答对空数
  bool _clozeChecked = false;
  final List<TextEditingController> _blankCtrls = [];
  List<PuzzleBlank> _clozeBlanks = const [];
  bool _done = false;

  ContentPlugin get _plugin => widget.plugin;

  List<ContentItem> get _items => _plugin.items;

  @override
  void initState() {
    super.initState();
    // 首个内容若是填空，进入后立即生成空位（否则首屏无空可填）
    if (widget.plugin.kind == ContentKind.cloze) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(_initCloze);
      });
    }
  }

  @override
  void dispose() {
    _disposeBlankCtrl();
    super.dispose();
  }

  void _disposeBlankCtrl() {
    for (final c in _blankCtrls) {
      c.dispose();
    }
    _blankCtrls.clear();
  }

  void _rateFlashcard(int score) {
    setState(() {
      _score += score;
      _advance();
    });
  }

  void _pickQuiz(int i) {
    if (_selected != null) return;
    final item = _items[_index] as QuizItem;
    setState(() {
      _selected = i;
      if (i == item.answerIndex) _score++;
    });
  }

  void _nextQuiz() {
    if (_selected == null) return;
    setState(() {
      _selected = null;
      _advance();
    });
  }

  void _initCloze() {
    _disposeBlankCtrl();
    final item = _items[_index] as ClozeItem;
    final blanks = createBlanks(item.lines, count: 5, random: Random());
    _blankCtrls
      ..clear()
      ..addAll(
        [for (var i = 0; i < blanks.length; i++) TextEditingController()],
      );
    _clozeBlanks = blanks;
    _clozeChecked = false;
    _clozeCorrect = 0;
  }

  void _checkCloze() {
    final item = _items[_index] as ClozeItem;
    var correct = 0;
    for (var i = 0; i < _clozeBlanks.length; i++) {
      if (_blankCtrls[i].text.trim() ==
          _clozeBlanks[i].answerIn(item.lines)) {
        correct++;
      }
    }
    setState(() {
      _clozeChecked = true;
      _clozeCorrect = correct;
      _score += correct;
    });
  }

  void _clozeToScore() {
    setState(_advance);
  }

  void _advance() {
    _flipped = false;
    if (_index + 1 >= _items.length) {
      _done = true;
    } else {
      _index += 1;
      if (_items[_index] is ClozeItem) {
        _initCloze();
      }
    }
  }

  void _restart() {
    setState(() {
      _index = 0;
      _score = 0;
      _done = false;
      _selected = null;
      _flipped = false;
      _clozeChecked = false;
      if (_items.first is ClozeItem) {
        _initCloze();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return _buildCompletion();

    final item = _items[_index];
    final progress = _items.isEmpty ? 0.0 : _index / _items.length;

    return Scaffold(
      appBar: AppBar(
        title: Text('${_plugin.name} · ${_index + 1}/${_items.length}'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: LinearProgressIndicator(
                value: progress,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Expanded(
              child: Center(
                child: switch (_plugin.kind) {
                  ContentKind.flashcard => ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: 640,
                        maxHeight: 520,
                      ),
                      child: _buildFlashcard(item as FlashcardItem),
                    ),
                  ContentKind.quiz => SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 640),
                        child: _buildQuiz(item as QuizItem),
                      ),
                    ),
                  ContentKind.cloze => SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 640),
                        child: _buildCloze(item as ClozeItem),
                      ),
                    ),
                },
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildFlashcard(FlashcardItem item) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () => setState(() => _flipped = !_flipped),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: _flipped ? _fcBack(item) : _fcFront(item),
          ),
        ),
        const SizedBox(height: 24),
        if (_flipped)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _SelfRate(
                  label: '忘了',
                  icon: Icons.sentiment_very_dissatisfied,
                  color: Colors.redAccent,
                  onTap: () => _rateFlashcard(0)),
              _SelfRate(
                  label: '模糊',
                  icon: Icons.sentiment_neutral,
                  color: Colors.amber.shade700,
                  onTap: () => _rateFlashcard(1)),
              _SelfRate(
                  label: '记得',
                  icon: Icons.sentiment_satisfied_alt,
                  color: Colors.green.shade600,
                  onTap: () => _rateFlashcard(2)),
            ],
          )
        else
          Text(
            item.hint ?? '先回忆，点卡片看答案',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
      ],
    );
  }

  Widget _fcFront(FlashcardItem item) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('fc-front'),
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 260),
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Center(
        child: Text(
          item.front,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Widget _fcBack(FlashcardItem item) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('fc-back'),
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 260),
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Center(
        child: Text(
          item.back,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, height: 1.5),
        ),
      ),
    );
  }

  Widget _buildQuiz(QuizItem item) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          item.prompt,
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontSize: 20, fontWeight: FontWeight.w700, height: 1.4),
        ),
        const SizedBox(height: 24),
        for (var i = 0; i < item.options.length; i++) ...[
          _QuizOption(
            label: String.fromCharCode(0x41 + i),
            text: item.options[i],
            state: _selected == null
                ? _QuizOptionState.none
                : i == item.answerIndex
                    ? _QuizOptionState.correct
                    : i == _selected
                        ? _QuizOptionState.wrong
                        : _QuizOptionState.none,
            onTap: () => _pickQuiz(i),
          ),
          if (i < item.options.length - 1) const SizedBox(height: 10),
        ],
        if (_selected != null && item.explanation != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              item.explanation!,
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
          ),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _selected == null ? null : _nextQuiz,
          child: const Text('下一题'),
        ),
      ],
    );
  }

  Widget _buildCloze(ClozeItem item) {
    final scheme = Theme.of(context).colorScheme;
    final indexByBlank = {
      for (var i = 0; i < _clozeBlanks.length; i++) _clozeBlanks[i]: i,
    };
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.title,
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w700),
            ),
            if (item.subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                '【${item.subtitle}】',
                style: TextStyle(
                    fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 20),
            for (var li = 0; li < item.lines.length; li++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ClozeLine(
                  text: item.lines[li],
                  blanks:
                      _clozeBlanks.where((b) => b.lineIndex == li).toList(),
                  checked: _clozeChecked,
                  ctrls: _blankCtrls,
                  indexByBlank: indexByBlank,
                  lines: item.lines,
                ),
              ),
            const SizedBox(height: 8),
            Text(
              _clozeChecked
                  ? '本首答对 $_clozeCorrect/${_clozeBlanks.length}'
                  : '在划线处补全（${_clozeBlanks.length} 处）',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: _clozeChecked
                  ? FilledButton.icon(
                      onPressed: _clozeToScore,
                      icon: const Icon(Icons.skip_next, size: 20),
                      label: const Text('下一首'),
                    )
                  : FilledButton.icon(
                      onPressed: _checkCloze,
                      icon: const Icon(Icons.check, size: 20),
                      label: const Text('检查'),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompletion() {
    final total = _items.length;
    final avg = total == 0 ? 0.0 : _score / total;
    final pct = (avg / 2 * 100).clamp(0, 100).toStringAsFixed(0);
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
                '已完成',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                '「${_plugin.name}」共 $total 项 · 得分 $_score · 正确率 $pct%',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _restart,
                icon: const Icon(Icons.replay),
                label: const Text('再来一轮'),
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

/// 翻卡自评按钮。
class _SelfRate extends StatelessWidget {
  const _SelfRate({
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
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
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

enum _QuizOptionState { none, correct, wrong }

/// 单选选项。
class _QuizOption extends StatelessWidget {
  const _QuizOption({
    required this.label,
    required this.text,
    required this.state,
    required this.onTap,
  });

  final String label;
  final String text;
  final _QuizOptionState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Color border;
    final Color? bg;
    final Color? fg;
    switch (state) {
      case _QuizOptionState.none:
        border = scheme.outlineVariant;
        bg = null;
        fg = null;
      case _QuizOptionState.correct:
        border = Colors.green;
        bg = Colors.green.withValues(alpha: 0.1);
        fg = Colors.green.shade700;
      case _QuizOptionState.wrong:
        border = Colors.red;
        bg = Colors.red.withValues(alpha: 0.08);
        fg = Colors.red.shade700;
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: bg ?? scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border, width: 1.2),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 13,
              backgroundColor: state == _QuizOptionState.none
                  ? scheme.surfaceContainerHighest
                  : border,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: state == _QuizOptionState.none
                      ? scheme.onSurfaceVariant
                      : Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 15,
                  color: fg ?? scheme.onSurface,
                  fontWeight: state == _QuizOptionState.none
                      ? FontWeight.w400
                      : FontWeight.w600,
                ),
              ),
            ),
            if (state == _QuizOptionState.correct)
              const Icon(Icons.check_circle, color: Colors.green, size: 20)
            else if (state == _QuizOptionState.wrong)
              const Icon(Icons.cancel, color: Colors.red, size: 20),
          ],
        ),
      ),
    );
  }
}

/// 填空单行：文字片段 + 输入空位。
class _ClozeLine extends StatelessWidget {
  const _ClozeLine({
    required this.text,
    required this.blanks,
    required this.checked,
    required this.ctrls,
    required this.indexByBlank,
    required this.lines,
  });

  final String text;
  final List<PuzzleBlank> blanks;
  final bool checked;
  final List<TextEditingController> ctrls;
  final Map<PuzzleBlank, int> indexByBlank;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final segments = <Widget>[];
    var cursor = 0;
    for (final b in blanks) {
      if (b.start > cursor) {
        segments.add(Text(
          text.substring(cursor, b.start),
          style: const TextStyle(fontSize: 24, height: 1.4),
        ));
      }
      final idx = indexByBlank[b]!;
      segments.add(_BlankBox(
        blank: b,
        controller: ctrls[idx],
        checked: checked,
        lines: lines,
      ));
      cursor = b.start + b.length;
    }
    if (cursor < text.length) {
      segments.add(Text(
        text.substring(cursor),
        style: const TextStyle(fontSize: 24, height: 1.4),
      ));
    }
    return Wrap(
      spacing: 4,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: segments,
    );
  }
}

/// 挖空输入框（未检查可输入；检查后显示正误）。
class _BlankBox extends StatelessWidget {
  const _BlankBox({
    required this.blank,
    required this.controller,
    required this.checked,
    required this.lines,
  });

  final PuzzleBlank blank;
  final TextEditingController controller;
  final bool checked;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final answer = blank.answerIn(lines);
    final input = controller.text.trim();
    final correct = input == answer;
    final width = blank.length * 26.0 + 16;

    if (!checked) {
      return SizedBox(
        width: width,
        height: 44,
        child: TextField(
          controller: controller,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      );
    }
    return Tooltip(
      message: correct ? answer : '正确答案：$answer',
      child: Container(
        width: width,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: correct
              ? Colors.green.withValues(alpha: 0.14)
              : Colors.red.withValues(alpha: 0.12),
          border: Border.all(
            color: correct ? Colors.green : Colors.red,
            width: 1.2,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          correct ? answer : (input.isEmpty ? '×' : input),
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: correct ? Colors.green.shade700 : Colors.red.shade700,
          ),
        ),
      ),
    );
  }
}
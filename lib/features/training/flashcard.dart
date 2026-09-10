import 'package:flutter/material.dart';

/// 闪卡：先猜后看（正面 → 点按翻面 → 背面）。
/// 动效只做反馈不做表演：一次平滑的 3D 翻转。
class Flashcard extends StatefulWidget {
  const Flashcard({
    super.key,
    required this.front,
    required this.back,
    this.onFlip,
  });

  final Widget front;
  final Widget back;
  final VoidCallback? onFlip;

  @override
  State<Flashcard> createState() => _FlashcardState();
}

class _FlashcardState extends State<Flashcard> {
  bool _flipped = false;

  void _toggle() {
    setState(() => _flipped = !_flipped);
    widget.onFlip?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: _flipped ? '卡背面' : '卡正面，点按翻面',
      button: true,
      child: GestureDetector(
        onTap: _toggle,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: _flipped ? 1 : 0),
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOut,
          builder: (context, t, _) {
            final angle = t * 3.14159265;
            final showBack = t >= 0.5;
            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.001) // 透视
                ..rotateY(angle),
              child: showBack
                  ? Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()..rotateY(3.14159265),
                      child: widget.back,
                    )
                  : widget.front,
            );
          },
        ),
      ),
    );
  }
}

/// 卡面容器（正面/背面共用样式）。
class CardFace extends StatelessWidget {
  const CardFace({
    super.key,
    required this.child,
    this.hint,
  });

  final Widget child;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 320),
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        // iOS 卡片：白色浮层 + 大圆角 + 轻微阴影，无边框
        color: scheme.surface,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(child: Center(child: SingleChildScrollView(child: child))),
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                hint!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ),
        ],
      ),
    );
  }
}

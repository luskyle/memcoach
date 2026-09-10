import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../providers.dart';
import 'home_shell.dart' show kTabCommunity, kTabTraining;

/// iOS 风格侧边栏（HIG Sidebar）：大标题 + 主导航 + 底部设置。
///
/// 宽屏（桌面）专用；窄屏走底部 Tab，不渲染本组件。
class DesktopSidebar extends ConsumerWidget {
  const DesktopSidebar({
    super.key,
    required this.activeTab,
    required this.onSelectTab,
  });

  final int activeTab;
  final ValueChanged<int> onSelectTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final overview = ref.watch(reviewOverviewProvider);
    final due = overview.maybeWhen(data: (o) => o.due, orElse: () => 0);

    return Material(
      color: scheme.surface,
      child: SafeArea(
        child: SizedBox(
          width: 280,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 16, 6),
                child: Text(
                  'Memcoach',
                  style: Theme.of(context)
                      .textTheme
                      .displayMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 10),
              _SidebarGroup(
                children: [
                  _SidebarRow(
                    icon: Icons.fitness_center,
                    label: '训练',
                    badge: due,
                    selected: activeTab == kTabTraining,
                    onTap: () => onSelectTab(kTabTraining),
                  ),
                  _SidebarRow(
                    icon: Icons.explore,
                    label: '社区',
                    selected: activeTab == kTabCommunity,
                    onTap: () => onSelectTab(kTabCommunity),
                  ),
                ],
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

/// 分组容器（iOS inset grouped：圆角分组卡片）。
class _SidebarGroup extends StatelessWidget {
  const _SidebarGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Divider(
                height: 0.5,
                indent: 50,
                color: scheme.outlineVariant.withValues(alpha: 0.6),
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// 导航行：系统图标 + 标签 + 徽标；选中态：蓝色文字 + 圆角高亮。
class _SidebarRow extends StatelessWidget {
  const _SidebarRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.badge = 0,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? AppTheme.systemBlue : scheme.onSurface;
    return Material(
      color: selected
          ? AppTheme.systemBlue.withValues(alpha: 0.12)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: color,
                  ),
                ),
              ),
              if (badge > 0)
                Text(
                  '$badge',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
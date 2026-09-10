import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/analytics/analytics_service.dart';
import '../../providers.dart';
import '../community/community_screen.dart';
import '../settings/settings_screen.dart';
import '../training/curve_screen.dart';
import '../training/training_screen.dart';
import 'desktop_sidebar.dart';

/// 当前 Tab（默认落点 = 训练页）。
final homeTabIndexProvider = StateProvider<int>((ref) => 0);

/// Tab 含义：0=训练，1=社区。
const kTabTraining = 0;
const kTabCommunity = 1;

/// 外壳：响应式布局。
///
/// - 宽屏（>= 900，桌面）：左侧侧栏 + 内容区（IndexedStack 保状态）
/// - 窄屏（移动）：底部两 Tab（训练 / 社区）
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell>
    with WidgetsBindingObserver {
  static const _titles = ['训练', '社区'];
  static const _wideBreakpoint = 900.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ref.read(analyticsProvider).track(AnalyticsEvents.appOpen);
    // 词库引导：载入词库资产（内存索引 + words 表），失败静默
    ref.read(dictionaryBootstrapProvider.future).catchError((_) {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final analytics = ref.read(analyticsProvider);
    switch (state) {
      case AppLifecycleState.resumed:
        analytics.track(AnalyticsEvents.appResume);
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        analytics.track(AnalyticsEvents.appBackground);
      case AppLifecycleState.detached:
        break;
    }
  }

  void _trackTab(int index) {
    ref.read(analyticsProvider).track(
      AnalyticsEvents.appTabViewed,
      props: {'tab': index},
    );
  }

  @override
  Widget build(BuildContext context) {
    final tabIndex = ref.watch(homeTabIndexProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= _wideBreakpoint) {
          return _buildWide(context, tabIndex);
        }
        return _buildNarrow(context, tabIndex);
      },
    );
  }

  // ---- 宽屏（侧栏）----

  Widget _buildWide(BuildContext context, int tabIndex) {
    return Scaffold(
      body: Row(
        children: [
          DesktopSidebar(
            activeTab: tabIndex,
            onSelectTab: (i) {
              _trackTab(i);
              ref.read(homeTabIndexProvider.notifier).state = i;
            },
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              children: [
                _buildTopBar(context, tabIndex),
                const Divider(height: 1),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1280),
                      child: IndexedStack(
                        index: tabIndex,
                        children: [
                          TrainingScreen(active: tabIndex == kTabTraining),
                          CommunityScreen(active: tabIndex == kTabCommunity),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, int tabIndex) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Text(
            _titles[tabIndex],
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          if (tabIndex == kTabTraining)
            IconButton(
              tooltip: '遗忘曲线',
              icon: const Icon(Icons.show_chart),
              onPressed: _openCurve,
            ),
          // 设置常驻顶栏：任何页面都可直接进入
          IconButton(
            tooltip: '设置',
            icon: const Icon(Icons.settings_outlined),
            onPressed: _openSettings,
          ),
        ],
      ),
    );
  }

  // ---- 窄屏（移动 Tab）----

  Widget _buildNarrow(BuildContext context, int tabIndex) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[tabIndex]),
        actions: [
          if (tabIndex == kTabTraining)
            IconButton(
              tooltip: '遗忘曲线',
              icon: const Icon(Icons.show_chart),
              onPressed: _openCurve,
            ),
          // 设置常驻顶栏：任何页面都可直接进入
          IconButton(
            tooltip: '设置',
            icon: const Icon(Icons.settings_outlined),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: IndexedStack(
        index: tabIndex,
        children: [
          TrainingScreen(active: tabIndex == kTabTraining),
          CommunityScreen(active: tabIndex == kTabCommunity),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tabIndex,
        onDestinationSelected: (i) {
          _trackTab(i);
          ref.read(homeTabIndexProvider.notifier).state = i;
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.fitness_center_outlined),
            selectedIcon: Icon(Icons.fitness_center),
            label: '训练',
          ),
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore),
            label: '社区',
          ),
        ],
      ),
    );
  }

  void _openCurve() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CurveScreen()),
    );
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }
}
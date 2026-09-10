import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/analytics/analytics_service.dart';
import '../../providers.dart';
import '../library/library_screen.dart';
import '../memory/memory_manager_screen.dart';
import '../review/curve_screen.dart';
import '../review/review_screen.dart';
import '../settings/settings_screen.dart';
import '../study/study_screen.dart';
import 'desktop_sidebar.dart';

/// 当前 Tab（默认落点 = 复习页，见设计原则 2）。
final homeTabIndexProvider = StateProvider<int>((ref) => 0);

/// Tab 含义：0=今日复习，1=记忆库（卡片库），2=学习，3=记忆管理（宽屏侧栏）。
const kTabReview = 0;
const kTabLibrary = 1;
const kTabStudy = 2;
const kTabMemory = 3;

/// 外壳：Cubox 式响应式布局。
///
/// - 宽屏（>= 900，桌面）：左侧侧栏 + 顶栏搜索 + 内容区（IndexedStack 保状态）
/// - 窄屏（移动）：底部三 Tab（复习 / 记忆库 / 学习）
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell>
    with WidgetsBindingObserver {
  static const _titles = ['今日复习', '记忆库', '学习', '记忆管理'];
  static const _wideBreakpoint = 900.0;

  /// 顶栏全局搜索框控制器（宽屏）。
  final _searchCtrl = TextEditingController();

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
    _searchCtrl.dispose();
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

  // ---- 宽屏（Cubox 式）----

  Widget _buildWide(BuildContext context, int tabIndex) {
    return PopScope(
      canPop: tabIndex < kTabMemory,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && tabIndex >= kTabMemory) {
          ref.read(homeTabIndexProvider.notifier).state = kTabReview;
        }
      },
      child: Scaffold(
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
                  if (tabIndex < kTabMemory) ...[
                    _buildTopBar(context, tabIndex),
                    const Divider(height: 1),
                  ],
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1280),
                        child: IndexedStack(
                          index: tabIndex,
                          children: [
                            ReviewScreen(active: tabIndex == kTabReview),
                            LibraryScreen(active: tabIndex == kTabLibrary),
                            StudyScreen(active: tabIndex == kTabStudy),
                            const MemoryManagerScreen(),
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
          SizedBox(
            width: 320,
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: '搜索卡片库…',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchCtrl.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          ref.read(libraryFilterProvider.notifier).state = ref
                              .read(libraryFilterProvider)
                              .copyWith(search: '');
                        },
                      ),
                isDense: true,
                filled: true,
                fillColor:
                    scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
              onChanged: (v) {
                // 输入即切到记忆库并搜索
                if (tabIndex != kTabLibrary) {
                  ref.read(homeTabIndexProvider.notifier).state = kTabLibrary;
                }
                ref.read(libraryFilterProvider.notifier).state =
                    ref.read(libraryFilterProvider).copyWith(search: v);
              },
            ),
          ),
          const Spacer(),
          if (tabIndex == kTabReview)
            IconButton(
              tooltip: '遗忘曲线',
              icon: const Icon(Icons.show_chart),
              onPressed: () => _openCurve(),
            ),
          // 设置常驻顶栏：任何页面都可直接进入
          IconButton(
            tooltip: '设置',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => _openSettings(),
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
          // 分类入口：任何页面都可直接选分组查看内容
          IconButton(
            tooltip: '分类',
            icon: const Icon(Icons.folder_outlined),
            onPressed: () => _openCollectionPicker(),
          ),
          if (tabIndex == kTabReview)
            IconButton(
              tooltip: '遗忘曲线',
              icon: const Icon(Icons.show_chart),
              onPressed: () => _openCurve(),
            ),
          // 设置常驻顶栏：任何页面都可直接进入
          IconButton(
            tooltip: '设置',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => _openSettings(),
          ),
        ],
      ),
      body: IndexedStack(
        // 窄屏只有 0/1/2 三个内容页；从宽屏记忆管理页缩窄时夹到学习页
        index: tabIndex >= kTabStudy ? kTabStudy : tabIndex,
        children: [
          ReviewScreen(active: tabIndex == kTabReview),
          LibraryScreen(active: tabIndex == kTabLibrary),
          StudyScreen(active: tabIndex == kTabStudy),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tabIndex < kTabStudy ? tabIndex : tabIndex - 1,
        onDestinationSelected: (i) {
          final target = i;
          _trackTab(target);
          ref.read(homeTabIndexProvider.notifier).state = target;
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.school_outlined),
            selectedIcon: Icon(Icons.school),
            label: '复习',
          ),
          NavigationDestination(
            icon: Icon(Icons.collections_bookmark_outlined),
            selectedIcon: Icon(Icons.collections_bookmark),
            label: '记忆库',
          ),
          NavigationDestination(
            icon: Icon(Icons.translate),
            selectedIcon: Icon(Icons.translate),
            label: '学习',
          ),
        ],
      ),
    );
  }

  /// 窄屏分类入口：弹分组选择，点选后进入该分组内容（tab 1）。
  Future<void> _openCollectionPicker() async {
    final cols = await ref.read(itemRepositoryProvider).collections();
    if (!mounted) return;
    final res = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child:
                  Text('选择分组', style: Theme.of(context).textTheme.titleMedium),
            ),
            for (final c in cols)
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(c.name),
                onTap: () => Navigator.pop(context, '${c.id}'),
              ),
          ],
        ),
      ),
    );
    if (res != null) {
      final id = int.tryParse(res);
      ref.read(libraryFilterProvider.notifier).state =
          ref.read(libraryFilterProvider).withCollection(id);
      ref.read(homeTabIndexProvider.notifier).state = kTabLibrary;
    }
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
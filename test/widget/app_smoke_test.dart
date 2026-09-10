import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:memcoach/app.dart';
import 'package:memcoach/content/builtin_plugins.dart';
import 'package:memcoach/content/content_plugin.dart';
import 'package:memcoach/data/database/database.dart';
import 'package:memcoach/data/settings/settings_store.dart';
import 'package:memcoach/features/settings/settings_screen.dart';
import 'package:memcoach/providers.dart';

/// 测试用假目录：不读资产，避免 testWidgets 下 rootBundle 无法被 settle。
class _FakeTrainingSetSource implements TrainingSetSource {
  const _FakeTrainingSetSource();

  @override
  Future<List<ContentPlugin>> catalog() async => const [
        ContentPlugin(
          id: 'test.poetry',
          name: '古诗词',
          description: '经典古诗挖空',
          kind: ContentKind.cloze,
          items: [],
        ),
        ContentPlugin(
          id: 'test.quiz',
          name: '趣味常识',
          description: '常识单选',
          kind: ContentKind.quiz,
          items: [],
        ),
      ];
}

/// 测试环境公共搭建：内存库。
Future<ProviderContainer> buildTestContainer() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      databaseProvider.overrideWithValue(AppDatabase.forTesting()),
      sharedPrefsProvider.overrideWithValue(prefs),
      settingsProvider.overrideWithValue(SettingsStore(prefs)),
      trainingSetSourceProvider.overrideWithValue(
        const _FakeTrainingSetSource(),
      ),
    ],
  );
  // 触发一次数据库初始化
  container.read(databaseProvider);
  return container;
}

void main() {
  testWidgets('两 Tab 导航与默认训练页', (tester) async {
    final container = await buildTestContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MemcoachApp(),
      ),
    );
    await tester.pumpAndSettle();

    // 默认落点 = 训练页
    expect(find.text('先自评状态'), findsOneWidget);
    expect(find.text('开始训练'), findsNothing);
    expect(find.text('自我评估状态'), findsOneWidget);

    // 底部两 tab：切到社区
    await tester.tap(find.text('社区'));
    await tester.pumpAndSettle();
    expect(find.text('古诗词'), findsOneWidget); // 社区训练集目录
    expect(find.text('趣味常识'), findsOneWidget);
  });

  testWidgets('宽屏显示侧栏布局（训练/社区）', (tester) async {
    final container = await buildTestContainer();
    addTearDown(container.dispose);

    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MemcoachApp(),
      ),
    );
    await tester.pumpAndSettle();

    // 侧栏元素：大标题 / 导航
    expect(find.text('Memcoach'), findsOneWidget);
    expect(find.text('训练'), findsWidgets);
    expect(find.text('社区'), findsWidgets);

    // 窄屏底栏不再渲染
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('设置页可切换深色/浅色/跟随系统主题', (tester) async {
    final container = await buildTestContainer();
    addTearDown(container.dispose);

    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MemcoachApp(),
      ),
    );
    await tester.pumpAndSettle();

    // 默认跟随系统
    expect(container.read(themeModeProvider), ThemeMode.system);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('外观'), findsOneWidget);

    // 点亮「深色」→ provider + 持久化
    await tester.tap(find.text('深色'));
    await tester.pumpAndSettle();
    expect(container.read(themeModeProvider), ThemeMode.dark);
    expect(container.read(settingsProvider).themeMode, 'dark');

    // 切「浅色」
    await tester.tap(find.text('浅色'));
    await tester.pumpAndSettle();
    expect(container.read(themeModeProvider), ThemeMode.light);
    expect(container.read(settingsProvider).themeMode, 'light');
  });
}
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shiyi/app.dart';
import 'package:shiyi/data/database/database.dart';
import 'package:shiyi/data/settings/settings_store.dart';
import 'package:shiyi/features/settings/settings_screen.dart';
import 'package:shiyi/providers.dart';

/// 测试环境公共搭建：内存库。
Future<ProviderContainer> buildTestContainer() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      databaseProvider.overrideWithValue(AppDatabase.forTesting()),
      sharedPrefsProvider.overrideWithValue(prefs),
      settingsProvider.overrideWithValue(SettingsStore(prefs)),
    ],
  );
  // 触发一次数据库初始化（完成系统库种子）
  container.read(databaseProvider);
  return container;
}

void main() {
  testWidgets('三 Tab 导航与空态', (tester) async {
    final container = await buildTestContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MemcoachApp(),
      ),
    );
    await tester.pumpAndSettle();

    // 默认落点 = 复习页（设计原则 2）
    expect(find.text('今日复习'), findsOneWidget);
    expect(find.text('今天还没有复习任务'), findsOneWidget);

    // 底栏三主 tab：切到记忆库
    await tester.tap(find.text('记忆库'));
    await tester.pumpAndSettle();
    expect(find.text('卡片库还空着'), findsOneWidget);

    // 切到学习
    await tester.tap(find.text('学习'));
    await tester.pumpAndSettle();
    expect(find.text('日语'), findsWidgets); // 学习页语言包列表

    // 顶栏分类按钮 → 弹分组选择 → 进入分组内容
    await tester.tap(find.byIcon(Icons.folder_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('工作'));
    await tester.pumpAndSettle();
    expect(find.text('「工作」还空着'), findsOneWidget);
  });

  testWidgets('空库时复习页显示引导，且不显示开始按钮', (tester) async {
    final container = await buildTestContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MemcoachApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, '开始复习'), findsNothing);
    expect(find.text('今天还没有复习任务'), findsOneWidget);
  });

  testWidgets('宽屏显示 Cubox 式侧栏布局', (tester) async {
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

    // iOS 侧栏元素：大标题 / 导航 / 分组
    expect(find.text('Memcoach'), findsOneWidget);
    expect(find.text('今日复习'), findsOneWidget);
    expect(find.text('分组'), findsOneWidget);

    // 窄屏底栏不再渲染
    expect(find.byType(NavigationBar), findsNothing);
    // 仍显示复习页默认落点内容
    expect(find.text('今天还没有复习任务'), findsOneWidget);

    // 侧栏分组 → 分组内容（宽屏）
    await tester.tap(find.text('工作'));
    await tester.pumpAndSettle();
    expect(find.text('「工作」还空着'), findsOneWidget);
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

    // 进入设置（侧栏底部设置入口 → 这里通过 Provider 容器直接推到设置页较复杂，
    // 改为验证设置页组件可独立渲染并切换）
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
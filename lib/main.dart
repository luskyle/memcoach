import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'data/analytics/analytics_service.dart';
import 'data/settings/settings_store.dart';
import 'providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  // 埋点落盘目录（平台不可用时降级为内存缓冲，不影响主流程）
  AnalyticsService? analytics;
  try {
    final docs = await getApplicationDocumentsDirectory();
    analytics = AnalyticsService(
      directory: Directory(p.join(docs.path, 'museum', 'analytics')),
    );
  } catch (_) {}

  runApp(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        settingsProvider.overrideWithValue(SettingsStore(prefs)),
        if (analytics != null) analyticsProvider.overrideWithValue(analytics),
      ],
      child: const MemcoachApp(),
    ),
  );
}

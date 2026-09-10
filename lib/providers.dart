import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'content/builtin_plugins.dart';
import 'content/content_plugin.dart';
import 'data/analytics/analytics_service.dart';
import 'data/database/database.dart';
import 'data/dictionary/dictionary_service.dart';
import 'data/repositories/item_repository.dart';
import 'data/repositories/review_repository.dart';
import 'data/repositories/training_set_repository.dart';
import 'data/settings/settings_store.dart';
import 'data/speech/speech_service.dart';
import 'domain/srs/sm2.dart';
import 'domain/tagging/language.dart';
import 'domain/training.dart';

/// 数据库（测试中可 override 为内存库）。
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase.open();
  ref.onDispose(db.close);
  return db;
});

/// 发音服务（系统 TTS）。
final speechServiceProvider = Provider<SpeechService>((ref) {
  return SpeechService();
});

/// 埋点服务（本地 JSONL 记录 + 上报占位）。
final analyticsProvider = Provider<AnalyticsService>((ref) {
  final svc = AnalyticsService();
  ref.onDispose(svc.dispose);
  return svc;
});

/// 设置存储（测试中可 override）。
final settingsProvider = Provider<SettingsStore>((ref) {
  throw UnimplementedError('settingsProvider must be overridden in tests or '
      'initialized in main() via settingsStoreProvider');
});

/// 由 main() 注入的 SharedPreferences 实例。
final sharedPrefsProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPrefsProvider must be overridden in main()');
});

final itemRepositoryProvider = Provider<ItemRepository>((ref) {
  return ItemRepository(ref.watch(databaseProvider));
});

final trainingSetRepositoryProvider = Provider<TrainingSetRepository>((ref) {
  return TrainingSetRepository(ref.watch(databaseProvider));
});

final reviewRepositoryProvider = Provider<ReviewRepository>((ref) {
  return ReviewRepository(ref.watch(databaseProvider));
});

final dictionaryServiceProvider = Provider<DictionaryService>((ref) {
  return DictionaryService();
});

/// 词库引导：载入词库资产到内存索引 + 批量导入 words 表 + 旧数据对账，
/// 启动时执行一次。
final dictionaryBootstrapProvider = FutureProvider<void>((ref) async {
  final svc = ref.read(dictionaryServiceProvider);
  final repo = ref.read(itemRepositoryProvider);
  try {
    await svc.loadFromAsset();
    await repo.importDictionaryEntries(svc.loadedEntries);
    await repo.upgradeLegacyInbox();
  } catch (_) {
    // 词库不可用不影响核心流程（样例词库兜底）
  }
});

// ---------------------------------------------------------------------------
// 训练集（社区 / 训练）
// ---------------------------------------------------------------------------

/// 社区训练集目录（内置来源；远程来源预留扩展）。
final trainingSetSourceProvider = Provider<TrainingSetSource>((ref) {
  return const BuiltinTrainingSetSource();
});

/// 目录全部训练集。
final trainingSetCatalogProvider = FutureProvider<List<ContentPlugin>>((ref) {
  return ref.watch(trainingSetSourceProvider).catalog();
});

/// 已下载（安装）训练集 id 集合。
final installedTrainingSetIdsProvider = FutureProvider<Set<String>>((ref) {
  return ref.watch(trainingSetRepositoryProvider).installedIds();
});

/// 自评强度（null = 尚未自评；开训前必选）。
final trainingIntensityProvider = StateProvider<TrainingIntensity?>((ref) {
  return null;
});

// ---------------------------------------------------------------------------
// 训练统计
// ---------------------------------------------------------------------------

/// 今日到期复习卡。
final dueCardsProvider = FutureProvider<List<CardWithItem>>((ref) async {
  return ref.watch(reviewRepositoryProvider).dueCards();
});

/// 今日任务数 / 积压 / 已训练 / 掌握率（训练页头部数据）。
final reviewOverviewProvider = FutureProvider<ReviewOverview>((ref) async {
  final repo = ref.watch(reviewRepositoryProvider);
  final now = DateTime.now();
  final due = await repo.dueCount(now);
  final backlog = await repo.backlogCount(now);
  final reviewedToday = await repo.reviewsToday(now);
  final masterRatio = await repo.masterRatio();
  return ReviewOverview(
    due: due,
    backlog: backlog,
    reviewedToday: reviewedToday,
    masterRatio: masterRatio,
  );
});

class ReviewOverview {
  const ReviewOverview({
    required this.due,
    required this.backlog,
    required this.reviewedToday,
    required this.masterRatio,
  });

  final int due;
  final int backlog;
  final int reviewedToday;
  final double masterRatio;
}

/// 周视图曲线数据。
final weeklyStatsProvider = FutureProvider<List<WeeklyStat>>((ref) {
  return ref.watch(reviewRepositoryProvider).weeklyStats();
});

/// 训练热力图数据（每日次数，近 12 周）。
final reviewHeatmapProvider = FutureProvider<Map<DateTime, int>>((ref) {
  return ref.watch(reviewRepositoryProvider).dailyReviewCounts();
});

// ---------------------------------------------------------------------------
// 免费额度 / 订阅
// ---------------------------------------------------------------------------

class QuotaState {
  const QuotaState({
    required this.isPro,
    required this.libraryCards,
    required this.reviewsToday,
  });

  final bool isPro;
  final int libraryCards;
  final int reviewsToday;

  bool get libraryFull => !isPro && libraryCards >= Quota.maxLibraryCards;

  bool get dailyReviewFull => false; // 已移除每日复习次数限制
}

final quotaProvider = FutureProvider<QuotaState>((ref) async {
  final settings = ref.watch(settingsProvider);
  final itemRepo = ref.watch(itemRepositoryProvider);
  final reviewRepo = ref.watch(reviewRepositoryProvider);
  final now = DateTime.now();
  final results = await Future.wait<int>([
    itemRepo.cardCount(),
    reviewRepo.reviewsToday(now),
  ]);
  return QuotaState(
    isPro: settings.isPro,
    libraryCards: results[0],
    reviewsToday: results[1],
  );
});

// ---------------------------------------------------------------------------
// 主题
// ---------------------------------------------------------------------------

/// 主题模式（UI 状态：system / light / dark；随设置持久化）。
final themeModeProvider = StateProvider<ThemeMode>((ref) {
  final raw = ref.watch(settingsProvider).themeMode;
  return switch (raw) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };
});

// ---------------------------------------------------------------------------
// 语言标签帮助函数
// ---------------------------------------------------------------------------

String languageLabel(ContentLang lang) {
  return switch (lang) {
    ContentLang.ja => '日语',
    ContentLang.zh => '中文',
    ContentLang.en => '英语',
    ContentLang.other => '其他',
  };
}

/// 中文状态文案（列表徽标用）。
String statusLabel(String status) {
  return switch (status) {
    'learning' => '学习中',
    'mastered' => '已掌握',
    'cold' => '冷置',
    'inbox' => '待归类',
    _ => status,
  };
}

Color statusColor(String status) {
  return switch (status) {
    'learning' => Colors.teal,
    'mastered' => Colors.green,
    'cold' => Colors.orange,
    'inbox' => Colors.blueGrey,
    _ => Colors.blueGrey,
  };
}

/// 三键评级 UI 文案。
String ratingLabel(ReviewRating r) {
  return switch (r) {
    ReviewRating.forgot => '忘了',
    ReviewRating.fuzzy => '模糊',
    ReviewRating.remembered => '记得',
  };
}
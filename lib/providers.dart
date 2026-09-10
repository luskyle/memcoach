import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/analytics/analytics_service.dart';
import 'data/database/database.dart';
import 'data/dictionary/dictionary_service.dart';
import 'data/repositories/item_repository.dart';
import 'data/repositories/memory_set_repository.dart';
import 'data/repositories/review_repository.dart';
import 'data/settings/settings_store.dart';
import 'data/speech/speech_service.dart';
import 'domain/srs/sm2.dart';
import 'domain/tagging/language.dart';

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

/// 记忆集仓储（记忆教练：自建复习集合）。
final memorySetRepositoryProvider = Provider<MemorySetRepository>((ref) {
  return MemorySetRepository(
    ref.watch(databaseProvider),
    items: ref.watch(itemRepositoryProvider),
  );
});

/// 记忆集列表（新在前）。
final memorySetsProvider = FutureProvider<List<MemorySetRow>>((ref) {
  return ref.watch(memorySetRepositoryProvider).all();
});

/// 记忆集详情（含条目），按 id 缓存。
final memorySetDetailProvider =
    FutureProvider.autoDispose.family<MemorySetWithItems, int>((ref, setId) {
  return ref.watch(memorySetRepositoryProvider).detail(setId);
});

final reviewRepositoryProvider = Provider<ReviewRepository>((ref) {
  return ReviewRepository(ref.watch(databaseProvider));
});

final dictionaryServiceProvider = Provider<DictionaryService>((ref) {
  return DictionaryService();
});

/// 词库引导：载入词库资产到内存索引 + 批量导入 words 表 + 数据对账
/// （默认分类补齐、遗留收件箱条目升级），启动时执行一次。
final dictionaryBootstrapProvider = FutureProvider<void>((ref) async {
  final svc = ref.read(dictionaryServiceProvider);
  final repo = ref.read(itemRepositoryProvider);
  try {
    await svc.loadFromAsset();
    await repo.importDictionaryEntries(svc.loadedEntries);
    await ref.read(databaseProvider).ensureDefaultCollections();
    await repo.upgradeLegacyInbox();
  } catch (_) {
    // 词库不可用不影响核心流程（样例词库兜底）
  }
});

// ---------------------------------------------------------------------------
// 收件箱 / 记忆库
// ---------------------------------------------------------------------------

/// 记忆库筛选参数。
class LibraryFilter {
  const LibraryFilter(
      {this.search = '', this.lang, this.status, this.collectionId});

  final String search;
  final String? lang;
  final String? status;

  /// 按库（主库）过滤，null = 全部。
  final int? collectionId;

  LibraryFilter copyWith(
      {String? search, String? lang, String? status, int? collectionId}) {
    return LibraryFilter(
      search: search ?? this.search,
      lang: lang ?? this.lang,
      status: status ?? this.status,
      collectionId: collectionId ?? this.collectionId,
    );
  }

  /// 切换语言筛选（再点一次取消）。
  LibraryFilter toggleLang(String l) {
    return LibraryFilter(
      search: search,
      lang: lang == l ? null : l,
      status: status,
      collectionId: collectionId,
    );
  }

  /// 切到指定分组（null = 全部）。
  LibraryFilter withCollection(int? id) {
    return LibraryFilter(
      search: search,
      lang: lang,
      status: status,
      collectionId: id,
    );
  }

  /// 清空（切回"全部"视图）。
  LibraryFilter reset() => const LibraryFilter();

  @override
  bool operator ==(Object other) =>
      other is LibraryFilter &&
      other.search == search &&
      other.lang == lang &&
      other.status == status &&
      other.collectionId == collectionId;

  @override
  int get hashCode => Object.hash(search, lang, status, collectionId);
}

final libraryFilterProvider = StateProvider<LibraryFilter>((ref) {
  return const LibraryFilter();
});

/// 记忆库视图模式：list | grid（初始自设置，切换时持久化）。
final libraryViewModeProvider = StateProvider<String>((ref) {
  return ref.watch(settingsProvider).libraryViewMode;
});

final libraryItemsProvider = StreamProvider<List<ItemWithCard>>((ref) {
  final filter = ref.watch(libraryFilterProvider);
  return ref.watch(itemRepositoryProvider).watchLibrary(
        search: filter.search,
        lang: filter.lang,
        status: filter.status,
        collectionId: filter.collectionId,
      );
});

final collectionsProvider = FutureProvider<List<CollectionRow>>((ref) {
  return ref.watch(itemRepositoryProvider).collections();
});

/// 条目-库 多对多关系流（记忆库分组用）。
final itemCollectionLinksProvider =
    StreamProvider<List<ItemCollectionRow>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.select(db.itemCollections).watch();
});

final collectionStatsProvider =
    FutureProvider<Map<int, ({int total, int mastered})>>((ref) {
  return ref.watch(itemRepositoryProvider).collectionStats();
});

// ---------------------------------------------------------------------------
// 复习
// ---------------------------------------------------------------------------

/// 今日复习任务卡片（到期队列）。
final dueCardsProvider = FutureProvider<List<CardWithItem>>((ref) async {
  return ref.watch(reviewRepositoryProvider).dueCards();
});

/// 今日任务数 / 积压 / 已复习 / 掌握率（复习页头部数据）。
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

/// 复习热力图数据（每日次数，近 12 周）。
final reviewHeatmapProvider = FutureProvider<Map<DateTime, int>>((ref) {
  return ref.watch(reviewRepositoryProvider).dailyReviewCounts();
});

/// 学习产生的卡片数（按语言，默认页学习情况）。
final learnedByLangProvider = FutureProvider<Map<String, int>>((ref) {
  return ref.watch(itemRepositoryProvider).learnedCountByLang();
});

/// 今日复习进度（已答/总数），复习会话开始时建立。
final reviewSessionProvider = StateProvider<ReviewSessionState?>((ref) => null);

class ReviewSessionState {
  const ReviewSessionState({
    required this.total,
    required this.answered,
    required this.qualitySum,
  });

  final int total;
  final int answered;
  final int qualitySum;
}

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
    'inbox' => '待归类',
    'learning' => '学习中',
    'mastered' => '已掌握',
    'cold' => '冷置',
    _ => status,
  };
}

Color statusColor(String status) {
  return switch (status) {
    'inbox' => Colors.blueGrey,
    'learning' => Colors.teal,
    'mastered' => Colors.green,
    'cold' => Colors.orange,
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

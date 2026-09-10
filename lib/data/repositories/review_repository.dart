import 'package:drift/drift.dart';

import '../../domain/srs/sm2.dart';
import '../../domain/training.dart';
import '../database/database.dart';
import 'item_repository.dart';

/// 周视图统计点（遗忘曲线数据源，由 review_log 派生）。
class WeeklyStat {
  const WeeklyStat({
    required this.weekStart,
    required this.reviews,
    required this.avgQuality,
    required this.correctRatio,
  });

  final DateTime weekStart;
  final int reviews;
  final double avgQuality;

  /// 正确率（quality >= 3 占比），0~1。
  final double correctRatio;
}

/// 学习域仓储：SRS 调度落库、复习队列、统计投影。
class ReviewRepository {
  ReviewRepository(this.db);

  final AppDatabase db;

  /// 到期复习卡：dueAt <= now（含积压），按到期时间升序，封顶 [limit]。
  Future<List<CardWithItem>> dueCards({
    DateTime? now,
    int limit = 200,
  }) async {
    final ts = now ?? DateTime.now();
    final q = db.select(db.cards).join([
      innerJoin(db.items, db.items.cardId.equalsExp(db.cards.id)),
    ])
      ..where(db.items.cardId.isNotNull() &
          db.cards.dueAt.isSmallerOrEqualValue(ts))
      ..orderBy([OrderingTerm.asc(db.cards.dueAt)])
      ..limit(limit);
    final rows = await q.get();
    return rows
        .map((r) => CardWithItem(
              card: r.readTable(db.cards),
              item: r.readTable(db.items),
            ))
        .toList();
  }

  /// 新卡：尚未训练过（lastReviewedAt 为空）且未到期（dueAt 在未来），
  /// 按创建时间升序。训练会话据此引入下载训练集的新内容，
  /// 与「到期复习卡」互斥，避免同卡重复入队。
  Future<List<CardWithItem>> newCards({
    DateTime? now,
    int limit = 30,
  }) async {
    final ts = now ?? DateTime.now();
    final q = db.select(db.cards).join([
      innerJoin(db.items, db.items.cardId.equalsExp(db.cards.id)),
    ])
      ..where(db.cards.lastReviewedAt.isNull() &
          db.cards.dueAt.isBiggerThanValue(ts))
      ..orderBy([OrderingTerm.asc(db.cards.createdAt)])
      ..limit(limit);
    final rows = await q.get();
    return rows
        .map((r) => CardWithItem(
              card: r.readTable(db.cards),
              item: r.readTable(db.items),
            ))
        .toList();
  }

  /// 今日任务数 = 到期卡数。
  Future<int> dueCount(DateTime? now) async =>
      (await dueCards(now: now)).length;

  /// 积压 = 超过自己 1 个 SRS 间隔仍未复习（防囤积提示）。
  Future<int> backlogCount(DateTime? now) async {
    final ts = now ?? DateTime.now();
    final cards = await dueCards(now: ts, limit: 500);
    return cards
        .where((c) => ts.difference(c.card.dueAt).inDays > c.card.intervalDays)
        .length;
  }

  /// 今日已复习次数（免费额度判定）。
  Future<int> reviewsToday(DateTime? now) async {
    final ts = now ?? DateTime.now();
    final start = DateTime(ts.year, ts.month, ts.day);
    final query = db.selectOnly(db.reviewLogs)
      ..addColumns([countAll()])
      ..where(db.reviewLogs.reviewedAt.isBiggerOrEqualValue(start) &
          db.reviewLogs.reviewedAt
              .isSmallerThanValue(start.add(const Duration(days: 1))));
    final row = await query.getSingle();
    return row.read(countAll()) ?? 0;
  }

  /// 一次评级落库：SM-2 更新 + 追加 review_log（append-only）+ 条目状态投影刷新。
  ///
  /// [intervalMultiplier]：训练强度带来的间隔增幅（>1 更快，<1 更保守）。
  Future<void> reviewCard({
    required int cardId,
    required ReviewRating rating,
    double intervalMultiplier = 1.0,
    DateTime? now,
  }) async {
    final ts = now ?? DateTime.now();
    final quality = sm2QualityFor(rating);

    final card = await (db.select(db.cards)..where((t) => t.id.equals(cardId)))
        .getSingleOrNull();
    if (card == null) throw StateError('card not found: $cardId');

    // 复习前状态（learning | review | relearning）
    final preState = card.repetitions == 0
        ? 'learning'
        : (quality >= 3 ? 'review' : 'relearning');

    final result = sm2Review(
      Sm2State(
        repetitions: card.repetitions,
        easeFactor: card.easeFactor,
        intervalDays: card.intervalDays,
      ),
      quality,
      now: ts,
    );

    // 强度增幅作用于间隔（不影响 EF 与重复次数）
    final intervalDays =
        applyIntervalMultiplier(result.state.intervalDays, intervalMultiplier);
    final dueAt = ts.add(Duration(days: intervalDays));

    await (db.update(db.cards)..where((t) => t.id.equals(cardId))).write(
      CardsCompanion(
        repetitions: Value(result.state.repetitions),
        easeFactor: Value(result.state.easeFactor),
        intervalDays: Value(intervalDays),
        dueAt: Value(dueAt),
        lastReviewedAt: Value(ts),
      ),
    );

    await db.into(db.reviewLogs).insert(
          ReviewLogsCompanion.insert(
            cardId: cardId,
            reviewedAt: ts,
            quality: quality,
            intervalDays: intervalDays,
            easeFactor: result.state.easeFactor,
            state: preState,
          ),
        );

    // 条目状态投影刷新（mastered / cold / learning）
    final state = result.state.copyWith(intervalDays: intervalDays);
    final newStatus = _projectStatus(state, lastReviewedAt: ts, now: ts);
    final itemRows = await (db.select(db.items)
          ..where((t) => t.cardId.equals(cardId)))
        .get();
    for (final it in itemRows) {
      await (db.update(db.items)..where((t) => t.id.equals(it.id)))
          .write(ItemsCompanion(status: Value(newStatus)));
    }
    assert(itemRows.isNotEmpty, 'card has no item (unreachable)');
  }

  /// 状态投影（依据《记忆教练App架构》§五：状态从数据派生，实时计算）。
  String _projectStatus(Sm2State state,
      {required DateTime lastReviewedAt, required DateTime now}) {
    if (isMastered(state)) return 'mastered';
    if (isCold(lastReviewedAt: lastReviewedAt, now: now)) return 'cold';
    return 'learning';
  }

  /// 周视图统计（近 [weeks] 周）：个人正确率 + 复习量 + 平均质量。
  Future<List<WeeklyStat>> weeklyStats({int weeks = 8, DateTime? now}) async {
    final ts = now ?? DateTime.now();
    final monday = _startOfWeek(ts);
    final from = monday.subtract(Duration(days: 7 * (weeks - 1)));

    final logs = await (db.select(db.reviewLogs)
          ..where((t) => t.reviewedAt.isBiggerOrEqualValue(from)))
        .get();

    final buckets = <DateTime, List<ReviewLogRow>>{};
    for (final log in logs) {
      final weekStart = _startOfWeek(log.reviewedAt);
      buckets.putIfAbsent(weekStart, () => []).add(log);
    }

    return List.generate(weeks, (i) {
      final start = from.add(Duration(days: 7 * i));
      final bucket = buckets[start] ?? const <ReviewLogRow>[];
      if (bucket.isEmpty) {
        return WeeklyStat(
            weekStart: start, reviews: 0, avgQuality: 0, correctRatio: 0);
      }
      final sum = bucket.fold<int>(0, (acc, l) => acc + l.quality);
      final correct = bucket.where((l) => l.quality >= 3).length;
      return WeeklyStat(
        weekStart: start,
        reviews: bucket.length,
        avgQuality: sum / bucket.length,
        correctRatio: correct / bucket.length,
      );
    });
  }

  /// 掌握率（成卡条目中 mastered 占比）。
  Future<double> masterRatio() async {
    final query = db.selectOnly(db.items)
      ..addColumns([countAll()])
      ..where(db.items.cardId.isNotNull());
    final total = (await query.getSingle()).read(countAll()) ?? 0;
    if (total == 0) return 0;

    final mastered = db.selectOnly(db.items)
      ..addColumns([countAll()])
      ..where(db.items.cardId.isNotNull() & db.items.status.equals('mastered'));
    final m = (await mastered.getSingle()).read(countAll()) ?? 0;
    return m / total;
  }

  /// 每日复习次数（热力图数据源，review_log 投影）。
  Future<Map<DateTime, int>> dailyReviewCounts({
    DateTime? now,
    int weeks = 12,
  }) async {
    final ts = now ?? DateTime.now();
    final from = ts.subtract(Duration(days: 7 * weeks + 1));

    final logs = await (db.select(db.reviewLogs)
          ..where((t) => t.reviewedAt.isBiggerOrEqualValue(from)))
        .get();

    final counts = <DateTime, int>{};
    for (final log in logs) {
      final day = DateTime(
          log.reviewedAt.year, log.reviewedAt.month, log.reviewedAt.day);
      counts[day] = (counts[day] ?? 0) + 1;
    }
    return counts;
  }

  DateTime _startOfWeek(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    return day.subtract(Duration(days: day.weekday - 1)); // 周一
  }
}

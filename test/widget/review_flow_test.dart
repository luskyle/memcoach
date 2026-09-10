import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shiyi/data/database/database.dart';
import 'package:shiyi/data/repositories/item_repository.dart';
import 'package:shiyi/data/repositories/review_repository.dart';
import 'package:shiyi/data/settings/settings_store.dart';
import 'package:shiyi/domain/srs/sm2.dart';
import 'package:shiyi/features/review/review_session_screen.dart';
import 'package:shiyi/providers.dart';

void main() {
  late ProviderContainer container;
  late AppDatabase db;
  late ReviewRepository reviewRepo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    db = AppDatabase.forTesting();
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        sharedPrefsProvider.overrideWithValue(prefs),
        settingsProvider.overrideWithValue(SettingsStore(prefs)),
      ],
    );
    reviewRepo = ReviewRepository(db);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
  });

  /// 造一张"今天到期"的卡（已成卡条目）。
  Future<int> seedDueCard() async {
    final now = DateTime(2026, 9, 7, 10);
    final due = now.subtract(const Duration(minutes: 1));
    final cardId = await db.into(db.cards).insert(
          CardsCompanion.insert(
            kind: const drift.Value('word'),
            prompt: 'remember',
            answer: '记得；想起',
            lang: const drift.Value('en'),
            dueAt: due,
            createdAt: now,
          ),
        );
    await db.into(db.items).insert(
          ItemsCompanion.insert(
            cardId: drift.Value(cardId),
            source: const drift.Value('manual'),
            lang: const drift.Value('en'),
            status: const drift.Value('learning'),
            createdAt: now,
          ),
        );
    return cardId;
  }

  testWidgets('复习闭环：翻卡 → 评级「记得」→ 完成页 → 日志与间隔更新', (tester) async {
    final cardId = await seedDueCard();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ReviewSessionScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // 正面显示 prompt
    expect(find.text('remember'), findsOneWidget);
    // 未翻面时没有评级按钮
    expect(find.text('忘了'), findsNothing);

    // 翻面
    await tester.tap(find.text('remember'));
    await tester.pumpAndSettle();
    expect(find.text('记得；想起'), findsOneWidget);

    // 评级"记得"
    await tester.tap(find.text('记得'));
    await tester.pumpAndSettle();

    // 完成页
    expect(find.text('今日复习完成'), findsOneWidget);

    // 落库校验：review_log 追加 + SM-2 状态更新
    final logs = await (db.select(db.reviewLogs)
          ..where((t) => t.cardId.equals(cardId)))
        .get();
    expect(logs.length, 1);
    expect(logs.first.quality, 4); // 记得 → quality 4
    expect(logs.first.intervalDays, 1);

    final card = await (db.select(db.cards)..where((t) => t.id.equals(cardId)))
        .getSingle();
    expect(card.repetitions, 1);
    expect(card.intervalDays, 1);
    expect(card.lastReviewedAt, isNotNull);
  });

  testWidgets('答错走重学路径：repetitions 归零、间隔回到 1 天', (tester) async {
    // 先让一张卡连续答对 3 次，形成成熟卡
    final cardId = await seedDueCard();
    var now = DateTime(2026, 9, 7, 10);
    for (var i = 0; i < 3; i++) {
      await reviewRepo.reviewCard(
        cardId: cardId,
        rating: ReviewRating.remembered,
        now: now,
      );
      now = now.add(const Duration(days: 30));
    }
    final before = await (db.select(db.cards)
          ..where((t) => t.id.equals(cardId)))
        .getSingle();
    expect(before.repetitions, 3);
    expect(before.intervalDays, greaterThan(6));

    // 到期后答错 → 重学
    await reviewRepo.reviewCard(
      cardId: cardId,
      rating: ReviewRating.forgot,
      now: now,
    );
    final after = await (db.select(db.cards)
          ..where((t) => t.id.equals(cardId)))
        .getSingle();
    expect(after.repetitions, 0);
    expect(after.intervalDays, 1);
  });

  test('成卡后条目状态投影为 learning，掌握后为 mastered', () async {
    final now = DateTime(2026, 9, 7, 10);
    final itemRepo = ItemRepository(db);

    final itemId = await itemRepo.createManualCard(
      prompt: 'remember',
      answer: '记得',
      kind: 'word',
      lang: 'en',
      now: now,
    );
    final item1 = await (db.select(db.items)..where((t) => t.id.equals(itemId)))
        .getSingle();
    expect(item1.status, 'learning');

    // 快速推进到 90 天间隔（已掌握）
    var t = now;
    var cardId = item1.cardId!;
    for (var i = 0; i < 30; i++) {
      final card = await (db.select(db.cards)
            ..where((t) => t.id.equals(cardId)))
          .getSingle();
      await reviewRepo.reviewCard(cardId: cardId, rating: ReviewRating.remembered, now: t);
      t = t.add(Duration(days: card.intervalDays + 1));
    }
    final item2 = await (db.select(db.items)..where((t) => t.id.equals(itemId)))
        .getSingle();
    expect(item2.status, 'mastered');
  });
}
import 'package:flutter_test/flutter_test.dart';
import 'package:memcoach/content/content_plugin.dart';
import 'package:memcoach/data/database/database.dart';
import 'package:memcoach/data/repositories/review_repository.dart';
import 'package:memcoach/data/repositories/training_set_repository.dart';
import 'package:memcoach/domain/srs/sm2.dart';

void main() {
  late AppDatabase db;
  late TrainingSetRepository repo;

  setUp(() {
    db = AppDatabase.forTesting();
    repo = TrainingSetRepository(db);
  });

  tearDown(() async => db.close());

  ContentPlugin plugin() => const ContentPlugin(
        id: 'test.set',
        name: '测试集',
        description: '测试用',
        kind: ContentKind.flashcard,
        items: [
          FlashcardItem(front: 'a', back: 'A'),
          FlashcardItem(front: 'b', back: 'B'),
          FlashcardItem(front: 'c', back: 'C'),
        ],
      );

  test('下载安装 → 记录状态；导入按需引入卡片+条目', () async {
    await repo.install(plugin());
    expect(await repo.installedIds(), {'test.set'});
    expect(await repo.installed(), hasLength(1));

    final imported = await repo.importItems(plugin(), 2);
    expect(imported, 2);

    final cards = await (db.select(db.cards)
          ..where((t) => t.trainingSetId.equals('test.set')))
        .get();
    expect(cards, hasLength(2));
    expect(cards.first.prompt, 'a');

    // 每张训练集卡都有对应条目（SM-2 投影不变式）
    final items = await (db.select(db.items)
          ..where((t) => t.source.equals('training_set')))
        .get();
    expect(items, hasLength(2));
  });

  test('重复导入幂等：不重复引入已引入条目', () async {
    await repo.install(plugin());
    await repo.importItems(plugin(), 3);
    final again = await repo.importItems(plugin(), 3);
    expect(again, 0);

    final cards = await (db.select(db.cards)
          ..where((t) => t.trainingSetId.equals('test.set')))
        .get();
    expect(cards, hasLength(3));
  });

  test('卸载：移除安装记录，清理未训练卡，保留已训练卡', () async {
    await repo.install(plugin());
    await repo.importItems(plugin(), 2);

    final cards = await (db.select(db.cards)
          ..where((t) => t.trainingSetId.equals('test.set')))
        .get();
    // 训练其中一张
    await ReviewRepository(db).reviewCard(
      cardId: cards.first.id,
      rating: ReviewRating.remembered,
      now: DateTime(2026, 9, 1, 10),
    );

    await repo.uninstall('test.set');

    expect(await repo.installedIds(), isEmpty);
    final remaining = await db.select(db.cards).get();
    expect(
      remaining.where((c) => c.trainingSetId == 'test.set').length,
      1,
      reason: '已训练卡保留，未训练卡删除',
    );
  });
}
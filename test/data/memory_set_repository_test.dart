import 'package:drift/drift.dart' as drift;
import 'package:flutter_test/flutter_test.dart';
import 'package:memcoach/data/database/database.dart';
import 'package:memcoach/data/repositories/item_repository.dart';
import 'package:memcoach/data/repositories/memory_set_repository.dart';
import 'package:memcoach/data/repositories/review_repository.dart';

void main() {
  late AppDatabase db;
  late MemorySetRepository sets;
  late ItemRepository items;
  late ReviewRepository reviews;

  setUp(() {
    db = AppDatabase.forTesting();
    items = ItemRepository(db);
    sets = MemorySetRepository(db, items: items);
    reviews = ReviewRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  /// 造一张成卡条目（收藏侧）。
  Future<int> seedCard() async {
    return items.createManualCard(
      prompt: 'remember',
      answer: '记得',
      kind: 'word',
      lang: 'en',
      now: DateTime(2026, 9, 1, 10),
    );
  }

  test('记忆集 CRUD：建集 / 改名 / 删集', () async {
    final id = await sets.create('考研真题', purpose: '英语一近十年');
    var all = await sets.all();
    expect(all, hasLength(1));
    expect(all.first.name, '考研真题');

    await sets.rename(id, '考研英语');
    expect((await sets.all()).first.name, '考研英语');

    await sets.delete(id);
    expect(await sets.all(), isEmpty);
  });

  test('拉入收藏自动入集合：条目进集合，卡片进复习队列', () async {
    final itemId = await seedCard();

    final setId = await sets.create('单词本');
    await sets.addItem(setId, itemId);

    final detail = await sets.detail(setId);
    expect(detail.items, hasLength(1));
    // 卡片已建（明天首复）
    expect(detail.items.first.hasCard, isTrue);

    // 把到期时间拨回过去，使其进入复习队列
    final now = DateTime(2026, 9, 1, 10);
    final future = DateTime(2026, 9, 10, 10);
    await db.update(db.cards).write(
          CardsCompanion(dueAt: drift.Value(now)),
        );

    // 记忆集过滤的到期队列应含该卡
    final due = await reviews.dueCards(memorySetId: setId, now: future);
    expect(due, hasLength(1));
    expect(due.first.card.prompt, 'remember');

    // 全局队列同样包含
    final allDue = await reviews.dueCards(now: future);
    expect(allDue.map((c) => c.card.id), contains(due.first.card.id));
  });

  test('删除记忆集不动收藏，但移出集合生效', () async {
    final itemId = await seedCard();

    final setId = await sets.create('临时集');
    await sets.addItem(setId, itemId);

    // 移出集合
    await sets.removeItem(setId, itemId);
    expect((await sets.detail(setId)).items, isEmpty);

    // 再拉入 + 删集：收藏与卡片保留
    await sets.addItem(setId, itemId);
    await sets.delete(setId);
    final kept = await (db.select(db.items)..where((t) => t.id.equals(itemId)))
        .getSingle();
    expect(kept.cardId, isNotNull, reason: '删集不应删除收藏');
  });

  test('重复拉入幂等：同一收藏只出现一次', () async {
    final itemId = await seedCard();
    final setId = await sets.create('去重集');

    await sets.addItem(setId, itemId);
    await sets.addItem(setId, itemId);

    expect((await sets.detail(setId)).items, hasLength(1));
  });
}
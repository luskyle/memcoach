import 'package:drift/drift.dart';

import '../database/database.dart';
import '../dictionary/dictionary_service.dart';
import '../../domain/srs/sm2.dart';

/// 默认「未分类」分组名（列表排序时恒置底）。
const kUncategorizedName = '未分类';

/// 收藏条目 + 关联卡片（join 视图）。
class ItemWithCard {
  const ItemWithCard({required this.item, this.card});

  final ItemRow item;
  final CardRow? card;

  bool get hasCard => card != null;
}

/// 卡片 + 所属收藏条目（join 视图）。
class CardWithItem {
  const CardWithItem({required this.card, required this.item});

  final CardRow card;
  final ItemRow item;
}

/// 收藏域仓储：收藏管道 → 成卡 → 记忆库查询。
class ItemRepository {
  ItemRepository(this.db, {DictionaryService? dictionary})
      : _dictionary = dictionary ?? DictionaryService();

  final AppDatabase db;
  final DictionaryService _dictionary;

  /// 词库批量导入 words 表（幂等：按 headword+reading 去重；层级纠错）。
  Future<void> importDictionaryEntries(List<DictionaryEntry> entries) async {
    final existing = await db.select(db.words).get();
    final byKey = {
      for (final w in existing) '${w.headword}|${w.reading}': w,
    };

    final batch = <WordsCompanion>[];
    final fixes = <WordsCompanion>[];
    for (final e in entries) {
      final key = '${e.headword}|${e.reading}';
      final current = byKey[key];
      if (current == null) {
        batch.add(
          WordsCompanion.insert(
            lang: e.lang,
            headword: e.headword,
            reading: Value(e.reading),
            level: Value(e.level),
          ),
        );
      } else if (current.level != e.level) {
        // 旧版本把 A1/入门 误标为 NA1/N入门：纠错
        fixes.add(
          WordsCompanion(
            id: Value(current.id),
            level: Value(e.level),
          ),
        );
      }
    }
    if (batch.isNotEmpty) {
      await db.batch((b) => b.insertAll(db.words, batch));
    }
    for (final fix in fixes) {
      await (db.update(db.words)..where((t) => t.id.equals(fix.id.value)))
          .write(WordsCompanion(level: Value(fix.level.value)));
    }
  }

  /// 指定语言中尚未学习（未成卡）的词条（主动学习数据源，可按关卡过滤）。
  Future<List<WordRow>> unstudiedWords({
    required String lang,
    String? level,
    int limit = 20,
  }) async {
    final used = await (db.selectOnly(db.cards)
          ..addColumns([db.cards.wordId])
          ..where(db.cards.wordId.isNotNull()))
        .get();
    final usedIds =
        used.map((r) => r.read(db.cards.wordId)).whereType<int>().toSet();

    final query = db.select(db.words);
    if (level != null) {
      query.where((t) => t.lang.equals(lang) & t.level.equals(level));
    } else {
      query.where((t) => t.lang.equals(lang));
    }
    final words = await query.get();
    return words.where((w) => !usedIds.contains(w.id)).take(limit).toList();
  }

  /// 各关卡已学（已成卡）词数：lang + level → count（渐进解锁进度）。
  Future<Map<String, int>> learnedCountByLevel(String lang) async {
    final rows = await (db.select(db.words).join([
      innerJoin(db.cards, db.cards.wordId.equalsExp(db.words.id)),
    ])
          ..where(db.words.lang.equals(lang) & db.cards.wordId.isNotNull()))
        .get();
    final counts = <String, int>{};
    for (final r in rows) {
      final level = r.readTable(db.words).level ?? '默认';
      counts[level] = (counts[level] ?? 0) + 1;
    }
    return counts;
  }

  /// 某关卡总词数（词库元数据）。
  Future<int> levelWordCount(String lang, String level) async {
    final row = await (db.selectOnly(db.words)
          ..addColumns([countAll()])
          ..where(db.words.lang.equals(lang) & db.words.level.equals(level)))
        .getSingle();
    return row.read(countAll()) ?? 0;
  }

  /// 通过「学习」产生的卡片数（按语言统计，默认页学习情况展示）。
  Future<Map<String, int>> learnedCountByLang() async {
    final rows = await (db.select(db.items).join([
      innerJoin(db.cards, db.cards.id.equalsExp(db.items.cardId)),
    ])
          ..where(
              db.items.source.equals('study') & db.items.cardId.isNotNull()))
        .get();
    final counts = <String, int>{};
    for (final r in rows) {
      final lang = r.readTable(db.cards).lang ?? 'other';
      counts[lang] = (counts[lang] ?? 0) + 1;
    }
    return counts;
  }

  /// 旧数据对账：取消收件箱后，遗留 inbox 条目升级为学习卡（无孤儿）。
  /// - 已有卡 → 状态改 learning（正常进复习）
  /// - 无卡（旧剪贴板待归类）→ 用备注文本自动成卡
  Future<void> upgradeLegacyInbox({DateTime? now}) async {
    final ts = now ?? DateTime.now();
    final inbox = await (db.select(db.items)
          ..where((t) => t.status.equals('inbox')))
        .get();
    for (final it in inbox) {
      if (it.cardId != null) {
        await (db.update(db.items)..where((t) => t.id.equals(it.id)))
            .write(const ItemsCompanion(status: Value('learning')));
        continue;
      }
      final text = it.note ?? '';
      if (text.trim().isEmpty) continue;
      final lang = it.lang ?? 'other';
      final kind = text.trim().length > 20 ? 'idea' : 'word';
      final cardId = await db.into(db.cards).insert(
            CardsCompanion.insert(
              kind: Value(kind),
              prompt: text.trim(),
              answer: '（待补充答案）',
              lang: Value(lang),
              dueAt: firstReviewDueAt(ts),
              createdAt: it.createdAt,
            ),
          );
      await (db.update(db.items)..where((t) => t.id.equals(it.id)))
          .write(ItemsCompanion(
        cardId: Value(cardId),
        status: const Value('learning'),
        note: const Value(null),
        lang: Value(lang),
      ));
    }
  }

  /// 全部卡片数（免费额度上限判定用）。
  Future<int> cardCount() async {
    final query = db.selectOnly(db.items)
      ..addColumns([countAll()])
      ..where(db.items.cardId.isNotNull());
    final row = await query.getSingle();
    return row.read(countAll()) ?? 0;
  }

  /// 手录/主动学习创建：成卡 + 条目（status=learning，首次复习排期明天）。
  /// 词条类命中离线词库 → 自动补释义/读音并关联 word 行（官方词库路径）；
  /// [wordId] 显式传入时直接关联（主动学习从词库取词的路径）。
  Future<int> createManualCard({
    required String prompt,
    required String answer,
    required String kind,
    required String lang,
    List<String> tags = const [],
    String? note,
    String source = 'manual',
    int? collectionId,
    int? wordId,
    DateTime? now,
  }) async {
    final ts = now ?? DateTime.now();

    // 词条类：先查离线词库，命中则建 word 行并关联（本地优先原则）
    if (kind == 'word' && wordId == null) {
      final hits = _dictionary.lookup(prompt);
      final hit = hits.isNotEmpty ? hits.first : null;
      if (hit != null) {
        wordId = await db.into(db.words).insert(
              WordsCompanion.insert(
                lang: hit.lang,
                headword: hit.headword,
                reading: Value(hit.reading),
                level: Value(hit.level),
              ),
            );
      }
    }

    final cardId = await db.into(db.cards).insert(
          CardsCompanion.insert(
            kind: Value(kind),
            prompt: prompt,
            answer: answer,
            wordId: Value(wordId),
            lang: Value(lang),
            tags: tags.isEmpty ? const Value(null) : Value(tags.join(',')),
            dueAt: firstReviewDueAt(ts),
            createdAt: ts,
          ),
        );

    final itemId = await db.into(db.items).insert(
          ItemsCompanion.insert(
            cardId: Value(cardId),
            source: Value(source),
            note: Value(note),
            lang: Value(lang),
            status: const Value('learning'),
            createdAt: ts,
          ),
        );

    await _linkTags(itemId, tags);
    if (collectionId != null) {
      await _linkCollection(itemId, collectionId);
    }
    return itemId;
  }

  List<ItemWithCard> _mapItemWithCard(List<TypedResult> rows) {
    return rows
        .map((r) => ItemWithCard(
              item: r.readTable(db.items),
              card: r.readTableOrNull(db.cards),
            ))
        .toList();
  }

  /// 记忆库流：全部成卡条目 + 可选搜索/筛选/按主库过滤。
  Stream<List<ItemWithCard>> watchLibrary({
    String search = '',
    String? lang,
    String? status,
    int? collectionId,
  }) {
    final q = db.select(db.items).join([
      leftOuterJoin(db.cards, db.cards.id.equalsExp(db.items.cardId)),
      if (collectionId != null)
        innerJoin(
          db.itemCollections,
          db.itemCollections.itemId.equalsExp(db.items.id),
        ),
    ])
      ..where(db.items.cardId.isNotNull())
      ..orderBy([OrderingTerm.desc(db.items.createdAt)]);

    final where = q.where;
    if (search.trim().isNotEmpty) {
      final like = '%${search.trim()}%';
      where(db.cards.prompt.like(like) |
          db.cards.answer.like(like) |
          db.cards.tags.like(like) |
          db.items.note.like(like));
    }
    if (lang != null && lang.isNotEmpty) {
      where(db.cards.lang.equals(lang));
    }
    if (status != null && status.isNotEmpty) {
      where(db.items.status.equals(status));
    }
    if (collectionId != null) {
      where(db.itemCollections.collectionId.equals(collectionId) &
          db.itemCollections.isPrimary.equals(true));
    }

    return q.watch().map(_mapItemWithCard);
  }

  /// 删除条目与对应卡片（复习日志级联删除）。
  Future<void> deleteItem(int itemId) async {
    final item = await (db.select(db.items)..where((t) => t.id.equals(itemId)))
        .getSingleOrNull();
    await (db.delete(db.items)..where((t) => t.id.equals(itemId))).go();
    if (item?.cardId != null) {
      await (db.delete(db.cards)..where((t) => t.id.equals(item!.cardId!)))
          .go();
    }
  }

  /// 编辑卡面字段。
  Future<void> updateCardFields(
    int itemId, {
    String? prompt,
    String? answer,
    List<String>? tags,
  }) async {
    final item = await (db.select(db.items)..where((t) => t.id.equals(itemId)))
        .getSingleOrNull();
    if (item?.cardId == null) return;
    await (db.update(db.cards)..where((t) => t.id.equals(item!.cardId!))).write(
      CardsCompanion(
        prompt: prompt == null ? const Value.absent() : Value(prompt),
        answer: answer == null ? const Value.absent() : Value(answer),
        tags: tags == null ? const Value.absent() : Value(tags.join(',')),
      ),
    );
  }

  // ---- 标签 ----

  Future<void> _linkTags(int itemId, List<String> tags) async {
    for (final tag in tags.where((t) => t.trim().isNotEmpty)) {
      await db.into(db.itemTags).insert(
            ItemTagsCompanion.insert(itemId: itemId, tag: tag.trim()),
            mode: InsertMode.insertOrIgnore,
          );
    }
  }

  // ---- 分组（库）----

  /// 分类列表（「未分类」恒置底，其余按 id 即创建顺序）。
  Future<List<CollectionRow>> collections() async {
    final all = await db.select(db.collections).get();
    final uncategorized =
        all.where((c) => c.name == kUncategorizedName).toList();
    final rest = all.where((c) => c.name != kUncategorizedName).toList();
    return [...rest, ...uncategorized];
  }

  Future<int> createCollection(String name, {bool isSystem = false}) {
    return db.into(db.collections).insert(
          CollectionsCompanion.insert(
            name: name,
            isSystem: Value(isSystem),
            createdAt: DateTime.now(),
          ),
        );
  }

  Future<void> renameCollection(int id, String name) =>
      (db.update(db.collections)..where((t) => t.id.equals(id)))
          .write(CollectionsCompanion(name: Value(name)));

  Future<void> deleteCollection(int id) async {
    await (db.delete(db.itemCollections)
          ..where((t) => t.collectionId.equals(id)))
        .go();
    await (db.delete(db.collections)..where((t) => t.id.equals(id))).go();
  }

  Future<void> _linkCollection(int itemId, int collectionId) {
    return db.into(db.itemCollections).insert(
          ItemCollectionsCompanion.insert(
            itemId: itemId,
            collectionId: collectionId,
            isPrimary: const Value(true),
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  /// 条目所属的库（详情页展示用）。
  Future<List<CollectionRow>> collectionsOfItem(int itemId) async {
    final rows = await (db.select(db.itemCollections).join([
      innerJoin(db.collections,
          db.collections.id.equalsExp(db.itemCollections.collectionId)),
    ])
          ..where(db.itemCollections.itemId.equals(itemId)))
        .get();
    return rows.map((r) => r.readTable(db.collections)).toList();
  }

  /// 库统计：卡片数 + 已掌握数（记忆库分组头部数据条）。
  Future<Map<int, ({int total, int mastered})>> collectionStats() async {
    final items =
        await (db.select(db.items)..where((t) => t.cardId.isNotNull())).get();
    final links = await db.select(db.itemCollections).get();

    final stats = <int, ({int total, int mastered})>{};
    final itemsById = {for (final i in items) i.id: i};
    for (final link in links) {
      final item = itemsById[link.itemId];
      if (item == null) continue;
      final entry =
          stats.putIfAbsent(link.collectionId, () => (total: 0, mastered: 0));
      stats[link.collectionId] = (
        total: entry.total + 1,
        mastered: entry.mastered + (item.status == 'mastered' ? 1 : 0),
      );
    }
    return stats;
  }
}

import 'package:drift/drift.dart' as drift;

import '../database/database.dart';
import 'item_repository.dart';

/// 记忆集数据（含条目展开视图）。
class MemorySetWithItems {
  const MemorySetWithItems({required this.set, required this.items});

  final MemorySetRow set;
  final List<ItemWithCard> items;
}

/// 记忆集仓储（记忆教练：用户自建复习集合）：
/// 记忆集 = 一组收藏条目（卡片），可整体学习/复习/回顾。
class MemorySetRepository {
  MemorySetRepository(this.db, {required this.items});

  final AppDatabase db;
  final ItemRepository items;

  // ---- 集合 CRUD ----

  /// 全部记忆集（新在前）。
  Future<List<MemorySetRow>> all() async {
    final q = db.select(db.memorySets)
      ..orderBy([(t) => drift.OrderingTerm.desc(t.createdAt)]);
    return q.get();
  }

  Future<int> create(String name, {String? purpose}) {
    return db.into(db.memorySets).insert(
          MemorySetsCompanion.insert(
            name: name,
            purpose: drift.Value(purpose),
            createdAt: DateTime.now(),
          ),
        );
  }

  Future<void> rename(int id, String name) async {
    await (db.update(db.memorySets)..where((t) => t.id.equals(id)))
        .write(MemorySetsCompanion(name: drift.Value(name)));
  }

  Future<void> setPurpose(int id, String? purpose) async {
    await (db.update(db.memorySets)..where((t) => t.id.equals(id))).write(
      MemorySetsCompanion(
        purpose:
            purpose == null ? const drift.Value.absent() : drift.Value(purpose),
      ),
    );
  }

  Future<void> delete(int id) async {
    // 条目级联；只移除集合关联，不删除收藏
    await (db.delete(db.memorySetItems)..where((t) => t.memorySetId.equals(id)))
        .go();
    await (db.delete(db.memorySets)..where((t) => t.id.equals(id))).go();
  }

  // ---- 条目 ----

  /// 集合内的收藏条目（join 卡片）。
  Future<List<ItemWithCard>> itemsOf(int setId) async {
    final q = db.select(db.items).join([
      drift.innerJoin(
          db.memorySetItems, db.memorySetItems.itemId.equalsExp(db.items.id)),
      drift.leftOuterJoin(db.cards, db.cards.id.equalsExp(db.items.cardId)),
    ])
      ..where(db.memorySetItems.memorySetId.equals(setId))
      ..orderBy([drift.OrderingTerm.desc(db.items.createdAt)]);
    final rows = await q.get();
    return rows
        .map((r) => ItemWithCard(
              item: r.readTable(db.items),
              card: r.readTableOrNull(db.cards),
            ))
        .toList();
  }

  Future<MemorySetWithItems> detail(int setId) async {
    final set = await (db.select(db.memorySets)
          ..where((t) => t.id.equals(setId)))
        .getSingle();
    return MemorySetWithItems(set: set, items: await itemsOf(setId));
  }

  /// 拉入已有收藏条目。
  Future<void> addItem(int setId, int itemId) async {
    await db.into(db.memorySetItems).insert(
          MemorySetItemsCompanion.insert(
            memorySetId: setId,
            itemId: itemId,
          ),
          mode: drift.InsertMode.insertOrIgnore,
        );
  }

  /// 从集合移除条目（不删除收藏）。
  Future<void> removeItem(int setId, int itemId) async {
    await (db.delete(db.memorySetItems)
          ..where((t) => t.memorySetId.equals(setId) & t.itemId.equals(itemId)))
        .go();
  }
}

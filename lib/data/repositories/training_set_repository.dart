import 'package:drift/drift.dart';

import '../../content/content_plugin.dart';
import '../../domain/srs/sm2.dart';
import '../database/database.dart';

/// 训练集仓储：社区「下载」后的安装状态，以及训练时按需把训练集条目
/// 引入为 Cards（source='training_set'，SM-2 调度单元）。
class TrainingSetRepository {
  TrainingSetRepository(this.db);

  final AppDatabase db;

  /// 已下载（安装）的训练集，新在前。
  Future<List<TrainingSetRow>> installed() async {
    final q = db.select(db.trainingSets)
      ..orderBy([(t) => OrderingTerm.desc(t.installedAt)]);
    return q.get();
  }

  /// 已安装 id 集合（社区目录「已下载」状态标记）。
  Future<Set<String>> installedIds() async {
    final rows = await db.select(db.trainingSets).get();
    return rows.map((r) => r.id).toSet();
  }

  /// 下载（安装）训练集：仅记录状态，不立即导入条目。
  /// 条目在训练时按强度需要才引入（Anki「每日新卡」思路）。
  Future<void> install(ContentPlugin plugin) async {
    await db.into(db.trainingSets).insertOnConflictUpdate(
          TrainingSetsCompanion.insert(
            id: plugin.id,
            name: plugin.name,
            description: plugin.description,
            kind: contentKindLabel(plugin.kind),
            installedAt: DateTime.now(),
          ),
        );
  }

  /// 卸载训练集：移除安装记录，并清理尚未训练过的已引入卡片及其条目。
  Future<void> uninstall(String id) async {
    await (db.delete(db.trainingSets)..where((t) => t.id.equals(id))).go();
    // 仅删「从未复习」的卡；已进入排期的卡保留（不破坏历史）。
    final pending = await (db.select(db.cards)
          ..where(
              (t) => t.trainingSetId.equals(id) & t.lastReviewedAt.isNull()))
        .get();
    for (final c in pending) {
      await (db.delete(db.items)..where((t) => t.cardId.equals(c.id))).go();
      await (db.delete(db.cards)..where((t) => t.id.equals(c.id))).go();
    }
  }

  /// 某训练集已引入的条目下标集合（去重用）。
  Future<Set<int>> importedIndices(String setId) async {
    final rows = await (db.select(db.cards)
          ..where((t) =>
              t.trainingSetId.equals(setId) & t.trainingItemIndex.isNotNull()))
        .get();
    return rows.map((c) => c.trainingItemIndex!).toSet();
  }

  /// 把训练集里尚未引入的条目引入为卡片 + 条目，最多 [cardCount] 张；
  /// 返回实际引入数。卡片 maintain「每卡必有条目」不变式，供 SM-2 复习日志投影使用。
  Future<int> importItems(
    ContentPlugin plugin,
    int count, {
    DateTime? now,
  }) async {
    final ts = now ?? DateTime.now();
    final existing = await importedIndices(plugin.id);
    var imported = 0;
    for (var i = 0; i < plugin.items.length && imported < count; i++) {
      if (existing.contains(i)) continue;
      final (prompt, answer) = plugin.items[i].toTrainingCard();
      final cardId = await db.into(db.cards).insert(
            CardsCompanion.insert(
              kind: Value(contentKindLabel(plugin.kind)),
              prompt: prompt,
              answer: answer,
              lang: Value(plugin.locale),
              trainingSetId: Value(plugin.id),
              trainingItemIndex: Value(i),
              dueAt: firstReviewDueAt(ts),
              createdAt: ts,
            ),
          );
      await db.into(db.items).insert(
            ItemsCompanion.insert(
              cardId: Value(cardId),
              source: const Value('training_set'),
              lang: Value(plugin.locale),
              status: const Value('learning'),
              createdAt: ts,
            ),
          );
      imported++;
    }
    return imported;
  }

  /// 已安装训练集未引入的剩余条目总数（社区详情「待训练」提示）。
  Future<int> pendingCount(String setId, int totalItems) async {
    final existing = await importedIndices(setId);
    return totalItems - existing.length;
  }
}
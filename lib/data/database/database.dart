import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables.dart';

part 'database.g.dart';

const kSchemaVersion = 7;

/// Memcoach 主库（drift/SQLite）。
///
/// 打开方式：`driftDatabase(name: 'memcoach')`（drift_flutter 一站式，
/// 自带 sqlite3_flutter_libs 原生库与 path 处理；测试中改为内存库）。
@DriftDatabase(
  tables: [
    Words,
    Cards,
    Items,
    ReviewLogs,
    ItemTags,
    TrainingSets,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// 打开磁盘上的应用数据库（正式运行入口）。
  factory AppDatabase.open() => AppDatabase(driftDatabase(name: 'memcoach'));

  /// 测试用内存库。
  factory AppDatabase.forTesting() =>
      AppDatabase(NativeDatabase.memory(logStatements: false));

  @override
  int get schemaVersion => kSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        onUpgrade: (m, from, to) async {
          // v7（社区版）：移除「分组」与「记忆管理」，引入「训练集」。
          if (from < 7) {
            await customStatement(
                'DROP TABLE IF EXISTS memory_set_items');
            await customStatement('DROP TABLE IF EXISTS memory_sets');
            await customStatement(
                'DROP TABLE IF EXISTS item_collections');
            await customStatement('DROP TABLE IF EXISTS collections');
            await m.createTable(trainingSets);
            await m.addColumn(cards, cards.trainingSetId);
            await m.addColumn(cards, cards.trainingItemIndex);
          }
          if (from < 6) {
            await customStatement('DROP TABLE IF EXISTS sync_deletions');
            await customStatement('DROP TABLE IF EXISTS media_assets');
            await customStatement('DROP TABLE IF EXISTS media_folders');
            try {
              // SQLite >= 3.35 支持 DROP COLUMN；旧版本忽略（多余列不影响读写）
              await customStatement(
                  'ALTER TABLE items DROP COLUMN media_asset_id');
            } catch (_) {}
          }
          if (from < 3) {
            await m.addColumn(items, items.sourceTitle);
          }
          // 破坏性迁移保留：数据模型锁定后再补备份导出
          if (from < 1) {
            await m.createAll();
          }
        },
      );
}
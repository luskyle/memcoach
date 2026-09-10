import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables.dart';

part 'database.g.dart';

const kSchemaVersion = 6;

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
    Collections,
    ItemCollections,
    ItemTags,
    MemorySets,
    MemorySetItems,
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
          await _seedSystemCollections();
        },
        onUpgrade: (m, from, to) async {
          // v6（记忆教练）：移除素材库与云同步（独立不互通）
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
          if (from < 5) {
            await m.createTable(memorySets);
            await m.createTable(memorySetItems);
          }
          if (from < 3) {
            await m.addColumn(items, items.sourceTitle);
          }
          if (from < 2) {
            // v2 引入的同步墓碑表已随 v6 移除，这里不再创建
          }
          // 破坏性迁移保留：数据模型锁定后再补备份导出
          if (from < 1) {
            await m.createAll();
          }
        },
      );

  Future<void> _seedSystemCollections() async {
    await ensureDefaultCollections();
  }

  /// 确保默认分类（工作/学习/未分类）存在且为系统分类（不可删除）。
  /// 幂等：旧库/新库均可安全调用（启动 bootstrap 也会执行）。
  Future<void> ensureDefaultCollections() async {
    const defaults = {'工作', '学习', '未分类'};
    final existing = await (select(collections)
          ..where((t) => t.isSystem.equals(true)))
        .get();
    final names = existing.map((c) => c.name).toSet();

    for (final name in defaults) {
      if (names.contains(name)) continue;
      await into(collections).insert(
        CollectionsCompanion.insert(
          name: name,
          isSystem: const Value(true),
          createdAt: DateTime.now(),
        ),
      );
    }
    // 旧库历史系统分类（非默认）降级为普通分类，允许用户删除
    for (final c in existing) {
      if (!defaults.contains(c.name)) {
        await (update(collections)..where((t) => t.id.equals(c.id)))
            .write(const CollectionsCompanion(isSystem: Value(false)));
      }
    }
  }
}

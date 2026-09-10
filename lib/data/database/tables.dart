import 'package:drift/drift.dart';

/// 词条（官方词库，多模态素材复用；MVP 内置小词库，后续由 Python 词库管线导入）
@DataClassName('WordRow')
class Words extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get lang => text()();
  TextColumn get headword => text()();
  TextColumn get reading => text().nullable()();
  TextColumn get ipa => text().nullable()();
  TextColumn get audioFile => text().nullable()();
  TextColumn get level => text().nullable()();
  TextColumn get tags => text().nullable()();
}

/// 卡片（SRS 对象，复习引擎的调度单元）
@DataClassName('CardRow')
class Cards extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get wordId => integer()
      .nullable()
      .references(Words, #id, onDelete: KeyAction.setNull)();

  /// 卡种：word | quote | idea | clip
  TextColumn get kind => text().withDefault(const Constant('word'))();
  TextColumn get prompt => text()();
  TextColumn get answer => text()();
  TextColumn get audioFile => text().nullable()();

  /// 语言标签（自动标注，复习过滤用）
  TextColumn get lang => text().nullable()();

  /// 冗余标签（搜索增强）
  TextColumn get tags => text().nullable()();

  // ---- SRS 调度状态（SM-2）----
  IntColumn get repetitions => integer().withDefault(const Constant(0))();
  RealColumn get easeFactor => real().withDefault(const Constant(2.5))();
  IntColumn get intervalDays => integer().withDefault(const Constant(0))();
  DateTimeColumn get dueAt => dateTime()();
  DateTimeColumn get lastReviewedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
}

/// 收藏条目（工具版核心：收藏管道的一等公民）
@DataClassName('ItemRow')
class Items extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 成卡后可空（未成卡 = 待归类）
  IntColumn get cardId => integer()
      .nullable()
      .references(Cards, #id, onDelete: KeyAction.setNull)();

  /// 来源：share | manual | study | memory_set
  TextColumn get source => text().withDefault(const Constant('manual'))();
  TextColumn get mediaPath => text().nullable()();
  TextColumn get originalUrl => text().nullable()();

  /// 网页摘录来源页标题（Phase 1：划词收藏自动带出处）
  TextColumn get sourceTitle => text().nullable()();

  /// 用户备注（为什么收）
  TextColumn get note => text().nullable()();

  /// 语言标签（自动标注）
  TextColumn get lang => text().nullable()();

  /// 状态 = SRS + review_log 的投影缓存：inbox | learning | mastered | cold
  TextColumn get status => text().withDefault(const Constant('inbox'))();
  DateTimeColumn get createdAt => dateTime()();
}

/// 复习日志（append-only，唯一事实来源之一；投影与统计全部从这里派生）
@DataClassName('ReviewLogRow')
class ReviewLogs extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get cardId =>
      integer().references(Cards, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get reviewedAt => dateTime()();
  IntColumn get quality => integer()();
  IntColumn get intervalDays => integer()();
  RealColumn get easeFactor => real()();

  /// learning | review | relearning（记录复习时所处阶段）
  TextColumn get state => text()();

  /// review | exam | import（来源）
  TextColumn get source => text().withDefault(const Constant('review'))();
}

/// 库 / 子集（三层分类：库 Collection → 子集 Series → 条目 Item，MVP 实现两层）
@DataClassName('CollectionRow')
class Collections extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  IntColumn get parentId => integer().nullable().references(Collections, #id)();
  IntColumn get ownerId => integer().nullable()();
  BoolColumn get isSystem => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
}

/// 条目-库 多对多（主库标记决定默认归属视图）
@DataClassName('ItemCollectionRow')
class ItemCollections extends Table {
  IntColumn get itemId =>
      integer().references(Items, #id, onDelete: KeyAction.cascade)();
  IntColumn get collectionId =>
      integer().references(Collections, #id, onDelete: KeyAction.cascade)();
  BoolColumn get isPrimary => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {itemId, collectionId};
}

/// 条目标签（多标签交叉，搜索增强）
@DataClassName('ItemTagRow')
class ItemTags extends Table {
  IntColumn get itemId =>
      integer().references(Items, #id, onDelete: KeyAction.cascade)();
  TextColumn get tag => text()();

  @override
  Set<Column<Object>> get primaryKey => {itemId, tag};
}

/// 记忆集（记忆教练：用户自建的复习集合）：
/// 一个记忆集 = 一组收藏条目（卡片），可对集合整体学习/复习/回顾。
@DataClassName('MemorySetRow')
class MemorySets extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get name => text()();

  /// 集合用途/说明
  TextColumn get purpose => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();
}

/// 记忆集条目（收藏条目 → 记忆集 多对多）。
@DataClassName('MemorySetItemRow')
class MemorySetItems extends Table {
  IntColumn get memorySetId =>
      integer().references(MemorySets, #id, onDelete: KeyAction.cascade)();
  IntColumn get itemId =>
      integer().references(Items, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column<Object>> get primaryKey => {memorySetId, itemId};
}

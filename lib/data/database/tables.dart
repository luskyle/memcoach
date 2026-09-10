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

/// 卡片（SRS 对象，训练引擎的调度单元）
@DataClassName('CardRow')
class Cards extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get wordId => integer()
      .nullable()
      .references(Words, #id, onDelete: KeyAction.setNull)();

  /// 卡种：word | quote | idea | clip | flashcard | quiz | cloze
  TextColumn get kind => text().withDefault(const Constant('word'))();
  TextColumn get prompt => text()();
  TextColumn get answer => text()();
  TextColumn get audioFile => text().nullable()();

  /// 语言标签（自动标注，训练过滤用）
  TextColumn get lang => text().nullable()();

  /// 冗余标签（搜索增强）
  TextColumn get tags => text().nullable()();

  /// 所属训练集（若此卡由「社区 → 下载训练集」引入）
  TextColumn get trainingSetId => text().nullable()();

  /// 训练集内条目下标（训练集引入去重用）
  IntColumn get trainingItemIndex => integer().nullable()();

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

  /// 来源：share | manual | study | training_set
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

/// 条目标签（多标签交叉，搜索增强）
@DataClassName('ItemTagRow')
class ItemTags extends Table {
  IntColumn get itemId =>
      integer().references(Items, #id, onDelete: KeyAction.cascade)();
  TextColumn get tag => text()();

  @override
  Set<Column<Object>> get primaryKey => {itemId, tag};
}

/// 已下载训练集：社区目录中「下载」后记录安装状态。
/// 训练集条目在训练时按需引入为 Cards（source='training_set'）。
@DataClassName('TrainingSetRow')
class TrainingSets extends Table {
  /// 目录 id（与内置 / 远程来源的 ContentPlugin.id 一致）。
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get description => text()();

  /// 训练类型：flashcard | quiz | cloze
  TextColumn get kind => text()();
  DateTimeColumn get installedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
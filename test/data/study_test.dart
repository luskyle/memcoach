import 'package:flutter_test/flutter_test.dart';
import 'package:memcoach/data/database/database.dart';
import 'package:memcoach/data/dictionary/dictionary_service.dart';
import 'package:memcoach/data/dictionary/language_catalog.dart';
import 'package:memcoach/data/repositories/item_repository.dart';
import 'package:memcoach/domain/study_plan.dart';

void main() {
  late AppDatabase db;
  late ItemRepository repo;

  setUp(() {
    db = AppDatabase.forTesting();
    repo = ItemRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('渐进解锁：第一级恒开；下一级需上一级学满门槛 min(prev,100)', () {
    // 第一级
    expect(
      StudyPlan.isLevelUnlocked(index: 0, prevLearned: 0, prevTotal: 697),
      isTrue,
    );
    // 大词级（N5 697）：学满 100 解锁 N4
    expect(
      StudyPlan.isLevelUnlocked(index: 1, prevLearned: 99, prevTotal: 697),
      isFalse,
    );
    expect(
      StudyPlan.isLevelUnlocked(index: 1, prevLearned: 100, prevTotal: 697),
      isTrue,
    );
    // 小词级（15 词）：需学完
    expect(
      StudyPlan.isLevelUnlocked(index: 1, prevLearned: 14, prevTotal: 15),
      isFalse,
    );
    expect(
      StudyPlan.isLevelUnlocked(index: 1, prevLearned: 15, prevTotal: 15),
      isTrue,
    );
  });

  test('关卡顺序与标签', () {
    expect(StudyPlan.levelsFor('ja'), ['kana', 'N5', 'N4']);
    expect(StudyPlan.levelsFor('en'), ['A1', 'A2']);
    expect(StudyPlan.labelOf('N5'), 'N5 基础');
  });

  test('按关卡过滤未学词（渐进学习数据源）', () async {
    await repo.importDictionaryEntries(const [
      DictionaryEntry(
          lang: 'en',
          headword: 'apple',
          reading: '/a/',
          meaning: '苹果',
          level: 'A1'),
      DictionaryEntry(
          lang: 'en',
          headword: 'school',
          reading: '/s/',
          meaning: '学校',
          level: 'A2'),
    ]);

    final a1 = await repo.unstudiedWords(lang: 'en', level: 'A1');
    expect(a1, hasLength(1));
    expect(a1.single.headword, 'apple');

    final a2 = await repo.unstudiedWords(lang: 'en', level: 'A2');
    expect(a2.single.headword, 'school');
  });

  test('语言包分级：日语/英语免费，其余 Pro 解锁', () {
    expect(LanguageCatalog.isFree('ja'), isTrue);
    expect(LanguageCatalog.isFree('en'), isTrue);
    expect(LanguageCatalog.isFree('ko'), isFalse);

    expect(LanguageCatalog.unlocked('ko', isPro: false), isFalse);
    expect(LanguageCatalog.unlocked('ko', isPro: true), isTrue);
    expect(LanguageCatalog.unlocked('ja', isPro: false), isTrue);
  });

  test('默认分类：工作/学习/未分类（系统，幂等补齐）', () async {
    final cols = await db.select(db.collections).get();
    final names = cols.where((c) => c.isSystem).map((c) => c.name).toSet();
    expect(names, containsAll(['工作', '学习', '未分类']));

    // 幂等：再确保一次不重复插入
    await db.ensureDefaultCollections();
    final again = await db.select(db.collections).get();
    expect(again.length, cols.length);
  });

  test('分类列表排序：「未分类」恒置底', () async {
    // 默认分类（工作/学习/未分类）+ 一个新分类
    final newId = await repo.createCollection('英语');
    final ordered = await repo.collections();
    final names = ordered.map((c) => c.name).toList();

    expect(names.last, '未分类', reason: '未分类应恒在列表最后');
    expect(names.indexOf('英语'), lessThan(names.indexOf('未分类')));

    // 新分类 id 存在，顺序稳定（其余按创建顺序）
    expect(ordered.map((c) => c.id), contains(newId));
  });

  test('词库导入支持多语言；unstudiedWords 返回未学词', () async {
    // 模拟导入韩语示例包
    await repo.importDictionaryEntries(const [
      DictionaryEntry(
          lang: 'ko', headword: '사랑', reading: 'sarang', meaning: '爱'),
      DictionaryEntry(
          lang: 'ko', headword: '시간', reading: 'sigan', meaning: '时间'),
      DictionaryEntry(
          lang: 'en', headword: 'apple', reading: '/ˈæpəl/', meaning: '苹果'),
    ]);

    final koWords =
        await (db.select(db.words)..where((t) => t.lang.equals('ko'))).get();
    expect(koWords, hasLength(2));

    final pending = await repo.unstudiedWords(lang: 'ko');
    expect(pending, hasLength(2));
  });

  test('学习成卡：wordId 关联 + 未学列表排除已学', () async {
    await repo.importDictionaryEntries(const [
      DictionaryEntry(
          lang: 'ko', headword: '사랑', reading: 'sarang', meaning: '爱'),
    ]);
    final pending = await repo.unstudiedWords(lang: 'ko');
    final word = pending.first;

    final itemId = await repo.createManualCard(
      prompt: word.headword,
      answer: '爱',
      kind: 'word',
      lang: 'ko',
      wordId: word.id,
      source: 'study',
    );

    final item = await (db.select(db.items)..where((t) => t.id.equals(itemId)))
        .getSingle();
    final card = await (db.select(db.cards)
          ..where((t) => t.id.equals(item.cardId!)))
        .getSingle();
    expect(card.wordId, word.id); // 关联官方词条
    expect(card.lang, 'ko');

    // 已学词不再出现在未学列表
    final remaining = await repo.unstudiedWords(lang: 'ko');
    expect(remaining, isEmpty);
  });
}

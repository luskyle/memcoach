import 'package:flutter_test/flutter_test.dart';
import 'package:memcoach/data/dictionary/dictionary_service.dart';

const _sampleJson = '''
{
  "version": "2026-09",
  "entries": [
    {"headword": "会う", "reading": "あう", "meaning": "to meet; to encounter", "level": "5"},
    {"headword": "楽しい", "reading": "たのしい", "meaning": "enjoyable", "level": "4"},
    {"headword": "あ", "reading": "a", "meaning": "五十音：あ → a", "level": "kana"},
    {"headword": "食べる", "reading": "たべる", "meaning": "to eat", "level": "5"}
  ]
}
''';

void main() {
  group('词库载入', () {
    test('loadJson 合并进内存索引并标记已加载', () {
      final svc = DictionaryService();
      expect(svc.loadedFromAsset, isFalse);

      svc.loadJson(_sampleJson);

      expect(svc.loadedFromAsset, isTrue);
      // 样例 29 条 + 新增 3 条（会う/楽しい/あ；食べる 与样例同形同音被去重）
      expect(svc.loadedCount, 32);
    });

    test('lookup 命中词库词条', () {
      final svc = DictionaryService()..loadJson(_sampleJson);
      final hits = svc.lookup('会う');
      expect(hits, hasLength(1));
      expect(hits.first.reading, 'あう');
      expect(hits.first.meaning, contains('meet'));
      expect(hits.first.level, 'N5');
    });

    test('发音方式/级别转换：4 → N4，kana 保留', () {
      final svc = DictionaryService()..loadJson(_sampleJson);
      expect(svc.lookup('楽しい').first.level, 'N4');
      expect(svc.lookup('あ').first.level, 'kana');
    });

    test('同形同音去重：食べる 不重复计数', () {
      final svc = DictionaryService()..loadJson(_sampleJson);
      final hits = svc.lookup('食べる');
      expect(hits, hasLength(1));
    });
  });

  group('内置兜底', () {
    test('样例词库未加载也能命中', () {
      final svc = DictionaryService();
      expect(svc.lookup('remember').first.meaning, contains('记得'));
      expect(svc.lookup('不存在的词'), isEmpty);
    });

    test('readingAnnotation 假名转罗马音', () {
      final svc = DictionaryService();
      expect(svc.readingAnnotation('たべる'), 'taberu');
      expect(svc.readingAnnotation('食べる'), isNull); // 含汉字不标注
      expect(svc.readingAnnotation('abc'), isNull);
    });

    test('buildWordAnswer 附带读音与等级', () {
      final svc = DictionaryService()..loadJson(_sampleJson);
      final answer = svc.buildWordAnswer(svc.lookup('会う').first);
      expect(answer, contains('【あう】'));
      expect(answer, contains('N5'));
    });
  });

  test('loadedEntries 暴露全部词条（words 表导入用）', () {
    final svc = DictionaryService()..loadJson(_sampleJson);
    final all = svc.loadedEntries;
    expect(all.any((e) => e.headword == '会う'), isTrue);
    expect(all.any((e) => e.headword == 'remember'), isTrue); // 含样例
  });
}

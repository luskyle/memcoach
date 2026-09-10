import 'package:flutter_test/flutter_test.dart';
import 'package:memcoach/content/builtin_plugins.dart';
import 'package:memcoach/content/content_plugin.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ContentRegistry.builtin', () {
    test('注册四个内置插件，玩法齐全', () async {
      final plugins = await ContentRegistry.builtin();
      expect(plugins, hasLength(4));
      final kinds = plugins.map((p) => p.kind).toSet();
      expect(kinds, containsAll(
          {ContentKind.flashcard, ContentKind.quiz, ContentKind.cloze}));
    });

    test('翻卡插件：英语/日语词条内容完整', () async {
      final plugins = await ContentRegistry.builtin();
      final en = plugins.firstWhere((p) => p.id == 'words.en.daily');
      expect(en.items, hasLength(50));
      for (final item in en.items) {
        final fc = item as FlashcardItem;
        expect(fc.front, isNotEmpty);
        expect(fc.back, isNotEmpty);
      }

      final ja = plugins.firstWhere((p) => p.id == 'words.ja.jlpt');
      expect(ja.items.length, greaterThan(0));
      expect(ja.items.length, lessThanOrEqualTo(60));
    });

    test('单选插件：答案下标合法', () async {
      final plugins = await ContentRegistry.builtin();
      final quiz = plugins.firstWhere((p) => p.kind == ContentKind.quiz);
      expect(quiz.items.length, greaterThanOrEqualTo(10));
      for (final item in quiz.items) {
        final q = item as QuizItem;
        expect(q.options.length, greaterThanOrEqualTo(3));
        expect(q.answerIndex, inInclusiveRange(0, q.options.length - 1));
      }
    });

    test('填空插件：古诗词行数据完整', () async {
      final plugins = await ContentRegistry.builtin();
      final poetry = plugins.firstWhere((p) => p.id == 'poetry.cn');
      expect(poetry.items.length, greaterThanOrEqualTo(20));
      for (final item in poetry.items) {
        final c = item as ClozeItem;
        expect(c.title, isNotEmpty);
        expect(c.lines.length, greaterThanOrEqualTo(2));
        expect(c.subtitle, isNotEmpty);
      }
    });
  });
}
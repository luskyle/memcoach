import 'package:flutter_test/flutter_test.dart';
import 'package:memcoach/domain/tagging/language.dart';

void main() {
  group('detectLang', () {
    test('日语：含假名即判定 ja（无论是否混汉字）', () {
      expect(detectLang('たべる'), ContentLang.ja);
      expect(detectLang('食べる'), ContentLang.ja);
      expect(detectLang('ありがとうございます'), ContentLang.ja);
      expect(detectLang('日本語を勉強しています'), ContentLang.ja);
    });

    test('中文：含汉字但无假名', () {
      expect(detectLang('你好世界'), ContentLang.zh);
      expect(detectLang('复习记忆曲线'), ContentLang.zh);
    });

    test('英语：纯拉丁字母', () {
      expect(detectLang('hello world'), ContentLang.en);
      expect(detectLang('Spaced repetition'), ContentLang.en);
    });

    test('混合英中按规则回退到 zh（含汉字）', () {
      expect(detectLang('hello 世界'), ContentLang.zh);
    });

    test('其它：数字符号与空文本', () {
      expect(detectLang(''), ContentLang.other);
      expect(detectLang('12345'), ContentLang.other);
      expect(detectLang('---'), ContentLang.other);
    });
  });

  group('langCodeOf / langsFromCodes', () {
    test('代码映射', () {
      expect(langCodeOf(ContentLang.ja), 'ja');
      expect(langCodeOf(ContentLang.zh), 'zh');
      expect(langCodeOf(ContentLang.en), 'en');
      expect(langCodeOf(ContentLang.other), 'other');
    });

    test('代码反查', () {
      final langs = langsFromCodes(['ja', 'en', ''])
        ..sort((a, b) => a.index.compareTo(b.index));
      expect(langs, [ContentLang.ja, ContentLang.en, ContentLang.other]);
    });
  });
}
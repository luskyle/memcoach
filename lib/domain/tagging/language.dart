/// 收藏内容的语言判定（纯函数）。
///
/// 依据《记忆教练-内容分类机制设计》：「语言」是自动标注的副标签，
/// 决定复习过滤与多语言统计。MVP 用启发式规则（LLM 打标为后期增强路线）。
library;

enum ContentLang { ja, en, zh, other }

/// 简单的语言启发式判定：
/// - 含假名（平/片假名）→ 日语
/// - 含 CJK 汉字但无假名 → 中文
/// - 以拉丁字母为主 → 英语
/// - 其余 → other
ContentLang detectLang(String text) {
  if (text.isEmpty) return ContentLang.other;

  final hasKana = RegExp(r'[\u3040-\u30ff]').hasMatch(text);
  final hasKanji = RegExp(r'[\u3400-\u4dbf\u4e00-\u9fff]').hasMatch(text);
  final latinLetters = RegExp(r'[a-zA-Z]').allMatches(text).length;

  if (hasKana) return ContentLang.ja;
  if (hasKanji) return ContentLang.zh;
  if (latinLetters > 0) return ContentLang.en;
  return ContentLang.other;
}

/// 语言代码（数据库 lang 字段用 ISO 639-1 小写）。
String langCodeOf(ContentLang lang) {
  return switch (lang) {
    ContentLang.ja => 'ja',
    ContentLang.zh => 'zh',
    ContentLang.en => 'en',
    ContentLang.other => 'other',
  };
}

/// 以指定列表判定（收件箱/记忆库筛选用）。
List<ContentLang> langsFromCodes(Iterable<String> codes) {
  return codes.map((c) => switch (c) {
        'ja' => ContentLang.ja,
        'zh' => ContentLang.zh,
        'en' => ContentLang.en,
        _ => ContentLang.other,
      }).toList();
}
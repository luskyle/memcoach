import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'content_plugin.dart';

/// 内置内容插件注册表。
///
/// 每个内置插件 = 清单信息 + 内容数据（JSON 资产或动态生成）。
/// 未来在线商店：新增网络来源的插件列表即可，内容结构保持一致。
class ContentRegistry {
  /// 全部内置插件。
  static Future<List<ContentPlugin>> builtin() async => [
        await _poetryPlugin(),
        await _enWordsPlugin(),
        await _jaWordsPlugin(),
        await _quizPlugin(),
      ];

  // ---- 古诗词（cloze）----

  static const _poetryAsset = 'lib/assets/poetry/poems.json';

  static Future<ContentPlugin> _poetryPlugin() async {
    final raw = jsonDecode(await rootBundle.loadString(_poetryAsset));
    final items = <ContentItem>[
      for (final e in (raw as List))
        ClozeItem(
          title: e['title'] as String,
          subtitle: e['author'] as String,
          lines: (e['lines'] as List).cast<String>(),
        ),
    ];
    return ContentPlugin(
      id: 'poetry.cn',
      name: '古诗词',
      description: '经典古诗，挖空补全背诵',
      kind: ContentKind.cloze,
      items: items,
    );
  }

  // ---- 英语常用词（flashcard）----

  static const _enAsset = 'lib/assets/content/en-daily.json';

  static Future<ContentPlugin> _enWordsPlugin() async {
    final raw = jsonDecode(await rootBundle.loadString(_enAsset));
    final entries = (raw['entries'] as List).cast<Map<String, dynamic>>();
    final items = <ContentItem>[
      for (final e in entries)
        FlashcardItem(front: e['word'] as String, back: e['meaning'] as String),
    ];
    return ContentPlugin(
      id: 'words.en.daily',
      name: '英语常用词',
      description: '50 个高频英语核心词（翻卡）',
      kind: ContentKind.flashcard,
      locale: 'en',
      items: items,
    );
  }

  // ---- 日语常用词（flashcard，取自 JLPT 词库资产）----

  static const _jlptAsset = 'lib/assets/dictionary/jlpt.json';

  static Future<ContentPlugin> _jaWordsPlugin() async {
    final raw = jsonDecode(await rootBundle.loadString(_jlptAsset));
    final entries = (raw['entries'] as List).cast<Map<String, dynamic>>();
    // 取 N5（level == '5'）优先，不足再用 kana/其他，最多 60 词
    final n5 = entries.where((e) => e['level'] == '5').toList();
    final picked = (n5.isNotEmpty ? n5 : entries).take(60).toList();
    final items = <ContentItem>[
      for (final e in picked)
        FlashcardItem(
          front: e['headword'] is String
              ? '${e['headword']}（${e['reading']}）'
              : '${e['headword']}',
          back: e['meaning'] as String,
        ),
    ];
    return ContentPlugin(
      id: 'words.ja.jlpt',
      name: '日语基础词',
      description: 'JLPT N5 高频词汇（翻卡）',
      kind: ContentKind.flashcard,
      locale: 'ja',
      items: items,
    );
  }

  // ---- 趣味常识问答（quiz）----

  static const _quizAsset = 'lib/assets/content/general-quiz.json';

  static Future<ContentPlugin> _quizPlugin() async {
    final raw = jsonDecode(await rootBundle.loadString(_quizAsset));
    final items = <ContentItem>[
      for (final e in (raw['items'] as List))
        QuizItem(
          prompt: e['prompt'] as String,
          options: (e['options'] as List).cast<String>(),
          answerIndex: e['answer'] as int,
          explanation: e['explanation'] as String?,
        ),
    ];
    return ContentPlugin(
      id: 'quiz.cn.general',
      name: '趣味常识',
      description: '20 道常识趣味单选',
      kind: ContentKind.quiz,
      items: items,
    );
  }
}

/// 训练集目录来源（社区）。
///
/// 当前为内置来源；未来接远程服务器时实现 [RemoteTrainingSetSource] 即可，
/// 社区界面与训练流程无需改动。
abstract class TrainingSetSource {
  Future<List<ContentPlugin>> catalog();
}

/// 内置目录（App 打包的资产）。
class BuiltinTrainingSetSource implements TrainingSetSource {
  const BuiltinTrainingSetSource();

  @override
  Future<List<ContentPlugin>> catalog() => ContentRegistry.builtin();
}

/// 远程目录（预留接口，尚未接入后端）。
class RemoteTrainingSetSource implements TrainingSetSource {
  const RemoteTrainingSetSource();

  @override
  Future<List<ContentPlugin>> catalog() async => const <ContentPlugin>[];
}
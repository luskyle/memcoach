import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:memcoach/domain/poetry/poetry_puzzle.dart';

void main() {
  group('createBlanks', () {
    const lines = [
      '床前明月光',
      '疑是地上霜',
      '举头望明月',
      '低头思故乡',
    ];

    test('挖空数量正确且位置在句内', () {
      final rng = Random(42);
      final blanks = createBlanks(lines, count: 4, random: rng);
      expect(blanks, hasLength(4));
      for (final b in blanks) {
        expect(b.lineIndex, inInclusiveRange(0, lines.length - 1));
        expect(b.start + b.length, lessThanOrEqualTo(lines[b.lineIndex].length));
        expect(b.length, inInclusiveRange(1, 2));
        // 挖掉的字不是空串
        expect(b.answerIn(lines), isNotEmpty);
      }
    });

    test('短句不挖空', () {
      final rng = Random(1);
      final blanks = createBlanks(['鹅', '鹅鹅鹅', '曲项向天歌'], count: 3, random: rng);
      // '鹅' 只有 1 字，'鹅鹅鹅' 只有 3 字（== 3 允许挖）
      // 至少 '鹅' 不会被挖
      for (final b in blanks) {
        expect(lines[b.lineIndex].length, greaterThanOrEqualTo(3));
      }
    });
  });

  group('PoetryPuzzle.segmentsOf', () {
    test('片段拼接还原原句', () {
      const poem = Poem(
        title: '静夜思',
        author: '李白',
        lines: ['床前明月光', '疑是地上霜', '举头望明月', '低头思故乡'],
      );
      final blanks = createBlanks(poem.lines, count: 4, random: Random(1));
      final puzzle = PoetryPuzzle(poem: poem, blanks: blanks);
      for (var li = 0; li < poem.lines.length; li++) {
        final segments = puzzle.segmentsOf(li);
        final buf = StringBuffer();
        for (final s in segments) {
          buf.write(s.text ?? s.blank!.answerIn(poem.lines));
        }
        expect(buf.toString(), poem.lines[li]);
      }
    });

    test('空位不重叠', () {
      const poem = Poem(
        title: '静夜思',
        author: '李白',
        lines: ['床前明月光', '疑是地上霜', '举头望明月', '低头思故乡'],
      );
      final blanks = createBlanks(poem.lines, count: 4, random: Random(7));
      // 同一句至多一个空（我们的生成策略保证）
      final perLine = <int, int>{};
      for (final b in blanks) {
        perLine[b.lineIndex] = (perLine[b.lineIndex] ?? 0) + 1;
      }
      for (final v in perLine.values) {
        expect(v, 1);
      }
    });
  });

  group('blankIsCorrect', () {
    test('空格容错正确判定', () {
      const lines = ['床前明月光'];
      const b = PuzzleBlank(lineIndex: 0, start: 0, length: 1);
      expect(blankIsCorrect(b, lines, '床'), isTrue);
      expect(blankIsCorrect(b, lines, ' 床 '), isTrue);
      expect(blankIsCorrect(b, lines, '明'), isFalse);
    });
  });
}
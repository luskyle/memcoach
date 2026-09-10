import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter_test/flutter_test.dart';
import 'package:memcoach/data/database/database.dart';
import 'package:memcoach/data/export/export_service.dart';
import 'package:memcoach/data/repositories/review_repository.dart';
import 'package:memcoach/domain/srs/sm2.dart';

void main() {
  late AppDatabase db;
  late Directory exportDir;

  setUp(() {
    db = AppDatabase.forTesting();
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> seedLogs() async {
    final now = DateTime(2026, 9, 1, 10);
    final cardId = await db.into(db.cards).insert(
          CardsCompanion.insert(
            kind: const drift.Value('word'),
            prompt: 'remember',
            answer: '记得',
            lang: const drift.Value('en'),
            dueAt: now,
            createdAt: now,
          ),
        );
    await db.into(db.items).insert(
          ItemsCompanion.insert(
            cardId: drift.Value(cardId),
            source: const drift.Value('manual'),
            lang: const drift.Value('en'),
            status: const drift.Value('learning'),
            createdAt: now,
          ),
        );
    final repo = ReviewRepository(db);
    await repo.reviewCard(
        cardId: cardId, rating: ReviewRating.remembered, now: now);
    await repo.reviewCard(
        cardId: cardId,
        rating: ReviewRating.fuzzy,
        now: now.add(const Duration(days: 2)));
  }

  test('导出 zip：内含 memcoach_data.json 与 README，数据完整', () async {
    exportDir = await Directory.systemTemp.createTemp('export_test');
    addTearDown(() => exportDir.delete(recursive: true));
    await seedLogs();

    final path = await ExportService(directory: exportDir).export(db);
    expect(path, endsWith('.zip'));
    expect(File(path).existsSync(), isTrue);

    final bytes = File(path).readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);
    expect(archive.findFile('memcoach_data.json'), isNotNull);
    expect(archive.findFile('README.txt'), isNotNull);

    final rawJson = archive.findFile('memcoach_data.json')!.content;
    final payload =
        jsonDecode(utf8.decode(rawJson as List<int>)) as Map<String, dynamic>;
    expect(payload['app'], 'memcoach');
    expect(payload['items'], hasLength(1));
    expect(payload['review_logs'], hasLength(2));
    expect(payload['cards'], hasLength(1));
  });

  test('dailyReviewCounts：按天聚合复习次数', () async {
    await seedLogs();

    final repo = ReviewRepository(db);
    final counts = await repo.dailyReviewCounts(
      now: DateTime(2026, 9, 3, 10),
      weeks: 4,
    );

    expect(counts[DateTime(2026, 9, 1)], 1);
    expect(counts[DateTime(2026, 9, 3)], 1);
    // 远离窗口外的日期不应出现（默认 12 周窗口外）
    expect(counts[DateTime(2026, 1, 1)], isNull);
  });
}

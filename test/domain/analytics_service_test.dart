import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memcoach/data/analytics/analytics_service.dart';

void main() {
  group('埋点服务（内存模式）', () {
    test('track 记录事件（含时间戳与属性）', () {
      final svc = AnalyticsService();
      svc.track(AnalyticsEvents.appOpen);
      svc.track(AnalyticsEvents.reviewRating, props: {'quality': 4});
      svc.track(AnalyticsEvents.itemCollected, props: {'source': 'study'});

      expect(svc.events, hasLength(3));
      expect(svc.events[0]['event'], AnalyticsEvents.appOpen);
      expect(svc.events[0]['ts'], isNotNull);
      expect(svc.events[1]['quality'], 4);
      expect(svc.events[2]['source'], 'study');
    });

    test('一次会话中包含留存漏斗关键事件', () {
      final svc = AnalyticsService();
      svc.track(AnalyticsEvents.appOpen);
      svc.track(AnalyticsEvents.itemCollected, props: {'source': 'study'});
      svc.track(AnalyticsEvents.reviewRating, props: {'quality': 3});
      svc.track(AnalyticsEvents.reviewSessionCompleted, props: {'count': 5});
      svc.track(AnalyticsEvents.paywallShown, props: {'reason': '配额'});
      svc.track(AnalyticsEvents.exportUsed);

      expect(svc.events, hasLength(6));
    });
  });

  group('埋点服务（落盘模式）', () {
    test('事件写入 JSONL 文件（append-only）', () async {
      final dir = await Directory.systemTemp.createTemp('analytics_test');
      addTearDown(() => dir.delete(recursive: true));

      final svc = AnalyticsService(directory: dir);
      svc.track(AnalyticsEvents.appOpen);
      svc.track(AnalyticsEvents.itemCollected, props: {'source': 'manual'});

      // 等待异步落盘完成
      File? file;
      for (var i = 0; i < 50; i++) {
        final f = dir.listSync().whereType<File>().toList();
        file = f.isEmpty ? null : f.single;
        if (file != null &&
            file.existsSync() &&
            file.readAsLinesSync().length == 2) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      expect(file, isNotNull);
      final lines = file!.readAsLinesSync();
      expect(lines, hasLength(2));
      expect(lines[0], contains('"event":"app_open"'));
      expect(lines[1], contains('"source":"manual"'));
    });
  });
}

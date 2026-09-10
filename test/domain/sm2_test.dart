import 'package:flutter_test/flutter_test.dart';
import 'package:memcoach/domain/srs/sm2.dart';

void main() {
  final now = DateTime(2026, 9, 7, 10, 0); // 固定时间，保证可复现

  group('新卡初始状态', () {
    test('默认状态：reps=0, ef=2.5, interval=0', () {
      const s = Sm2State();
      expect(s.repetitions, 0);
      expect(s.easeFactor, Sm2State.defaultEase);
      expect(s.intervalDays, 0);
    });

    test('首次排期 = 明天', () {
      final due = firstReviewDueAt(now);
      expect(due, now.add(const Duration(days: 1)));
    });
  });

  group('答对路径（quality >= 3）', () {
    test('第一次答对：间隔 1 天，reps=1', () {
      final r = sm2Review(const Sm2State(), 4, now: now);
      expect(r.state.repetitions, 1);
      expect(r.state.intervalDays, 1);
      expect(r.dueAt, now.add(const Duration(days: 1)));
    });

    test('第二次连续答对：间隔 6 天，reps=2', () {
      final first = sm2Review(const Sm2State(), 4, now: now);
      final second = sm2Review(first.state, 4, now: now);
      expect(second.state.repetitions, 2);
      expect(second.state.intervalDays, 6);
    });

    test('第三次答对：间隔 = round(6 × EF)', () {
      final a = sm2Review(const Sm2State(), 4, now: now);
      final b = sm2Review(a.state, 4, now: now);
      // EF=2.5（q=4 不改变 EF）→ 6×2.5=15
      final c = sm2Review(b.state, 4, now: now);
      expect(c.state.intervalDays, 15);
    });

    test('间隔单调增长：连续答对间隔越来越大（含 EF 变化）', () {
      var s = const Sm2State();
      var prev = 0;
      for (var i = 0; i < 12; i++) {
        final r = sm2Review(s, 4, now: now);
        expect(r.state.intervalDays, greaterThan(prev));
        prev = r.state.intervalDays;
        s = r.state;
      }
    });

    test('quality=5 时 EF 提升 0.1', () {
      const s = Sm2State();
      final r = sm2Review(s, 5, now: now);
      expect(r.state.easeFactor, closeTo(2.6, 1e-9));
    });

    test('quality=4 时 EF 不变', () {
      const s = Sm2State();
      final r = sm2Review(s, 4, now: now);
      expect(r.state.easeFactor, closeTo(2.5, 1e-9));
    });

    test('quality=3 时 EF 略微下降（-0.14）', () {
      const s = Sm2State();
      final r = sm2Review(s, 3, now: now);
      expect(r.state.easeFactor, closeTo(2.36, 1e-9));
    });
  });

  group('答错路径（quality < 3，重学）', () {
    test('新卡答错：reps=0，间隔 1 天，EF 不变', () {
      const s = Sm2State();
      final r = sm2Review(s, 1, now: now);
      expect(r.state.repetitions, 0);
      expect(r.state.intervalDays, 1);
      expect(r.state.easeFactor, Sm2State.defaultEase);
      expect(r.dueAt, now.add(const Duration(days: 1)));
    });

    test('成熟卡答错：重学路径（reps 归零、间隔重置 1 天）', () {
      // 构造一个成熟卡：三次答对后
      var s = const Sm2State();
      for (var i = 0; i < 3; i++) {
        s = sm2Review(s, 4, now: now).state;
      }
      expect(s.repetitions, 3);
      final fail = sm2Review(s, 1, now: now);
      expect(fail.state.repetitions, 0);
      expect(fail.state.intervalDays, 1);
      // EF 在失败时不改变
      expect(fail.state.easeFactor, s.easeFactor);
    });

    test('重学后再答对：重新走 1 → 6 → ... 阶梯', () {
      var s = sm2Review(const Sm2State(), 4, now: now).state;
      s = sm2Review(s, 1, now: now).state; // 答错，回到学习态
      final again = sm2Review(s, 4, now: now);
      expect(again.state.repetitions, 1);
      expect(again.state.intervalDays, 1);
      final again2 = sm2Review(again.state, 4, now: now);
      expect(again2.state.intervalDays, 6);
    });

    test('quality=0 与 quality=2 同样视为答错', () {
      final r0 = sm2Review(const Sm2State(), 0, now: now);
      final r2 = sm2Review(const Sm2State(), 2, now: now);
      expect(r0.state.repetitions, 0);
      expect(r2.state.repetitions, 0);
      expect(r0.state.intervalDays, 1);
      expect(r2.state.intervalDays, 1);
    });
  });

  group('EF 钳制（1.3 ~ 3.0）', () {
    test('连续答错不把 EF 压到 1.3 以下', () {
      var s = const Sm2State();
      // 故意用低 quality 多次：q=3 每次 -0.14，最多压到 1.3
      for (var i = 0; i < 100; i++) {
        s = sm2Review(s, 3, now: now).state;
      }
      expect(s.easeFactor, Sm2State.minEase);
      expect(s.easeFactor, greaterThanOrEqualTo(Sm2State.minEase));
    });

    test('长期全对 EF 不超过 3.0', () {
      var s = const Sm2State();
      for (var i = 0; i < 100; i++) {
        s = sm2Review(s, 5, now: now).state;
      }
      expect(s.easeFactor, Sm2State.maxEase);
    });

    test('损坏状态（非法 EF）也能被修正钳制', () {
      const bad = Sm2State(easeFactor: 0.5);
      final r = sm2Review(bad, 4, now: now);
      expect(r.state.easeFactor, Sm2State.minEase);
    });
  });

  group('参数校验', () {
    test('quality 越界抛 ArgumentError', () {
      expect(() => sm2Review(const Sm2State(), -1, now: now), throwsArgumentError);
      expect(() => sm2Review(const Sm2State(), 6, now: now), throwsArgumentError);
    });
  });

  group('到期判定', () {
    test('isDue：到期日当天即到期', () {
      final due = now.add(const Duration(days: 1));
      expect(isDue(due, due), isTrue);
      expect(isDue(due, due.subtract(const Duration(seconds: 1))), isFalse);
    });

    test('sm2QualityFor 三键映射', () {
      expect(sm2QualityFor(ReviewRating.forgot), 1);
      expect(sm2QualityFor(ReviewRating.fuzzy), 3);
      expect(sm2QualityFor(ReviewRating.remembered), 4);
    });
  });

  group('掌握度投影', () {
    test('间隔 >= 90 天视为已掌握', () {
      expect(isMastered(const Sm2State(intervalDays: 90)), isTrue);
      expect(isMastered(const Sm2State(intervalDays: 89)), isFalse);
    });

    test('冷置：超过 30 天未复习', () {
      final last = now.subtract(const Duration(days: 31));
      expect(isCold(lastReviewedAt: last, now: now), isTrue);
      final recent = now.subtract(const Duration(days: 29));
      expect(isCold(lastReviewedAt: recent, now: now), isFalse);
      expect(isCold(lastReviewedAt: null, now: now), isFalse);
    });
  });

  group('长周期稳定性', () {
    test('一年模拟：稳定复习的卡间隔进入数月量级', () {
      var s = const Sm2State();
      var t = now;
      for (var i = 0; i < 60; i++) {
        final r = sm2Review(s, 4, now: t);
        t = r.dueAt;
        s = r.state;
      }
      expect(s.intervalDays, greaterThanOrEqualTo(30));
      expect(s.repetitions, 60);
    });
  });
}
import 'package:flutter_test/flutter_test.dart';
import 'package:memcoach/domain/training.dart';

void main() {
  test('强度预设随强度递减：题量 / 新卡占比 / 间隔增幅 / 时长上限', () {
    final max = intensityPreset(TrainingIntensity.max);
    final medium = intensityPreset(TrainingIntensity.medium);
    final relaxed = intensityPreset(TrainingIntensity.relaxed);

    expect(max.cardCount, greaterThan(medium.cardCount));
    expect(medium.cardCount, greaterThan(relaxed.cardCount));

    expect(max.newRatio, greaterThan(medium.newRatio));
    expect(medium.newRatio, greaterThan(relaxed.newRatio));

    expect(max.intervalMultiplier, greaterThan(medium.intervalMultiplier));
    expect(medium.intervalMultiplier, greaterThan(relaxed.intervalMultiplier));

    expect(max.durationCapMinutes, greaterThan(medium.durationCapMinutes));
    expect(medium.durationCapMinutes, greaterThan(relaxed.durationCapMinutes));
  });

  test('新卡目标 = 题量 × 新卡占比（向下取整）', () {
    final max = intensityPreset(TrainingIntensity.max);
    final medium = intensityPreset(TrainingIntensity.medium);
    final relaxed = intensityPreset(TrainingIntensity.relaxed);

    expect(max.newCardTarget(), (max.cardCount * max.newRatio).round());
    expect(medium.newCardTarget(), (medium.cardCount * medium.newRatio).round());
    expect(relaxed.newCardTarget(),
        (relaxed.cardCount * relaxed.newRatio).round());
  });

  test('applyIntervalMultiplier 缩放间隔并钳制到至少 1 天', () {
    expect(applyIntervalMultiplier(4, 0.75), 3); // 轻松：增长放缓
    expect(applyIntervalMultiplier(10, 1.1), 11); // Max：增长加快
    expect(applyIntervalMultiplier(1, 0.75), 1); // 最低 1 天
    expect(applyIntervalMultiplier(0, 2.0), 1); // 非法输入钳制
  });

  test('强度文案映射：自评状态与模式名', () {
    expect(intensityStateLabel(TrainingIntensity.max), '状态很好');
    expect(intensityModeLabel(TrainingIntensity.max), 'Max 强度模式');
    expect(intensityStateLabel(TrainingIntensity.medium), '状态一般');
    expect(intensityModeLabel(TrainingIntensity.relaxed), '轻松训练模式');
  });
}
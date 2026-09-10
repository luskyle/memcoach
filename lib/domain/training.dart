/// 训练强度机制：开训前自评状态 → 映射到三种强度模式。
///
/// 强度影响四个维度（2026-09-10 确认）：
/// 1. 每次训练题量 / 卡片数（cardCount）
/// 2. SM-2 间隔增幅（intervalMultiplier）
/// 3. 新卡 vs 复习卡比例（newRatio）
/// 4. 训练时长 / 上限（durationCapMinutes）
library;

/// 三种训练强度。
enum TrainingIntensity { max, medium, relaxed }

/// 强度预设参数。
class IntensityPreset {
  const IntensityPreset({
    required this.cardCount,
    required this.newRatio,
    required this.intervalMultiplier,
    required this.durationCapMinutes,
  });

  /// 一轮训练的目标卡片数。
  final int cardCount;

  /// 新卡占比（0~1），剩余为到期复习卡。
  final double newRatio;

  /// SM-2 间隔增幅：>1 增长更快，<1 更保守（轻松模式复习更频繁）。
  final double intervalMultiplier;

  /// 单轮训练时长上限（分钟，软上限：到时给「今日训练已达上限」提示）。
  final int durationCapMinutes;

  /// 本轮新卡目标数（向下取整）。
  int newCardTarget() => (cardCount * newRatio).round();
}

/// 强度 → 预设（题量递减 / 间隔增幅递减 / 新卡占比递减）。
IntensityPreset intensityPreset(TrainingIntensity intensity) {
  return switch (intensity) {
    TrainingIntensity.max => const IntensityPreset(
        cardCount: 30,
        newRatio: 0.6,
        intervalMultiplier: 1.1,
        durationCapMinutes: 20,
      ),
    TrainingIntensity.medium => const IntensityPreset(
        cardCount: 20,
        newRatio: 0.35,
        intervalMultiplier: 1.0,
        durationCapMinutes: 12,
      ),
    TrainingIntensity.relaxed => const IntensityPreset(
        cardCount: 10,
        newRatio: 0.1,
        intervalMultiplier: 0.75,
        durationCapMinutes: 8,
      ),
  };
}

/// 强度 → 自评文案（用户视角的状态描述）。
String intensityStateLabel(TrainingIntensity intensity) {
  return switch (intensity) {
    TrainingIntensity.max => '状态很好',
    TrainingIntensity.medium => '状态一般',
    TrainingIntensity.relaxed => '状态很差',
  };
}

/// 强度 → 模式文案。
String intensityModeLabel(TrainingIntensity intensity) {
  return switch (intensity) {
    TrainingIntensity.max => 'Max 强度模式',
    TrainingIntensity.medium => '中等训练强度',
    TrainingIntensity.relaxed => '轻松训练模式',
  };
}

/// 强度 → 一句话说明（自评卡片副文案）。
String intensityDescription(TrainingIntensity intensity) {
  return switch (intensity) {
    TrainingIntensity.max => '精神饱满，来一轮高强度冲刺',
    TrainingIntensity.medium => '平稳推进，保持节奏',
    TrainingIntensity.relaxed => '状态欠佳，轻松巩固为主',
  };
}

/// 对 SM-2 计算出的间隔应用强度增幅，返回钳制到 [1, maxIntervalDays] 的天数。
int applyIntervalMultiplier(int interval, double multiplier) {
  if (interval <= 0) return 1;
  final scaled = (interval * multiplier).round();
  if (scaled < 1) return 1;
  return scaled;
}
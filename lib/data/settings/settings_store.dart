import 'package:shared_preferences/shared_preferences.dart';

/// 应用设置 KV（Hive 缓存的轻量替代：设置类数据无需关系查询）。
class SettingsStore {
  SettingsStore(this._prefs);

  final SharedPreferences _prefs;

  static const _kPro = 'settings.is_pro';
  static const _kOnboarded = 'settings.onboarded';
  static const _kThemeMode = 'settings.theme_mode';
  static const _kViewMode = 'settings.library_view_mode';

  /// 是否 Pro（MVP 阶段默认 false；内购在阶段 2 接入）。
  bool get isPro => _prefs.getBool(_kPro) ?? false;
  Future<void> setPro(bool v) => _prefs.setBool(_kPro, v);

  /// 主题模式：system | light | dark。
  String get themeMode => _prefs.getString(_kThemeMode) ?? 'system';
  Future<void> setThemeMode(String v) => _prefs.setString(_kThemeMode, v);

  /// 记忆库视图：list | grid（网格卡片）。
  String get libraryViewMode => _prefs.getString(_kViewMode) ?? 'list';
  Future<void> setLibraryViewMode(String v) => _prefs.setString(_kViewMode, v);

  bool get onboarded => _prefs.getBool(_kOnboarded) ?? false;
  Future<void> setOnboarded() => _prefs.setBool(_kOnboarded, true);
}

/// 免费额度（非 Pro）。
class Quota {
  const Quota._();

  static const int maxLibraryCards = 100;
  static const int maxDailyReviews = 9999; // 已移除每日复习次数限制
}

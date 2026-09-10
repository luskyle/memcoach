import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// 埋点事件（10+ 核心事件，见《开发计划》阶段 0「埋点骨架」）。
///
/// 用途：
/// - 本地 JSONL 落盘（append-only，随日期分文件）——离线可用、可回放
/// - 上报占位：接入轻量服务器/Supabase 后，在 [track] 内追加 POST
class AnalyticsEvents {
  AnalyticsEvents._();

  static const appOpen = 'app_open';
  static const appResume = 'app_resume';
  static const appBackground = 'app_background';
  static const appTabViewed = 'app_tab_viewed';
  static const itemCollected = 'item_collected';
  static const itemCardCreated = 'item_card_created';
  static const reviewRating = 'review_rating';
  static const reviewSessionCompleted = 'review_session_completed';
  static const paywallShown = 'paywall_shown';
  static const exportUsed = 'export_used';
}

/// 埋点服务：本地记录 + 上报占位。
class AnalyticsService {
  AnalyticsService({Directory? directory}) : _directory = directory;

  final Directory? _directory;
  File? _file;

  /// 内存缓冲（无目录/测试模式；也用于避免小事件频繁 IO 的批量攒批）。
  final List<Map<String, Object?>> _buffer = [];

  /// 已记录的事件（测试与导出用）。
  List<Map<String, Object?>> get events => List.unmodifiable(_buffer);

  Future<void> _ensureFile() async {
    if (_file != null || _directory == null) return;
    final dir = _directory; // 已判非空
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    final now = DateTime.now();
    final stamp = '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}';
    _file = File(p.join(dir.path, 'events_$stamp.jsonl'));
  }

  /// 记录事件。[props] 应只含可 JSON 序列化的基本类型。
  void track(String name, {Map<String, Object?>? props}) {
    final row = <String, Object?>{
      'ts': DateTime.now().toIso8601String(),
      'event': name,
      ...?props,
    };
    _buffer.add(row);
    unawaited(_write(row));
  }

  Future<void> _write(Map<String, Object?> row) async {
    // 上报占位：接入自建轻量服务器 / Supabase 后在此时发送 JSON。
    // TODO(analytics): POST $serverUrl/events（文本日志，绝不包含媒体路径/正文内容）
    try {
      await _ensureFile(); // 首事件需先建文件，避免丢事件
      _file?.writeAsStringSync(
        '${jsonEncode(row)}\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {
      // 落盘失败不影响主流程
    }
  }

  void dispose() {
    _file = null;
  }
}

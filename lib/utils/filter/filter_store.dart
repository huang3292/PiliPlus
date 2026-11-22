import 'dart:convert';

import 'package:PiliPlus/utils/filter/filter_engine.dart';
import 'package:PiliPlus/utils/filter/filter_marks.dart';
import 'package:PiliPlus/utils/filter/filter_migration.dart';
import 'package:PiliPlus/utils/filter/filter_rule.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter/foundation.dart';

/// 隐藏规则的读写入口：启动时加载、把旧数据一次性搬到当前版本，
/// 之后所有判定都走内存里的引擎。
abstract final class FilterStore {
  static FilterConfig _config = FilterConfig.empty;
  static FilterEngine _engine = FilterEngine(_config);

  /// 规则、例外或显示设置一变就 +1，已经打开的设置页靠它刷新。
  static final ValueNotifier<int> revision = ValueNotifier(0);

  static FilterEngine get engine => _engine;
  static FilterConfig get config => _config;

  /// 迁移过程中丢掉/改写的东西，界面上要能让用户看见。
  static List<String> get notes => _config.warnings;

  static Future<void> load() async {
    _config = await _migrate();
    _refresh();
  }

  static Future<void> save(FilterConfig config) async {
    _config = config;
    await GStorage.setting.put(SettingBoxKey.filterRules, jsonEncode(config));
    _refresh();
  }

  static void _refresh() {
    _engine = FilterEngine(_config);
    FilterMarks.clear();
    revision.value++;
  }

  /// 读旧数据 → 当前版本。任何一份原始字符串在改写前都先备份一份。
  static Future<FilterConfig> _migrate() async {
    final stored =
        GStorage.setting.get(SettingBoxKey.filterRules, defaultValue: '')
            as String;
    var config = FilterConfig.empty;

    if (stored.isNotEmpty) {
      final decoded = _tryJson(stored);
      if (decoded is Map) {
        final version = decoded['version'] is int
            ? decoded['version'] as int
            : 1;
        if (version < FilterConfig.currentVersion) {
          await GStorage.setting.put(SettingBoxKey.filterRulesBackup, stored);
          config = FilterMigration.v1(decoded) ?? FilterConfig.empty;
        } else {
          config = FilterConfig.fromJson(decoded);
        }
      } else {
        await GStorage.setting.put(SettingBoxKey.filterRulesBackup, stored);
        config = FilterConfig(
          warnings: const ['保存下来的规则读不出来，已备份成原始内容后按空规则处理'],
        );
      }
    }

    return config;
  }

  static int nextId([List<FilterRule>? rules]) {
    var max = 0;
    for (final rule in rules ?? _config.rules) {
      if (rule.id > max) max = rule.id;
    }
    for (final exempt in _config.exempts) {
      if (exempt.id > max) max = exempt.id;
    }
    return max + 1;
  }

  static int _nextExemptId() {
    var max = 0;
    for (final exempt in _config.exempts) {
      if (exempt.id > max) max = exempt.id;
    }
    return max + 1;
  }

  static Object? _tryJson(String source) {
    try {
      return jsonDecode(source);
    } on FormatException {
      return null;
    }
  }

  // ---------------------------------------------------------------- 规则

  static Future<void> upsert(FilterRule rule) async {
    final rules = [..._config.rules];
    final index = rules.indexWhere((item) => item.id == rule.id);
    if (index < 0) {
      rules.add(rule);
    } else {
      rules[index] = rule;
    }
    await save(_config.copyWith(rules: rules));
  }

  static Future<void> remove(FilterRule rule) async {
    await save(
      _config.copyWith(rules: [..._config.rules]..remove(rule)),
    );
  }

  static Future<void> toggle(FilterRule rule, bool enabled) async {
    final rules = [..._config.rules];
    final index = rules.indexWhere((item) => item.id == rule.id);
    if (index < 0) return;
    final old = rules[index];
    rules[index] = FilterRule(
      id: old.id,
      enabled: enabled,
      targets: old.targets,
      conditions: old.conditions,
      action: old.action,
      source: old.source,
    );
    await save(_config.copyWith(rules: rules));
  }

  static Future<void> setAction(FilterTarget target, FilterAction? action) async {
    final display = {..._config.display};
    if (action == null || action == target.defaultAction) {
      display.remove(target);
    } else {
      display[target] = action;
    }
    await save(_config.copyWith(display: display));
  }

  /// 条目上的「隐藏此人」：同一个 uid 可以只隐藏评论，也可以一起隐藏视频和动态。
  static Future<void> blockUid(
    int uid,
    Set<FilterTarget> targets, {
    String name = '',
  }) async {
    final rules = [..._config.rules];
    final index = rules.indexWhere(
      (rule) =>
          rule.conditions.length == 1 &&
          rule.conditions.first.field == FilterField.uid &&
          rule.conditions.first.op == FilterOp.equals &&
          rule.conditions.first.values.first == '$uid',
    );

    if (index < 0) {
      rules.add(
        FilterRule(
          id: nextId(rules),
          targets: targets,
          source: FilterSource.local,
          conditions: [
            FilterCondition(
              field: FilterField.uid,
              op: FilterOp.equals,
              values: ['$uid'],
            ),
          ],
        ),
      );
    } else {
      final old = rules[index];
      final merged = {...old.targets, ...targets};
      if (merged.length == old.targets.length && old.enabled) {
        return;
      }
      rules[index] = FilterRule(
        id: old.id,
        enabled: true,
        targets: merged,
        conditions: old.conditions,
        action: old.action,
        source: old.source,
      );
    }
    await save(_config.copyWith(rules: rules));
    if (name.isNotEmpty) {
      // 只为了以后看得懂这条规则是谁，匹配仍然只认 UID。
      await _rememberName(uid, name);
    }
  }

  // ---------------------------------------------------------------- 例外

  static bool isExempt(int uid) =>
      _config.exempts.any((exempt) => exempt.uid == uid);

  static FilterExempt? exemptOf(int uid) {
    for (final exempt in _config.exempts) {
      if (exempt.uid == uid) return exempt;
    }
    return null;
  }

  static Future<void> exemptUid(int uid, {String name = ''}) async {
    if (isExempt(uid)) return;
    await save(
      _config.copyWith(
        exempts: [
          ..._config.exempts,
          FilterExempt(id: _nextExemptId(), uid: uid, name: name),
        ],
      ),
    );
  }

  static Future<void> removeExempt(int uid) async {
    await save(
      _config.copyWith(
        exempts: [..._config.exempts]..removeWhere(
          (exempt) => exempt.uid == uid,
        ),
      ),
    );
  }

  /// 例外名单里只存了 UID 时，从条目操作进来顺手补个名字方便辨认。
  static Future<void> _rememberName(int uid, String name) async {
    final exempts = [..._config.exempts];
    var changed = false;
    for (var i = 0; i < exempts.length; i++) {
      if (exempts[i].uid == uid && exempts[i].name.isEmpty) {
        exempts[i] = FilterExempt(id: exempts[i].id, uid: uid, name: name);
        changed = true;
      }
    }
    if (changed) await save(_config.copyWith(exempts: exempts));
  }
}

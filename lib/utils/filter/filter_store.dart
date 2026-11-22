import 'dart:convert';

import 'package:PiliPlus/utils/filter/filter_engine.dart';
import 'package:PiliPlus/utils/filter/filter_rule.dart';
import 'package:PiliPlus/utils/filter/legacy_ban_word.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';

/// 屏蔽规则库的读写入口：启动时加载并把旧的 `|` 表达式一次性迁移成
/// 结构化规则，之后所有判定都走内存里的引擎。
abstract final class FilterStore {
  static FilterConfig _config = FilterConfig.empty;
  static FilterEngine _engine = FilterEngine(_config);

  static FilterEngine get engine => _engine;
  static FilterConfig get config => _config;

  static bool blocked(FilterTarget target, FilterSubject subject) =>
      _engine.match(target, subject).isBlocked;

  static Future<void> load() async {
    await _migrateLegacy();
    _replace(GStorage.setting.get(SettingBoxKey.filterRules, defaultValue: ''));
  }

  static Future<void> save(FilterConfig config) async {
    _replace(config);
    await GStorage.setting.put(
      SettingBoxKey.filterRules,
      jsonEncode(config),
    );
  }

  static void _replace(Object? raw) {
    _config = FilterConfig.tryDecode(raw);
    _engine = FilterEngine(_config);
  }

  /// 长按「屏蔽此人」：同一个 uid 可以只屏蔽评论，也可以评论加视频一起屏蔽。
  static Future<void> blockUid(int uid, Set<FilterTarget> targets) async {
    final value = uid.toString();
    final rules = [..._config.rules];
    final index = rules.indexWhere(
      (rule) => rule.field == FilterField.uid && rule.value == value,
    );

    if (index < 0) {
      rules.add(
        FilterRule(
          id: _nextId(),
          targets: targets,
          field: FilterField.uid,
          match: FilterMatch.equals,
          value: value,
        ),
      );
    } else {
      final old = rules[index];
      if (old.targets.containsAll(targets) && old.enabled) return;
      rules[index] = FilterRule(
        id: old.id,
        targets: {...old.targets, ...targets},
        field: old.field,
        match: old.match,
        value: old.value,
        caseSensitive: old.caseSensitive,
        exceptValue: old.exceptValue,
      );
    }

    await save(FilterConfig(rules: rules, exempts: _config.exempts));
  }

  /// 误伤补救：把这个人加进例外名单，优先于所有规则。
  static Future<void> exemptUid(int uid, String nickname) async {
    final value = uid.toString();
    if (_config.exempts.any(
      (exempt) => exempt.field == FilterField.uid && exempt.value == value,
    )) {
      return;
    }
    final exempts = [
      ..._config.exempts,
      FilterExempt(id: _nextId(), field: FilterField.uid, value: value),
      if (nickname.isNotEmpty)
        FilterExempt(id: _nextId(), field: FilterField.nickname, value: nickname),
    ];
    await save(FilterConfig(rules: _config.rules, exempts: exempts));
  }

  static int _nextId() {
    var max = 0;
    for (final rule in _config.rules) {
      if (rule.id > max) max = rule.id;
    }
    for (final exempt in _config.exempts) {
      if (exempt.id > max) max = exempt.id;
    }
    return max + 1;
  }

  static Future<void> _migrateLegacy() async {
    if (GStorage.setting.getBool(SettingBoxKey.filterRulesMigrated)) return;

    final stored = GStorage.setting.get(
      SettingBoxKey.filterRules,
      defaultValue: '',
    );
    if ((stored as String).isEmpty) {
      final rules = LegacyBanWord.migrate([
        (FilterTarget.reply, Pref.banWordForReply),
        (FilterTarget.video, Pref.banWordForRecommend),
        (FilterTarget.video, Pref.banWordForZone),
        (FilterTarget.dyn, Pref.banWordForDyn),
      ]);
      if (rules.isNotEmpty) {
        await GStorage.setting.put(
          SettingBoxKey.filterRules,
          jsonEncode(FilterConfig(rules: rules)),
        );
      }
    }
    await GStorage.setting.put(SettingBoxKey.filterRulesMigrated, true);
  }
}

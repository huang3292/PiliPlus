/// 隐藏判定核心：只做纯计算，不碰网络、不碰存储，也不认识 Hive 里的偏好。
/// 缺数据一律按「放行」处理，宁可漏藏也不误藏，避免把接口没给字段的条目
/// 当成条件成立。
library;

import 'package:PiliPlus/utils/filter/filter_rule.dart';

class FilterSubject {
  final int? uid;
  final String? nickname;
  final String? replyContent;
  final String? dynText;
  final String? dynOrigText;
  final String? videoTitle;
  final String? videoZone;
  final int? level;

  /// 认证：`<0` 无、`0` 个人、`1` 机构；null 表示这个接口没给。
  final int? officialType;

  /// 会员类型：`0` 无、`1` 月度、`2` 年度及以上；null 表示没给。
  final int? vipType;

  /// `1` 表示会员仍在有效期内。
  final int? vipStatus;

  const FilterSubject({
    this.uid,
    this.nickname,
    this.replyContent,
    this.dynText,
    this.dynOrigText,
    this.videoTitle,
    this.videoZone,
    this.level,
    this.officialType,
    this.vipType,
    this.vipStatus,
  });

  int? get uidLength => uid?.toString().length;

  /// 有效大会员要看 status，过期号 type 可能还留着 1/2。
  bool? get vipEffective {
    if (vipType == null || vipStatus == null) return null;
    return vipStatus == 1 && vipType! > 0;
  }

  Object? valueOf(FilterField field) => switch (field) {
    FilterField.replyContent => _text(replyContent),
    FilterField.dynText => _text(dynText),
    FilterField.dynOrigText => _text(dynOrigText),
    FilterField.videoTitle => _text(videoTitle),
    FilterField.videoZone => _text(videoZone),
    FilterField.nickname => _text(nickname),
    FilterField.uid => uid,
    FilterField.uidLength => uidLength,
    FilterField.level => level,
    FilterField.official => _normalizedOfficial,
    FilterField.vipType => vipType,
    FilterField.vipEffective => vipEffective,
  };

  /// 空字符串跟「接口没给这个字段」按同一件事处理：反向条件（不包含、
  /// 不等于）不能因为内容为空就判定成立。
  static String? _text(String? value) =>
      value == null || value.isEmpty ? null : value;

  int? get _normalizedOfficial {
    final value = officialType;
    if (value == null) return null;
    return value < 0 ? -1 : value;
  }
}

class FilterDecision {
  /// 为空表示放行。
  final FilterAction? action;
  final FilterRule? rule;
  final FilterSource? source;

  /// 给人看的说明，用来回答「这条为什么被藏了」。
  final String reason;

  const FilterDecision._({
    this.action,
    this.rule,
    this.source,
    this.reason = '',
  });

  const FilterDecision.pass() : this._();

  factory FilterDecision.hidden({
    required FilterAction action,
    FilterRule? rule,
    required FilterSource source,
    required String reason,
  }) => FilterDecision._(action: action, rule: rule, source: source, reason: reason);

  bool get isHidden => action != null;

  bool get shouldRemove => action == FilterAction.remove;
}

class FilterEngine {
  final FilterConfig _config;
  final Map<String, RegExp?> _compiled = {};

  FilterEngine(this._config);

  /// 没有任何隐藏来源时调用方可以完全跳过判定。
  bool get hasActiveRules => _config.hasActiveRules;

  RegExp? _regExpFor(String source, bool caseSensitive) {
    final key = caseSensitive ? 'C$source' : 'i$source';
    if (_compiled.containsKey(key)) return _compiled[key];
    RegExp? built;
    try {
      built = RegExp(source, caseSensitive: caseSensitive);
    } on FormatException {
      built = null;
    }
    return _compiled[key] = built;
  }

  /// 优先级：手动例外 → 明确隐藏 → B 站黑名单 → 其余规则 → 旧关键词过滤。
  /// [legacyHit] 由调用方按各范围自己的字段算出来（旧表达式匹配的字段和
  /// 新规则不完全一样），这里只负责排在最后。
  FilterDecision decide({
    required FilterTarget target,
    required FilterSubject subject,
    bool blacklisted = false,
    bool legacyHit = false,
  }) {
    for (final exempt in _config.exempts) {
      if (exempt.uid == subject.uid && subject.uid != null) {
        return const FilterDecision.pass();
      }
    }

    final explicit = _firstHit(target, subject, explicitOnly: true);
    if (explicit != null) return explicit;

    if (blacklisted) {
      return FilterDecision.hidden(
        action: _config.actionFor(target),
        source: FilterSource.official,
        reason: '在 B 站黑名单里',
      );
    }

    final general = _firstHit(target, subject, explicitOnly: false);
    if (general != null) return general;

    if (legacyHit) {
      return FilterDecision.hidden(
        action: _config.actionFor(target),
        source: FilterSource.legacy,
        reason: '命中旧关键词过滤',
      );
    }
    return const FilterDecision.pass();
  }

  FilterDecision? _firstHit(
    FilterTarget target,
    FilterSubject subject, {
    required bool explicitOnly,
  }) {
    for (final rule in _config.rules) {
      if (!rule.enabled || !rule.targets.contains(target)) continue;
      if (rule.source.isExplicit != explicitOnly) continue;
      if (!_ruleHits(rule, subject)) continue;
      return FilterDecision.hidden(
        action: rule.action ?? _config.actionFor(target),
        rule: rule,
        source: rule.source,
        reason: rule.summary,
      );
    }
    return null;
  }

  /// 一条规则里的条件是「且」关系。
  bool _ruleHits(FilterRule rule, FilterSubject subject) {
    for (final condition in rule.conditions) {
      if (!_conditionHits(condition, subject)) return false;
    }
    return rule.conditions.isNotEmpty;
  }

  bool _conditionHits(FilterCondition condition, FilterSubject subject) {
    final value = subject.valueOf(condition.field);
    if (value == null) return false;
    return switch (condition.field.kind) {
      FilterFieldKind.text => _hitsText(condition, value as String),
      FilterFieldKind.number => _hitsNumber(condition, value as int),
      FilterFieldKind.choice => _hitsCode(condition, (value as int).toString()),
      FilterFieldKind.toggle =>
        _codeEquals(condition, (value as bool) ? '1' : '0'),
    };
  }

  bool _hitsText(FilterCondition condition, String text) {
    if (condition.op == FilterOp.matches || condition.op == FilterOp.notMatches) {
      final regExp = _regExpFor(condition.values.first, condition.caseSensitive);
      if (regExp == null) return false;
      final matched = regExp.hasMatch(text);
      return condition.op == FilterOp.matches ? matched : !matched;
    }

    final needle = _fold(condition.values.first, condition.caseSensitive);
    final haystack = _fold(text, condition.caseSensitive);
    return switch (condition.op) {
      FilterOp.contains => haystack.contains(needle),
      FilterOp.notContains => !haystack.contains(needle),
      FilterOp.equals => haystack == needle,
      FilterOp.notEquals => haystack != needle,
      FilterOp.startsWith => haystack.startsWith(needle),
      FilterOp.endsWith => haystack.endsWith(needle),
      _ => false,
    };
  }

  bool _hitsNumber(FilterCondition condition, int actual) {
    if (condition.op == FilterOp.between) {
      if (condition.values.length < 2) return false;
      final min = int.tryParse(condition.values[0]);
      final max = int.tryParse(condition.values[1]);
      if (min == null || max == null) return false;
      return actual >= min && actual <= max;
    }
    final bound = int.tryParse(condition.values.first);
    if (bound == null) return false;
    return switch (condition.op) {
      FilterOp.equals => actual == bound,
      FilterOp.notEquals => actual != bound,
      FilterOp.lt => actual < bound,
      FilterOp.lte => actual <= bound,
      FilterOp.gt => actual > bound,
      FilterOp.gte => actual >= bound,
      _ => false,
    };
  }

  /// 认证/会员类型这类固定选项，存的是接口口径的编号。
  bool _hitsCode(FilterCondition condition, String actual) =>
      switch (condition.op) {
        FilterOp.inList => condition.values.contains(actual),
        FilterOp.notInList => !condition.values.contains(actual),
        _ => false,
      };

  bool _codeEquals(FilterCondition condition, String actual) =>
      switch (condition.op) {
        FilterOp.equals => condition.values.first == actual,
        FilterOp.notEquals => condition.values.first != actual,
        _ => false,
      };

  static String _fold(String value, bool caseSensitive) =>
      caseSensitive ? value : value.toLowerCase();

  /// 编辑页的「测试一下」：拿一段文字冒充各字段。
  FilterDecision preview({
    required FilterTarget target,
    required String sample,
  }) => decide(
    target: target,
    subject: FilterSubject(
      uid: int.tryParse(sample),
      nickname: sample,
      replyContent: sample,
      dynText: sample,
      dynOrigText: sample,
      videoTitle: sample,
      videoZone: sample,
      level: int.tryParse(sample),
    ),
  );
}

/// 屏蔽规则的判定核心：只做纯计算，不碰网络、不碰存储，
/// 因此粉丝数/关注数缺失时按“放行”处理，具体补查由调用方负责。
library;

import 'package:PiliPlus/utils/filter/filter_rule.dart';

class FilterSubject {
  final int? uid;
  final String? nickname;
  final String? content;
  final int? level;
  final int? uidLength;
  final int? fans;
  final int? following;
  final int? officialType;
  final bool? isVip;

  const FilterSubject({
    this.uid,
    this.nickname,
    this.content,
    this.level,
    this.uidLength,
    this.fans,
    this.following,
    this.officialType,
    this.isVip,
  });

  int? get _resolvedUidLength =>
      uidLength ?? uid?.toString().length;
}

class FilterMatchResult {
  /// 命中并放行（例外名单）。
  final bool exempted;

  /// 命中的规则，用于「为什么屏蔽了我」和命中预览。
  final FilterRule? rule;

  /// 规则要用的用户资料还没查到。
  final bool needsUserStats;

  const FilterMatchResult._({
    this.exempted = false,
    this.rule,
    this.needsUserStats = false,
  });

  static const pass = FilterMatchResult._();
  static FilterMatchResult blocked(FilterRule rule) =>
      FilterMatchResult._(rule: rule);
  static const FilterMatchResult exempt = FilterMatchResult._(exempted: true);
  static const FilterMatchResult pendingStats = FilterMatchResult._(
    needsUserStats: true,
  );

  bool get isBlocked => rule != null;
}

class FilterEngine {
  final FilterConfig _config;
  final Map<String, RegExp?> _compiled = {};

  FilterEngine(this._config);

  /// 没有任何启用规则时调用方可以完全跳过判定。
  bool get hasActiveRules => _config.rules.any((rule) => rule.enabled);

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

  /// 是否存在“当前作用域生效、且需要额外用户资料”的启用规则。
  bool needsUserStats(FilterTarget target) {
    for (final rule in _config.rules) {
      if (rule.enabled &&
          rule.targets.contains(target) &&
          rule.field.needsRemoteLookup) {
        return true;
      }
    }
    return false;
  }

  FilterMatchResult match(FilterTarget target, FilterSubject subject) {
    var sawPending = false;

    for (final exempt in _config.exempts) {
      if (exempt.enabled && _hitsExempt(exempt, subject)) {
        return FilterMatchResult.exempt;
      }
    }

    for (final rule in _config.rules) {
      if (!rule.enabled || !rule.targets.contains(target)) continue;
      switch (_evaluate(rule, subject)) {
        case _Outcome.hit:
          return FilterMatchResult.blocked(rule);
        case _Outcome.pending:
          sawPending = true;
        case _Outcome.miss:
          break;
      }
    }

    return sawPending ? FilterMatchResult.pendingStats : FilterMatchResult.pass;
  }

  bool _hitsExempt(FilterExempt exempt, FilterSubject subject) {
    return switch (exempt.field) {
      FilterField.uid => subject.uid?.toString() == exempt.value,
      FilterField.nickname =>
        subject.nickname?.toLowerCase() == exempt.value.toLowerCase(),
      _ => false,
    };
  }

  _Outcome _evaluate(FilterRule rule, FilterSubject subject) {
    final field = rule.field;
    if (field.needsRemoteLookup) {
      final value = field == FilterField.fans ? subject.fans : subject.following;
      if (value == null) return _Outcome.pending;
      return _compareNumber(rule, value);
    }

    return switch (field) {
      FilterField.content => _matchText(rule, subject.content),
      FilterField.nickname => _matchText(rule, subject.nickname),
      FilterField.uid => _matchUid(rule, subject.uid),
      FilterField.uidLength => _compareNumber(
        rule,
        subject._resolvedUidLength,
      ),
      FilterField.level => _compareNumber(rule, subject.level),
      FilterField.official => _compareNumber(rule, subject.officialType),
      FilterField.vip => _matchVip(rule, subject.isVip),
      FilterField.fans || FilterField.following => _Outcome.miss,
    };
  }

  _Outcome _matchVip(FilterRule rule, bool? isVip) {
    if (isVip == null) return _Outcome.miss;
    final want = rule.value == '1';
    return want == isVip ? _Outcome.hit : _Outcome.miss;
  }

  _Outcome _matchUid(FilterRule rule, int? uid) {
    if (uid == null) return _Outcome.miss;
    final text = uid.toString();
    return switch (rule.match) {
      FilterMatch.equals => text == rule.value ? _Outcome.hit : _Outcome.miss,
      FilterMatch.regex => _regexHit(rule, text),
      _ => _Outcome.miss,
    };
  }

  _Outcome _compareNumber(FilterRule rule, int? actual) {
    if (actual == null) return _Outcome.miss;
    final bound = int.tryParse(rule.value.trim());
    if (bound == null) return _Outcome.miss;
    return switch (rule.match) {
      FilterMatch.lessThan => actual < bound ? _Outcome.hit : _Outcome.miss,
      FilterMatch.atLeast => actual >= bound ? _Outcome.hit : _Outcome.miss,
      FilterMatch.equals => actual == bound ? _Outcome.hit : _Outcome.miss,
      _ => _Outcome.miss,
    };
  }

  _Outcome _matchText(FilterRule rule, String? text) {
    if (text == null) return _Outcome.miss;

    final except = rule.exceptValue;
    if (except != null && _contains(text, except, rule.caseSensitive)) {
      return _Outcome.miss;
    }

    if (rule.isRegex) return _regexHit(rule, text);

    final haystack = _fold(text, rule.caseSensitive);
    final needle = _fold(rule.value, rule.caseSensitive);

    final hit = switch (rule.match) {
      FilterMatch.contains => haystack.contains(needle),
      FilterMatch.equals => haystack == needle,
      FilterMatch.startsWith => haystack.startsWith(needle),
      FilterMatch.endsWith => haystack.endsWith(needle),
      _ => false,
    };
    return hit ? _Outcome.hit : _Outcome.miss;
  }

  static String _fold(String value, bool caseSensitive) =>
      caseSensitive ? value : value.toLowerCase();

  static bool _contains(String text, String needle, bool caseSensitive) =>
      _fold(text, caseSensitive).contains(_fold(needle, caseSensitive));

  _Outcome _regexHit(FilterRule rule, String text) {
    final regExp = _regExpFor(rule.value, rule.caseSensitive);
    if (regExp == null) return _Outcome.miss;
    return regExp.hasMatch(text) ? _Outcome.hit : _Outcome.miss;
  }

  /// 规则源码是否可编译，编辑页用来标红。
  static bool isValidPattern(String source) {
    try {
      RegExp(source);
      return true;
    } on FormatException {
      return false;
    }
  }
}

enum _Outcome { hit, miss, pending }

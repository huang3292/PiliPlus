/// 自定义屏蔽规则的数据模型。
///
/// 一条规则 = 在某个作用域下，对某个字段做某种匹配。规则之间是“或”，
/// 命中任意一条即屏蔽；[FilterExempt] 例外名单优先级最高。
library;

import 'dart:convert';

enum FilterTarget {
  reply('评论'),
  video('视频'),
  dyn('动态'),
  search('搜索'),
  danmaku('弹幕');

  const FilterTarget(this.label);
  final String label;

  static FilterTarget? parse(Object? value) => _parse(values, value);
}

enum FilterField {
  content('正文'),
  nickname('昵称'),
  uid('UID'),
  uidLength('UID 长度'),
  level('用户等级'),
  fans('粉丝数'),
  following('关注数'),
  official('认证状态'),
  vip('大会员');

  const FilterField(this.label);
  final String label;

  static FilterField? parse(Object? value) => _parse(values, value);

  /// 需要额外请求用户资料才拿得到的字段，默认不查询。
  bool get needsRemoteLookup => this == fans || this == following;
}

enum FilterMatch {
  contains('包含'),
  equals('等于'),
  startsWith('开头是'),
  endsWith('结尾是'),
  regex('正则表达式'),
  lessThan('小于'),
  atLeast('大于等于');

  const FilterMatch(this.label);
  final String label;

  static FilterMatch? parse(Object? value) => _parse(values, value);

  bool get isNumeric => this == lessThan || this == atLeast || this == equals;
}

T? _parse<T extends Enum>(List<T> values, Object? name) {
  if (name is! String) return null;
  for (final value in values) {
    if (value.name == name) return value;
  }
  return null;
}

class FilterRule {
  final int id;
  final bool enabled;
  final Set<FilterTarget> targets;
  final FilterField field;
  final FilterMatch match;

  /// 文字模式下存原文，正则模式下存正则源码。
  final String value;
  final bool caseSensitive;

  /// 正文/昵称命中后再看一层：包含这个词就放行，代替旧的“不包含”规则。
  final String? exceptValue;

  const FilterRule({
    required this.id,
    required this.targets,
    required this.field,
    required this.match,
    required this.value,
    this.enabled = true,
    this.caseSensitive = false,
    this.exceptValue,
  });

  bool get isRegex => match == FilterMatch.regex;

  Map<String, dynamic> toJson() => {
    'id': id,
    'on': enabled,
    'targets': targets.map((e) => e.name).toList(),
    'field': field.name,
    'match': match.name,
    'value': value,
    if (caseSensitive) 'caseSensitive': true,
    if (exceptValue != null) 'except': exceptValue,
  };

  /// 字段非法或值为空时返回 null，由调用方丢弃，保证坏数据不影响整体。
  static FilterRule? fromJson(Map<dynamic, dynamic> json) {
    final targets =
        (json['targets'] as List?)
            ?.map(FilterTarget.parse)
            .whereType<FilterTarget>()
            .toSet() ??
        <FilterTarget>{};
    if (targets.isEmpty) return null;

    final field = FilterField.parse(json['field']);
    final match = FilterMatch.parse(json['match']);
    final value = json['value'];
    if (field == null || match == null || value is! String) return null;
    if (value.isEmpty) return null;
    if (!_matchAllowed(field, match)) return null;

    return FilterRule(
      id: switch (json['id']) {
        final int id => id,
        final String id => int.tryParse(id) ?? 0,
        _ => 0,
      },
      enabled: json['on'] != false,
      targets: targets,
      field: field,
      match: match,
      value: value,
      caseSensitive: json['caseSensitive'] == true,
      exceptValue: _parseExcept(field, json['except']),
    );
  }

  static String? _parseExcept(FilterField field, Object? raw) {
    if (field != FilterField.content && field != FilterField.nickname) {
      return null;
    }
    return raw is String && raw.isNotEmpty ? raw : null;
  }

  static bool _matchAllowed(FilterField field, FilterMatch match) =>
      allowedMatches(field).contains(match);

  /// 界面上的「匹配方式」下拉框只列出这个字段能用的方式，
  /// 用户不需要知道哪些组合是无意义的。
  static List<FilterMatch> allowedMatches(FilterField field) {
    return switch (field) {
      FilterField.content || FilterField.nickname => const [
        FilterMatch.contains,
        FilterMatch.equals,
        FilterMatch.startsWith,
        FilterMatch.endsWith,
        FilterMatch.regex,
      ],
      FilterField.uid => const [FilterMatch.equals, FilterMatch.regex],
      FilterField.uidLength || FilterField.level || FilterField.fans || FilterField.following => const [
        FilterMatch.lessThan,
        FilterMatch.atLeast,
        FilterMatch.equals,
      ],
      FilterField.official || FilterField.vip => const [FilterMatch.equals],
    };
  }

  /// 设置页展示用的一行摘要。
  String get summary {
    final String base;
    if (field.needsRemoteLookup) {
      final bound = int.tryParse(value);
      base = bound == null
          ? '${field.label} 待填写'
          : '${field.label} ${match.label} $bound';
    } else if (field == FilterField.official) {
      base = '认证状态 ${officialLabel(value)}';
    } else if (field == FilterField.vip) {
      base = value == '1' ? '是大会员' : '非大会员';
    } else {
      base =
          '${field.label} ${match.label} ${isRegex ? '/$value/' : value}';
    }
    final except = exceptValue;
    return except == null ? base : '$base（但不含$except）';
  }

  static String officialLabel(String value) => switch (value) {
    '0' => '无认证',
    '1' => '个人认证',
    '2' => '机构认证',
    '3' => '反向认证',
    _ => value,
  };
}

/// 例外名单：命中则直接放行，用来救被规则误伤的人。
class FilterExempt {
  final int id;
  final bool enabled;
  final FilterField field;
  final String value;

  const FilterExempt({
    required this.id,
    required this.field,
    required this.value,
    this.enabled = true,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'on': enabled,
    'field': field.name,
    'value': value,
  };

  static FilterExempt? fromJson(Map<dynamic, dynamic> json) {
    final field = FilterField.parse(json['field']);
    final value = json['value'];
    if (field == null || value is! String || value.isEmpty) return null;
    return FilterExempt(
      id: json['id'] is int ? json['id'] as int : 0,
      enabled: json['on'] != false,
      field: field,
      value: value,
    );
  }
}

class FilterConfig {
  static const currentVersion = 1;

  final int version;
  final List<FilterRule> rules;
  final List<FilterExempt> exempts;

  const FilterConfig({
    this.version = currentVersion,
    this.rules = const [],
    this.exempts = const [],
  });

  static const empty = FilterConfig();

  bool get isEmpty => rules.isEmpty && exempts.isEmpty;

  Map<String, dynamic> toJson() => {
    'version': version,
    'rules': rules.map((e) => e.toJson()).toList(),
    if (exempts.isNotEmpty)
      'exempts': exempts.map((e) => e.toJson()).toList(),
  };

  static FilterConfig fromJson(Map<dynamic, dynamic> json) {
    return FilterConfig(
      version: json['version'] is int ? json['version'] as int : currentVersion,
      rules: _list(json['rules'], FilterRule.fromJson),
      exempts: _list(json['exempts'], FilterExempt.fromJson),
    );
  }

  /// 存储或导入的内容坏了就当没有规则，不能让屏蔽功能整体崩掉。
  static FilterConfig tryDecode(Object? raw) {
    if (raw is! String || raw.trim().isEmpty) return empty;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? fromJson(decoded) : empty;
    } on FormatException {
      return empty;
    }
  }

  static List<T> _list<T>(Object? raw, T? Function(Map) parse) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map(parse)
        .whereType<T>()
        .toList(growable: false);
  }
}

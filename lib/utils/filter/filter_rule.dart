/// 「本地隐藏」的数据模型。
///
/// 一条规则 = 生效范围 + 若干**且**关系的条件 + 命中后的动作。
/// 规则之间是「或」，命中任意一条即隐藏；[FilterExempt] 手动例外优先级最高。
///
/// 范围与字段不是随意组合的：某个列表接口拿不到的字段（例如视频卡片没有
/// 等级）不允许出现在该范围下，见 [FilterField.availableFor]。
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

  /// 该范围在界面里能选出来的字段。
  List<FilterField> get fields =>
      FilterField.values.where((field) => field.availableFor(this)).toList();

  /// 未单独设置动作时，该范围默认怎么显示。
  FilterAction get defaultAction =>
      this == FilterTarget.reply ? FilterAction.collapse : FilterAction.placeholder;

  static FilterTarget? parse(Object? value) => _parse(values, value);
}

/// 隐藏之后条目怎么显示。条目始终保留在列表里，只有 [remove] 才真的丢掉。
enum FilterAction {
  placeholder('显示占位卡片'),
  collapse('折叠成一行'),
  remove('直接移除');

  const FilterAction(this.label);
  final String label;

  static FilterAction? parse(Object? value) => _parse(values, value);
}

/// 隐藏是谁要求的，用来说明「为什么这条被藏了」和优先级。
enum FilterSource {
  manual('手动规则'),
  local('条目里隐藏'),
  official('B 站黑名单'),
  legacy('旧关键词过滤');

  const FilterSource(this.label);
  final String label;

  static FilterSource? parse(Object? value) => _parse(values, value);

  /// 从条目上点出来的「隐藏此人」属于明确隐藏，优先级排在 B 站黑名单之前；
  /// 手写的关键词/属性规则属于通用规则，排在黑名单之后。
  bool get isExplicit => this == FilterSource.local;
}

enum FilterFieldKind {
  /// 文本，支持包含/开头/正则等。
  text,

  /// 整数，支持比较与区间。
  number,

  /// 固定几个选项，可多选。
  choice,

  /// 是/否。
  toggle,
}

enum FilterField {
  replyContent('评论正文', FilterFieldKind.text, {FilterTarget.reply}),
  dynText('动态正文', FilterFieldKind.text, {FilterTarget.dyn}),
  dynOrigText('转发的原文', FilterFieldKind.text, {FilterTarget.dyn}),
  videoTitle('视频标题', FilterFieldKind.text, {FilterTarget.video}),
  videoZone('分区名称', FilterFieldKind.text, {FilterTarget.video}),
  nickname(
    '昵称',
    FilterFieldKind.text,
    {FilterTarget.reply, FilterTarget.video, FilterTarget.dyn},
  ),
  uid(
    'UID',
    FilterFieldKind.number,
    {FilterTarget.reply, FilterTarget.video, FilterTarget.dyn},
  ),
  uidLength(
    'UID 位数',
    FilterFieldKind.number,
    {FilterTarget.reply, FilterTarget.video, FilterTarget.dyn},
  ),
  level('用户等级', FilterFieldKind.number, {FilterTarget.reply}),
  official('认证状态', FilterFieldKind.choice, {FilterTarget.reply, FilterTarget.dyn}),
  vipType('大会员类型', FilterFieldKind.choice, {FilterTarget.reply, FilterTarget.dyn}),
  vipEffective(
    '有效大会员',
    FilterFieldKind.toggle,
    {FilterTarget.reply, FilterTarget.dyn},
  );

  const FilterField(this.label, this.kind, this._targets);

  final String label;
  final FilterFieldKind kind;
  final Set<FilterTarget> _targets;

  bool availableFor(FilterTarget target) => _targets.contains(target);

  /// 该范围下为什么不能用这个字段，界面上要说清楚，不能留空入口。
  String? unavailableReason(FilterTarget target) {
    if (availableFor(target)) return null;
    return switch (this) {
      level => '${target.label}列表的接口里没有用户等级',
      official || vipType || vipEffective => '${target.label}列表的接口里没有会员与认证信息',
      _ => '${target.label}不支持「$label」',
    };
  }

  static List<(String, String)> optionsFor(FilterField field) =>
      switch (field) {
        official => const [
          ('-1', '无认证'),
          ('0', '个人认证'),
          ('1', '机构认证'),
        ],
        vipType => const [
          ('0', '无大会员'),
          ('1', '月度大会员'),
          ('2', '年度及以上大会员'),
        ],
        vipEffective => const [('1', '是'), ('0', '否')],
        _ => const [],
      };

  static String optionLabel(FilterField field, String value) {
    for (final (code, label) in optionsFor(field)) {
      if (code == value) return label;
    }
    return value;
  }

  static FilterField? parse(Object? value) => _parse(values, value);
}

enum FilterOp {
  contains('包含'),
  notContains('不包含'),
  equals('等于'),
  notEquals('不等于'),
  startsWith('开头是'),
  endsWith('结尾是'),
  matches('正则匹配'),
  notMatches('正则不匹配'),
  lt('小于'),
  lte('小于等于'),
  gt('大于'),
  gte('大于等于'),
  between('介于'),
  inList('属于'),
  notInList('不属于');

  const FilterOp(this.label);
  final String label;

  /// 该操作符需要几个值。
  int get valueCount => this == between ? 2 : 1;

  bool get needsCaseSensitive =>
      this == contains ||
      this == notContains ||
      this == equals ||
      this == notEquals ||
      this == startsWith ||
      this == endsWith ||
      this == matches ||
      this == notMatches;

  static FilterOp? parse(Object? value) => _parse(values, value);
}

T? _parse<T extends Enum>(List<T> values, Object? name) {
  if (name is! String) return null;
  for (final value in values) {
    if (value.name == name) return value;
  }
  return null;
}

/// 界面上「怎么算命中」只列出这个字段能用的操作符。
List<FilterOp> allowedOps(FilterField field) => switch (field.kind) {
  FilterFieldKind.text => const [
    FilterOp.contains,
    FilterOp.notContains,
    FilterOp.equals,
    FilterOp.notEquals,
    FilterOp.startsWith,
    FilterOp.endsWith,
    FilterOp.matches,
    FilterOp.notMatches,
  ],
  FilterFieldKind.number => const [
    FilterOp.equals,
    FilterOp.notEquals,
    FilterOp.lt,
    FilterOp.lte,
    FilterOp.gt,
    FilterOp.gte,
    FilterOp.between,
  ],
  FilterFieldKind.choice => const [FilterOp.inList, FilterOp.notInList],
  FilterFieldKind.toggle => const [FilterOp.equals, FilterOp.notEquals],
};

class FilterCondition {
  final FilterField field;
  final FilterOp op;

  /// 一般是 1 个；[FilterOp.between] 是 2 个；[FilterOp.inList] 可以多个。
  final List<String> values;
  final bool caseSensitive;

  const FilterCondition({
    required this.field,
    required this.op,
    required this.values,
    this.caseSensitive = false,
  });

  /// 返回不能保存的原因，界面上直接显示这句话。
  String? problem() {
    if (!allowedOps(field).contains(op)) return '「${field.label}」不支持这个匹配方式';
    for (final value in values) {
      if (value.isEmpty) return '请填写要匹配的内容';
    }
    if (op.valueCount == 2) {
      if (values.length < 2) return '请填写区间的最小值和最大值';
      final min = int.tryParse(values[0]);
      final max = int.tryParse(values[1]);
      if (min == null || max == null) return '区间只能是整数';
      if (min > max) return '区间的最小值不能大于最大值';
      return null;
    }
    if (values.isEmpty) return '请填写要匹配的内容';
    switch (field.kind) {
      case FilterFieldKind.text:
        return null;
      case FilterFieldKind.number:
        final bound = int.tryParse(values.first);
        if (bound == null) return '这里只能填整数';
        if (field == FilterField.uidLength && (bound < 1 || bound > 19)) {
          return 'UID 位数在 1~19 之间';
        }
        if (field == FilterField.level && (bound < 0 || bound > 6)) {
          return '用户等级只有 Lv0~Lv6';
        }
        return null;
      case FilterFieldKind.choice:
        for (final value in values) {
          final known = FilterField.optionsFor(field)
              .any((option) => option.$1 == value);
          if (!known) return '「${field.label}」没有这个选项';
        }
        return null;
      case FilterFieldKind.toggle:
        return values.first == '0' || values.first == '1'
            ? null
            : '只能选是或否';
    }
  }

  String describe() {
    final matched = switch (field.kind) {
      FilterFieldKind.choice ||
      FilterFieldKind.toggle => values
          .map((value) => FilterField.optionLabel(field, value))
          .join('、'),
      _ => op == FilterOp.between
          ? '${values.first}~${values.last}'
          : op == FilterOp.matches || op == FilterOp.notMatches
          ? '/${values.first}/'
          : values.first,
    };
    return '${field.label} ${op.label} $matched';
  }

  Map<String, dynamic> toJson() => {
    'field': field.name,
    'op': op.name,
    'values': values,
    if (caseSensitive && op.needsCaseSensitive) 'caseSensitive': true,
  };

  /// 字段、操作符或值对不上时返回 null，由调用方决定丢弃还是报错。
  static FilterCondition? fromJson(Map<dynamic, dynamic> json) {
    final field = FilterField.parse(json['field']);
    final op = FilterOp.parse(json['op']);
    final raw = json['values'];
    if (field == null || op == null || raw is! List) return null;
    final values = raw.whereType<String>().toList(growable: false);
    final condition = FilterCondition(
      field: field,
      op: op,
      values: values,
      caseSensitive: json['caseSensitive'] == true,
    );
    return condition.problem() == null ? condition : null;
  }
}

class FilterRule {
  final int id;
  final bool enabled;
  final Set<FilterTarget> targets;
  final List<FilterCondition> conditions;

  /// 为空表示跟随该范围在 [FilterConfig.actionFor] 里的默认动作。
  final FilterAction? action;
  final FilterSource source;

  const FilterRule({
    required this.id,
    required this.targets,
    required this.conditions,
    this.enabled = true,
    this.action,
    this.source = FilterSource.manual,
  });

  bool get isRegex => conditions.any(
    (condition) =>
        condition.op == FilterOp.matches || condition.op == FilterOp.notMatches,
  );

  /// 有正则条件时给出写坏的那一条源码，编辑页用来标红。
  String? get brokenPattern {
    for (final condition in conditions) {
      if ((condition.op == FilterOp.matches ||
              condition.op == FilterOp.notMatches) &&
          condition.values.isNotEmpty &&
          !isValidPattern(condition.values.first)) {
        return condition.values.first;
      }
    }
    return null;
  }

  static bool isValidPattern(String source) {
    try {
      RegExp(source);
      return true;
    } on FormatException {
      return false;
    }
  }

  /// 单条规则内部的校验：范围与字段要能成立，条件本身要合法。
  String? problem() {
    if (targets.isEmpty) return '至少选一个生效范围';
    if (conditions.isEmpty) return '至少添加一个条件';
    for (final condition in conditions) {
      final broken = condition.problem();
      if (broken != null) return broken;
      for (final target in targets) {
        final unavailable = condition.field.unavailableReason(target);
        if (unavailable != null) return unavailable;
      }
    }
    if (brokenPattern != null) return '正则表达式写错了，先改好再保存';
    return null;
  }

  /// 规则里只要有一个字段在该范围不可用，这个范围就不能留。
  Set<FilterTarget> supportedTargets() => targets
      .where(
        (target) => conditions.every((condition) => condition.field.availableFor(target)),
      )
      .toSet();

  /// 设置页展示用的一行摘要。
  String get summary => conditions
      .map((condition) => condition.describe())
      .join(' 且 ');

  String get actionLabel => action?.label ?? '跟随范围默认';

  Map<String, dynamic> toJson() => {
    'id': id,
    'on': enabled,
    'targets': targets.map((e) => e.name).toList(),
    'conditions': conditions.map((e) => e.toJson()).toList(),
    if (action != null) 'action': action!.name,
    'source': source.name,
  };

  static FilterRule? fromJson(Map<dynamic, dynamic> json) {
    final targets =
        (json['targets'] as List?)
            ?.map(FilterTarget.parse)
            .whereType<FilterTarget>()
            .toSet() ??
        <FilterTarget>{};
    if (targets.isEmpty) return null;
    final conditions = _conditions(json['conditions']);
    if (conditions == null) return null;
    return FilterRule(
      id: switch (json['id']) {
        final int id => id,
        final String id => int.tryParse(id) ?? 0,
        _ => 0,
      },
      enabled: json['on'] != false,
      targets: targets,
      conditions: conditions,
      action: FilterAction.parse(json['action']),
      source: FilterSource.parse(json['source']) ?? FilterSource.manual,
    );
  }

  static List<FilterCondition>? _conditions(Object? raw) {
    if (raw is! List) return null;
    final conditions = raw
        .whereType<Map>()
        .map(FilterCondition.fromJson)
        .whereType<FilterCondition>()
        .toList(growable: false);
    return conditions.isEmpty ? null : conditions;
  }
}

/// 手动例外：命中 UID 就直接放行，优先级高于所有隐藏，包括 B 站黑名单。
class FilterExempt {
  final int id;
  final int uid;

  /// 只用来显示是谁，不参与匹配（昵称可以改，按昵称放行会误放）。
  final String name;

  const FilterExempt({required this.id, required this.uid, this.name = ''});

  Map<String, dynamic> toJson() => {
    'id': id,
    'uid': uid,
    if (name.isNotEmpty) 'name': name,
  };

  static FilterExempt? fromJson(Map<dynamic, dynamic> json) {
    final uid = switch (json['uid']) {
      final int uid => uid,
      final String uid => int.tryParse(uid),
      _ => null,
    };
    if (uid == null || uid <= 0) return null;
    return FilterExempt(
      id: json['id'] is int ? json['id'] as int : 0,
      uid: uid,
      name: json['name'] is String ? json['name'] as String : '',
    );
  }
}

class FilterConfig {
  static const currentVersion = 2;

  final int version;
  final List<FilterRule> rules;
  final List<FilterExempt> exempts;

  /// 各范围命中后怎么显示；没设置的用 [FilterTarget.defaultAction]。
  final Map<FilterTarget, FilterAction> display;

  /// 解析时被丢弃的内容，界面上要提示，不能静默。
  final List<String> warnings;

  const FilterConfig({
    this.version = currentVersion,
    this.rules = const [],
    this.exempts = const [],
    this.display = const {},
    this.warnings = const [],
  });

  static const empty = FilterConfig();

  bool get isEmpty => rules.isEmpty && exempts.isEmpty;

  FilterAction actionFor(FilterTarget target) =>
      display[target] ?? target.defaultAction;

  bool get hasActiveRules => rules.any((rule) => rule.enabled);

  FilterConfig copyWith({
    List<FilterRule>? rules,
    List<FilterExempt>? exempts,
    Map<FilterTarget, FilterAction>? display,
    List<String>? warnings,
  }) => FilterConfig(
    rules: rules ?? this.rules,
    exempts: exempts ?? this.exempts,
    display: display ?? this.display,
    warnings: warnings ?? this.warnings,
  );

  Map<String, dynamic> toJson() => {
    'version': version,
    'rules': rules.map((e) => e.toJson()).toList(),
    if (exempts.isNotEmpty) 'manualExceptions': exempts.map((e) => e.toJson()).toList(),
    if (display.isNotEmpty)
      'displaySettings': {
        for (final entry in display.entries) entry.key.name: entry.value.name,
      },
  };

  static FilterConfig fromJson(Map<dynamic, dynamic> json) {
    final warnings = <String>[];

    final rawRules = (json['rules'] as List?)?.whereType<Map>().toList() ?? const [];
    final rules = <FilterRule>[];
    for (final raw in rawRules) {
      final rule = FilterRule.fromJson(raw);
      if (rule == null) {
        warnings.add('有一条规则读不出来，已跳过');
      } else {
        rules.add(rule);
      }
    }

    final rawExempts =
        (json['manualExceptions'] as List?)?.whereType<Map>().toList() ??
        const [];
    final exempts = <FilterExempt>[];
    for (final raw in rawExempts) {
      final exempt = FilterExempt.fromJson(raw);
      if (exempt == null) {
        warnings.add('例外名单里有一条读不出来，已跳过');
      } else {
        exempts.add(exempt);
      }
    }

    final display = <FilterTarget, FilterAction>{};
    final rawDisplay = json['displaySettings'];
    if (rawDisplay is Map) {
      rawDisplay.forEach((key, value) {
        final target = FilterTarget.parse(key);
        final action = FilterAction.parse(value);
        if (target == null || action == null) {
          warnings.add('显示设置里有一项不认识，已跳过');
        } else {
          display[target] = action;
        }
      });
    }

    return FilterConfig(
      version: json['version'] is int ? json['version'] as int : currentVersion,
      rules: rules,
      exempts: exempts,
      display: display,
      warnings: warnings,
    );
  }

  /// 存储或导入的内容坏了就当没有规则，不能让隐藏功能整体崩掉。
  static FilterConfig tryDecode(Object? raw) {
    if (raw is! String || raw.trim().isEmpty) return empty;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return FilterConfig(
          warnings: const ['保存的规则不是认得的格式，已按空规则处理'],
        );
      }
      return fromJson(decoded);
    } on Object {
      return FilterConfig(warnings: const ['保存的规则解析失败，已按空规则处理']);
    }
  }
}

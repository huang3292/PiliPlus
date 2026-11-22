/// 旧数据搬到新模型：v1 的结构化规则逐条翻译成 v2。
/// 原则是**能搬的全搬、搬不动的说明**，并且保留原字符串，出问题能人工恢复。
library;

import 'package:PiliPlus/utils/filter/filter_rule.dart';

abstract final class FilterMigration {
  /// v1 的一条规则 = 一个字段 + 一种匹配 + 一个值。字段名和匹配方式在
  /// v2 里都换了，所以逐条翻译；`content` 要按范围落到不同字段，
  /// 一条可能变成多条。
  ///
  /// 返回 null 表示这份数据不是 v1（已经是 v2 或读不懂）。
  static FilterConfig? v1(Map<dynamic, dynamic> json) {
    final rawRules = json['rules'];
    if (rawRules is! List) return null;

    final warnings = <String>[];
    final rules = <FilterRule>[];
    var nextId = 1;
    for (final raw in rawRules.whereType<Map>()) {
      final id = raw['id'] is int ? raw['id'] as int : nextId;
      nextId = id > nextId ? id + 1 : nextId;
      final targets =
          (raw['targets'] as List?)
              ?.map(FilterTarget.parse)
              .whereType<FilterTarget>()
              .toSet() ??
          <FilterTarget>{};
      final field = raw['field'];
      final match = raw['match'];
      final value = raw['value'];
      if (targets.isEmpty || field is! String || match is! String || value is! String) {
        warnings.add('有一条旧规则读不出来，已跳过');
        continue;
      }
      if (value.isEmpty) continue;

      if (field == 'fans' || field == 'following') {
        warnings.add('「${field == 'fans' ? '粉丝数' : '关注数'}」规则已取消，原值「$value」留在备份里');
        continue;
      }

      final condition = _v1Condition(field, match, value, raw);
      if (condition == null || condition.problem() != null) {
        warnings.add('有一条旧规则的条件不再支持（${_v1FieldLabel(field)} $value），已跳过');
        continue;
      }

      final except = raw['except'];
      final exceptText = except is String && except.isNotEmpty ? except : null;
      final wantsExcept =
          exceptText != null && (field == 'content' || field == 'nickname');

      if (field == 'content') {
        // v1 的「正文」不分范围，v2 要按范围落到各自字段上。
        for (final target in targets) {
          final contentField = _contentField(target);
          if (contentField == null) {
            warnings.add('「正文」在${target.label}里还没有接入隐藏判定，已跳过');
            continue;
          }
          rules.add(
            FilterRule(
              id: targets.length == 1 ? id : nextId++,
              enabled: raw['on'] != false,
              targets: {target},
              source: FilterSource.manual,
              conditions: [
                FilterCondition(
                  field: contentField,
                  op: condition.op,
                  values: condition.values,
                  caseSensitive: condition.caseSensitive,
                ),
                if (wantsExcept)
                  FilterCondition(
                    field: contentField,
                    op: FilterOp.notContains,
                    values: [exceptText],
                  ),
              ],
            ),
          );
        }
      } else {
        final supported = targets
            .where((target) => condition.field.availableFor(target))
            .toSet();
        if (supported.isEmpty) {
          warnings.add('「${condition.field.label}」在 ${_targetLabels(targets)} 里取不到数据，已跳过');
          continue;
        }
        rules.add(
          FilterRule(
            id: id,
            enabled: raw['on'] != false,
            targets: supported,
            source: FilterSource.manual,
            conditions: [
              condition,
              if (wantsExcept && condition.field == FilterField.nickname)
                FilterCondition(
                  field: FilterField.nickname,
                  op: FilterOp.notContains,
                  values: [exceptText],
                ),
            ],
          ),
        );
      }
    }

    final exempts = <FilterExempt>[];
    var nextExemptId = 1;
    for (final raw in (json['exempts'] as List? ?? const []).whereType<Map>()) {
      final field = raw['field'];
      final value = raw['value'];
      if (field == 'uid' && value is String) {
        final uid = int.tryParse(value);
        if (uid == null) {
          warnings.add('例外名单里有一个 UID 读不出来，已跳过');
        } else {
          exempts.add(
            FilterExempt(id: nextExemptId++, uid: uid),
          );
        }
      } else {
        warnings.add('例外名单里有一条不是按 UID 的，已跳过（昵称可以改，容易放错人）');
      }
    }

    return FilterConfig(
      version: FilterConfig.currentVersion,
      rules: rules,
      exempts: exempts,
      warnings: warnings,
    );
  }

  /// v1 的 `field` + `match` + `value` 翻译成 v2 条件，翻译不了返回 null。
  static FilterCondition? _v1Condition(
    String field,
    String match,
    String value,
    Map json,
  ) {
    final caseSensitive = json['caseSensitive'] == true;
    final op = switch (match) {
      'contains' => FilterOp.contains,
      'equals' => FilterOp.equals,
      'startsWith' => FilterOp.startsWith,
      'endsWith' => FilterOp.endsWith,
      'regex' => FilterOp.matches,
      'lessThan' => FilterOp.lt,
      'atLeast' => FilterOp.gte,
      _ => null,
    };
    if (op == null) return null;

    switch (field) {
      case 'content':
        // v1 的「正文」不分范围，字段等下面按范围换；这里先借用一个文本字段
        // 把匹配方式与大小写带过去。
        return FilterCondition(
          field: FilterField.videoTitle,
          op: op,
          values: [value],
          caseSensitive: caseSensitive,
        );
      case 'nickname':
        return FilterCondition(
          field: FilterField.nickname,
          op: op,
          values: [value],
          caseSensitive: caseSensitive,
        );
      case 'uid':
        return FilterCondition(
          field: FilterField.uid,
          op: op == FilterOp.matches ? FilterOp.matches : FilterOp.equals,
          values: [value],
          caseSensitive: caseSensitive,
        );
      case 'uidLength':
      case 'level':
        final number = int.tryParse(value.trim());
        if (number == null) return null;
        final target = field == 'uidLength' ? FilterField.uidLength : FilterField.level;
        return FilterCondition(
          field: target,
          op: op == FilterOp.equals ? FilterOp.equals : op,
          values: [number.toString()],
        );
      case 'official':
        // v1 的编号是错的（当时按 0无/1个人/2机构/3反向 存），这里搬到接口口径。
        final code = switch (value) {
          '0' => '-1',
          '1' => '0',
          '2' => '1',
          _ => null,
        };
        if (code == null) return null;
        return FilterCondition(
          field: FilterField.official,
          op: FilterOp.inList,
          values: [code],
        );
      case 'vip':
        return FilterCondition(
          field: FilterField.vipEffective,
          op: FilterOp.equals,
          values: [value == '1' ? '1' : '0'],
        );
      default:
        return null;
    }
  }

  /// v1 的一个「正文」在 v2 里要落到各范围自己的文本字段；还没接入的范围
  /// 返回 null，不能硬套一个取不到数据的字段。
  static FilterField? _contentField(FilterTarget target) => switch (target) {
    FilterTarget.reply => FilterField.replyContent,
    FilterTarget.video => FilterField.videoTitle,
    FilterTarget.dyn => FilterField.dynText,
    FilterTarget.search || FilterTarget.danmaku => null,
  };

  static String _v1FieldLabel(String field) => switch (field) {
    'content' => '正文',
    'nickname' => '昵称',
    'uid' => 'UID',
    'uidLength' => 'UID 位数',
    'level' => '用户等级',
    'official' => '认证状态',
    'vip' => '大会员',
    _ => field,
  };

  static String _targetLabels(Set<FilterTarget> targets) =>
      targets.map((e) => e.label).join('、');
}

/// 旧版屏蔽词是**一整条正则字符串**，多个词靠 `|` 分隔（`使用|隔开，如：尝试|测试`）。
/// 新规则库把它拆成结构化条目，同时保留反向拼回的能力，
/// 供「原始表达式」页继续导入导出。
library;

import 'package:PiliPlus/utils/filter/filter_rule.dart';

abstract final class LegacyBanWord {
  static final _metachar = RegExp(r'[.*+?^${}()|[\]\\]');

  /// 原始字符串不能以反斜杠收尾，这里用普通转义写法。
  static const _slash = '\\';

  /// 只在顶层切分：括号 `(a|b)` 与字符类 `[a|b]` 里的 `|` 属于正则本身，不能拆。
  static List<String> split(String source) {
    if (source.trim().isEmpty) return const [];

    final result = <String>[];
    final buffer = StringBuffer();
    var groupDepth = 0;
    var inCharClass = false;

    void flush() {
      final part = buffer.toString().trim();
      buffer.clear();
      if (part.isNotEmpty) result.add(part);
    }

    for (var i = 0; i < source.length; i++) {
      final char = source[i];

      if (char == _slash) {
        buffer.write(char);
        if (i + 1 < source.length) buffer.write(source[++i]);
        continue;
      }

      if (inCharClass) {
        if (char == ']') inCharClass = false;
        buffer.write(char);
        continue;
      }

      switch (char) {
        case '[':
          inCharClass = true;
        case '(':
          groupDepth++;
        case ')':
          if (groupDepth > 0) groupDepth--;
        case '|' when groupDepth == 0:
          flush();
          continue;
      }
      buffer.write(char);
    }
    flush();

    return result;
  }

  static String escape(String text) => text.replaceAllMapped(
    _metachar,
    (match) => _slash + match[0]!,
  );

  /// 片段里每个元字符都被转义过，说明它想表达的就是普通文字；
  /// 出现任何未转义的元字符才按正则处理。
  static String? asPlainText(String fragment) {
    final buffer = StringBuffer();
    for (var i = 0; i < fragment.length; i++) {
      final char = fragment[i];
      if (char == _slash) {
        if (i + 1 >= fragment.length) return null;
        buffer.write(fragment[++i]);
        continue;
      }
      if (_metachar.hasMatch(char)) return null;
      buffer.write(char);
    }
    return buffer.toString();
  }

  static FilterRule toRule(String fragment, Set<FilterTarget> targets, int id) {
    final plain = asPlainText(fragment);
    return FilterRule(
      id: id,
      targets: targets,
      field: FilterField.content,
      match: plain == null ? FilterMatch.regex : FilterMatch.contains,
      value: plain ?? fragment,
    );
  }

  /// 把某作用域的规则拼回旧的 `|` 表达式；数值条件和排除条件无法用
  /// 肯定匹配表达，会被跳过，界面上要提示用户。
  static String join(Iterable<FilterRule> rules) => rules
      .map(tokenOf)
      .whereType<String>()
      .join('|');

  static String? tokenOf(FilterRule rule) {
    if (rule.exceptValue != null) return null;
    final value = rule.value;
    return switch (rule.match) {
      FilterMatch.regex => value,
      FilterMatch.contains => escape(value),
      FilterMatch.startsWith => '^${escape(value)}',
      FilterMatch.endsWith => '${escape(value)}\$',
      FilterMatch.equals => '^(?:${escape(value)})\$',
      _ => null,
    };
  }

  /// 旧的每个作用域各存一条串，迁移后规则归属到对应作用域；
  /// 一个作用域可能对应多条旧表达式（推荐流和分区共用视频类规则）。
  static List<FilterRule> migrate(Iterable<(FilterTarget, String)> sources) {
    final rules = <FilterRule>[];
    var id = 1;
    for (final (target, pattern) in sources) {
      for (final fragment in split(pattern)) {
        rules.add(toRule(fragment, {target}, id++));
      }
    }
    return rules;
  }
}

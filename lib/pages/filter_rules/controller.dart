import 'package:PiliPlus/utils/filter/filter_rule.dart';
import 'package:PiliPlus/utils/filter/filter_store.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

/// 规则页管理的范围。弹幕走 B 站服务端的屏蔽规则（uid 还是哈希过的），
/// 不在这个列表里，以后单独设计；搜索结果暂时没有接入判定。
const List<FilterTarget> kFilterScopes = [
  FilterTarget.reply,
  FilterTarget.video,
  FilterTarget.dyn,
];

class FilterRulesController extends GetxController {
  final rules = <FilterRule>[].obs;
  final exempts = <FilterExempt>[].obs;

  List<FilterRule> rulesFor(FilterTarget target) =>
      rules.where((rule) => rule.targets.contains(target)).toList(growable: false);

  @override
  void onInit() {
    super.onInit();
    rules.value = FilterStore.config.rules;
    exempts.value = FilterStore.config.exempts;
  }

  int nextId() {
    var max = 0;
    for (final rule in rules) {
      if (rule.id > max) max = rule.id;
    }
    for (final exempt in exempts) {
      if (exempt.id > max) max = exempt.id;
    }
    return max + 1;
  }

  Future<void> upsert(FilterRule rule) async {
    final index = rules.indexWhere((item) => item.id == rule.id);
    if (index < 0) {
      rules.add(rule);
    } else {
      rules[index] = rule;
    }
    await _save();
  }

  Future<void> remove(FilterRule rule) async {
    rules.remove(rule);
    await _save();
    SmartDialog.showToast('已删除');
  }

  Future<void> toggle(FilterRule rule, bool enabled) async {
    final index = rules.indexWhere((item) => item.id == rule.id);
    if (index < 0) return;
    rules[index] = _copy(rule, enabled: enabled);
    await _save();
  }

  Future<void> removeExempt(FilterExempt exempt) async {
    exempts.remove(exempt);
    await _save();
  }

  /// 导入 JSON 文件：同一条规则不重复添加，换账号登录时可以直接合并。
  Future<void> importConfig(Map json) async {
    final incoming = FilterConfig.fromJson(json);
    if (incoming.rules.isEmpty && incoming.exempts.isEmpty) {
      throw Exception('文件里没有可用的规则');
    }
    final merged = [...rules];
    final known = merged.map(_signature).toSet();
    var id = nextId();
    for (final rule in incoming.rules) {
      if (known.add(_signature(rule))) {
        merged.add(
          FilterRule(
            id: id++,
            enabled: rule.enabled,
            targets: rule.targets,
            field: rule.field,
            match: rule.match,
            value: rule.value,
            caseSensitive: rule.caseSensitive,
            exceptValue: rule.exceptValue,
          ),
        );
      }
    }
    final mergedExempts = [...exempts];
    final knownExempts = mergedExempts.map((e) => '${e.field.name}${e.value}').toSet();
    for (final exempt in incoming.exempts) {
      final key = '${exempt.field.name}${exempt.value}';
      if (knownExempts.add(key)) {
        mergedExempts.add(
          FilterExempt(id: id++, field: exempt.field, value: exempt.value),
        );
      }
    }
    await FilterStore.save(
      FilterConfig(rules: merged, exempts: mergedExempts),
    );
    reload();
  }

  static String _signature(FilterRule rule) =>
      '${rule.field.name}|${rule.match.name}|${rule.value}|'
      '${(rule.targets.toList()..sort((a, b) => a.index - b.index)).map((e) => e.index).join()}';

  void reload() {
    rules.value = FilterStore.config.rules;
    exempts.value = FilterStore.config.exempts;
  }

  Future<void> exemptUid(int uid, String nickname) async {
    await FilterStore.exemptUid(uid, nickname);
    reload();
    SmartDialog.showToast('已加入例外名单');
  }

  Future<void> _save() async {
    await FilterStore.save(FilterConfig(rules: rules, exempts: exempts));
  }

  static FilterRule _copy(
    FilterRule rule, {
    bool? enabled,
    Set<FilterTarget>? targets,
  }) {
    return FilterRule(
      id: rule.id,
      enabled: enabled ?? rule.enabled,
      targets: targets ?? rule.targets,
      field: rule.field,
      match: rule.match,
      value: rule.value,
      caseSensitive: rule.caseSensitive,
      exceptValue: rule.exceptValue,
    );
  }
}

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

/// 只是 [FilterStore] 的一份可观察快照：真正写数据的一律走 FilterStore，
/// 所以从评论长按里加的规则也能立刻出现在这里。
class FilterRulesController extends GetxController {
  final rules = <FilterRule>[].obs;
  final exempts = <FilterExempt>[].obs;
  final display = <FilterTarget, FilterAction>{}.obs;
  final notes = <String>[].obs;

  @override
  void onInit() {
    super.onInit();
    FilterStore.revision.addListener(_sync);
    _sync();
  }

  @override
  void onClose() {
    FilterStore.revision.removeListener(_sync);
    super.onClose();
  }

  void _sync() {
    final config = FilterStore.config;
    rules.value = config.rules;
    exempts.value = config.exempts;
    display.value = config.display;
    notes.value = config.warnings;
  }

  List<FilterRule> rulesFor(FilterTarget target) =>
      rules.where((rule) => rule.targets.contains(target)).toList(growable: false);

  FilterAction actionFor(FilterTarget target) =>
      display[target] ?? target.defaultAction;

  int nextId() => FilterStore.nextId();

  Future<void> upsert(FilterRule rule) => FilterStore.upsert(rule);

  Future<void> remove(FilterRule rule) async {
    await FilterStore.remove(rule);
    SmartDialog.showToast('已删除');
  }

  Future<void> toggle(FilterRule rule, bool enabled) =>
      FilterStore.toggle(rule, enabled);

  Future<void> setAction(FilterTarget target, FilterAction? action) =>
      FilterStore.setAction(target, action);

  Future<void> removeExempt(FilterExempt exempt) =>
      FilterStore.removeExempt(exempt.uid);

  Future<void> exemptUid(int uid, {String name = ''}) async {
    await FilterStore.exemptUid(uid, name: name);
    SmartDialog.showToast('已加入例外名单');
  }

  /// 导入 JSON 文件：同一条规则不重复添加，换账号登录时可以直接合并。
  Future<void> importConfig(Map json) async {
    final incoming = FilterConfig.fromJson(json);
    if (incoming.rules.isEmpty && incoming.exempts.isEmpty) {
      throw Exception('文件里没有可用的规则');
    }
    final merged = [...rules];
    final known = merged.map(_signature).toSet();
    final ruleCount = rules.length;
    final exemptCount = exempts.length;
    var id = nextId();
    for (final rule in incoming.rules) {
      if (known.add(_signature(rule))) {
        merged.add(
          FilterRule(
            id: id++,
            enabled: rule.enabled,
            targets: rule.targets,
            conditions: rule.conditions,
            action: rule.action,
            source: FilterSource.manual,
          ),
        );
      }
    }
    final mergedExempts = [...exempts];
    final knownUids = mergedExempts.map((e) => e.uid).toSet();
    for (final exempt in incoming.exempts) {
      if (knownUids.add(exempt.uid)) {
        mergedExempts.add(
          FilterExempt(id: id++, uid: exempt.uid, name: exempt.name),
        );
      }
    }
    final display = {...FilterStore.config.display};
    incoming.display.forEach((target, action) => display[target] ??= action);

    final importedRules = merged.length - ruleCount;
    final importedExempts = mergedExempts.length - exemptCount;
    await FilterStore.save(
      FilterConfig(
        rules: merged,
        exempts: mergedExempts,
        display: display,
        warnings: [
          ...FilterStore.config.warnings,
          ...incoming.warnings,
          if (incoming.display.isNotEmpty) '导入文件里的显示方式只补了没设置过的范围',
        ],
      ),
    );
    SmartDialog.showToast('新增了 $importedRules 条规则、$importedExempts 条例外');
  }

  static String _signature(FilterRule rule) => [
    for (final target in rule.targets.toList()..sort((a, b) => a.index - b.index))
      target.name,
    for (final condition in rule.conditions)
      '${condition.field.name}/${condition.op.name}/'
          '${condition.values.join()}/${condition.caseSensitive}',
    rule.action?.name ?? '',
  ].join('|');
}

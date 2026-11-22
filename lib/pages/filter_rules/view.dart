import 'package:PiliPlus/common/widgets/dialog/dialog.dart';
import 'package:PiliPlus/common/widgets/dialog/export_import.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/pages/filter_rules/controller.dart';
import 'package:PiliPlus/pages/filter_rules/rule_editor.dart';
import 'package:PiliPlus/pages/setting/widgets/select_dialog.dart';
import 'package:PiliPlus/utils/filter/filter_rule.dart';
import 'package:PiliPlus/utils/filter/filter_store.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// 本地隐藏规则：一条规则 = 若干「且」关系的条件，命中后按范围设置显示成
/// 占位卡片、折叠条或直接移除；最后一个标签页放例外名单，用来救被误伤的人。
class FilterRulesPage extends StatefulWidget {
  const FilterRulesPage({super.key});

  @override
  State<FilterRulesPage> createState() => _FilterRulesPageState();
}

class _FilterRulesPageState extends State<FilterRulesPage>
    with SingleTickerProviderStateMixin {
  final FilterRulesController _controller = Get.put(FilterRulesController());
  late final TabController _tabController;

  static const _scopes = kFilterScopes;

  @override
  void initState() {
    super.initState();
    final target = Get.arguments;
    final initialIndex = target is FilterTarget ? _scopes.indexOf(target) : -1;
    _tabController = TabController(
      length: _scopes.length + 1,
      initialIndex: initialIndex < 0 ? 0 : initialIndex,
      vsync: this,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  bool get _onExemptTab => _tabController.index == _scopes.length;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SimpleScaffold(
      appBar: AppBar(
        title: const Text('本地隐藏'),
        actions: [
          IconButton(
            tooltip: '导入/导出规则',
            icon: const Icon(Icons.import_export),
            onPressed: () => showImportExportDialog<Map>(
              context,
              title: '隐藏规则',
              localFileName: () => 'filterRules',
              onExport: () =>
                  Utils.jsonEncoder.convert(FilterStore.config.toJson()),
              onImport: _controller.importConfig,
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: [
            for (final target in _scopes) Tab(text: target.label),
            const Tab(text: '例外'),
          ],
        ),
      ),
      body: Obx(
        () => TabBarView(
          controller: _tabController,
          children: [
            for (final target in _scopes) _ruleList(target, theme),
            _exemptList(theme),
          ],
        ),
      ),
      fab: FloatingActionButton(
        tooltip: '添加',
        onPressed: () => _onExemptTab ? _addExempt() : _add(),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _ruleList(FilterTarget target, ThemeData theme) {
    final rules = _controller.rulesFor(target);
    return Column(
      children: [
        _notes(theme),
        _displayRow(target, theme),
        Expanded(
          child: rules.isEmpty
              ? _empty('还没有规则，点右下角加一条', theme)
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 96),
                  itemCount: rules.length,
                  itemBuilder: (context, index) {
                    final rule = rules[index];
                    return ListTile(
                      title: Text(rule.summary, style: theme.textTheme.bodyMedium),
                      subtitle: Text(_scopeText(rule, target)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Switch(
                            value: rule.enabled,
                            onChanged: (value) => _controller.toggle(rule, value),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => _edit(rule),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => showConfirmDialog(
                              context: context,
                              title: const Text('确定删除该规则？'),
                              onConfirm: () => _controller.remove(rule),
                            ),
                          ),
                        ],
                      ),
                      onTap: () => _edit(rule),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// 每个范围各自的默认显示方式。
  Widget _displayRow(FilterTarget target, ThemeData theme) {
    final action = _controller.actionFor(target);
    return ListTile(
      dense: true,
      title: Text('命中后怎么显示', style: theme.textTheme.bodyMedium),
      subtitle: Text(
        '${target.label}：${action.label}',
        style: TextStyle(fontSize: 12, color: theme.colorScheme.outline),
      ),
      trailing: const Icon(Icons.unfold_more, size: 20),
      onTap: () async {
        final picked = await showDialog<FilterAction>(
          context: context,
          builder: (context) => SelectDialog<FilterAction>(
            title: '${target.label}命中之后',
            value: action,
            values: [
              for (final item in FilterAction.values) (item, item.label),
            ],
          ),
        );
        if (picked == null) return;
        _controller.setAction(target, picked);
        SmartDialog.showToast('已改为${picked.label}');
      },
    );
  }

  Widget _notes(ThemeData theme) {
    final notes = _controller.notes;
    if (notes.isEmpty) return const SizedBox.shrink();
    return Material(
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final note in notes)
              Text(
                note,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _exemptList(ThemeData theme) {
    final exempts = _controller.exempts;
    if (exempts.isEmpty) {
      return _empty('例外名单里的人永远不会被隐藏，用来救误伤', theme);
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: exempts.length,
      itemBuilder: (context, index) {
        final exempt = exempts[index];
        return ListTile(
          title: Text(
            exempt.name.isEmpty ? 'UID ${exempt.uid}' : exempt.name,
            style: theme.textTheme.bodyMedium,
          ),
          subtitle: Text('UID ${exempt.uid}'),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => showConfirmDialog(
              context: context,
              title: const Text('确定移出例外名单？'),
              onConfirm: () {
                _controller.removeExempt(exempt);
                SmartDialog.showToast('已移除');
              },
            ),
          ),
        );
      },
    );
  }

  Widget _empty(String text, ThemeData theme) => Center(
    child: Text(text, style: TextStyle(color: theme.colorScheme.outline)),
  );

  /// 当前标签之外还勾了哪些范围，一并显示出来，避免规则“看起来不在这里”。
  String _scopeText(FilterRule rule, FilterTarget current) {
    final others = rule.targets
        .where((target) => target != current)
        .map((target) => target.label)
        .join('、');
    final scopes = [current.label, if (others.isNotEmpty) others].join('、');
    return '范围：$scopes'
        ' · ${rule.actionLabel}'
        '${rule.enabled ? '' : '（已停用）'}';
  }

  void _add() {
    final target = _scopes[_tabController.index];
    final field = target.fields.first;
    showRuleEditorDialog(
      context,
      rule: FilterRule(
        id: _controller.nextId(),
        targets: {target},
        conditions: [
          FilterCondition(field: field, op: allowedOps(field).first, values: const ['']),
        ],
      ),
      onSave: (rule) {
        _controller.upsert(rule);
        SmartDialog.showToast('已保存');
      },
    );
  }

  void _edit(FilterRule rule) {
    showRuleEditorDialog(context, rule: rule, onSave: _controller.upsert);
  }

  void _addExempt() {
    var text = '';
    showConfirmDialog(
      context: context,
      title: const Text('加入例外名单'),
      content: TextField(
        autofocus: true,
        textInputAction: TextInputAction.done,
        keyboardType: TextInputType.number,
        onChanged: (value) => text = value,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(
          labelText: 'UID',
          border: OutlineInputBorder(),
        ),
      ),
      onConfirm: () {
        final uid = int.tryParse(text);
        if (uid == null || uid <= 0) {
          SmartDialog.showToast('请输入 UID');
          return;
        }
        _controller.exemptUid(uid);
      },
    );
  }
}

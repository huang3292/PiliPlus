import 'package:PiliPlus/common/widgets/dialog/dialog.dart';
import 'package:PiliPlus/common/widgets/dialog/export_import.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/pages/filter_rules/controller.dart';
import 'package:PiliPlus/pages/filter_rules/rule_editor.dart';
import 'package:PiliPlus/utils/filter/filter_rule.dart';
import 'package:PiliPlus/utils/filter/filter_store.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// 自定义屏蔽规则：一条规则就是一个下拉能选出来的条件，
/// 最后一个标签页放例外名单，用来救被误伤的人。
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
        title: const Text('自定义屏蔽'),
        actions: [
          IconButton(
            tooltip: '导入/导出规则',
            icon: const Icon(Icons.import_export),
            onPressed: () => showImportExportDialog<Map>(
              context,
              title: '屏蔽规则',
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
    if (rules.isEmpty) {
      return _empty('还没有规则，点右下角加一条', theme);
    }
    return ListView.builder(
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
    );
  }

  Widget _exemptList(ThemeData theme) {
    final exempts = _controller.exempts;
    if (exempts.isEmpty) {
      return _empty('例外名单里的人永远不会被屏蔽，用来救误伤', theme);
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: exempts.length,
      itemBuilder: (context, index) {
        final exempt = exempts[index];
        return ListTile(
          title: Text(
            '${exempt.field.label} ${exempt.value}',
            style: theme.textTheme.bodyMedium,
          ),
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
    return '范围：$scopes${rule.enabled ? '' : '（已停用）'}';
  }

  void _add() {
    final target = _scopes[_tabController.index];
    showRuleEditorDialog(
      context,
      rule: FilterRule(
        id: _controller.nextId(),
        targets: {target},
        field: FilterField.content,
        match: FilterMatch.contains,
        value: '',
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
        if (uid == null) {
          SmartDialog.showToast('请输入 UID');
          return;
        }
        _controller.exemptUid(uid, '');
      },
    );
  }
}

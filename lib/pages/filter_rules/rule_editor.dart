import 'package:PiliPlus/pages/filter_rules/controller.dart';
import 'package:PiliPlus/pages/setting/widgets/select_dialog.dart';
import 'package:PiliPlus/utils/filter/filter_engine.dart';
import 'package:PiliPlus/utils/filter/filter_rule.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// 新建/修改一条规则。条件和匹配方式全部从列表里选，只有「正则」方式需要
/// 自己写表达式；底部的测试框会马上说明这条规则会不会命中。
Future<void> showRuleEditorDialog(
  BuildContext context, {
  required FilterRule rule,
  required ValueChanged<FilterRule> onSave,
}) {
  return showDialog(
    context: context,
    builder: (_) => _RuleEditorDialog(rule: rule, onSave: onSave),
  );
}

class _RuleEditorDialog extends StatefulWidget {
  final FilterRule rule;
  final ValueChanged<FilterRule> onSave;

  const _RuleEditorDialog({required this.rule, required this.onSave});

  @override
  State<_RuleEditorDialog> createState() => _RuleEditorDialogState();
}

class _RuleEditorDialogState extends State<_RuleEditorDialog> {
  late final Set<FilterTarget> _targets;
  late FilterField _field;
  late FilterMatch _match;
  late bool _caseSensitive;
  late String _choiceValue;

  final _valueController = TextEditingController();
  final _exceptController = TextEditingController();
  final _sampleController = TextEditingController();

  bool get _isText =>
      _field == FilterField.content || _field == FilterField.nickname;

  bool get _isChoice =>
      _field == FilterField.official || _field == FilterField.vip;

  bool get _isDigits =>
      !_isText &&
      !_isChoice &&
      _field != FilterField.uid &&
      _match != FilterMatch.regex;

  String get _value => _isChoice ? _choiceValue : _valueController.text;

  @override
  void initState() {
    super.initState();
    final rule = widget.rule;
    _targets = {...rule.targets};
    _field = rule.field;
    _match = rule.match;
    _caseSensitive = rule.caseSensitive;
    _choiceValue = rule.value;
    _valueController.text = _isChoice ? '' : rule.value;
    _exceptController.text = rule.exceptValue ?? '';
    for (final controller in _controllers) {
      controller.addListener(_onInputChanged);
    }
  }

  List<TextEditingController> get _controllers =>
      [_valueController, _exceptController, _sampleController];

  void _onInputChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _setField(FilterField field) {
    final allowed = FilterRule.allowedMatches(field);
    final isChoice = field == FilterField.official || field == FilterField.vip;
    setState(() {
      _field = field;
      if (!allowed.contains(_match)) _match = allowed.first;
      if (isChoice) _choiceValue = '0';
    });
  }

  Future<void> _pickField() async {
    final field = await showDialog<FilterField>(
      context: context,
      builder: (context) => SelectDialog<FilterField>(
        title: '屏蔽条件',
        value: _field,
        values: [
          for (final item in FilterField.values) (item, item.label),
        ],
      ),
    );
    if (field != null) _setField(field);
  }

  Future<void> _pickMatch() async {
    final match = await showDialog<FilterMatch>(
      context: context,
      builder: (context) => SelectDialog<FilterMatch>(
        title: '怎么算命中',
        value: _match,
        values: [
          for (final item in FilterRule.allowedMatches(_field)) (item, item.label),
        ],
      ),
    );
    if (match != null) setState(() => _match = match);
  }

  Future<void> _pickChoiceValue() async {
    final isVip = _field == FilterField.vip;
    final value = await showDialog<String>(
      context: context,
      builder: (context) => SelectDialog<String>(
        title: isVip ? '大会员' : '认证状态',
        value: _choiceValue,
        values: isVip
            ? const [('1', '是大会员'), ('0', '非大会员')]
            : [
                for (final code in const ['0', '1', '2', '3'])
                  (code, FilterRule.officialLabel(code)),
              ],
      ),
    );
    if (value != null) setState(() => _choiceValue = value);
  }

  FilterRule get _draft => FilterRule(
    id: widget.rule.id,
    targets: _targets,
    field: _field,
    match: _match,
    value: _value.trim(),
    caseSensitive: _caseSensitive,
    exceptValue: _exceptController.text.isEmpty
        ? null
        : _exceptController.text.trim(),
  );

  bool get _regexBroken =>
      _match == FilterMatch.regex && !FilterEngine.isValidPattern(_value);

  bool get _canSave =>
      _targets.isNotEmpty && _value.trim().isNotEmpty && !_regexBroken;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      clipBehavior: Clip.hardEdge,
      constraints: const BoxConstraints.tightFor(width: 360),
      title: const Text('屏蔽规则'),
      content: Material(
        type: MaterialType.transparency,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _label('在哪些地方生效（可多选）'),
              for (final target in kFilterScopes)
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '屏蔽他的${target.label}',
                    style: theme.textTheme.bodyMedium,
                  ),
                  value: _targets.contains(target),
                  onChanged: (value) => setState(() {
                    if (value ?? false) {
                      _targets.add(target);
                    } else {
                      _targets.remove(target);
                    }
                  }),
                ),
              Divider(color: theme.colorScheme.outlineVariant),
              _pickerRow('条件', _field.label, _pickField),
              if (FilterRule.allowedMatches(_field).length > 1)
                _pickerRow('怎么算命中', _match.label, _pickMatch),
              const SizedBox(height: 8),
              _valueEditor(),
              if (_regexBroken)
                _note('正则表达式写错了，先改好再保存', theme.colorScheme.error),
              if (_isText) ...[
                _label('但不含（可选，用来避免误伤）'),
                _textField(_exceptController, '例如：免剧透'),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('区分大小写', style: theme.textTheme.bodyMedium),
                  value: _caseSensitive,
                  onChanged: (value) => setState(() => _caseSensitive = value),
                ),
              ],
              if (_field.needsRemoteLookup)
                _note('粉丝数/关注数不会自动获取，需在屏蔽页手动查询。'),
              if (_canPreview) ...[
                _label('测试一下（粘贴一条评论，看会不会被屏蔽）'),
                _textField(_sampleController, '输入一条内容'),
                _preview(theme),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('取消', style: TextStyle(color: theme.colorScheme.outline)),
        ),
        FilledButton(
          onPressed: _canSave
              ? () {
                  final draft = _draft;
                  Navigator.of(context).pop();
                  widget.onSave(draft);
                }
              : null,
          child: const Text('保存'),
        ),
      ],
    );
  }

  /// 粉丝数/关注数要查资料，认证/大会员是选好的码，这两种预览没意义。
  bool get _canPreview =>
      !_isChoice && !_field.needsRemoteLookup && _field != FilterField.uidLength;

  Widget _valueEditor() {
    if (_isChoice) {
      return _pickerRow('要求', _choiceValueLabel, _pickChoiceValue);
    }
    return _textField(
      _valueController,
      _match == FilterMatch.regex ? r'例如：剧透.+(第\d+集)?' : '要屏蔽的内容',
      digits: _isDigits,
    );
  }

  String get _choiceValueLabel => _field == FilterField.vip
      ? (_choiceValue == '1' ? '是大会员' : '非大会员')
      : FilterRule.officialLabel(_choiceValue);

  Widget _pickerRow(String label, String value, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: _label(label)),
          TextButton(onPressed: onTap, child: Text(value)),
          const Icon(Icons.arrow_drop_down, size: 18),
        ],
      ),
    );
  }

  Widget _textField(
    TextEditingController controller,
    String hint, {
    bool digits = false,
  }) {
    return TextField(
      controller: controller,
      inputFormatters: digits
          ? [FilteringTextInputFormatter.digitsOnly]
          : null,
      keyboardType: digits ? TextInputType.number : null,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _preview(ThemeData theme) {
    final sample = _sampleController.text.trim();
    if (sample.isEmpty || !_canSave) return const SizedBox.shrink();
    final blocked = FilterEngine(FilterConfig(rules: [_draft])).match(
      _targets.first,
      FilterSubject(
        content: sample,
        nickname: sample,
        uid: int.tryParse(sample),
        level: int.tryParse(sample),
      ),
    ).isBlocked;
    return _note(
      blocked ? '「$sample」会被屏蔽' : '「$sample」不会被屏蔽',
      blocked ? theme.colorScheme.error : theme.colorScheme.primary,
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 4, top: 10),
    child: Text(text, style: const TextStyle(fontSize: 13)),
  );

  Widget _note(String text, [Color? color]) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Text(
      text,
      style: TextStyle(fontSize: 13, color: color ?? Colors.grey),
    ),
  );
}

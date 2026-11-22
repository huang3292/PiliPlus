import 'package:PiliPlus/pages/filter_rules/controller.dart';
import 'package:PiliPlus/pages/setting/widgets/select_dialog.dart';
import 'package:PiliPlus/utils/filter/filter_engine.dart';
import 'package:PiliPlus/utils/filter/filter_rule.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:material_ui/material_ui.dart';

/// 新建/修改一条规则。字段、匹配方式、动作全部从列表里点出来，
/// 只有正则方式需要自己写表达式；底部会按每个勾选的范围分别说明会不会命中。
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
  late FilterOp _op;
  late bool _caseSensitive;
  late FilterAction? _action;
  late List<String> _options;

  final _valueController = TextEditingController();
  final _upperController = TextEditingController();
  final _exceptController = TextEditingController();
  final _sampleController = TextEditingController();

  FilterCondition get _main => FilterCondition(
    field: _field,
    op: _op,
    values: _values,
    caseSensitive: _caseSensitive,
  );

  List<String> get _values => switch (_field.kind) {
    FilterFieldKind.choice || FilterFieldKind.toggle => _options,
    _ => _op == FilterOp.between
        ? [_valueController.text.trim(), _upperController.text.trim()]
        : [_valueController.text.trim()],
  };

  bool get _isText => _field.kind == FilterFieldKind.text;

  bool get _isDigits => _field.kind == FilterFieldKind.number;

  /// 「但不含」这一层只在文本条件上有意义。
  bool get _canExcept => _isText && _op != FilterOp.notContains;

  String? get _exceptText {
    if (!_canExcept) return null;
    final text = _exceptController.text.trim();
    return text.isEmpty ? null : text;
  }

  FilterRule get _draft {
    final except = _exceptText;
    return FilterRule(
      id: widget.rule.id,
      enabled: widget.rule.enabled,
      targets: {..._targets},
      conditions: [
        _main,
        if (except != null)
          FilterCondition(
            field: _field,
            op: FilterOp.notContains,
            values: [except],
            caseSensitive: _caseSensitive,
          ),
      ],
      action: _action,
      // 用户改过就算手动规则，旧关键词搬来的那条不再算「旧数据」。
      source: FilterSource.manual,
    );
  }

  String? get _problem => _draft.problem();

  bool get _canSave => _problem == null;

  @override
  void initState() {
    super.initState();
    final rule = widget.rule;
    _targets = {...rule.targets};
    final condition = rule.conditions.first;
    _field = condition.field;
    _op = condition.op;
    _caseSensitive = condition.caseSensitive;
    _action = rule.action;
    _options = switch (_field.kind) {
      FilterFieldKind.choice || FilterFieldKind.toggle => condition.values,
      _ => const [],
    };
    if (_op == FilterOp.between && condition.values.length > 1) {
      _valueController.text = condition.values.first;
      _upperController.text = condition.values[1];
    } else if (_field.kind != FilterFieldKind.choice &&
        _field.kind != FilterFieldKind.toggle) {
      _valueController.text = condition.values.isNotEmpty
          ? condition.values.first
          : '';
    }
    final except = rule.conditions.length > 1 ? rule.conditions[1] : null;
    if (except != null && except.op == FilterOp.notContains) {
      _exceptController.text = except.values.first;
    }
    for (final controller in _controllers) {
      controller.addListener(_onInputChanged);
    }
  }

  List<TextEditingController> get _controllers =>
      [_valueController, _upperController, _exceptController, _sampleController];

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

  /// 当前勾选的范围能一起支持哪些字段：某条规则勾了评论+视频，
  /// 就只列两边都取得到数据的字段，避免存一条永远不生效的规则。
  List<FilterField> get _availableFields {
    if (_targets.isEmpty) return FilterField.values.toList();
    return FilterField.values
        .where(
          (field) => _targets.every((target) => field.availableFor(target)),
        )
        .toList(growable: false);
  }

  void _setField(FilterField field) {
    final allowed = allowedOps(field);
    setState(() {
      _field = field;
      if (!allowed.contains(_op)) _op = allowed.first;
      _options = const [];
      if (field.kind == FilterFieldKind.toggle) _options = const ['1'];
      _valueController.clear();
      _upperController.clear();
    });
  }

  void _setOp(FilterOp op) {
    setState(() {
      _op = op;
      if (op != FilterOp.between) _upperController.clear();
    });
  }

  Future<void> _pickField() async {
    final fields = _availableFields;
    if (fields.isEmpty) {
      _showNote('这几个范围没有共同的判断依据，请少勾一个范围');
      return;
    }
    final field = await showDialog<FilterField>(
      context: context,
      builder: (context) => SelectDialog<FilterField>(
        title: '隐藏依据',
        value: fields.contains(_field) ? _field : fields.first,
        values: [
          for (final item in fields) (item, item.label),
        ],
      ),
    );
    if (field != null) _setField(field);
  }

  Future<void> _pickOp() async {
    final op = await showDialog<FilterOp>(
      context: context,
      builder: (context) => SelectDialog<FilterOp>(
        title: '怎么算命中',
        value: _op,
        values: [
          for (final item in allowedOps(_field)) (item, item.label),
        ],
      ),
    );
    if (op != null) _setOp(op);
  }

  Future<void> _pickAction() async {
    const followDefault = 0;
    final current = _action == null ? followDefault : _action!.index + 1;
    final picked = await showDialog<int>(
      context: context,
      builder: (context) => SelectDialog<int>(
        title: '命中之后',
        value: current,
        values: const [
          (followDefault, '跟随范围默认'),
          (1, '显示占位卡片'),
          (2, '折叠成一行'),
          (3, '直接移除'),
        ],
      ),
    );
    if (picked == null) return;
    setState(
      () => _action = picked == followDefault
          ? null
          : FilterAction.values[picked - 1],
    );
  }

  /// 选项类字段（认证、大会员类型）可以多选，纯点选，不要求用户写编号。
  Future<void> _pickOptions() async {
    final options = FilterField.optionsFor(_field);
    if (options.isEmpty) return;
    final selected = await showDialog<List<String>>(
      context: context,
      builder: (context) => _OptionDialog(
        title: _field.label,
        options: options,
        selected: _options,
        single: _field.kind == FilterFieldKind.toggle,
      ),
    );
    if (selected != null) setState(() => _options = selected);
  }

  String get _valueLabel {
    if (_field.kind == FilterFieldKind.choice ||
        _field.kind == FilterFieldKind.toggle) {
      if (_options.isEmpty) return '还没选';
      return _options.map((value) => FilterField.optionLabel(_field, value)).join('、');
    }
    if (_op == FilterOp.between) {
      final lower = _valueController.text.trim();
      final upper = _upperController.text.trim();
      return lower.isEmpty || upper.isEmpty ? '还没填' : '$lower ~ $upper';
    }
    return _valueController.text.trim().isEmpty ? '还没填' : _valueController.text.trim();
  }

  void _showNote(String text) {
    SmartDialog.showToast(text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final problem = _problem;
    return AlertDialog(
      clipBehavior: Clip.hardEdge,
      constraints: const BoxConstraints.tightFor(width: 360),
      title: const Text('隐藏规则'),
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
                  title: Text(target.label, style: theme.textTheme.bodyMedium),
                  value: _targets.contains(target),
                  onChanged: (value) => setState(() {
                    if (value ?? false) {
                      _targets.add(target);
                    } else {
                      _targets.remove(target);
                    }
                    final fields = _availableFields;
                    if (!fields.contains(_field) && fields.isNotEmpty) {
                      _field = fields.first;
                      final allowed = allowedOps(_field);
                      if (!allowed.contains(_op)) _op = allowed.first;
                    }
                  }),
                ),
              Divider(color: theme.colorScheme.outlineVariant),
              _pickerRow('隐藏依据', _field.label, _pickField),
              if (allowedOps(_field).length > 1)
                _pickerRow('条件', _op.label, _pickOp),
              const SizedBox(height: 8),
              _valueEditor(theme),
              if (_isText) ...[
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '区分大小写',
                    style: theme.textTheme.bodyMedium,
                  ),
                  value: _caseSensitive,
                  onChanged: (value) => setState(() => _caseSensitive = value),
                ),
                if (_canExcept) ...[
                  _label('但不含（可选，用来避免误伤）'),
                  _textField(_exceptController, '例如：免剧透'),
                ],
              ],
              _pickerRow('命中之后', _action?.label ?? '跟随范围默认', _pickAction),
              _hint(),
              if (problem != null && _valueLabel != '还没填')
                _note(problem, theme.colorScheme.error),
              if (_canPreview) ...[
                _label('测试一下（单独看这条规则）'),
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

  Widget _valueEditor(ThemeData theme) {
    if (_field.kind == FilterFieldKind.choice ||
        _field.kind == FilterFieldKind.toggle) {
      return _pickerRow('要求', _valueLabel, _pickOptions);
    }
    if (_op == FilterOp.between) {
      return Row(
        children: [
          Expanded(child: _textField(_valueController, '最小值', digits: true)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text('~', style: theme.textTheme.bodyMedium),
          ),
          Expanded(child: _textField(_upperController, '最大值', digits: true)),
        ],
      );
    }
    return _textField(
      _valueController,
      switch (_field.kind) {
        FilterFieldKind.number => switch (_field) {
          FilterField.level => '0 到 6',
          FilterField.uidLength => '例如：9',
          _ => '例如：12345',
        },
        _ => _op == FilterOp.matches || _op == FilterOp.notMatches
            ? r'例如：剧透.+(第\d+集)?'
            : '要匹配的内容',
      },
      digits: _isDigits,
    );
  }

  /// 有些依据在某些范围根本取不到数据，写清楚比让人猜强。
  Widget _hint() {
    final missing = FilterField.values
        .where((field) => _targets.any((target) => !field.availableFor(target)))
        .map((field) => field.label)
        .join('、');
    if (missing.isEmpty) return const SizedBox.shrink();
    return _note(
      '「$missing」不是当前勾选范围都能取到的依据，所以选不到；'
      '想用它就把范围改成评论或动态',
    );
  }

  bool get _canPreview => _isText || (_isDigits && _op != FilterOp.between);

  Widget _preview(ThemeData theme) {
    final sample = _sampleController.text.trim();
    if (sample.isEmpty || !_canSave) return const SizedBox.shrink();
    final engine = FilterEngine(FilterConfig(rules: [_draft]));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final target in _targets)
          _previewLine(engine, target, sample, theme),
      ],
    );
  }

  Widget _previewLine(
    FilterEngine engine,
    FilterTarget target,
    String sample,
    ThemeData theme,
  ) {
    final decision = engine.preview(target: target, sample: sample);
    return _note(
      '${target.label}：${decision.isHidden ? '会隐藏（${decision.reason}）' : '不会隐藏'}',
      decision.isHidden ? theme.colorScheme.error : theme.colorScheme.outline,
    );
  }

  Widget _pickerRow(String label, String value, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: _label(label)),
          Flexible(
            child: TextButton(
              onPressed: onTap,
              child: Text(value, overflow: TextOverflow.ellipsis),
            ),
          ),
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

/// 认证状态、大会员类型这类固定选项，用勾选代替让用户写编号。
class _OptionDialog extends StatefulWidget {
  final String title;
  final List<(String, String)> options;
  final List<String> selected;
  final bool single;

  const _OptionDialog({
    required this.title,
    required this.options,
    required this.selected,
    required this.single,
  });

  @override
  State<_OptionDialog> createState() => _OptionDialogState();
}

class _OptionDialogState extends State<_OptionDialog> {
  late final Set<String> _selected = {...widget.selected};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: Material(
        type: MaterialType.transparency,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (code, label) in widget.options)
                CheckboxListTile(
                  dense: true,
                  title: Text(label, style: theme.textTheme.bodyMedium),
                  value: _selected.contains(code),
                  onChanged: (value) => setState(() {
                    if (widget.single) {
                      _selected
                        ..clear()
                        ..add(code);
                    } else if (value ?? false) {
                      _selected.add(code);
                    } else {
                      _selected.remove(code);
                    }
                  }),
                ),
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
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.of(context).pop(_selected.toList()),
          child: const Text('确定'),
        ),
      ],
    );
  }
}

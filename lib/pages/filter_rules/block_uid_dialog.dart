import 'package:PiliPlus/http/video.dart';
import 'package:PiliPlus/pages/filter_rules/controller.dart';
import 'package:PiliPlus/utils/filter/filter_rule.dart';
import 'package:PiliPlus/utils/filter/filter_store.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:material_ui/material_ui.dart';

/// 长按评论/视频里的「隐藏此人」：一次勾选就能决定隐藏他的哪些内容。
/// 弹幕不在这里，弹幕的作者 id 是哈希过的，走弹幕屏蔽页。
Future<void> showBlockUserDialog(
  BuildContext context, {
  required int uid,
  required String? nickname,
  required Set<FilterTarget> presets,
  VoidCallback? onBlocked,
}) {
  return showDialog(
    context: context,
    builder: (_) => _BlockUserDialog(
      uid: uid,
      nickname: nickname ?? '',
      presets: presets,
      onBlocked: onBlocked,
    ),
  );
}

class _BlockUserDialog extends StatefulWidget {
  final int uid;
  final String nickname;
  final Set<FilterTarget> presets;
  final VoidCallback? onBlocked;

  const _BlockUserDialog({
    required this.uid,
    required this.nickname,
    required this.presets,
    this.onBlocked,
  });

  @override
  State<_BlockUserDialog> createState() => _BlockUserDialogState();
}

class _BlockUserDialogState extends State<_BlockUserDialog> {
  late final Set<FilterTarget> _selected = {...widget.presets};
  bool _alsoOfficialBlacklist = false;

  /// 这个人在例外名单里的话，隐藏规则对他无效，必须先说清楚。
  FilterExempt? get _exempt => FilterStore.exemptOf(widget.uid);

  Future<void> _confirm() async {
    final selected = {..._selected};
    final alsoBlacklist = _alsoOfficialBlacklist;
    final exempt = _exempt;
    if (exempt != null && !await _askConflict(exempt)) return;
    Navigator.of(context).pop();

    await FilterStore.blockUid(widget.uid, selected, name: widget.nickname);
    if (exempt != null) await FilterStore.removeExempt(widget.uid);
    if (alsoBlacklist) {
      final res = await VideoHttp.relationMod(
        mid: widget.uid,
        act: 5,
        reSrc: 11,
      );
      if (!res.isSuccess) res.toast();
    }
    SmartDialog.showToast(
      '已隐藏 ${widget.nickname} 的${selected.map((e) => e.label).join('、')}'
      '，可在「本地隐藏」里撤销',
    );
    widget.onBlocked?.call();
  }

  /// 手动例外 vs 明确隐藏的冲突：默认例外赢，用户也可以选「移除例外并继续」。
  Future<bool> _askConflict(FilterExempt exempt) async {
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('这个人在例外名单里'),
        content: const Material(
          type: MaterialType.transparency,
          child: Text(
            '例外名单优先级最高，直接隐藏他不会生效。\n'
            '要移除例外再隐藏，还是保留例外（等于不隐藏他）？',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop('keep'),
            child: const Text('保留例外'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop('remove'),
            child: const Text('移除例外并隐藏'),
          ),
        ],
      ),
    );
    return action == 'remove';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      clipBehavior: Clip.hardEdge,
      constraints: const BoxConstraints.tightFor(width: 360),
      title: Text('隐藏 ${widget.nickname}'),
      content: Material(
        type: MaterialType.transparency,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _label('隐藏他的（可多选）', theme),
              for (final target in kFilterScopes)
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(target.label, style: theme.textTheme.bodyMedium),
                  value: _selected.contains(target),
                  onChanged: (value) => setState(() {
                    if (value ?? false) {
                      _selected.add(target);
                    } else {
                      _selected.remove(target);
                    }
                  }),
                ),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '同时加入 B 站官方黑名单',
                  style: theme.textTheme.bodyMedium,
                ),
                subtitle: Text(
                  '换设备也生效，但对方会知道你拉黑了他；'
                  'B 站黑名单不分范围，他的视频和评论都会一起藏起来',
                  style: TextStyle(fontSize: 12, color: theme.colorScheme.outline),
                ),
                value: _alsoOfficialBlacklist,
                onChanged: (value) =>
                    setState(() => _alsoOfficialBlacklist = value ?? false),
              ),
              if (_exempt != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '此人已在例外名单，规则对他不生效',
                    style: TextStyle(fontSize: 12, color: theme.colorScheme.error),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _addExempt,
          child: const Text('加入例外名单'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('取消', style: TextStyle(color: theme.colorScheme.outline)),
        ),
        FilledButton(
          onPressed: _selected.isEmpty ? null : _confirm,
          child: const Text('隐藏'),
        ),
      ],
    );
  }

  Widget _label(String text, ThemeData theme) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(
      text,
      style: theme.textTheme.bodySmall ?? const TextStyle(fontSize: 13),
    ),
  );

  /// 误伤补救：这个人不该被隐藏时，直接放他进例外名单。
  Future<void> _addExempt() async {
    Navigator.of(context).pop();
    await FilterStore.exemptUid(widget.uid, name: widget.nickname);
    SmartDialog.showToast('已把 ${widget.nickname} 加入例外名单');
  }
}

import 'package:PiliPlus/http/video.dart';
import 'package:PiliPlus/pages/filter_rules/controller.dart';
import 'package:PiliPlus/utils/filter/filter_rule.dart';
import 'package:PiliPlus/utils/filter/filter_store.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:material_ui/material_ui.dart';

/// 长按评论/视频里的「屏蔽此人」：一次勾选就能决定屏蔽他的哪些内容。
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

  Future<void> _confirm() async {
    final selected = {..._selected};
    final alsoBlacklist = _alsoOfficialBlacklist;
    Navigator.of(context).pop();
    await FilterStore.blockUid(widget.uid, selected);
    if (alsoBlacklist) {
      final res = await VideoHttp.relationMod(
        mid: widget.uid,
        act: 5,
        reSrc: 11,
      );
      if (!res.isSuccess) res.toast();
    }
    SmartDialog.showToast(
      '已屏蔽 ${widget.nickname} 的${selected.map((e) => e.label).join('、')}',
    );
    widget.onBlocked?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      clipBehavior: Clip.hardEdge,
      constraints: const BoxConstraints.tightFor(width: 360),
      title: Text('屏蔽 ${widget.nickname}'),
      content: Material(
        type: MaterialType.transparency,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final target in kFilterScopes)
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '屏蔽他的${target.label}',
                    style: theme.textTheme.bodyMedium,
                  ),
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
                  '换设备也生效，但对方会知道你拉黑了他',
                  style: TextStyle(fontSize: 12, color: theme.colorScheme.outline),
                ),
                value: _alsoOfficialBlacklist,
                onChanged: (value) =>
                    setState(() => _alsoOfficialBlacklist = value ?? false),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => _addExempt(),
          child: const Text('加入例外名单'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('取消', style: TextStyle(color: theme.colorScheme.outline)),
        ),
        FilledButton(
          onPressed: _selected.isEmpty ? null : _confirm,
          child: const Text('屏蔽'),
        ),
      ],
    );
  }

  /// 误伤补救：这个人不该被屏蔽时，直接放他进例外名单。
  Future<void> _addExempt() async {
    Navigator.of(context).pop();
    await FilterStore.exemptUid(widget.uid, widget.nickname);
    SmartDialog.showToast('已把 ${widget.nickname} 加入例外名单');
  }
}

import 'package:PiliPlus/utils/filter/filter_engine.dart';
import 'package:material_ui/material_ui.dart';

/// 命中隐藏规则后盖在原条目上的占位层。尺寸与点击区域跟原条目一致，
/// 点一下只展开这一条，不会解除规则；列表的分页、计数都按「条目还在」处理。
class HiddenOverlay extends StatefulWidget {
  final Widget child;

  /// 卡片上写的那句话，例如「已隐藏视频」。
  final String label;
  final FilterDecision decision;

  const HiddenOverlay({
    super.key,
    required this.label,
    required this.decision,
    required this.child,
  });

  @override
  State<HiddenOverlay> createState() => _HiddenOverlayState();
}

class _HiddenOverlayState extends State<HiddenOverlay> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    if (_revealed) return widget.child;
    final colorScheme = Theme.of(context).colorScheme;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        IgnorePointer(child: Opacity(opacity: 0, child: widget.child)),
        Positioned.fill(
          child: Material(
            color: colorScheme.secondaryContainer,
            child: InkWell(
              onTap: () => setState(() => _revealed = true),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.visibility_off_outlined,
                        size: 20,
                        color: colorScheme.onSecondaryContainer,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.label,
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.onSecondaryContainer,
                        ),
                      ),
                      Text(
                        _sourceText(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSecondaryContainer.withValues(
                            alpha: 0.7,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _sourceText() {
    final decision = widget.decision;
    final source = decision.rule?.source ?? decision.source;
    final label = source?.label ?? '';
    return label.isEmpty ? '点击展开' : '$label · 点击展开';
  }
}

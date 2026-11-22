import 'package:PiliPlus/utils/filter/filter_engine.dart';
import 'package:PiliPlus/utils/filter/filter_marks.dart';
import 'package:PiliPlus/utils/filter/filter_rule.dart';
import 'package:PiliPlus/utils/filter/filter_store.dart';
import 'package:PiliPlus/utils/global_data.dart';

/// 数据层唯一该问的地方：把「规则、B 站黑名单、旧关键词过滤」三套判断收敛成一次判定，
/// 并把结果交给渲染层。
abstract final class FilterJudge {
  /// 返回 true 表示这一条直接从列表里去掉（用户选了「直接移除」，或者这条列表
  /// 没有可用的 id、没法打标记）。返回 false 且命中隐藏时，结论已写进
  /// [FilterMarks]，item widget 渲染时按它显示占位或折叠条。
  static bool removeOrMark({
    required FilterTarget target,
    required Object? markKey,
    required FilterSubject subject,
    bool legacyHit = false,
  }) {
    final decision = decide(target: target, subject: subject, legacyHit: legacyHit);
    if (!decision.isHidden) return false;
    if (markKey == null || decision.shouldRemove) return true;
    FilterMarks.put(target, markKey, decision);
    return false;
  }

  static FilterDecision decide({
    required FilterTarget target,
    required FilterSubject subject,
    bool legacyHit = false,
  }) {
    if (!FilterStore.engine.hasActiveRules &&
        !legacyHit &&
        !blacklisted(subject.uid)) {
      return const FilterDecision.pass();
    }
    return FilterStore.engine.decide(
      target: target,
      subject: subject,
      blacklisted: blacklisted(subject.uid),
      legacyHit: legacyHit,
    );
  }

  /// 例外名单优先级最高，所以「为什么要问用户」这一步也得走完整判定。
  static bool blacklisted(int? uid) =>
      uid != null && uid > 0 && GlobalData().blackMids.contains(uid);
}

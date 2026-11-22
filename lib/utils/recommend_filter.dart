import 'package:PiliPlus/models/model_video.dart';
import 'package:PiliPlus/utils/filter/filter_engine.dart';
import 'package:PiliPlus/utils/filter/filter_judge.dart';
import 'package:PiliPlus/utils/filter/filter_rule.dart';
import 'package:PiliPlus/utils/storage_pref.dart';

/// 视频列表的统一入口。
///
/// 分成两类，语义不一样，别再混着用：
/// - 「不够好看」：时长/播放量/点赞比阈值，命中就不进列表，属于推荐质量过滤；
/// - 「要隐藏」：自定义规则、B 站黑名单、旧关键词过滤，命中后条目照常入列表，
///   由卡片按设置渲染成占位卡或直接移除。
abstract final class RecommendFilter {
  static int minDurationForRcmd = Pref.minDurationForRcmd;
  static int minPlayForRcmd = Pref.minPlayForRcmd;
  static int minLikeRatioForRecommend = Pref.minLikeRatioForRecommend;
  static bool exemptFilterForFollowed = Pref.exemptFilterForFollowed;
  static bool applyFilterToRelatedVideos = Pref.applyFilterToRelatedVideos;

  /// 旧「标题关键词」，只匹配标题。
  static RegExp titleRegExp = RegExp(
    Pref.banWordForRecommend,
    caseSensitive: false,
  );

  /// 旧「分区关键词」，只匹配分区名（tname），不会被当成标题匹配。
  static RegExp zoneRegExp = RegExp(Pref.banWordForZone, caseSensitive: false);

  /// [zone] 只有热门/排行/App 推荐给得到，缺了就不参与分区判定。
  /// 返回 null 表示这条不进列表；否则是隐藏结论，未命中为 pass。
  static FilterDecision? filter(
    BaseVideoItemModel item, {
    String? zone,
    bool checkDuration = true,
  }) {
    if (item.isFollowed && exemptFilterForFollowed) {
      return const FilterDecision.pass();
    }
    if (_tooWeak(item, checkDuration: checkDuration)) return null;
    final decision = FilterJudge.decide(
      target: FilterTarget.video,
      subject: FilterSubject(
        uid: item.owner.mid,
        nickname: item.owner.name,
        videoTitle: item.title,
        videoZone: zone,
      ),
      legacyHit: _legacyHit(item.title, zone),
    );
    return decision.shouldRemove ? null : decision;
  }

  static bool _tooWeak(
    BaseVideoItemModel item, {
    required bool checkDuration,
  }) {
    if (checkDuration) {
      final duration = item.duration;
      if (duration > 0 && duration < minDurationForRcmd) return true;
    }
    final stat = item.stat;
    final view = stat.view;
    final like = stat.like;
    if (view != null && view > -1 && view < minPlayForRcmd) return true;
    return like != null &&
        view != null &&
        view > -1 &&
        like > -1 &&
        like * 100 < minLikeRatioForRecommend * view;
  }

  static bool _legacyHit(String title, String? zone) {
    if (titleRegExp.pattern.isNotEmpty && titleRegExp.hasMatch(title)) {
      return true;
    }
    return zone != null &&
        zoneRegExp.pattern.isNotEmpty &&
        zoneRegExp.hasMatch(zone);
  }
}

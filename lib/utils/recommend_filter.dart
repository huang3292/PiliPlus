import 'package:PiliPlus/models/model_video.dart';
import 'package:PiliPlus/utils/filter/filter_engine.dart';
import 'package:PiliPlus/utils/filter/filter_rule.dart';
import 'package:PiliPlus/utils/filter/filter_store.dart';
import 'package:PiliPlus/utils/storage_pref.dart';

abstract final class RecommendFilter {
  static int minDurationForRcmd = Pref.minDurationForRcmd;
  static int minPlayForRcmd = Pref.minPlayForRcmd;
  static int minLikeRatioForRecommend = Pref.minLikeRatioForRecommend;
  static bool exemptFilterForFollowed = Pref.exemptFilterForFollowed;
  static bool applyFilterToRelatedVideos = Pref.applyFilterToRelatedVideos;
  static RegExp rcmdRegExp = RegExp(
    Pref.banWordForRecommend,
    caseSensitive: false,
  );
  static bool enableFilter = rcmdRegExp.pattern.isNotEmpty;

  // (web/app)rcmd
  static bool filterWithExempt(BaseVideoItemModel videoItem) {
    //由于相关视频中没有已关注标签，只能视为非关注视频
    if (videoItem.isFollowed && exemptFilterForFollowed) {
      return false;
    }
    return filterAll(videoItem);
  }

  /// hot/rank/[filterAll]
  static bool filterLikeRatio(int? like, int? view) {
    if (view != null) {
      return (view > -1 && view < minPlayForRcmd) ||
          (like != null &&
              like > -1 &&
              like * 100 < minLikeRatioForRecommend * view);
    }
    return false;
  }

  /// hot/rank/[filterAll]
  static bool filterTitle(String title) {
    return (enableFilter && rcmdRegExp.hasMatch(title));
  }

  /// [filterAll]
  static bool filterDuration(int duration) {
    return duration > 0 && duration < minDurationForRcmd;
  }

  /// related/[filterWithExempt]
  static bool filterAll(BaseVideoItemModel videoItem) {
    return filterDuration(videoItem.duration) ||
        filterLikeRatio(videoItem.stat.like, videoItem.stat.view) ||
        filterTitle(videoItem.title) ||
        _blockedByRules(videoItem);
  }

  /// 热门/排行此时还是原始 json，只能自己从 map 里取 up 主。
  static bool blockedFromJson(Map video) {
    if (!FilterStore.engine.hasActiveRules) return false;
    final owner = video['owner'];
    final mid = owner is Map ? owner['mid'] : null;
    final name = owner is Map ? owner['name'] : null;
    return FilterStore.blocked(
      FilterTarget.video,
      FilterSubject(
        uid: mid is int ? mid : null,
        nickname: name is String ? name : null,
        content: video['title'] is String ? video['title'] : null,
      ),
    );
  }

  /// 自定义规则里的「视频」条件；列表项只有 up 主和标题可用来比对。
  static bool _blockedByRules(BaseVideoItemModel videoItem) {
    if (!FilterStore.engine.hasActiveRules) return false;
    final owner = videoItem.owner;
    return FilterStore.blocked(
      FilterTarget.video,
      FilterSubject(
        uid: owner.mid,
        nickname: owner.name,
        content: videoItem.title,
      ),
    );
  }
}

import 'package:PiliPlus/utils/filter/filter_engine.dart';
import 'package:PiliPlus/utils/filter/filter_rule.dart';

/// 判定发生在数据层（那时字段最全），渲染发生在 item widget（只拿得到 id），
/// 中间靠这张表把结论带到界面上。表有上限，规则一变整体作废重算。
abstract final class FilterMarks {
  static const _capacity = 4000;

  static final Map<FilterTarget, Map<Object, FilterDecision>> _store = {};

  static void put(FilterTarget target, Object key, FilterDecision decision) {
    final marks = _store.putIfAbsent(target, () => {});
    marks[key] = decision;
    if (marks.length > _capacity) {
      marks.remove(marks.keys.first);
    }
  }

  static FilterDecision? of(FilterTarget target, Object? key) {
    if (key == null) return null;
    return _store[target]?[key];
  }

  /// 规则、例外或显示设置改了就全部作废，下一条数据重新判定。
  static void clear() => _store.clear();
}

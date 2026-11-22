import 'package:PiliPlus/utils/filter/filter_engine.dart';
import 'package:PiliPlus/utils/filter/filter_marks.dart';
import 'package:PiliPlus/utils/filter/filter_migration.dart';
import 'package:PiliPlus/utils/filter/filter_rule.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> oldRule({
  int? id,
  bool? on,
  List<String> targets = const ['reply'],
  Object? field = 'content',
  String match = 'contains',
  Object? value = '剧透',
  Object? except,
}) {
  return {
    if (id != null) 'id': id,
    if (on != null) 'on': on,
    'targets': targets,
    'field': field,
    'match': match,
    'value': value,
    if (except != null) 'except': except,
  };
}

FilterConfig migrate(List<Map<String, dynamic>> rules, {List exempts = const []}) =>
    FilterMigration.v1({'rules': rules, 'exempts': exempts})!;

void main() {
  group('旧规则搬到 v2', () {
    test('正文按范围落到各自的文本字段', () {
      final config = migrate([
        oldRule(targets: const ['reply', 'video', 'dyn'], value: '剧透'),
      ]);
      expect(config.rules, hasLength(3));
      expect(
        config.rules.map((rule) => rule.summary).toList(),
        ['评论正文 包含 剧透', '视频标题 包含 剧透', '动态正文 包含 剧透'],
      );
      expect(config.rules.map((rule) => rule.id).toList(), [1, 2, 3]);
      expect(config.rules.map((rule) => rule.targets.length).toList(), [1, 1, 1]);
      expect(config.warnings, isEmpty);
    });

    test('旧的「排除词」搬成同一条规则里的「不包含」', () {
      final config = migrate([
        oldRule(value: '广告', except: '游戏广告'),
        oldRule(targets: const ['video'], field: 'nickname', value: '小', except: '小心'),
        oldRule(targets: const ['video'], field: 'uid', match: 'equals', value: '123', except: '321'),
      ]);
      expect(config.rules[0].conditions, hasLength(2));
      expect(config.rules[0].conditions.last.op, FilterOp.notContains);
      expect(config.rules[0].summary, '评论正文 包含 广告 且 评论正文 不包含 游戏广告');
      expect(config.rules[1].conditions, hasLength(2));
      // UID 规则的排除词以前就没有意义，不硬造条件。
      expect(config.rules[2].conditions, hasLength(1));
    });

    test('认证状态改成接口口径', () {
      final config = migrate([
        oldRule(field: 'official', value: '0'),
        oldRule(id: 2, field: 'official', value: '1'),
        oldRule(id: 3, field: 'official', value: '2'),
        oldRule(id: 4, field: 'official', value: '3'),
      ]);
      expect(
        config.rules.map((rule) => rule.summary).toList(),
        ['认证状态 属于 无认证', '认证状态 属于 个人认证', '认证状态 属于 机构认证'],
      );
      expect(config.rules.singleWhere((rule) => rule.conditions.first.values.first == '1')
          .conditions.first.field, FilterField.official);
      expect(config.warnings, hasLength(1));
      expect(config.warnings.single, contains('认证状态'));
    });

    test('数值条件保留比较方式', () {
      final config = migrate([
        oldRule(field: 'level', match: 'lessThan', value: '3'),
        oldRule(id: 2, field: 'uidLength', match: 'atLeast', value: '6'),
        oldRule(id: 3, field: 'vip', value: '1'),
      ]);
      expect(config.rules[0].summary, '用户等级 小于 3');
      expect(config.rules[1].summary, 'UID 位数 大于等于 6');
      expect(config.rules[2].summary, '有效大会员 等于 是');
      expect(config.rules.every((rule) => rule.problem() == null), isTrue);
    });

    test('粉丝数与关注数一律丢弃并说明原因', () {
      final config = migrate([
        oldRule(field: 'fans', value: '100'),
        oldRule(id: 2, field: 'following', value: '50'),
        oldRule(id: 3, field: 'nope', value: 'x'),
      ]);
      expect(config.rules, isEmpty);
      expect(config.warnings, hasLength(3));
      expect(config.warnings[0], contains('粉丝数'));
      expect(config.warnings[1], contains('关注数'));
    });

    test('搬不动的旧范围只提示，不硬套字段', () {
      final config = migrate([
        oldRule(targets: const ['danmaku'], value: '剧透'),
        oldRule(id: 2, targets: const ['search'], field: 'level', match: 'lessThan', value: '2'),
      ]);
      expect(config.rules, isEmpty);
      expect(config.warnings, hasLength(2));
      expect(config.warnings.last, contains('等级'));
    });

    test('停用、空值、坏数据', () {
      final config = migrate([
        oldRule(on: false, id: 7),
        oldRule(id: 8, value: ''),
        oldRule(id: 9, field: null),
        oldRule(id: 10, targets: const ['nope']),
      ]);
      expect(config.rules, hasLength(1));
      expect(config.rules.single.enabled, isFalse);
      expect(config.rules.single.id, 7);
      expect(config.warnings, hasLength(2));
    });

    test('旧例外只按 UID 放行', () {
      final config = migrate(
        [oldRule()],
        exempts: [
          {'field': 'uid', 'value': '1234'},
          {'field': 'uid', 'value': '不是数字'},
          {'field': 'nickname', 'value': '老朋友'},
        ],
      );
      expect(config.exempts, hasLength(1));
      expect(config.exempts.single.uid, 1234);
      expect(config.warnings, hasLength(2));
      expect(config.warnings.last, contains('昵称'));
    });

    test('已经是 v2 或读不懂时不动数据', () {
      expect(FilterMigration.v1({}), isNull);
      expect(FilterMigration.v1({'rules': 'nope'}), isNull);
      expect(FilterMigration.v1({'rules': []})!.isEmpty, isTrue);
    });

    test('搬完的规则能直接跑起来', () {
      final config = migrate([oldRule(targets: const ['reply'], value: '剧透')]);
      final decision = FilterEngine(config).decide(
        target: FilterTarget.reply,
        subject: const FilterSubject(uid: 1, replyContent: '前面有剧透'),
      );
      expect(decision.isHidden, isTrue);
      expect(decision.source, FilterSource.manual);
      expect(decision.reason, '评论正文 包含 剧透');
    });
  });

  group('判定结果带到界面上', () {
    // protobuf 的评论消息不能加字段，命中结论记在这张侧表里。
    final hidden = FilterDecision.hidden(
      action: FilterAction.collapse,
      source: FilterSource.manual,
      reason: '评论正文 包含 剧透',
    );

    tearDown(FilterMarks.clear);

    test('按 id 取得到结论', () {
      FilterMarks.put(FilterTarget.reply, '123', hidden);
      expect(FilterMarks.of(FilterTarget.reply, '123'), same(hidden));
      expect(FilterMarks.of(FilterTarget.reply, '456'), isNull);
      expect(FilterMarks.of(FilterTarget.dyn, '123'), isNull);
      expect(FilterMarks.of(FilterTarget.reply, null), isNull);
    });

    test('规则一改就全部作废', () {
      FilterMarks.put(FilterTarget.reply, '1', hidden);
      FilterMarks.clear();
      expect(FilterMarks.of(FilterTarget.reply, '1'), isNull);
    });

    test('刷太久远的评论不会一直占着内存', () {
      for (var i = 0; i < 4050; i++) {
        FilterMarks.put(FilterTarget.reply, i, hidden);
      }
      expect(FilterMarks.of(FilterTarget.reply, 0), isNull);
      expect(FilterMarks.of(FilterTarget.reply, 4049), isNotNull);
    });
  });
}

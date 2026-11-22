import 'dart:convert';

import 'package:PiliPlus/utils/filter/filter_engine.dart';
import 'package:PiliPlus/utils/filter/filter_rule.dart';
import 'package:flutter_test/flutter_test.dart';

FilterCondition cond(
  FilterField field,
  FilterOp op,
  List<String> values, {
  bool caseSensitive = false,
}) {
  return FilterCondition(
    field: field,
    op: op,
    values: values,
    caseSensitive: caseSensitive,
  );
}

FilterRule rule(
  FilterTarget target,
  FilterCondition condition, {
  int id = 1,
  bool enabled = true,
  FilterAction? action,
  FilterSource source = FilterSource.manual,
}) {
  return FilterRule(
    id: id,
    targets: {target},
    conditions: [condition],
    enabled: enabled,
    action: action,
    source: source,
  );
}

FilterEngine engine(
  List<FilterRule> rules, {
  List<FilterExempt> exempts = const [],
  Map<FilterTarget, FilterAction> display = const {},
}) {
  return FilterEngine(
    FilterConfig(rules: rules, exempts: exempts, display: display),
  );
}

void main() {
  const video = FilterSubject(
    uid: 12345,
    nickname: 'TestUser',
    videoTitle: '这个广告真长 Hello World',
    videoZone: '影视',
  );
  const reply = FilterSubject(
    uid: 12345,
    nickname: 'TestUser',
    replyContent: '这个广告真长',
    level: 3,
  );

  group('文本条件', () {
    test('包含默认忽略大小写', () {
      final decision = engine([
        rule(FilterTarget.video, cond(FilterField.videoTitle, FilterOp.contains, ['hello'])),
      ]).decide(target: FilterTarget.video, subject: video);
      expect(decision.isHidden, isTrue);
      expect(decision.action, FilterAction.placeholder);
    });

    test('勾选区分大小写后不再误命中', () {
      expect(
        engine([
          rule(
            FilterTarget.video,
            cond(
              FilterField.videoTitle,
              FilterOp.contains,
              ['hello'],
              caseSensitive: true,
            ),
          ),
        ]).decide(target: FilterTarget.video, subject: video).isHidden,
        isFalse,
      );
    });

    test('开头/结尾/等于/不等于', () {
      bool hits(FilterOp op, List<String> values) => engine([
        rule(FilterTarget.video, cond(FilterField.videoTitle, op, values)),
      ]).decide(target: FilterTarget.video, subject: video).isHidden;
      expect(hits(FilterOp.startsWith, ['这个']), isTrue);
      expect(hits(FilterOp.endsWith, ['短']), isFalse);
      expect(hits(FilterOp.equals, ['这个广告真长 hello world']), isTrue);
      expect(hits(FilterOp.equals, ['别的标题']), isFalse);
      expect(hits(FilterOp.notEquals, ['别的标题']), isTrue);
    });

    test('正文为空时反向条件不算命中', () {
      // 「不包含」在接口没给正文时必须放行，否则整页都会被藏起来。
      expect(
        engine([
          rule(FilterTarget.reply, cond(FilterField.replyContent, FilterOp.notContains, ['广告'])),
        ]).decide(target: FilterTarget.reply, subject: const FilterSubject(uid: 1)).isHidden,
        isFalse,
      );
    });

    test('一条规则里的条件是「且」关系', () {
      final rules = [
        FilterRule(
          id: 1,
          targets: const {FilterTarget.reply},
          conditions: [
            cond(FilterField.replyContent, FilterOp.contains, ['广告']),
            cond(FilterField.uid, FilterOp.equals, ['999']),
          ],
        ),
      ];
      expect(engine(rules).decide(target: FilterTarget.reply, subject: reply).isHidden, isFalse);
      expect(
        engine(rules)
            .decide(
              target: FilterTarget.reply,
              subject: const FilterSubject(uid: 999, replyContent: '广告'),
            )
            .isHidden,
        isTrue,
      );
    });

    test('写坏的正则既不隐藏也不抛', () {
      final decision = engine([
        rule(FilterTarget.reply, cond(FilterField.replyContent, FilterOp.matches, ['('])),
      ]).decide(target: FilterTarget.reply, subject: reply);
      expect(decision.isHidden, isFalse);
      expect(FilterRule.isValidPattern('('), isFalse);
      expect(FilterRule.isValidPattern('a.*'), isTrue);
    });
  });

  group('数值与枚举条件', () {
    test('等级支持比较与区间', () {
      bool level(FilterOp op, List<String> values) =>
          engine([rule(FilterTarget.reply, cond(FilterField.level, op, values))])
              .decide(target: FilterTarget.reply, subject: reply)
              .isHidden;
      expect(level(FilterOp.lt, ['4']), isTrue);
      expect(level(FilterOp.gte, ['3']), isTrue);
      expect(level(FilterOp.between, ['2', '6']), isTrue);
      expect(level(FilterOp.between, ['4', '6']), isFalse);
    });

    test('UID 位数从 UID 本身推出来', () {
      expect(
        engine([
          rule(FilterTarget.reply, cond(FilterField.uidLength, FilterOp.lt, ['6'])),
        ]).decide(target: FilterTarget.reply, subject: reply).isHidden,
        isTrue,
      );
    });

    test('乱填的边界值不会隐藏任何东西', () {
      expect(
        engine([
          rule(FilterTarget.reply, cond(FilterField.level, FilterOp.lt, ['很高'])),
        ]).decide(target: FilterTarget.reply, subject: reply).isHidden,
        isFalse,
      );
    });

    test('接口没给的字段一律放行', () {
      // 视频列表里没有等级，等级规则不能把视频全藏了。
      expect(
        engine([
          rule(FilterTarget.video, cond(FilterField.level, FilterOp.lt, ['6'])),
        ]).decide(target: FilterTarget.video, subject: video).isHidden,
        isFalse,
      );
    });

    test('认证按接口口径：<0 无、0 个人、1 机构', () {
      bool official(int? type, List<String> values) =>
          engine([
            rule(FilterTarget.reply, cond(FilterField.official, FilterOp.inList, values)),
          ]).decide(
            target: FilterTarget.reply,
            subject: FilterSubject(uid: 1, officialType: type),
          ).isHidden;
      expect(official(-1, ['-1']), isTrue);
      expect(official(-7, ['-1']), isTrue);
      expect(official(0, ['-1']), isFalse);
      expect(official(0, ['0']), isTrue);
      expect(official(1, ['1']), isTrue);
      expect(official(null, ['-1', '0', '1']), isFalse);
    });

    test('有效大会员看 status，过期号不算', () {
      bool effective(List<String> values, {int? type, int? status}) =>
          engine([
            rule(
              FilterTarget.reply,
              cond(FilterField.vipEffective, FilterOp.equals, values),
            ),
          ]).decide(
            target: FilterTarget.reply,
            subject: FilterSubject(uid: 1, vipType: type, vipStatus: status),
          ).isHidden;
      expect(effective(['1'], type: 2, status: 1), isTrue);
      expect(effective(['1'], type: 2, status: 0), isFalse);
      expect(effective(['0'], type: 2, status: 0), isTrue);
      expect(effective(['1'], type: 0, status: 0), isFalse);
      expect(effective(['0'], type: null, status: null), isFalse);
    });
  });

  group('判定顺序', () {
    final blacklist = rule(
      FilterTarget.reply,
      cond(FilterField.nickname, FilterOp.contains, ['Test']),
    );
    final explicit = rule(
      FilterTarget.reply,
      cond(FilterField.uid, FilterOp.equals, ['12345']),
      id: 2,
      source: FilterSource.local,
    );

    test('例外名单高于一切，包括明确隐藏与 B 站黑名单', () {
      final decision = engine(
        [blacklist, explicit],
        exempts: const [FilterExempt(id: 9, uid: 12345)],
      ).decide(target: FilterTarget.reply, subject: reply, blacklisted: true);
      expect(decision.isHidden, isFalse);
    });

    test('条目里明确的隐藏优先于 B 站黑名单，用的是那条规则的动作', () {
      final decision = engine([
        rule(
          FilterTarget.reply,
          cond(FilterField.uid, FilterOp.equals, ['12345']),
          source: FilterSource.local,
          action: FilterAction.placeholder,
        ),
      ]).decide(target: FilterTarget.reply, subject: reply, blacklisted: true);
      expect(decision.source, FilterSource.local);
      expect(decision.action, FilterAction.placeholder);
    });

    test('B 站黑名单高于通用规则', () {
      final decision = engine([
        rule(
          FilterTarget.reply,
          cond(FilterField.nickname, FilterOp.contains, ['Test']),
          action: FilterAction.placeholder,
        ),
      ]).decide(target: FilterTarget.reply, subject: reply, blacklisted: true);
      expect(decision.source, FilterSource.official);
      expect(decision.action, FilterAction.collapse);
    });

    test('通用规则高于旧关键词', () {
      final decision = engine([blacklist]).decide(
        target: FilterTarget.reply,
        subject: reply,
        legacyHit: true,
      );
      expect(decision.source, FilterSource.manual);
    });

    test('只有旧关键词命中时说明写得很清楚', () {
      final decision = engine([]).decide(
        target: FilterTarget.reply,
        subject: reply,
        legacyHit: true,
      );
      expect(decision.isHidden, isTrue);
      expect(decision.source, FilterSource.legacy);
      expect(decision.reason, contains('旧关键词'));
    });

    test('停用与别的范围都不参与', () {
      final off = rule(
        FilterTarget.reply,
        cond(FilterField.nickname, FilterOp.contains, ['Test']),
        enabled: false,
      );
      expect(engine([off]).decide(target: FilterTarget.reply, subject: reply).isHidden, isFalse);
      expect(engine([off]).hasActiveRules, isFalse);
      expect(
        engine([blacklist]).decide(target: FilterTarget.dyn, subject: reply).isHidden,
        isFalse,
      );
    });
  });

  group('显示动作', () {
    final any = rule(
      FilterTarget.video,
      cond(FilterField.videoTitle, FilterOp.contains, ['广告']),
    );

    test('评论默认折叠，其它默认占位', () {
      expect(FilterTarget.reply.defaultAction, FilterAction.collapse);
      expect(FilterTarget.video.defaultAction, FilterAction.placeholder);
      expect(
        engine([
          FilterRule(
            id: 1,
            targets: const {FilterTarget.dyn},
            conditions: [cond(FilterField.dynText, FilterOp.contains, ['广告'])],
          ),
        ]).decide(target: FilterTarget.dyn, subject: const FilterSubject(dynText: '广告')).action,
        FilterAction.placeholder,
      );
    });

    test('范围设置覆盖默认', () {
      expect(
        engine([any], display: {FilterTarget.video: FilterAction.remove})
            .decide(target: FilterTarget.video, subject: video)
            .shouldRemove,
        isTrue,
      );
    });

    test('单条规则的动作覆盖范围设置', () {
      final one = rule(
        FilterTarget.video,
        cond(FilterField.videoTitle, FilterOp.contains, ['广告']),
        action: FilterAction.collapse,
      );
      expect(
        engine([one], display: {FilterTarget.video: FilterAction.remove})
            .decide(target: FilterTarget.video, subject: video)
            .action,
        FilterAction.collapse,
      );
    });
  });

  group('编辑期的校验', () {
    test('等级只有 Lv0~Lv6', () {
      expect(cond(FilterField.level, FilterOp.lt, ['7']).problem(), isNotNull);
      expect(cond(FilterField.level, FilterOp.lt, ['3']).problem(), isNull);
    });

    test('UID 位数只做合理的位数校验', () {
      expect(cond(FilterField.uidLength, FilterOp.lt, ['6']).describe(), 'UID 位数 小于 6');
      expect(cond(FilterField.uidLength, FilterOp.gt, ['0']).problem(), isNotNull);
      expect(cond(FilterField.uidLength, FilterOp.gt, ['20']).problem(), isNotNull);
      expect(cond(FilterField.uidLength, FilterOp.gt, ['19']).problem(), isNull);
      expect(cond(FilterField.uidLength, FilterOp.equals, ['9']).problem(), isNull);
    });

    test('区间要两个数且前小后大', () {
      expect(cond(FilterField.level, FilterOp.between, ['3']).problem(), isNotNull);
      expect(cond(FilterField.level, FilterOp.between, ['5', '2']).problem(), isNotNull);
      expect(cond(FilterField.level, FilterOp.between, ['2', '5']).problem(), isNull);
    });

    test('认证只能选接口里有的编号', () {
      expect(cond(FilterField.official, FilterOp.inList, ['9']).problem(), isNotNull);
      expect(cond(FilterField.official, FilterOp.inList, ['-1', '1']).problem(), isNull);
    });

    test('该范围取不到的字段不给保存', () {
      final bad = rule(FilterTarget.video, cond(FilterField.level, FilterOp.lt, ['2']));
      expect(bad.problem(), contains('等级'));
      expect(bad.supportedTargets(), isEmpty);
    });

    test('视频列表里没有正文之外的评论字段', () {
      expect(FilterField.replyContent.availableFor(FilterTarget.video), isFalse);
      expect(FilterField.videoZone.availableFor(FilterTarget.video), isTrue);
      expect(FilterField.dynOrigText.availableFor(FilterTarget.dyn), isTrue);
    });
  });

  group('存储与导入', () {
    test('一条规则能原样存回去', () {
      final config = FilterConfig(
        rules: [
          FilterRule(
            id: 1,
            targets: const {FilterTarget.reply, FilterTarget.dyn},
            conditions: [
              cond(FilterField.replyContent, FilterOp.contains, ['剧透']),
              cond(FilterField.uid, FilterOp.between, ['1', '9999']),
            ],
            action: FilterAction.remove,
          ),
        ],
        exempts: const [FilterExempt(id: 2, uid: 42, name: '好友')],
        display: const {FilterTarget.video: FilterAction.remove},
      );
      final decoded = FilterConfig.fromJson(jsonDecode(jsonEncode(config)) as Map);
      expect(decoded.version, FilterConfig.currentVersion);
      expect(decoded.rules.single.targets, {FilterTarget.reply, FilterTarget.dyn});
      expect(decoded.rules.single.conditions, hasLength(2));
      expect(decoded.rules.single.action, FilterAction.remove);
      expect(decoded.exempts.single.name, '好友');
      expect(decoded.actionFor(FilterTarget.video), FilterAction.remove);
      expect(decoded.actionFor(FilterTarget.reply), FilterAction.collapse);
    });

    test('认不出的字段丢掉并留下说明', () {
      final decoded = FilterConfig.fromJson({
        'version': 2,
        'rules': [
          {'targets': ['reply'], 'conditions': [{'field': 'nope', 'op': 'contains', 'values': ['x']}]},
          {'targets': ['nope'], 'conditions': [{'field': 'videoTitle', 'op': 'contains', 'values': ['x']}]},
          {'targets': ['reply'], 'conditions': [{'field': 'replyContent', 'op': 'contains', 'values': ['']}]},
          {'targets': ['reply'], 'conditions': [{'field': 'nickname', 'op': 'contains', 'values': ['ok']}]},
        ],
        'manualExceptions': [
          {'uid': 0},
          {'uid': '77', 'name': '回来再改昵称也拦不住'},
        ],
      });
      expect(decoded.rules.map((e) => e.summary), ['昵称 包含 ok']);
      expect(decoded.exempts.map((e) => e.uid), [77]);
      expect(decoded.warnings, isNotEmpty);
    });

    test('坏了的存储按没有规则处理，不崩', () {
      expect(FilterConfig.tryDecode('{ not json').isEmpty, isTrue);
      expect(FilterConfig.tryDecode('').isEmpty, isTrue);
      expect(FilterConfig.tryDecode('[]').isEmpty, isTrue);
      expect(FilterConfig.tryDecode('{"rules":"nope"}').isEmpty, isTrue);
      expect(FilterConfig.tryDecode('{"rules":[]}').isEmpty, isTrue);
      expect(FilterConfig.tryDecode('{"rules":"nope"}').warnings, isNotEmpty);
    });
  });

  group('摘要与试算', () {
    test('每条规则一句话说清', () {
      expect(
        rule(FilterTarget.reply, cond(FilterField.nickname, FilterOp.contains, ['广告'])).summary,
        '昵称 包含 广告',
      );
      expect(
        cond(FilterField.level, FilterOp.lt, ['2']).describe(),
        '用户等级 小于 2',
      );
      expect(
        cond(FilterField.videoTitle, FilterOp.matches, [r'试.*']).describe(),
        '视频标题 正则匹配 /试.*/',
      );
      expect(
        cond(FilterField.official, FilterOp.inList, ['1']).describe(),
        '认证状态 属于 机构认证',
      );
      expect(
        FilterRule(
          id: 1,
          targets: const {FilterTarget.reply},
          conditions: [
            cond(FilterField.replyContent, FilterOp.contains, ['剧透']),
            cond(FilterField.uid, FilterOp.notEquals, ['1']),
          ],
        ).summary,
        '评论正文 包含 剧透 且 UID 不等于 1',
      );
      expect(rule(FilterTarget.reply, cond(FilterField.level, FilterOp.lt, ['2'])).actionLabel, '跟随范围默认');
    });

    test('编辑页的试算按范围分别给结论', () {
      final one = engine([
        rule(FilterTarget.reply, cond(FilterField.nickname, FilterOp.contains, ['广告'])),
      ]);
      expect(one.preview(target: FilterTarget.reply, sample: '广告').isHidden, isTrue);
      expect(one.preview(target: FilterTarget.video, sample: '广告').isHidden, isFalse);
      expect(
        engine([rule(FilterTarget.video, cond(FilterField.uid, FilterOp.equals, ['123']))])
            .preview(target: FilterTarget.video, sample: '123')
            .isHidden,
        isTrue,
      );
    });
  });
}

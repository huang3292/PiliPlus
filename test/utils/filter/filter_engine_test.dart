import 'dart:convert';

import 'package:PiliPlus/utils/filter/filter_engine.dart';
import 'package:PiliPlus/utils/filter/filter_rule.dart';
import 'package:flutter_test/flutter_test.dart';

FilterRule rule(
  FilterField field,
  FilterMatch match,
  String value, {
  Set<FilterTarget>? targets,
  bool enabled = true,
  bool caseSensitive = false,
  int id = 1,
}) {
  return FilterRule(
    id: id,
    targets: targets ?? {FilterTarget.reply},
    field: field,
    match: match,
    value: value,
    enabled: enabled,
    caseSensitive: caseSensitive,
  );
}

FilterEngine engine(List<FilterRule> rules, [List<FilterExempt> exempts = const []]) {
  return FilterEngine(FilterConfig(rules: rules, exempts: exempts));
}

void main() {
  const text = FilterSubject(content: '这个广告真长', nickname: 'TestUser');

  group('text fields', () {
    test('contains ignores case by default', () {
      final result = engine([rule(FilterField.nickname, FilterMatch.contains, 'testuser')])
          .match(FilterTarget.reply, text);
      expect(result.isBlocked, isTrue);
    });

    test('contains can be case sensitive', () {
      expect(
        engine([
          rule(FilterField.nickname, FilterMatch.contains, 'testuser', caseSensitive: true),
        ]).match(FilterTarget.reply, text).isBlocked,
        isFalse,
      );
    });

    test('startsWith and endsWith', () {
      expect(
        engine([rule(FilterField.content, FilterMatch.startsWith, '这个')])
            .match(FilterTarget.reply, text).isBlocked,
        isTrue,
      );
      expect(
        engine([rule(FilterField.content, FilterMatch.endsWith, '短')])
            .match(FilterTarget.reply, text).isBlocked,
        isFalse,
      );
    });

    test('the except word rescues a plain match', () {
      final result = engine([
        FilterRule(
          id: 1,
          targets: {FilterTarget.reply},
          field: FilterField.content,
          match: FilterMatch.contains,
          value: '广告',
          exceptValue: '真长',
        ),
      ]).match(FilterTarget.reply, text);
      expect(result.isBlocked, isFalse);
    });

    test('the except word also rescues a regex match', () {
      FilterRule one(String? except) => FilterRule(
        id: 1,
        targets: {FilterTarget.reply},
        field: FilterField.content,
        match: FilterMatch.regex,
        value: r'广告.+',
        exceptValue: except,
      );
      expect(engine([one('免广告')]).match(FilterTarget.reply, text).isBlocked, isTrue);
      expect(engine([one('真长')]).match(FilterTarget.reply, text).isBlocked, isFalse);
      expect(engine([one(null)]).match(FilterTarget.reply, text).isBlocked, isTrue);
    });

    test('invalid regex never blocks and never throws', () {
      final result = engine([rule(FilterField.content, FilterMatch.regex, r'(')])
          .match(FilterTarget.reply, text);
      expect(result.isBlocked, isFalse);
      expect(FilterEngine.isValidPattern(r'('), isFalse);
      expect(FilterEngine.isValidPattern('a.*'), isTrue);
    });

    test('missing subject field is skipped', () {
      expect(
        engine([rule(FilterField.nickname, FilterMatch.contains, 'any')])
            .match(FilterTarget.reply, const FilterSubject(content: 'x'))
            .isBlocked,
        isFalse,
      );
    });
  });

  group('numeric fields', () {
    const author = FilterSubject(level: 3, uid: 12345, officialType: 0, isVip: false);

    test('level atLeast and lessThan', () {
      expect(
        engine([rule(FilterField.level, FilterMatch.atLeast, '2')])
            .match(FilterTarget.reply, author).isBlocked,
        isTrue,
      );
      expect(
        engine([rule(FilterField.level, FilterMatch.lessThan, '3')])
            .match(FilterTarget.reply, author).isBlocked,
        isFalse,
      );
    });

    test('uid length is derived from the uid itself', () {
      expect(
        engine([rule(FilterField.uidLength, FilterMatch.lessThan, '6')])
            .match(FilterTarget.reply, author).isBlocked,
        isTrue,
      );
      expect(
        engine([rule(FilterField.uidLength, FilterMatch.atLeast, '6')])
            .match(FilterTarget.reply, author).isBlocked,
        isFalse,
      );
    });

    test('official and vip compare by label value', () {
      expect(
        engine([rule(FilterField.official, FilterMatch.equals, '0')])
            .match(FilterTarget.reply, author).isBlocked,
        isTrue,
      );
      expect(
        engine([rule(FilterField.vip, FilterMatch.equals, '0')])
            .match(FilterTarget.reply, author).isBlocked,
        isTrue,
      );
    });

    test('a garbage bound disables the rule', () {
      expect(
        engine([rule(FilterField.level, FilterMatch.atLeast, '很高')])
            .match(FilterTarget.reply, author).isBlocked,
        isFalse,
      );
    });
  });

  group('remote stats stay lazy', () {
    final fansRule = [rule(FilterField.fans, FilterMatch.lessThan, '10')];

    test('unknown fans never blocks', () {
      final result = engine(fansRule).match(FilterTarget.reply, const FilterSubject(content: 'x'));
      expect(result.isBlocked, isFalse);
      expect(result.needsUserStats, isTrue);
    });

    test('fans are only requested when a live rule needs them', () {
      expect(engine(fansRule).needsUserStats(FilterTarget.reply), isTrue);
      expect(engine(fansRule).needsUserStats(FilterTarget.video), isFalse);
      expect(
        engine([rule(FilterField.level, FilterMatch.atLeast, '1')]).needsUserStats(FilterTarget.reply),
        isFalse,
      );
      expect(
        engine([rule(FilterField.fans, FilterMatch.lessThan, '10', enabled: false)])
            .needsUserStats(FilterTarget.reply),
        isFalse,
      );
    });

    test('a level rule still wins while fans stay pending', () {
      final result = engine([
        rule(FilterField.fans, FilterMatch.lessThan, '10'),
        rule(FilterField.level, FilterMatch.atLeast, '5', id: 2),
      ]).match(FilterTarget.reply, const FilterSubject(level: 6));
      expect(result.isBlocked, isTrue);
    });

    test('fans block once supplied', () {
      expect(
        engine(fansRule).match(FilterTarget.reply, const FilterSubject(fans: 3)).isBlocked,
        isTrue,
      );
      expect(
        engine(fansRule).match(FilterTarget.reply, const FilterSubject(fans: 30)).isBlocked,
        isFalse,
      );
    });
  });

  group('scope and exemptions', () {
    final uidRule = rule(FilterField.uid, FilterMatch.equals, '12345', targets: {FilterTarget.reply});
    const subject = FilterSubject(uid: 12345, content: 'x');

    test('a rule only fires in its own scope', () {
      expect(engine([uidRule]).match(FilterTarget.reply, subject).isBlocked, isTrue);
      expect(engine([uidRule]).match(FilterTarget.video, subject).isBlocked, isFalse);
    });

    test('a mixed scope rule covers both', () {
      final mixed = rule(
        FilterField.uid,
        FilterMatch.equals,
        '12345',
        targets: {FilterTarget.reply, FilterTarget.video},
      );
      expect(engine([mixed]).match(FilterTarget.reply, subject).isBlocked, isTrue);
      expect(engine([mixed]).match(FilterTarget.video, subject).isBlocked, isTrue);
    });

    test('exempts override every rule', () {
      final result = engine(
        [uidRule],
        [const FilterExempt(id: 9, field: FilterField.uid, value: '12345')],
      ).match(FilterTarget.reply, subject);
      expect(result.isBlocked, isFalse);
      expect(result.exempted, isTrue);
    });

    test('a disabled exempt does not protect', () {
      expect(
        engine(
          [uidRule],
          [const FilterExempt(id: 9, field: FilterField.uid, value: '12345', enabled: false)],
        ).match(FilterTarget.reply, subject).isBlocked,
        isTrue,
      );
    });

    test('a blocked result reports which rule fired', () {
      final fired = engine([uidRule]).match(FilterTarget.reply, subject).rule;
      expect(fired, isNotNull);
      expect(fired!.field, FilterField.uid);
    });
  });

  group('persistence', () {
    test('config survives a json round trip', () {
      final config = FilterConfig(
        rules: [
          FilterRule(
            id: 1,
            targets: {FilterTarget.reply, FilterTarget.dyn},
            field: FilterField.content,
            match: FilterMatch.contains,
            value: '剧透',
            exceptValue: '剧透警告',
          ),
          rule(FilterField.level, FilterMatch.lessThan, '2', id: 2),
        ],
        exempts: [
          const FilterExempt(id: 3, field: FilterField.nickname, value: '好友'),
        ],
      );
      final decoded = FilterConfig.fromJson(jsonDecode(jsonEncode(config)) as Map);
      expect(decoded.rules, hasLength(2));
      expect(decoded.rules[0].targets, {FilterTarget.reply, FilterTarget.dyn});
      expect(decoded.rules[0].exceptValue, '剧透警告');
      expect(decoded.rules[1].field, FilterField.level);
      expect(decoded.exempts.single.value, '好友');
    });

    test('unknown codes and empty values are dropped, not fatal', () {
      final decoded = FilterConfig.fromJson({
        'version': 1,
        'rules': [
          {'targets': ['reply'], 'field': 'nope', 'match': 'contains', 'value': 'x'},
          {'targets': ['nope'], 'field': 'content', 'match': 'contains', 'value': 'x'},
          {'targets': ['reply'], 'field': 'content', 'match': 'contains', 'value': ''},
          {'targets': ['reply'], 'field': 'fans', 'match': 'contains', 'value': '10'},
          {'targets': ['reply'], 'field': 'content', 'match': 'contains', 'value': 'ok'},
        ],
      });
      expect(decoded.rules.map((e) => e.value), ['ok']);
    });

    test('broken storage reads as no rules', () {
      expect(FilterConfig.tryDecode('{ not json').isEmpty, isTrue);
      expect(FilterConfig.tryDecode('').isEmpty, isTrue);
      expect(FilterConfig.tryDecode('   ').isEmpty, isTrue);
      expect(FilterConfig.tryDecode('{"rules":[]}').isEmpty, isTrue);
      expect(FilterConfig.tryDecode('[]').isEmpty, isTrue);
      expect(FilterConfig.tryDecode('{"rules":"nope"}').isEmpty, isTrue);
    });
  });

  group('summary', () {
    test('describes each rule kind in one line', () {
      expect(
        rule(FilterField.nickname, FilterMatch.contains, '广告').summary,
        '昵称 包含 广告',
      );
      expect(
        rule(FilterField.level, FilterMatch.lessThan, '2').summary,
        '用户等级 小于 2',
      );
      expect(
        rule(FilterField.content, FilterMatch.regex, r'试.*').summary,
        '正文 正则表达式 /试.*/',
      );
      expect(
        rule(FilterField.official, FilterMatch.equals, '2').summary,
        '认证状态 机构认证',
      );
    });
  });
}

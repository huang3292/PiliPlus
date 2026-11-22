import 'package:PiliPlus/utils/filter/filter_rule.dart';
import 'package:PiliPlus/utils/filter/legacy_ban_word.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('split', () {
    test('splits top-level alternation', () {
      expect(LegacyBanWord.split('尝试|测试'), ['尝试', '测试']);
    });

    test('keeps alternation inside a group', () {
      expect(LegacyBanWord.split('(尝试|测试)'), ['(尝试|测试)']);
    });

    test('keeps alternation inside a character class', () {
      expect(LegacyBanWord.split('[尝试|测试]'), ['[尝试|测试]']);
    });

    test('keeps an escaped separator inside one fragment', () {
      expect(LegacyBanWord.split(r'a\|b|c'), [r'a\|b', 'c']);
    });

    test('drops empty fragments left by stray separators', () {
      expect(LegacyBanWord.split('|测试'), ['测试']);
      expect(LegacyBanWord.split('测试|'), ['测试']);
      expect(LegacyBanWord.split('尝试||测试'), ['尝试', '测试']);
    });

    test('returns nothing for blank input', () {
      expect(LegacyBanWord.split(''), isEmpty);
      expect(LegacyBanWord.split('   '), isEmpty);
    });
  });

  group('toRule', () {
    FilterRule one(String fragment) =>
        LegacyBanWord.toRule(fragment, {FilterTarget.reply}, 1);

    test('plain words become contains rules', () {
      final rule = one('测试');
      expect(rule.match, FilterMatch.contains);
      expect(rule.value, '测试');
      expect(rule.field, FilterField.content);
    });

    test('fragments with metacharacters stay regex', () {
      final rule = one(r'试.*\d');
      expect(rule.match, FilterMatch.regex);
      expect(rule.value, r'试.*\d');
    });

    test('fully escaped fragments collapse back to plain text', () {
      final rule = one(r'a\.b');
      expect(rule.match, FilterMatch.contains);
      expect(rule.value, 'a.b');
    });

    test('a character class stays a regex rule', () {
      final migrated = LegacyBanWord.split('[尝试|测试]').map((fragment) {
        return LegacyBanWord.toRule(fragment, {FilterTarget.reply}, 1);
      }).single;
      expect(migrated.match, FilterMatch.regex);
      expect(migrated.value, '[尝试|测试]');
    });
  });

  group('join', () {
    FilterRule rule(FilterMatch match, String value) => FilterRule(
      id: 1,
      targets: {FilterTarget.reply},
      field: FilterField.content,
      match: match,
      value: value,
    );

    test('escapes literals so dots match themselves', () {
      expect(LegacyBanWord.join([rule(FilterMatch.contains, 'a.b')]), r'a\.b');
    });

    test('anchors startsWith and endsWith', () {
      expect(
        LegacyBanWord.join([rule(FilterMatch.startsWith, '开头')]),
        '^开头',
      );
      expect(LegacyBanWord.join([rule(FilterMatch.endsWith, '结尾')]), r'结尾$');
    });

    test('passes regex rules through untouched', () {
      expect(LegacyBanWord.join([rule(FilterMatch.regex, r'试.*')]), r'试.*');
    });

    test('skips rules an affirmative pattern cannot express', () {
      expect(
        LegacyBanWord.join([
          FilterRule(
            id: 1,
            targets: {FilterTarget.reply},
            field: FilterField.content,
            match: FilterMatch.contains,
            value: '广告',
            exceptValue: '免广告',
          ),
        ]),
        isEmpty,
      );
      expect(LegacyBanWord.join([rule(FilterMatch.regex, r'\d+岁')]), r'\d+岁');
    });

    test('keeps matching behavior after a round trip', () {
      final original = [
        rule(FilterMatch.contains, 'a.b'),
        rule(FilterMatch.contains, '普通词'),
        rule(FilterMatch.regex, r'\d+岁'),
      ];
      final pattern = LegacyBanWord.join(original);
      final restored = LegacyBanWord.split(pattern).map((fragment) {
        final migrated = LegacyBanWord.toRule(fragment, {FilterTarget.reply}, 1);
        return RegExp(migrated.value, caseSensitive: false);
      }).toList();

      final samples = ['a.b', '普通词', '他才18岁啊', '无关内容'];
      for (final sample in samples) {
        expect(
          restored.any((e) => e.hasMatch(sample)),
          RegExp(pattern, caseSensitive: false).hasMatch(sample),
          reason: 'round trip differs for $sample',
        );
      }
      expect(restored.any((e) => e.hasMatch('无关内容')), isFalse);
    });
  });

  group('migrate', () {
    test('assigns each legacy scope to its own target', () {
      final rules = LegacyBanWord.migrate([
        (FilterTarget.reply, '尝试|测试'),
        (FilterTarget.video, '广告'),
      ]);
      expect(rules, hasLength(3));
      expect(rules[0].targets, {FilterTarget.reply});
      expect(rules[2].targets, {FilterTarget.video});
      expect(rules.map((e) => e.id).toSet(), hasLength(3));
    });

    test('merges several legacy patterns into one target', () {
      final rules = LegacyBanWord.migrate([
        (FilterTarget.video, '推荐词'),
        (FilterTarget.video, '分区词'),
      ]);
      expect(rules.map((e) => e.value), ['推荐词', '分区词']);
      for (final item in rules) {
        expect(item.targets, {FilterTarget.video});
      }
    });
  });
}

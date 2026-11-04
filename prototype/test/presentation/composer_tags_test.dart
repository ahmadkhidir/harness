import 'package:flutter_test/flutter_test.dart';
import 'package:harness/presentation/utils/composer_tags.dart';

void main() {
  group('composer tag helpers', () {
    test('opens the skill picker only for a leading slash', () {
      expect(shouldOpenSkillPicker('', '/'), isTrue);
      expect(shouldOpenSkillPicker('hello', 'hello/'), isFalse);
      expect(shouldOpenSkillPicker('/', '/g'), isFalse);
    });

    test('detects a typed @ outside quotes', () {
      expect(fileTriggerIndex('', '@', 1), 0);
      expect(fileTriggerIndex('hello ', 'hello @', 7), 6);
    });

    test('ignores @ inside double, single, and backtick quotes', () {
      expect(fileTriggerIndex('"hello ', '"hello @', 8), isNull);
      expect(fileTriggerIndex("'hello ", "'hello @", 8), isNull);
      expect(fileTriggerIndex('`hello ', '`hello @', 8), isNull);
    });

    test('respects escaped quotes', () {
      // The quote before @ is escaped, so the @ is not inside a span.
      const previous = r'\"hello ';
      const next = r'\"hello @';
      expect(fileTriggerIndex(previous, next, next.length), isNotNull);
    });

    test('ignores pasted text and non-@ inserts', () {
      expect(fileTriggerIndex('', 'hi', 2), isNull);
      expect(fileTriggerIndex('', '@@', 2), isNull);
    });

    test('inserts a skill tag with trailing space', () {
      expect(insertSkillTag('my-skill'), '/my-skill ');
    });

    test('replaces the @ token and keeps trailing text', () {
      final result = insertFileTag(
        text: 'read @ and summarize',
        triggerIndex: 5,
        cursor: 6,
        path: 'primary/notes.md',
      );

      expect(result, 'read @primary/notes.md and summarize');
    });
  });
}

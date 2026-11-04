/// Pure helpers for `/` skill and `@` storage tagging in the chat composer.
library;

/// True when the user has just typed `/` as the first composer character.
bool shouldOpenSkillPicker(String previous, String next) {
  return next == '/' && !previous.startsWith('/');
}

/// Returns the index of an `@` typed at [cursor] that should open the picker.
///
/// Returns null when the edit is not a single-character insert, when the
/// inserted character is not `@`, or when the cursor sits inside a quoted
/// region (`"..."`, `'...'`, or `` `...` ``).
int? fileTriggerIndex(String previous, String next, int cursor) {
  if (cursor <= 0 || cursor > next.length) return null;
  if (next.length != previous.length + 1) return null;
  if (next[cursor - 1] != '@') return null;
  return isInsideQuotes(next, cursor - 1) ? null : cursor - 1;
}

/// Checks whether [index] falls inside an unclosed quoted or code span.
bool isInsideQuotes(String text, int index) {
  for (final quote in const ['"', "'", '`']) {
    var count = 0;
    for (var i = 0; i < index && i < text.length; i++) {
      if (text[i] == r'\') {
        i++;
        continue;
      }
      if (text[i] == quote) count++;
    }
    if (count.isOdd) return true;
  }
  return false;
}

/// Builds the composer text after choosing a skill.
String insertSkillTag(String skillName) => '/$skillName ';

/// Replaces the `@` token ending at [cursor] with `@path `.
String insertFileTag({
  required String text,
  required int triggerIndex,
  required int cursor,
  required String path,
}) {
  final safeTrigger = triggerIndex.clamp(0, text.length);
  final safeCursor = cursor.clamp(safeTrigger, text.length);
  final before = text.substring(0, safeTrigger);
  final after = text.substring(safeCursor).replaceFirst(RegExp(r'^\s+'), '');
  return after.isEmpty ? '$before@$path ' : '$before@$path $after';
}

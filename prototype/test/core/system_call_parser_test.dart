import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/engine/system_call_parser.dart';

void main() {
  group('SystemCallParser - XML Extraction & Zero Thinking Leakage', () {
    test('extracts single system call and isolates internal reasoning', () {
      const raw = '''
Thinking about which file to read.
I should inspect notes.txt first.
<system_call>
{"command": "read_file", "parameters": {"path": "workspace/notes.txt"}}
</system_call>
Done thinking.
''';

      final output = SystemCallParser.parse(raw);
      expect(output.hasSystemCalls, isTrue);
      expect(output.systemCalls.length, 1);
      expect(output.systemCalls.first.command, 'read_file');
      expect(output.systemCalls.first.parameters['path'], 'workspace/notes.txt');

      // Scratchpad text must contain the monologue
      expect(output.scratchpadText.contains('Thinking about which file to read'), isTrue);
      expect(output.scratchpadText.contains('Done thinking'), isTrue);

      // No explicit delivery has occurred yet
      expect(output.hasExplicitDelivery, isFalse);
      expect(output.explicitTextMessage, isNull);
    });

    test('extracts multiple parallel system calls', () {
      const raw = '''
<system_call>
{"command": "read_file", "parameters": {"path": "file1.txt"}}
</system_call>
<system_call>
{"command": "web_search", "parameters": {"query": "Flutter agent"}}
</system_call>
''';

      final output = SystemCallParser.parse(raw);
      expect(output.systemCalls.length, 2);
      expect(output.systemCalls[0].command, 'read_file');
      expect(output.systemCalls[1].command, 'web_search');
      expect(output.hasExplicitDelivery, isFalse);
    });

    test('extracts explicit send_message delivery command', () {
      const raw = '''
Internal scratchpad note: user requested summary.
<system_call>
{"command": "send_message", "parameters": {"text": "Here is the summary of the project."}}
</system_call>
''';

      final output = SystemCallParser.parse(raw);
      expect(output.hasSystemCalls, isFalse);
      expect(output.hasExplicitDelivery, isTrue);
      expect(output.explicitTextMessage, 'Here is the summary of the project.');
      expect(output.scratchpadText.contains('Internal scratchpad note'), isTrue);
    });

    test('extracts explicit send_a2ui delivery command with companion text', () {
      const raw = '''
<system_call>
{
  "command": "send_a2ui",
  "parameters": {
    "text": "Card mounted:",
    "messages": [
      {
        "version": "1.0",
        "createSurface": {"surfaceId": "card_1", "catalogId": "basic/v1"}
      }
    ]
  }
}
</system_call>
''';

      final output = SystemCallParser.parse(raw);
      expect(output.hasSystemCalls, isFalse);
      expect(output.hasExplicitDelivery, isTrue);
      expect(output.explicitTextMessage, 'Card mounted:');
      expect(output.explicitA2UIPayload, isNotNull);
      expect(output.explicitA2UIPayload?['messages'], isNotEmpty);
    });

    test('falls back to text delivery when no XML tags exist', () {
      const raw = 'Hello! How can I assist you with your project today?';
      final output = SystemCallParser.parse(raw);

      expect(output.hasSystemCalls, isFalse);
      expect(output.hasExplicitDelivery, isTrue);
      expect(output.explicitTextMessage, raw);
      expect(output.scratchpadText, isEmpty);
    });

    test('captures malformed JSON inside system_call tags safely', () {
      const raw = '''
<system_call>
{ invalid json here: missing quotes }
</system_call>
''';

      final output = SystemCallParser.parse(raw);
      expect(output.systemCalls.length, 1);
      expect(output.systemCalls.first.command, 'malformed_json_error');
    });

    test('extracts explicit send_message from unclosed <system_call> tag without closing tag', () {
      const raw = '<system_call>{"command": "send_message", "parameters": {"text": "### Scene 1: The Golden Key"}}';
      final output = SystemCallParser.parse(raw);

      expect(output.hasExplicitDelivery, isTrue);
      expect(output.explicitTextMessage, '### Scene 1: The Golden Key');
      expect(output.hasSystemCalls, isFalse);
      expect(output.explicitTextMessage?.contains('<system_call>'), isFalse);
    });

    test('recovers send_message with unclosed JSON string and braces without closing tag', () {
      const raw = '<system_call>{"command": "send_message", "parameters": {"text": "### Scene 1: The Gold...';
      final output = SystemCallParser.parse(raw);

      expect(output.hasExplicitDelivery, isTrue);
      expect(output.explicitTextMessage, startsWith('### Scene 1: The Gold'));
      expect(output.hasSystemCalls, isFalse);
      expect(output.explicitTextMessage?.contains('<system_call>'), isFalse);
    });

    test('extracts tool call from unclosed <system_call> tag without closing tag', () {
      const raw = '<system_call>{"command": "load_skill", "parameters": {"skill_name": "story_writer"}}';
      final output = SystemCallParser.parse(raw);

      expect(output.hasSystemCalls, isTrue);
      expect(output.systemCalls.length, 1);
      expect(output.systemCalls.first.command, 'load_skill');
      expect(output.systemCalls.first.parameters['skill_name'], 'story_writer');
      expect(output.hasExplicitDelivery, isFalse);
    });

    test('recovers tool call with unclosed JSON brackets from unclosed <system_call>', () {
      const raw = '<system_call>{"command": "load_skill", "parameters": {"skill_name": "story_writer"';
      final output = SystemCallParser.parse(raw);

      expect(output.hasSystemCalls, isTrue);
      expect(output.systemCalls.length, 1);
      expect(output.systemCalls.first.command, 'load_skill');
      expect(output.systemCalls.first.parameters['skill_name'], 'story_writer');
    });

    test('prevents raw <system_call> from leaking into fallback explicit text', () {
      const raw = '<system_call>gibberish: [[[ not json at all';
      final output = SystemCallParser.parse(raw);

      // Must NOT leak <system_call> into user text
      expect(output.explicitTextMessage, isNull);
      expect(output.hasSystemCalls, isTrue);
      expect(output.systemCalls.first.command, 'malformed_json_error');
    });

    test('strips markdown code fences (```json and ```xml) inside system_call block', () {
      const raw = '''
<system_call>
```json
{
  "command": "send_a2ui",
  "parameters": {
    "text": "Card:",
    "messages": [
      {
        "version": "1.0",
        "createSurface": {"surfaceId": "card_fenced", "catalogId": "basic/v1"}
      }
    ]
  }
}
```
</system_call>
''';
      final output = SystemCallParser.parse(raw);
      expect(output.hasSystemCalls, isFalse);
      expect(output.hasExplicitDelivery, isTrue);
      expect(output.explicitA2UIPayload, isNotNull);
      expect(output.explicitTextMessage, equals('Card:'));
    });

    test('cleans trailing commas before closing braces and brackets in system_call', () {
      const raw = '''
<system_call>
{
  "command": "send_a2ui",
  "parameters": {
    "messages": [
      {
        "version": "1.0",
        "createSurface": {
          "surfaceId": "card_commas",
          "components": [
            {"id": "t1", "component": "Text", "text": "Hello",},
          ],
        },
      },
    ],
  },
}
</system_call>
''';
      final output = SystemCallParser.parse(raw);
      expect(output.hasSystemCalls, isFalse);
      expect(output.hasExplicitDelivery, isTrue);
      expect(output.explicitA2UIPayload, isNotNull);
      expect(output.explicitA2UIPayload?['messages'], isNotEmpty);
    });

    test('reports exact line, column, and visual snippet on genuine syntax errors', () {
      const raw = '''
<system_call>
{
  "command": "load_skill",
  "parameters": {
    broken json without colon
  }
}
</system_call>
''';
      final output = SystemCallParser.parse(raw);
      expect(output.hasSystemCalls, isTrue);
      expect(output.systemCalls.first.command, equals('malformed_json_error'));
      final errorMsg = output.systemCalls.first.parameters['error']?.toString();
      expect(errorMsg, contains('JSON Syntax Error at line'));
      expect(errorMsg, contains('|'));
      expect(errorMsg, contains('^'));
    });

    test('resiliently salvages send_a2ui messages from unclosed or truncated payload', () {
      const raw = '''
<system_call>
{
  "command": "send_a2ui",
  "parameters": {
    "text": "Partial flight card:",
    "messages": [
      {
        "version": "1.0",
        "createSurface": {
          "surfaceId": "flight_card",
          "catalogId": "basic/v1"
        }
      }
''';
      final output = SystemCallParser.parse(raw);
      expect(output.hasExplicitDelivery, isTrue);
      expect(output.explicitA2UIPayload, isNotNull);
      expect(output.explicitTextMessage, equals('Partial flight card:'));
      expect(output.explicitA2UIPayload?['messages'], isNotEmpty);
    });
  });
}


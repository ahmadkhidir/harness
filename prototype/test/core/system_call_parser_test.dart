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
  });
}


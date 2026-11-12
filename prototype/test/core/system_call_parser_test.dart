import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/engine/system_call_parser.dart';

void main() {
  group('SystemCallParser - send_ui_message', () {
    test('extracts a text delivery', () {
      const raw = '''
I will answer directly.
<system_call>
{"command": "send_ui_message", "parameters": {"message": "Here is the summary."}}
</system_call>
''';

      final output = SystemCallParser.parse(raw);
      expect(output.hasExplicitDelivery, isTrue);
      expect(output.explicitTextMessage, 'Here is the summary.');
      expect(output.explicitA2UIPayload, isNull);
      expect(output.scratchpadText, contains('I will answer directly.'));
    });

    test('extracts an A2UI delivery and ignores companion text', () {
      const raw = '''
<system_call>
{
  "command": "send_ui_message",
  "parameters": {
    "message": {
      "a2ui": [
        {"version": "1.0", "createSurface": {"surfaceId": "main", "catalogId": "basic/v1"}}
      ],
      "text": "Here is your card."
    }
  }
}
</system_call>
''';

      final output = SystemCallParser.parse(raw);
      expect(output.hasExplicitDelivery, isTrue);
      expect(output.explicitTextMessage, isNull);
      expect(output.explicitA2UIPayload, isNotNull);
      expect(output.explicitA2UIPayload!['messages'], isA<List>());
      expect((output.explicitA2UIPayload!['messages'] as List).length, 1);
    });

    test('treats an empty message as no explicit delivery', () {
      const raw =
          '<system_call>{"command": "send_ui_message", "parameters": {"message": ""}}</system_call>';
      final output = SystemCallParser.parse(raw);
      expect(output.hasExplicitDelivery, isFalse);
    });

    test('does not treat the old send_message command as delivery', () {
      const raw =
          '<system_call>{"command": "send_message", "parameters": {"text": "Old"}}</system_call>';
      final output = SystemCallParser.parse(raw);
      expect(output.hasExplicitDelivery, isFalse);
    });

    test('recovers an unclosed text delivery', () {
      const raw =
          '<system_call>{"command": "send_ui_message", "parameters": {"message": "### Scene 1: The Gold Key"';
      final output = SystemCallParser.parse(raw);
      expect(output.hasExplicitDelivery, isTrue);
      expect(output.explicitTextMessage, startsWith('### Scene 1: The Gold Key'));
      expect(output.explicitTextMessage, isNot(contains('<system_call>')));
    });
  });

  group('SystemCallParser - tool calls', () {
    test('extracts a normal system call', () {
      const raw = '''
<system_call>
{"command": "read_file", "parameters": {"path": "primary/notes.txt"}}
</system_call>
''';

      final output = SystemCallParser.parse(raw);
      expect(output.hasSystemCalls, isTrue);
      expect(output.systemCalls.single.command, 'read_file');
      expect(output.systemCalls.single.parameters['path'], 'primary/notes.txt');
    });

    test('handles DSML send_ui_message text', () {
      final raw =
          '<\uFF5CDSML\uFF5Ccalls>\n'
          '<\uFF5CDSML\uFF5Cinvoke name="send_ui_message">\n'
          '<\uFF5CDSML\uFF5Cparameter name="message" string="true">'
          'Hello from DeepSeek'
          '</\uFF5CDSML\uFF5Cparameter>\n'
          '</\uFF5CDSML\uFF5Cinvoke>\n'
          '</\uFF5CDSML\uFF5Ccalls>';

      final output = SystemCallParser.parse(raw);
      expect(output.hasExplicitDelivery, isTrue);
      expect(output.explicitTextMessage, 'Hello from DeepSeek');
      expect(output.explicitTextMessage, isNot(contains('DSML')));
    });

    test('handles DSML send_ui_message A2UI object', () {
      final raw =
          '<\uFF5CDSML\uFF5Ccalls>\n'
          '<\uFF5CDSML\uFF5Cinvoke name="send_ui_message">\n'
          '<\uFF5CDSML\uFF5Cparameter name="message" string="false">'
          '{"a2ui":[{"version":"1.0","createSurface":{"surfaceId":"main","catalogId":"basic/v1"}}]}'
          '</\uFF5CDSML\uFF5Cparameter>\n'
          '</\uFF5CDSML\uFF5Cinvoke>\n'
          '</\uFF5CDSML\uFF5Ccalls>';

      final output = SystemCallParser.parse(raw);
      expect(output.hasExplicitDelivery, isTrue);
      expect(output.explicitA2UIPayload, isNotNull);
      expect(output.explicitA2UIPayload!['messages'], isA<List>());
    });

    test('records malformed JSON as a system call error', () {
      const raw = '''
<system_call>
{"command": "read_file", "parameters": {"path": }
</system_call>
''';

      final output = SystemCallParser.parse(raw);
      expect(output.hasSystemCalls, isTrue);
      expect(output.systemCalls.single.command, 'malformed_json_error');
    });
  });

  group('SystemCallParser - bare delivery recovery', () {
    const bareA2UI = '''
{"a2ui": [{"version": "1.0", "createSurface": {"surfaceId": "tictactoe", "catalogId": "basic/v1"}}, {"version": "1.0", "updateDataModel": {"surfaceId": "tictactoe", "path": "/difficulty", "value": "balanced"}}]}
''';

    test('recovers an untagged a2ui object as an A2UI delivery', () {
      final output = SystemCallParser.parse(bareA2UI);
      expect(output.hasSystemCalls, isFalse);
      expect(output.hasExplicitDelivery, isTrue);
      expect(output.explicitTextMessage, isNull);
      expect(output.explicitA2UIPayload, isNotNull);
      expect((output.explicitA2UIPayload!['messages'] as List).length, 2);
    });

    test('recovers an untagged a2ui object inside a markdown fence', () {
      final raw = '```json\n$bareA2UI\n```';
      final output = SystemCallParser.parse(raw);
      expect(output.hasExplicitDelivery, isTrue);
      expect(output.explicitA2UIPayload, isNotNull);
      expect((output.explicitA2UIPayload!['messages'] as List).length, 2);
    });

    test('recovers an untagged send_ui_message envelope', () {
      const raw = '''
{
  "command": "send_ui_message",
  "parameters": {
    "message": {
      "a2ui": [{"version": "1.0", "createSurface": {"surfaceId": "main", "catalogId": "basic/v1"}}]
    }
  }
}
''';

      final output = SystemCallParser.parse(raw);
      expect(output.hasExplicitDelivery, isTrue);
      expect(output.explicitA2UIPayload, isNotNull);
      expect((output.explicitA2UIPayload!['messages'] as List).length, 1);
    });

    test('recovers an untagged message-only text object', () {
      const raw = '{"message": "Here is the summary."}';
      final output = SystemCallParser.parse(raw);
      expect(output.hasExplicitDelivery, isTrue);
      expect(output.explicitTextMessage, 'Here is the summary.');
      expect(output.explicitA2UIPayload, isNull);
    });

    test('leaves an unrelated JSON object as plain text', () {
      const raw = '{"total": 3, "items": ["a", "b"]}';
      final output = SystemCallParser.parse(raw);
      expect(output.hasExplicitDelivery, isTrue);
      expect(output.explicitA2UIPayload, isNull);
      expect(output.explicitTextMessage, raw);
    });

    test('does not recover an empty a2ui list', () {
      const raw = '{"a2ui": []}';
      final output = SystemCallParser.parse(raw);
      expect(output.explicitA2UIPayload, isNull);
      expect(output.explicitTextMessage, raw);
    });
  });
}

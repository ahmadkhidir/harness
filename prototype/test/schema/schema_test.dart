import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/models/models.dart';

void main() {
  group('Schema - Session Model', () {
    test('serializes and deserializes Session correctly', () {
      final now = DateTime.utc(2026, 10, 30, 2, 0, 0);
      final session = Session(
        id: 'sess_1730235400',
        title: 'Document Analysis Task',
        createdAt: now,
        updatedAt: now,
        totalTurns: 4,
        contextSizeBytes: 1204,
        compactionCount: 1,
        lastCompactedAt: now,
      );

      final json = session.toJson();
      expect(json['id'], 'sess_1730235400');
      expect(json['title'], 'Document Analysis Task');
      expect(json['totalTurns'], 4);
      expect(json['contextSizeBytes'], 1204);
      expect(json['compactionCount'], 1);

      final restored = Session.fromJson(json);
      expect(restored, equals(session));
    });

    test('validates title length and non-negative integers', () {
      final now = DateTime.now();
      expect(
        () => Session(
          id: 'sess_1',
          title: 'A' * 129,
          createdAt: now,
          updatedAt: now,
        ),
        throwsArgumentError,
      );

      expect(
        () => Session(
          id: 'sess_1',
          title: 'Valid Title',
          createdAt: now,
          updatedAt: now,
          totalTurns: -1,
        ),
        throwsArgumentError,
      );
    });
  });

  group('Schema - Turn Model', () {
    test('serializes and deserializes text and a2ui turns', () {
      final now = DateTime.utc(2026, 10, 30, 2, 5, 0);
      final turnText = Turn(
        id: 'turn_001',
        sessionId: 'sess_1730235400',
        timestamp: now,
        sender: 'user',
        contentType: 'text',
        text: 'Summarize the document in workspace.',
      );

      final jsonText = turnText.toJson();
      expect(jsonText['sender'], 'user');
      expect(jsonText['contentType'], 'text');
      expect(Turn.fromJson(jsonText), equals(turnText));

      final turnA2UI = Turn(
        id: 'turn_002',
        sessionId: 'sess_1730235400',
        timestamp: now,
        sender: 'agent',
        contentType: 'a2ui',
        a2uiSurfaceId: 'surface_status_01',
        modelUsed: 'gemini-2.0-flash',
        tokenCount: 450,
      );

      final jsonA2UI = turnA2UI.toJson();
      expect(jsonA2UI['sender'], 'agent');
      expect(jsonA2UI['contentType'], 'a2ui');
      expect(jsonA2UI['a2uiSurfaceId'], 'surface_status_01');
      expect(Turn.fromJson(jsonA2UI), equals(turnA2UI));
    });

    test('validates sender and contentType constraints', () {
      final now = DateTime.now();
      expect(
        () => Turn(
          id: 'turn_1',
          sessionId: 'sess_1',
          timestamp: now,
          sender: 'invalid_sender',
          contentType: 'text',
        ),
        throwsArgumentError,
      );

      expect(
        () => Turn(
          id: 'turn_1',
          sessionId: 'sess_1',
          timestamp: now,
          sender: 'agent',
          contentType: 'invalid_content',
        ),
        throwsArgumentError,
      );
    });
  });

  group('Schema - ProviderConfig Model', () {
    test('serializes and validates ProviderConfig', () {
      final config = ProviderConfig(
        id: 'gemini_flash',
        providerType: 'gemini',
        displayName: 'Google Gemini 2.0 Flash',
        modelName: 'gemini-2.0-flash',
        temperature: 0.7,
        maxOutputTokens: 4096,
        isActive: true,
        customHeaders: {'X-Custom-Route': 'fast'},
        extraConfig: {'thinkingBudgetTokens': 1024},
      );

      final json = config.toJson();
      expect(json['id'], 'gemini_flash');
      expect(json['providerType'], 'gemini');
      expect(json['customHeaders']['X-Custom-Route'], 'fast');

      final restored = ProviderConfig.fromJson(json);
      expect(restored, equals(config));
    });

    test('rejects invalid providerType and temperature bounds', () {
      expect(
        () => ProviderConfig(
          id: 'invalid',
          providerType: 'unsupported_provider',
          displayName: 'Test',
          modelName: 'test',
        ),
        throwsArgumentError,
      );

      expect(
        () => ProviderConfig(
          id: 'test',
          providerType: 'openai',
          displayName: 'Test',
          modelName: 'gpt-4o',
          temperature: 2.5,
        ),
        throwsArgumentError,
      );
    });
  });

  group('Schema - CommandDefinition & SystemCall & SystemResponse', () {
    test('CommandDefinition validation and serialization', () {
      final cmd = CommandDefinition(
        command: 'grep',
        description: 'Regex pattern search across files',
        parametersSchema: {
          'type': 'object',
          'properties': {
            'pattern': {'type': 'string'},
          },
          'required': ['pattern'],
        },
      );

      final json = cmd.toJson();
      expect(json['command'], 'grep');
      expect(CommandDefinition.fromJson(json), equals(cmd));
    });

    test('SystemCall serialization', () {
      final call = SystemCall(
        command: 'read_file',
        parameters: {'path': 'workspace/notes.txt', 'start_line': 1},
      );

      final json = call.toJson();
      expect(json['command'], 'read_file');
      expect(json['parameters']['path'], 'workspace/notes.txt');
      expect(SystemCall.fromJson(json), equals(call));
    });

    test('SystemResponse success and error', () {
      final success = SystemResponse.success(
        command: 'read_file',
        data: 'File contents here',
      );
      expect(success.isSuccess, isTrue);
      expect(success.isError, isFalse);
      expect(SystemResponse.fromJson(success.toJson()), equals(success));

      final error = SystemResponse.error(
        command: 'read_file',
        errorMessage: 'File not found.',
      );
      expect(error.isSuccess, isFalse);
      expect(error.isError, isTrue);
      expect(SystemResponse.fromJson(error.toJson()), equals(error));
    });
  });

  group('Schema - SkillMetadata Model', () {
    test('validates kebab-case name and description length', () {
      final skill = SkillMetadata(
        name: 'pdf-extractor',
        description: 'Extracts tabular data and text from local PDF files.',
        version: '1.2.0',
      );

      final json = skill.toJson();
      expect(json['name'], 'pdf-extractor');
      expect(SkillMetadata.fromJson(json), equals(skill));

      // Rejects non kebab-case
      expect(
        () => SkillMetadata(
          name: 'Invalid_Skill_Name',
          description: 'Desc',
          version: '1.0.0',
        ),
        throwsArgumentError,
      );
    });
  });

  group('Schema - A2UIMessage Protocol', () {
    test('serializes and validates standard A2UI v1 payloads', () {
      final a2ui = A2UIMessage(
        version: '1.0',
        createSurface: A2UICreateSurface(
          surfaceId: 'card_flight_01',
          catalogId: 'basic/v1',
          sendDataModel: true,
        ),
        updateComponents: A2UIUpdateComponents(
          surfaceId: 'card_flight_01',
          components: [
            {
              'id': 'root',
              'type': 'Card',
              'properties': {'child': 'text_1'},
            },
            {
              'id': 'text_1',
              'type': 'Text',
              'properties': {'text': 'Flight SFO -> JFK'},
            },
          ],
        ),
        updateDataModel: A2UIUpdateDataModel(
          surfaceId: 'card_flight_01',
          value: {'status': 'On Time'},
        ),
      );

      final json = a2ui.toJson();
      expect(json['version'], '1.0');
      expect(json['createSurface']['surfaceId'], 'card_flight_01');
      expect(json['updateComponents']['components'].length, 2);
      expect(json['updateDataModel']['value']['status'], 'On Time');

      final restored = A2UIMessage.fromJson(json);
      expect(restored.version, '1.0');
      expect(restored.createSurface?.surfaceId, 'card_flight_01');
      expect(restored.updateComponents?.components.length, 2);
    });

    test('rejects non 1.0 version', () {
      expect(
        () => A2UIMessage(version: '2.0'),
        throwsArgumentError,
      );
    });
  });

  group('Plaintext Protocols - context.txt Line Protocol', () {
    test('formats and parses USER line with sanitization', () {
      final multiLinePrompt = 'Line 1 of prompt\nLine 2 of prompt\r\nLine 3';
      final line = ContextLine(
        type: ContextLineType.user,
        content: multiLinePrompt,
      );

      final formatted = line.format();
      // Must be a single line ending in newline
      expect(formatted.endsWith('\n'), isTrue);
      expect(formatted.contains('\r'), isFalse);
      expect(formatted.indexOf('\n'), formatted.length - 1);
      expect(formatted, 'USER: Line 1 of prompt\\nLine 2 of prompt\\nLine 3\n');

      final parsed = ContextLine.parse(formatted);
      expect(parsed.type, ContextLineType.user);
      expect(parsed.content, 'Line 1 of prompt\nLine 2 of prompt\nLine 3');
    });

    test('formats and parses AGENT line with A2UI stub', () {
      final stub = ContextLine.formatA2UIStub(
        surfaceId: 'surface_42',
        rootComponentType: 'Card',
      );
      final line = ContextLine(
        type: ContextLineType.agent,
        content: stub,
      );

      final formatted = line.format();
      expect(formatted, 'AGENT: [A2UI: surfaceId=surface_42, components=Card]\n');

      final parsed = ContextLine.parse(formatted);
      expect(parsed.type, ContextLineType.agent);
      expect(parsed.content, '[A2UI: surfaceId=surface_42, components=Card]');
    });

    test('formats and parses SUMMARY line', () {
      final summaryText = 'Previous 10 turns summarized: explored directory tree.';
      final line = ContextLine(
        type: ContextLineType.summary,
        content: summaryText,
      );

      final formatted = line.format();
      expect(formatted, 'SUMMARY: Previous 10 turns summarized: explored directory tree.\n');

      final parsed = ContextLine.parse(formatted);
      expect(parsed.type, ContextLineType.summary);
      expect(parsed.content, summaryText);
    });

    test('throws FormatException on invalid prefix', () {
      expect(
        () => ContextLine.parse('INVALID_PREFIX: text'),
        throwsFormatException,
      );
    });
  });
}


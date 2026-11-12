import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/schema/json_schema_validator.dart';

void main() {
  group('JsonSchemaValidator Tests', () {
    test('validates object with required properties and types', () {
      final schema = {
        'type': 'object',
        'required': ['name', 'age', 'isVerified'],
        'properties': {
          'name': {'type': 'string'},
          'age': {'type': 'integer', 'minimum': 0},
          'isVerified': {'type': 'boolean'},
        },
      };

      // Valid case
      final validData = {
        'name': 'Alice',
        'age': 30,
        'isVerified': true,
      };
      final validResult = JsonSchemaValidator.validate(validData, schema);
      expect(validResult.isValid, isTrue);
      expect(validResult.errors, isEmpty);

      // Missing required property
      final missingData = {
        'name': 'Alice',
        'isVerified': true,
      };
      final missingResult = JsonSchemaValidator.validate(missingData, schema);
      expect(missingResult.isValid, isFalse);
      expect(missingResult.errors.length, 1);
      expect(missingResult.errors.first.path, '/age');
      expect(missingResult.errors.first.message, contains('Required property "age" is missing'));

      // Wrong type
      final wrongTypeData = {
        'name': 12345,
        'age': 'thirty',
        'isVerified': 'yes',
      };
      final wrongTypeResult = JsonSchemaValidator.validate(wrongTypeData, schema);
      expect(wrongTypeResult.isValid, isFalse);
      expect(wrongTypeResult.errors.length, 3);
      expect(wrongTypeResult.errors[0].path, '/name');
      expect(wrongTypeResult.errors[1].path, '/age');
      expect(wrongTypeResult.errors[2].path, '/isVerified');
    });

    test('validates nested objects and arrays with exact JSON Pointer paths', () {
      final schema = {
        'type': 'object',
        'required': ['command', 'parameters'],
        'properties': {
          'command': {'type': 'string'},
          'parameters': {
            'type': 'object',
            'required': ['messages'],
            'properties': {
              'messages': {
                'type': 'array',
                'items': {
                  'type': 'object',
                  'required': ['createSurface'],
                  'properties': {
                    'createSurface': {
                      'type': 'object',
                      'required': ['surfaceId'],
                      'properties': {
                        'surfaceId': {'type': 'string'},
                      },
                    },
                  },
                },
              },
            },
          },
        },
      };

      final dataWithNestedError = {
        'command': 'send_ui_message',
        'parameters': {
          'messages': [
            {
              'createSurface': {'surfaceId': 'surf_01'},
            },
            {
              'createSurface': {'surfaceId': 999}, // Int instead of string!
            },
            {
              'missingCreateSurface': {}, // Missing createSurface!
            },
          ],
        },
      };

      final result = JsonSchemaValidator.validate(
        dataWithNestedError,
        schema,
        rootPath: '/parameters',
      );
      expect(result.isValid, isFalse);
      expect(result.errors.length, 2);

      // Verify exact JSON Pointer path tracking
      expect(result.errors[0].path, '/parameters/parameters/messages/1/createSurface/surfaceId');
      expect(result.errors[0].message, contains('Expected type "string"'));

      expect(result.errors[1].path, '/parameters/parameters/messages/2/createSurface');
      expect(result.errors[1].message, contains('Required property "createSurface" is missing'));

      // Formatted summary contains locations
      final summary = result.formatErrorSummary(contextName: 'send_ui_message');
      expect(summary, contains('at /parameters/parameters/messages/1/createSurface/surfaceId'));
      expect(summary, contains('at /parameters/parameters/messages/2/createSurface'));
    });

    test('supports union types', () {
      final schema = {
        'type': 'object',
        'properties': {
          'value': {
            'type': ['string', 'object'],
          },
        },
      };

      expect(
        JsonSchemaValidator.validate({'value': 'text'}, schema).isValid,
        isTrue,
      );
      expect(
        JsonSchemaValidator.validate({
          'value': {'@path': '/name'},
        }, schema).isValid,
        isTrue,
      );
      expect(
        JsonSchemaValidator.validate({'value': 42}, schema).isValid,
        isFalse,
      );
    });

    test('rejects additional properties when disallowed', () {
      final schema = {
        'type': 'object',
        'properties': {
          'child': {'type': 'string'},
        },
        'required': ['child'],
        'additionalProperties': false,
      };

      final valid = JsonSchemaValidator.validate({'child': 'a'}, schema);
      expect(valid.isValid, isTrue);

      final invalid = JsonSchemaValidator.validate({
        'child': 'a',
        'children': ['b'],
      }, schema);
      expect(invalid.isValid, isFalse);
      expect(invalid.errors.single.path, '/children');
      expect(invalid.errors.single.keyword, 'additionalProperties');
    });

    test('validates enum values', () {
      final schema = {
        'type': 'object',
        'properties': {
          'variant': {
            'type': 'string',
            'enum': ['headline', 'title', 'body', 'caption'],
          },
        },
      };

      final validData = {'variant': 'title'};
      expect(JsonSchemaValidator.validate(validData, schema).isValid, isTrue);

      final invalidData = {'variant': 'huge_banner'};
      final res = JsonSchemaValidator.validate(invalidData, schema);
      expect(res.isValid, isFalse);
      expect(res.errors.first.path, '/variant');
      expect(res.errors.first.message, contains('not one of allowed values'));
    });
  });
}


import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/engine/command_router.dart';
import 'package:harness/core/models/system_call.dart';
import 'package:harness/modules/platform_actions/platform_actions_module.dart';

import '../mocks/fake_platform_action_gateway.dart';

void main() {
  late FakePlatformActionGateway gateway;
  late PlatformActionsModule module;

  setUp(() {
    gateway = FakePlatformActionGateway();
    module = PlatformActionsModule(gateway: gateway);
  });

  group('PlatformActionsModule', () {
    test('exposes all four platform commands', () {
      expect(module.moduleName, equals('platform_actions'));
      final commands = module.commands.map((c) => c.command).toList();
      expect(
        commands,
        containsAll([
          'set_alarm',
          'schedule_notification',
          'open_url',
          'copy_to_clipboard',
        ]),
      );
    });

    group('set_alarm', () {
      test('schedules an alarm for a valid HH:mm time and label', () async {
        final response = await module.executeCommand('set_alarm', {
          'time': '07:00',
          'label': 'Morning Flight',
        });

        expect(response.isSuccess, isTrue);
        expect(response.data, equals({'status': 'success', 'action': 'set_alarm'}));
        expect(gateway.alarms, hasLength(1));
        expect(gateway.alarms.single['time'], equals('07:00'));
        expect(gateway.alarms.single['label'], equals('Morning Flight'));
      });

      test('accepts single-digit hour notation', () async {
        final response = await module.executeCommand('set_alarm', {
          'time': '7:05',
          'label': 'Wake up',
        });

        expect(response.isSuccess, isTrue);
        expect(gateway.alarms.single['time'], equals('7:05'));
      });

      test('rejects malformed times before invoking the gateway', () async {
        for (final invalid in ['25:00', '07:60', '7pm', '07-00']) {
          final response = await module.executeCommand('set_alarm', {
            'time': invalid,
            'label': 'Test',
          });

          expect(response.isError, isTrue, reason: 'time "$invalid" should fail');
          expect(response.errorMessage, contains('Invalid time format'));
        }
        expect(gateway.alarms, isEmpty);
      });

      test('rejects missing or empty times', () async {
        for (final invalid in ['', '   ']) {
          final response = await module.executeCommand('set_alarm', {
            'time': invalid,
            'label': 'Test',
          });

          expect(response.isError, isTrue);
          expect(response.errorMessage, contains('Missing or invalid "time"'));
        }
        expect(gateway.alarms, isEmpty);
      });

      test('rejects missing or empty labels', () async {
        final missing = await module.executeCommand('set_alarm', {
          'time': '07:00',
        });
        final empty = await module.executeCommand('set_alarm', {
          'time': '07:00',
          'label': '   ',
        });

        expect(missing.isError, isTrue);
        expect(empty.isError, isTrue);
        expect(gateway.alarms, isEmpty);
      });

      test('translates denied alarm permission into the specification error',
          () async {
        gateway.denyAlarmPermission = true;

        final response = await module.executeCommand('set_alarm', {
          'time': '07:00',
          'label': 'Morning Flight',
        });

        expect(response.isError, isTrue);
        expect(response.errorMessage, contains('Permission denied for alarms'));
      });
    });

    group('schedule_notification', () {
      test('schedules a delayed notification with the supplied fields', () async {
        final response = await module.executeCommand('schedule_notification', {
          'title': 'Standup',
          'body': 'Daily sync in five minutes',
          'delaySeconds': 300,
          'id': 42,
        });

        expect(response.isSuccess, isTrue);
        expect(response.data,
            equals({'status': 'success', 'action': 'schedule_notification'}));
        expect(gateway.notifications, hasLength(1));
        expect(gateway.notifications.single['id'], equals(42));
        expect(gateway.notifications.single['title'], equals('Standup'));
        expect(gateway.notifications.single['delayMs'], equals(300000));
      });

      test('rejects a missing title', () async {
        final response =
            await module.executeCommand('schedule_notification', {});

        expect(response.isError, isTrue);
        expect(response.errorMessage, contains('title'));
        expect(gateway.notifications, isEmpty);
      });

      test('rejects negative delays', () async {
        final response = await module.executeCommand('schedule_notification', {
          'title': 'Test',
          'delaySeconds': -1,
        });

        expect(response.isError, isTrue);
        expect(response.errorMessage, contains('delaySeconds'));
      });

      test('translates denied notification permission', () async {
        gateway.denyNotificationPermission = true;

        final response = await module.executeCommand('schedule_notification', {
          'title': 'Test',
        });

        expect(response.isError, isTrue);
        expect(
          response.errorMessage,
          contains('Permission denied for notifications'),
        );
      });
    });

    group('open_url', () {
      test('opens an absolute https URI', () async {
        final response = await module.executeCommand('open_url', {
          'url': 'https://example.com/path?q=1',
        });

        expect(response.isSuccess, isTrue);
        expect(gateway.openedUrls, equals(['https://example.com/path?q=1']));
      });

      test('opens a custom deep link', () async {
        final response = await module.executeCommand('open_url', {
          'url': 'harness://session/sess_123',
        });

        expect(response.isSuccess, isTrue);
        expect(gateway.openedUrls.single, equals('harness://session/sess_123'));
      });

      test('rejects relative and malformed URIs before invoking the gateway',
          () async {
        for (final invalid in ['example.com', '/relative/path', 'not a url']) {
          final response = await module.executeCommand('open_url', {
            'url': invalid,
          });

          expect(response.isError, isTrue, reason: 'url "$invalid" should fail');
          expect(response.errorMessage, contains('Invalid URL'));
        }
        expect(gateway.openedUrls, isEmpty);
      });

      test('returns an error when no handler accepts the URI', () async {
        gateway.openUrlResult = false;

        final response = await module.executeCommand('open_url', {
          'url': 'https://example.com',
        });

        expect(response.isError, isTrue);
        expect(response.errorMessage, contains('No application is available'));
      });
    });

    group('copy_to_clipboard', () {
      test('copies the supplied text', () async {
        final response = await module.executeCommand('copy_to_clipboard', {
          'text': 'Flight AA 404',
        });

        expect(response.isSuccess, isTrue);
        expect(gateway.copiedTexts, equals(['Flight AA 404']));
      });

      test('rejects empty text', () async {
        final response =
            await module.executeCommand('copy_to_clipboard', {'text': ''});

        expect(response.isError, isTrue);
        expect(gateway.copiedTexts, isEmpty);
      });
    });

    test('returns a structured error for unknown platform actions', () async {
      final response = await module.executeCommand('launch_rocket', {});

      expect(response.isError, isTrue);
      expect(response.errorMessage, contains('Unrecognized platform action'));
    });

    test('integrates with CommandRouter schema validation and dispatch',
        () async {
      final router = CommandRouter()..registerModule(module);

      final response = await router.executeCall(SystemCall(
        command: 'set_alarm',
        parameters: {'time': '07:00', 'label': 'Morning Flight'},
      ));

      expect(response.isSuccess, isTrue);
      expect(gateway.alarms, hasLength(1));
    });
  });
}

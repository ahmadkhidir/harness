import 'package:flutter_test/flutter_test.dart';
import 'package:harness/modules/platform_actions/a2ui_event_router.dart';
import 'package:harness/modules/platform_actions/platform_actions_module.dart';

import '../mocks/fake_platform_action_gateway.dart';

void main() {
  late FakePlatformActionGateway gateway;
  late A2UIEventRouter router;

  setUp(() {
    gateway = FakePlatformActionGateway();
    router = A2UIEventRouter(
      platformActions: PlatformActionsModule(gateway: gateway),
    );
  });

  group('A2UIEventRouter.resolve', () {
    test('routes platform prefix to a platform action', () {
      final route = router.resolve('platform:set_alarm', {
        'time': '07:00',
        'label': 'Morning Flight',
      });

      expect(route.kind, equals(A2UIEventKind.platformAction));
      expect(route.command, equals('set_alarm'));
      expect(route.parameters['time'], equals('07:00'));
      expect(route.parameters['label'], equals('Morning Flight'));
      expect(route.prompt, isNull);
    });

    test('merges inline query parameters over the data model', () {
      final route = router.resolve(
        'platform:set_alarm?time=08%3A30&label=Lunch',
        {'time': '07:00', 'label': 'Morning Flight', 'extra': 'kept'},
      );

      expect(route.command, equals('set_alarm'));
      expect(route.parameters['time'], equals('08:30'));
      expect(route.parameters['label'], equals('Lunch'));
      expect(route.parameters['extra'], equals('kept'));
    });

    test('routes non-prefixed actions to a conversational turn', () {
      final route = router.resolve('confirm_choice', {'choice': 'window'});

      expect(route.kind, equals(A2UIEventKind.conversationTurn));
      expect(route.command, isNull);
      expect(route.prompt, contains('"confirm_choice"'));
      expect(route.prompt, contains('"choice":"window"'));
      expect(route.parameters['choice'], equals('window'));
    });

    test('conversation prompt avoids UI modality keywords', () {
      final route = router.resolve('confirm_choice', {'choice': 'window'});

      final lower = route.prompt!.toLowerCase();
      for (final keyword in ['a2ui', 'button', 'widget', 'surface', 'card']) {
        expect(lower.contains(keyword), isFalse, reason: keyword);
      }
    });

    test('rejects empty and command-less platform actions', () {
      expect(router.resolve('', {}).kind, equals(A2UIEventKind.invalid));
      expect(
        router.resolve('platform:', {}).kind,
        equals(A2UIEventKind.invalid),
      );
    });
  });

  group('A2UIEventRouter.executePlatform', () {
    test('executes the routed platform command through the module', () async {
      final route = router.resolve('platform:copy_to_clipboard', {
        'text': 'Copied from an A2UI action',
      });

      final response = await router.executePlatform(route);

      expect(response.isSuccess, isTrue);
      expect(gateway.copiedTexts, equals(['Copied from an A2UI action']));
    });

    test('returns a structured error when no platform module is configured',
        () async {
      final route = router.resolve('platform:set_alarm', {
        'time': '07:00',
        'label': 'Test',
      });
      final unconfigured = const A2UIEventRouter();

      final response = await unconfigured.executePlatform(route);

      expect(response.isError, isTrue);
      expect(response.errorMessage, contains('unavailable'));
    });

    test('rejects conversational routes passed to the platform executor',
        () async {
      final route = router.resolve('confirm_choice', {});

      final response = await router.executePlatform(route);

      expect(response.isError, isTrue);
      expect(response.errorMessage, contains('not a platform action'));
    });
  });
}

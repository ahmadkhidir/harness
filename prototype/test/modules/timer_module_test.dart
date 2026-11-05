import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/models/scheduled_timer.dart';
import 'package:harness/core/utils/file_system_manager.dart';
import 'package:harness/data/database/app_database.dart';
import 'package:harness/data/services/session_service.dart';
import 'package:harness/data/services/timer_service.dart';
import 'package:harness/modules/timers/timer_module.dart';

void main() {
  late Directory tempDir;
  late HarnessFileSystem fileSystem;
  late SessionService sessionService;
  late TimerService timerService;
  late TimerModule module;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('harness_timer_module_');
    fileSystem = HarnessFileSystem(rootDir: tempDir);
    fileSystem.ensureBaseDirectoriesSync();
    sessionService = SessionService(
      fileSystem: fileSystem,
      database: AppDatabase.inMemory(),
    );
    final session = await sessionService.createSession(title: 'Timers');
    fileSystem.activeSessionId = session.id;
    timerService = TimerService(sessionService: sessionService);
    module = TimerModule(timerService: timerService);
  });

  tearDown(() async {
    await timerService.dispose();
    HarnessFileSystem.instance = null;
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  group('TimerModule', () {
    test('schedules, lists, and cancels a timer', () async {
      final scheduled = await module.executeCommand('schedule_timer', {
        'prompt': 'Ask how the exercise went',
        'delaySeconds': 600,
        'label': 'Workout check-in',
      });

      expect(scheduled.isSuccess, isTrue);
      final data = scheduled.data as Map<String, dynamic>;
      expect(data['timerId'], startsWith('timer_'));
      expect(data['firesAt'], isNotEmpty);

      final listed = await module.executeCommand('list_timers', {});
      expect(listed.isSuccess, isTrue);
      final timers = (listed.data as Map)['timers'] as List;
      expect(timers, hasLength(1));
      expect(timers.single, containsPair('label', 'Workout check-in'));
      expect(timers.single, containsPair('status', 'scheduled'));

      final cancelled = await module.executeCommand('cancel_timer', {
        'timerId': data['timerId'],
      });
      expect(cancelled.isSuccess, isTrue);

      expect(
        (await sessionService.loadTimers(fileSystem.activeSessionId!))
            .single
            .status,
        ScheduledTimerStatus.cancelled,
      );
    });

    test('rejects invalid delay and empty prompt', () async {
      final empty = await module.executeCommand('schedule_timer', {
        'prompt': ' ',
        'delaySeconds': 10,
      });
      expect(empty.isError, isTrue);

      final zero = await module.executeCommand('schedule_timer', {
        'prompt': 'Check in',
        'delaySeconds': 0,
      });
      expect(zero.isError, isTrue);

      final tooLong = await module.executeCommand('schedule_timer', {
        'prompt': 'Check in',
        'delaySeconds': 604801,
      });
      expect(tooLong.isError, isTrue);
    });

    test('cancelling an unknown timer returns an error', () async {
      final response = await module.executeCommand('cancel_timer', {
        'timerId': 'timer_missing',
      });

      expect(response.isError, isTrue);
      expect(response.errorMessage, contains('not found'));
    });
  });
}

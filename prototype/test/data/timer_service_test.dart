import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/models/scheduled_timer.dart';
import 'package:harness/core/models/turn.dart';
import 'package:harness/core/utils/file_system_manager.dart';
import 'package:harness/data/database/app_database.dart';
import 'package:harness/data/services/session_service.dart';
import 'package:harness/data/services/timer_service.dart';

void main() {
  late Directory tempDir;
  late HarnessFileSystem fileSystem;
  late SessionService sessionService;
  late TimerService timerService;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('harness_timers_');
    fileSystem = HarnessFileSystem(rootDir: tempDir);
    fileSystem.ensureBaseDirectoriesSync();
    sessionService = SessionService(
      fileSystem: fileSystem,
      database: AppDatabase.inMemory(),
    );
    timerService = TimerService(sessionService: sessionService);
  });

  tearDown(() async {
    await timerService.dispose();
    HarnessFileSystem.instance = null;
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  group('ScheduledTimer', () {
    test('omits unused timestamp fields', () {
      final timer = ScheduledTimer(
        id: 'timer_1',
        sessionId: 'sess_1',
        prompt: 'Check in',
        createdAt: DateTime.utc(2026, 1, 1),
        firesAt: DateTime.utc(2026, 1, 1, 0, 5),
      );

      final json = timer.toJson();
      expect(json.containsKey('firedAt'), isFalse);
      expect(json.containsKey('cancelledAt'), isFalse);

      final completed = timer.copyWith(
        status: ScheduledTimerStatus.completed,
        firedAt: DateTime.utc(2026, 1, 1, 0, 5),
      );
      expect(completed.toJson().containsKey('firedAt'), isTrue);
      expect(completed.toJson().containsKey('cancelledAt'), isFalse);
    });
  });

  group('TimerService', () {
    test('fires a due timer and queues it', () async {
      final session =
          await sessionService.createSession(title: 'Timer Test');
      ScheduledTimer? due;
      timerService.onDue = (timer) => due = timer;

      final timer = await timerService.schedule(
        sessionId: session.id,
        prompt: 'Ask how it went',
        delay: const Duration(milliseconds: 30),
      );

      expect(timer.status, ScheduledTimerStatus.scheduled);
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(due?.id, timer.id);
      final stored = (await sessionService.loadTimers(session.id)).single;
      expect(stored.status, ScheduledTimerStatus.queued);
    });

    test('cancels a pending timer and records the cancellation time', () async {
      final session = await sessionService.createSession(title: 'Cancel');
      final timer = await timerService.schedule(
        sessionId: session.id,
        prompt: 'Later',
        delay: const Duration(hours: 1),
      );

      expect(await timerService.cancel(session.id, timer.id), isTrue);

      final stored = (await sessionService.loadTimers(session.id)).single;
      expect(stored.status, ScheduledTimerStatus.cancelled);
      expect(stored.cancelledAt, isNotNull);
    });

    test('preserves timers when turns are appended', () async {
      final session = await sessionService.createSession(title: 'Preserve');
      await timerService.schedule(
        sessionId: session.id,
        prompt: 'Later',
        delay: const Duration(hours: 1),
      );

      await sessionService.appendTurn(
        session.id,
        Turn(
          id: 't1',
          sessionId: session.id,
          timestamp: DateTime.now().toUtc(),
          sender: 'agent',
          contentType: 'text',
          text: 'Hello',
        ),
      );

      expect(await sessionService.loadTimers(session.id), hasLength(1));
      expect((await sessionService.loadTurns(session.id)), hasLength(1));
    });

    test('restores overdue timers as queued and prunes old records', () async {
      final session = await sessionService.createSession(title: 'Restore');
      final now = DateTime.now().toUtc();

      await sessionService.upsertTimer(
        session.id,
        ScheduledTimer(
          id: 'timer_overdue',
          sessionId: session.id,
          prompt: 'Overdue',
          createdAt: now.subtract(const Duration(minutes: 10)),
          firesAt: now.subtract(const Duration(minutes: 5)),
        ),
      );
      await sessionService.upsertTimer(
        session.id,
        ScheduledTimer(
          id: 'timer_old',
          sessionId: session.id,
          prompt: 'Old',
          createdAt: now.subtract(const Duration(days: 3)),
          firesAt: now.subtract(const Duration(days: 2)),
          status: ScheduledTimerStatus.completed,
          firedAt: now.subtract(const Duration(days: 2)),
        ),
      );

      ScheduledTimer? due;
      timerService.onDue = (timer) => due = timer;
      await timerService.restoreAll();

      expect(due?.id, 'timer_overdue');
      final stored = await sessionService.loadTimers(session.id);
      expect(stored.map((timer) => timer.id), ['timer_overdue']);
      expect(stored.single.status, ScheduledTimerStatus.queued);
    });
  });
}

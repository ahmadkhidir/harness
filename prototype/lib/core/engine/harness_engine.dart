import 'dart:async';
import 'package:uuid/uuid.dart';
import '../models/turn.dart';
import '../utils/file_system_manager.dart';
import 'command_router.dart';
import 'context_builder.dart';
import 'engine_events.dart';
import 'system_call_parser.dart';
import '../../providers/model_provider.dart';

/// Central orchestration engine coordinating the autonomous multi-turn tool loop.
///
/// Implements the execution lifecycle specified in `docs/Harness/architecture.md`:
/// 1. Assembles prompt context (instructions, time, commands, skills, storage map).
/// 2. Queries active [ModelProvider].
/// 3. Extracts `<system_call>` blocks and suppresses scratchpad reasoning.
/// 4. Dispatches calls to [CommandRouter] for parallel concurrent execution.
/// 5. Feeds aggregated observations back into context until explicit user delivery.
class HarnessEngine {
  /// Central command routing registry.
  final CommandRouter router;

  /// Prompt context assembler.
  final ContextBuilder contextBuilder;

  /// Active LLM inference provider.
  ModelProvider modelProvider;

  /// Maximum permissible conversational turns per user task (prevents infinite loops).
  final int maxTurns;

  HarnessEngine({
    required this.router,
    required this.contextBuilder,
    required this.modelProvider,
    this.maxTurns = 15,
  });

  /// Updates the active inference adapter at runtime (e.g. user switched model in settings).
  void updateModelProvider(ModelProvider newProvider) {
    modelProvider = newProvider;
  }

  /// Executes an autonomous multi-turn agent interaction for the given [userPrompt].
  ///
  /// Yields progressive [EngineProgressEvent] instances to drive reactive UI indicators.
  Stream<EngineProgressEvent> executeTurn({
    required String userPrompt,
    required String sessionId,
    String? apiKey,
    String? storageTree,
  }) async* {
    yield EngineTurnStarted(userPrompt);

    final resolvedStorageTree = storageTree ??
        (HarnessFileSystem.instance?.formatFilesystemTree() ?? '<filesystem>\nprimary/\n  (empty)\n</filesystem>');

    // Build the baseline system instruction with dynamic tool catalog
    final systemInstruction = contextBuilder.buildSystemInstruction(
      commands: router.allCommandDefinitions,
      storageTree: resolvedStorageTree,
    );

    final dialogueHistory = <ModelMessage>[
      ModelMessage(role: 'user', content: userPrompt),
    ];

    int turnsCount = 0;

    while (turnsCount < maxTurns) {
      turnsCount++;
      yield EngineModelGenerating();

      String rawResponse;
      try {
        rawResponse = await modelProvider.generate(
          messages: dialogueHistory,
          systemInstruction: systemInstruction,
          tools: router.allCommandDefinitions,
          apiKey: apiKey,
        );
      } catch (e) {
        yield EngineErrorOccurred('Model inference failed: $e');
        return;
      }

      final parsed = SystemCallParser.parse(rawResponse);

      // Check for explicit final delivery commands (send_message / send_a2ui)
      if (parsed.hasExplicitDelivery) {
        final isA2UI = parsed.explicitA2UIPayload != null;
        final turn = Turn(
          id: 'turn_${const Uuid().v4().substring(0, 8)}',
          sessionId: sessionId,
          timestamp: DateTime.now().toUtc(),
          sender: 'agent',
          contentType: isA2UI ? 'a2ui' : 'text',
          text: parsed.explicitTextMessage,
          a2uiSurfaceId: parsed.explicitA2UIPayload?['messages']?[0]?['createSurface']?['surfaceId'],
          modelUsed: modelProvider.config.displayName,
        );

        yield EngineTurnCompleted(turn);
        return;
      }

      // Fallback: If no system calls and no delivery command, treat raw response as text delivery
      if (!parsed.hasSystemCalls) {
        final text = rawResponse.trim();
        final turn = Turn(
          id: 'turn_${const Uuid().v4().substring(0, 8)}',
          sessionId: sessionId,
          timestamp: DateTime.now().toUtc(),
          sender: 'agent',
          contentType: 'text',
          text: text,
          modelUsed: modelProvider.config.displayName,
        );

        yield EngineTurnCompleted(turn);
        return;
      }

      // Dispatched system calls: Notify start for all calls
      for (final call in parsed.systemCalls) {
        yield EngineSystemCallStarted(call);
      }

      // Execute all calls concurrently in parallel via Future.wait
      final responses = await router.executeCallsParallel(
        parsed.systemCalls,
        onProgress: (call, resp) {
          // Progress handled directly in loop below
        },
      );

      // Notify completion with observations
      for (int i = 0; i < parsed.systemCalls.length; i++) {
        yield EngineSystemCallFinished(parsed.systemCalls[i], responses[i]);
      }

      // Record the model's raw generation (containing system calls) and the returned
      // environment observations into conversation history for the next turn.
      dialogueHistory.add(ModelMessage(role: 'assistant', content: rawResponse));

      final observationsBuffer = StringBuffer();
      for (final resp in responses) {
        observationsBuffer.writeln(resp.toXmlString());
      }

      dialogueHistory.add(
        ModelMessage(role: 'user', content: observationsBuffer.toString().trim()),
      );
    }

    // Hard turn limit triggered
    yield EngineErrorOccurred(
      'Halted: Autonomous tool loop exceeded maximum turn limit ($maxTurns turns).',
    );
  }
}

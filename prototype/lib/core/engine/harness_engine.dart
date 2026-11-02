import 'dart:async';
import 'package:uuid/uuid.dart';
import '../../data/services/skills_service.dart';
import '../../modules/a2ui/a2ui_validator.dart';
import '../models/models.dart';
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

  /// Service scanning and managing installed skill packages.
  final SkillsService skillsService;

  /// Maximum permissible conversational turns per user task (prevents infinite loops).
  final int maxTurns;

  HarnessEngine({
    required this.router,
    required this.contextBuilder,
    required this.modelProvider,
    SkillsService? skillsService,
    this.maxTurns = 15,
  }) : skillsService = skillsService ?? SkillsService();

  /// Updates the active inference adapter at runtime (e.g. user switched model in settings).
  void updateModelProvider(ModelProvider newProvider) {
    modelProvider = newProvider;
  }

  /// Executes an autonomous multi-turn agent interaction for the given [userPrompt].
  ///
  /// Incorporates optional [recentHistory] (last 5-10 conversational turns) into prompt context
  /// so the model maintains short-term conversational awareness.
  /// Yields progressive [EngineProgressEvent] instances to drive reactive UI indicators.
  Stream<EngineProgressEvent> executeTurn({
    required String userPrompt,
    required String sessionId,
    String? apiKey,
    String? storageTree,
    List<Turn>? recentHistory,
  }) async* {
    yield EngineTurnStarted(userPrompt);

    HarnessFileSystem.instance?.activeSessionId = sessionId;

    final resolvedStorageTree = storageTree ??
        (HarnessFileSystem.instance?.formatFilesystemTree() ??
            '<filesystem>\nprimary/\n  (empty)\n</filesystem>');

    final availableSkills = skillsService.scanAvailableSkills();

    // Build the baseline system instruction with dynamic tool catalog and available skills
    final systemInstruction = contextBuilder.buildSystemInstruction(
      commands: router.allCommandDefinitions,
      storageTree: resolvedStorageTree,
      availableSkills: availableSkills,
    );

    final dialogueHistory = <ModelMessage>[];

    // Inject recent short-term conversational context (last 5-10 turns)
    if (recentHistory != null && recentHistory.isNotEmpty) {
      final historyWithoutCurrent = recentHistory.where((t) {
        if (t.sender == 'user' && t.text == userPrompt) return false;
        return true;
      }).toList();

      final sliceStart = historyWithoutCurrent.length > 10
          ? historyWithoutCurrent.length - 10
          : 0;
      final recentSlice = historyWithoutCurrent.sublist(sliceStart);

      for (final turn in recentSlice) {
        if (turn.sender == 'user') {
          final content = (turn.text ?? '').trim();
          if (content.isNotEmpty) {
            dialogueHistory.add(ModelMessage(role: 'user', content: content));
          }
        } else {
          var content = (turn.text ?? '').trim();
          if (content.isEmpty && turn.a2uiPayload != null) {
            content = '[Delivered interactive A2UI surface: ${turn.a2uiSurfaceId ?? 'main'}]';
          }
          if (content.isNotEmpty) {
            dialogueHistory.add(ModelMessage(role: 'assistant', content: content));
          }
        }
      }
    }

    dialogueHistory.add(ModelMessage(role: 'user', content: userPrompt));

    int turnsCount = 0;
    final accumulatedToolCalls = <ToolExecutionRecord>[];

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
        // If send_a2ui was dispatched, strictly validate that it contains renderable components
        if (parsed.explicitA2UIPayload != null) {
          final validation = A2UIValidator.validate(parsed.explicitA2UIPayload);
          if (validation.isValid) {
            final turn = Turn(
              id: 'turn_${const Uuid().v4().substring(0, 8)}',
              sessionId: sessionId,
              timestamp: DateTime.now().toUtc(),
              sender: 'agent',
              contentType: 'a2ui',
              text: parsed.explicitTextMessage,
              a2uiSurfaceId: validation.surfaceId,
              a2uiPayload: parsed.explicitA2UIPayload,
              modelUsed: modelProvider.config.displayName,
              toolCalls: List.unmodifiable(accumulatedToolCalls),
            );

            yield EngineTurnCompleted(turn);
            return;
          } else {
            // Self-Healing Loop: Do not abort with broken UI; feed error back to LLM for autonomous repair
            final a2uiCall = SystemCall(
              command: 'send_a2ui',
              parameters: parsed.explicitA2UIPayload!,
            );
            accumulatedToolCalls.add(ToolExecutionRecord(
              call: a2uiCall,
              status: 'error',
              errorMessage: validation.errorMessage,
            ));
            yield EngineSystemCallStarted(a2uiCall);
            yield EngineSystemCallFinished(
              a2uiCall,
              SystemResponse.error(
                command: 'send_a2ui',
                errorMessage: validation.errorMessage ?? 'Invalid A2UI payload structure.',
              ),
            );

            dialogueHistory.add(ModelMessage(role: 'assistant', content: rawResponse));
            dialogueHistory.add(
              ModelMessage(
                role: 'user',
                content:
                    '<system_response command="send_a2ui" status="error">\n${validation.errorMessage}\nAction Required: The user requested an interactive UI surface. Repair the A2UI surface/component hierarchy and re-emit send_a2ui with valid components (e.g. inside createSurface.components or updateComponents.components). Do NOT fall back to send_message or plain text.\n</system_response>',
              ),
            );
            continue;
          }
        }

        // Standard text message delivery via send_message
        if (parsed.explicitTextMessage != null) {
          final isUIRequired = accumulatedToolCalls.any(
                  (r) => r.call.command == 'send_a2ui' || r.call.command == 'load_a2ui_catalog') ||
              _isUIContextRequested(userPrompt, dialogueHistory, accumulatedToolCalls);

          if (isUIRequired && turnsCount < maxTurns) {
            dialogueHistory.add(ModelMessage(role: 'assistant', content: rawResponse));
            dialogueHistory.add(
              ModelMessage(
                role: 'user',
                content:
                    '<system_response status="error">\nModality Enforcement: An interactive UI interface was requested by the user or skill context. Do NOT downgrade to plain text or send_message. You must deliver using send_a2ui with a valid component hierarchy.\n</system_response>',
              ),
            );
            continue;
          }

          final turn = Turn(
            id: 'turn_${const Uuid().v4().substring(0, 8)}',
            sessionId: sessionId,
            timestamp: DateTime.now().toUtc(),
            sender: 'agent',
            contentType: 'text',
            text: parsed.explicitTextMessage,
            modelUsed: modelProvider.config.displayName,
            toolCalls: List.unmodifiable(accumulatedToolCalls),
          );

          yield EngineTurnCompleted(turn);
          return;
        }
      }

      // Fallback: If no system calls and no delivery command, treat raw response as text delivery
      if (!parsed.hasSystemCalls) {
        final isUIRequired = accumulatedToolCalls.any(
                (r) => r.call.command == 'send_a2ui' || r.call.command == 'load_a2ui_catalog') ||
            _isUIContextRequested(userPrompt, dialogueHistory, accumulatedToolCalls);

        if (isUIRequired && turnsCount < maxTurns) {
          dialogueHistory.add(ModelMessage(role: 'assistant', content: rawResponse));
          dialogueHistory.add(
            ModelMessage(
              role: 'user',
              content:
                  '<system_response status="error">\nModality Enforcement: An interactive UI interface was requested by the user or skill context. You must deliver using <system_call>{"command": "send_a2ui", "parameters": ...}</system_call>, not plain text. Please emit your A2UI component hierarchy now.\n</system_response>',
            ),
          );
          continue;
        }

        var text = (parsed.explicitTextMessage ?? rawResponse).trim();
        // Zero Leakage: Ensure raw <system_call> or <system_response> tags never leak to user
        if (text.contains('<system_call>')) {
          text = text.replaceAll(RegExp(r'<system_call>[\s\S]*'), '').trim();
        }
        if (text.isEmpty && parsed.scratchpadText.isNotEmpty) {
          text = parsed.scratchpadText;
        }

        final turn = Turn(
          id: 'turn_${const Uuid().v4().substring(0, 8)}',
          sessionId: sessionId,
          timestamp: DateTime.now().toUtc(),
          sender: 'agent',
          contentType: 'text',
          text: text,
          modelUsed: modelProvider.config.displayName,
          toolCalls: List.unmodifiable(accumulatedToolCalls),
        );

        yield EngineTurnCompleted(turn);
        return;
      }

      // Dispatched system calls: Notify start for all calls and record
      for (final call in parsed.systemCalls) {
        accumulatedToolCalls.add(ToolExecutionRecord(
          call: call,
          status: 'running',
        ));
        yield EngineSystemCallStarted(call);
      }

      // Execute all calls concurrently in parallel via Future.wait
      final responses = await router.executeCallsParallel(
        parsed.systemCalls,
        onProgress: (call, resp) {
          // Progress handled directly in loop below
        },
      );

      // Notify completion with observations and update accumulated records
      for (int i = 0; i < parsed.systemCalls.length; i++) {
        final call = parsed.systemCalls[i];
        final resp = responses[i];
        final recordIdx = accumulatedToolCalls.lastIndexWhere(
          (r) => r.call == call && r.isRunning,
        );
        if (recordIdx != -1) {
          accumulatedToolCalls[recordIdx] = accumulatedToolCalls[recordIdx].copyWith(
            status: resp.isSuccess ? 'success' : 'error',
            errorMessage: resp.errorMessage,
            output: resp.data,
          );
        }
        yield EngineSystemCallFinished(call, resp);
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

  /// Determines whether the current conversational turn or prior context mandates
  /// interactive UI delivery (A2UI) rather than plain text.
  static bool _isUIContextRequested(
    String userPrompt,
    List<ModelMessage> dialogueHistory,
    List<ToolExecutionRecord> accumulatedToolCalls,
  ) {
    // 1. Any A2UI or catalog tool executed in this session turn
    if (accumulatedToolCalls.any((r) =>
        r.call.command == 'send_a2ui' ||
        r.call.command == 'load_a2ui_catalog')) {
      return true;
    }

    // 2. Any tool output in this turn referencing A2UI or UI catalogs
    for (final record in accumulatedToolCalls) {
      final resText = record.output?.toString() ?? record.errorMessage ?? '';
      if (resText.contains('a2ui') ||
          resText.contains('catalog.json') ||
          resText.contains('send_a2ui')) {
        return true;
      }
    }

    // 3. User prompt explicitly requesting UI, cards, lists, forms, or interactive views
    final uiKeywords = RegExp(
      r'\b(ui|a2ui|interactive|card|cards|list|form|dashboard|surface|widget|component|components|button|buttons)\b',
      caseSensitive: false,
    );
    if (uiKeywords.hasMatch(userPrompt)) {
      return true;
    }

    // 4. Recent dialogue history indicating UI context (e.g. from prior turns)
    final historySlice = dialogueHistory.length > 6
        ? dialogueHistory.sublist(dialogueHistory.length - 6)
        : dialogueHistory;

    for (final msg in historySlice) {
      if (msg.role == 'user' && uiKeywords.hasMatch(msg.content)) {
        return true;
      }
      if (msg.content.contains('send_a2ui') ||
          msg.content.contains('load_a2ui_catalog')) {
        return true;
      }
    }

    return false;
  }
}

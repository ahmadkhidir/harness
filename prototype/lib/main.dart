import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_edge_ai_litertlm/flutter_edge_ai_litertlm.dart';
import 'core/config/app_config.dart';
import 'core/engine/command_router.dart';
import 'core/engine/context_builder.dart';
import 'core/engine/harness_engine.dart';
import 'core/models/provider_config.dart';
import 'core/routes/app_routes.dart';
import 'core/utils/file_system_manager.dart';
import 'data/database/app_database.dart';
import 'data/secure_storage/key_storage_service.dart';
import 'data/services/bridge_settings_service.dart';
import 'data/services/notification_tap_router.dart';
import 'data/services/session_service.dart';
import 'data/services/timer_service.dart';
import 'modules/a2ui/a2ui_module.dart';
import 'modules/platform_actions/a2ui_event_router.dart';
import 'modules/platform_actions/platform_actions_module.dart';
import 'modules/runner/runner_module.dart';
import 'modules/skills/skills_module.dart';
import 'modules/storage/storage_module.dart';
import 'modules/timers/timer_module.dart';
import 'modules/transfer/transfer_module.dart';
import 'modules/web/web_module.dart';
import 'presentation/bloc/harness_session_bloc.dart';
import 'presentation/bloc/harness_session_event.dart';
import 'presentation/bloc/model_switcher_bloc.dart';
import 'presentation/bloc/model_switcher_event.dart';
import 'presentation/screens/chat_screen.dart';
import 'presentation/screens/sessions_screen.dart';
import 'presentation/screens/settings_screen.dart';
import 'presentation/screens/workspace_screen.dart';
import 'providers/model_provider_factory.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await FlutterEdgeAi.initialize(
      huggingFaceToken: AppConfig.huggingFaceToken,
      inferenceEngines: const [LiteRtLmEngine()],
    );
  } catch (e) {
    debugPrint('FlutterEdgeAi initialization skipped or failed: $e');
  }

  AppDatabase database;
  KeyStorageService keyStorage;
  HarnessEngine engine;
  SessionService sessionService;
  TimerService timerService;

  try {
    database = AppDatabase();
    await HarnessFileSystem.init(null, database);
    keyStorage = KeyStorageService();

    final activeConfig = await database.getActiveProviderConfig();
    final modelProvider = ModelProviderFactory.create(
      config: activeConfig ??
          ProviderConfig(
            id: 'local_device',
            providerType: 'local_device',
            displayName: 'On-Device SLM',
            modelName: 'local-slm-1b',
            isActive: true,
          ),
    );

    final router = CommandRouter();
    router.registerModule(SkillsModule());
    router.registerModule(StorageModule());
    router.registerModule(A2UIModule());
    router.registerModule(PlatformActionsModule());
    final bridgeSettings = BridgeSettingsService(
      database: database,
      keyStorage: keyStorage,
    );
    router.registerModule(WebModule(
      searchProviderFactory: bridgeSettings.createSearchProvider,
      fetchProvider: bridgeSettings.createFetchProvider(),
    ));
    router.registerModule(RunnerModule(
      runnerProviderFactory: bridgeSettings.createRunnerProvider,
    ));
    router.registerModule(TransferModule(
      allowedHostsProvider: bridgeSettings.getAllowedHosts,
      fileSystemProvider: () => HarnessFileSystem.instance,
    ));
    sessionService = SessionService(
      database: database,
      fileSystem: HarnessFileSystem.instance,
    );
    timerService = TimerService(sessionService: sessionService);
    router.registerModule(TimerModule(timerService: timerService));
    final contextBuilder = ContextBuilder();
    engine = HarnessEngine(
      router: router,
      contextBuilder: contextBuilder,
      modelProvider: modelProvider,
    );
  } catch (_) {
    database = AppDatabase.inMemory();
    keyStorage = KeyStorageService(useInMemoryFallback: true);
    final router = CommandRouter();
    router.registerModule(SkillsModule());
    router.registerModule(StorageModule());
    router.registerModule(A2UIModule());
    router.registerModule(PlatformActionsModule());
    final bridgeSettings = BridgeSettingsService(
      database: database,
      keyStorage: keyStorage,
    );
    router.registerModule(WebModule(
      searchProviderFactory: bridgeSettings.createSearchProvider,
      fetchProvider: bridgeSettings.createFetchProvider(),
    ));
    router.registerModule(RunnerModule(
      runnerProviderFactory: bridgeSettings.createRunnerProvider,
    ));
    router.registerModule(TransferModule(
      allowedHostsProvider: bridgeSettings.getAllowedHosts,
      fileSystemProvider: () => HarnessFileSystem.instance,
    ));
    sessionService = SessionService(
      database: database,
      fileSystem: HarnessFileSystem.instance,
    );
    timerService = TimerService(sessionService: sessionService);
    router.registerModule(TimerModule(timerService: timerService));
    final contextBuilder = ContextBuilder();
    final modelProvider = ModelProviderFactory.create(
      config: ProviderConfig(
        id: 'local_device',
        providerType: 'local_device',
        displayName: 'On-Device SLM',
        modelName: 'local-slm-1b',
        isActive: true,
      ),
    );
    engine = HarnessEngine(
      router: router,
      contextBuilder: contextBuilder,
      modelProvider: modelProvider,
    );
  }

  runApp(HarnessApp(
    database: database,
    keyStorage: keyStorage,
    engine: engine,
    sessionService: sessionService,
    timerService: timerService,
  ));
}

/// Root widget for the Harness application.
///
/// Sets up global state management via [MultiBlocProvider], configures Material 3 theming,
/// and registers the application routing table.
class HarnessApp extends StatefulWidget {
  final AppDatabase? database;
  final KeyStorageService? keyStorage;
  final HarnessEngine? engine;
  final SessionService? sessionService;
  final TimerService? timerService;

  const HarnessApp({
    super.key,
    this.database,
    this.keyStorage,
    this.engine,
    this.sessionService,
    this.timerService,
  });

  @override
  State<HarnessApp> createState() => _HarnessAppState();
}

class _HarnessAppState extends State<HarnessApp> {
  late final AppDatabase _database;
  late final KeyStorageService _keyStorage;
  late final HarnessEngine _engine;
  late final SessionService _sessionService;
  late final TimerService _timerService;
  late final ModelSwitcherBloc _modelSwitcherBloc;
  late final HarnessSessionBloc _harnessSessionBloc;
  late final A2UIEventRouter _a2uiEventRouter;

  @override
  void initState() {
    super.initState();
    _database = widget.database ?? AppDatabase.inMemory();
    _keyStorage = widget.keyStorage ?? KeyStorageService(useInMemoryFallback: true);
    _sessionService = widget.sessionService ??
        SessionService(
          database: _database,
          fileSystem: HarnessFileSystem.instance,
        );
    _timerService =
        widget.timerService ?? TimerService(sessionService: _sessionService);

    if (widget.engine != null) {
      _engine = widget.engine!;
    } else {
      final router = CommandRouter();
      router.registerModule(SkillsModule());
      router.registerModule(StorageModule());
      router.registerModule(A2UIModule());
      router.registerModule(PlatformActionsModule());
      final bridgeSettings = BridgeSettingsService(
        database: _database,
        keyStorage: _keyStorage,
      );
      router.registerModule(WebModule(
        searchProviderFactory: bridgeSettings.createSearchProvider,
        fetchProvider: bridgeSettings.createFetchProvider(),
      ));
      router.registerModule(RunnerModule(
        runnerProviderFactory: bridgeSettings.createRunnerProvider,
      ));
      router.registerModule(TransferModule(
        allowedHostsProvider: bridgeSettings.getAllowedHosts,
        fileSystemProvider: () => HarnessFileSystem.instance,
      ));
      router.registerModule(TimerModule(timerService: _timerService));
      final contextBuilder = ContextBuilder();
      final defaultProvider = ModelProviderFactory.create(
        config: ProviderConfig(
          id: 'local_device',
          providerType: 'local_device',
          displayName: 'On-Device SLM',
          modelName: 'local-slm-1b',
          isActive: true,
        ),
      );
      _engine = HarnessEngine(
        router: router,
        contextBuilder: contextBuilder,
        modelProvider: defaultProvider,
      );
    }

    _modelSwitcherBloc = ModelSwitcherBloc(
      database: _database,
      keyStorage: _keyStorage,
      engine: _engine,
    )..add(const LoadProviderConfigsEvent());

    _a2uiEventRouter = A2UIEventRouter(
      platformActions: PlatformActionsModule(),
    );

    _harnessSessionBloc = HarnessSessionBloc(
      engine: _engine,
      keyStorage: _keyStorage,
      sessionService: _sessionService,
      timerService: _timerService,
      a2uiEventRouter: _a2uiEventRouter,
    );

    NotificationTapRouter.onTap = (payload) {
      if (payload == null || payload.isEmpty) return;
      try {
        final decoded = json.decode(payload);
        if (decoded is Map && decoded['sessionId'] is String) {
          _harnessSessionBloc
              .add(SwitchSessionEvent(decoded['sessionId'] as String));
        }
      } catch (_) {}
    };

    _timerService.start(
      onDue: (timer) =>
          _harnessSessionBloc.add(RunScheduledTimerEvent(timer)),
      onNotificationTap: (sessionId) =>
          _harnessSessionBloc.add(SwitchSessionEvent(sessionId)),
    );
    _timerService.restoreAll();
  }

  @override
  void dispose() {
    NotificationTapRouter.onTap = null;
    _timerService.dispose();
    _modelSwitcherBloc.close();
    _harnessSessionBloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<ModelSwitcherBloc>.value(value: _modelSwitcherBloc),
        BlocProvider<HarnessSessionBloc>.value(value: _harnessSessionBloc),
      ],
      child: MaterialApp(
        title: 'Harness',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF1E88E5),
            brightness: Brightness.light,
          ),
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF1E88E5),
            brightness: Brightness.dark,
          ),
        ),
        themeMode: ThemeMode.system,
        initialRoute: AppRoutes.chat,
        routes: {
          AppRoutes.chat: (_) => const ChatScreen(),
          AppRoutes.settings: (_) => const SettingsScreen(),
          AppRoutes.sessions: (_) => const SessionsScreen(),
          AppRoutes.workspace: (_) => const WorkspaceScreen(),
        },
      ),
    );
  }
}

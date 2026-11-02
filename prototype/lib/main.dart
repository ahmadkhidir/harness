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
import 'data/services/session_service.dart';
import 'modules/skills/skills_module.dart';
import 'modules/storage/storage_module.dart';
import 'presentation/bloc/harness_session_bloc.dart';
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

  const HarnessApp({
    super.key,
    this.database,
    this.keyStorage,
    this.engine,
  });

  @override
  State<HarnessApp> createState() => _HarnessAppState();
}

class _HarnessAppState extends State<HarnessApp> {
  late final AppDatabase _database;
  late final KeyStorageService _keyStorage;
  late final HarnessEngine _engine;
  late final ModelSwitcherBloc _modelSwitcherBloc;
  late final HarnessSessionBloc _harnessSessionBloc;

  @override
  void initState() {
    super.initState();
    _database = widget.database ?? AppDatabase.inMemory();
    _keyStorage = widget.keyStorage ?? KeyStorageService(useInMemoryFallback: true);

    if (widget.engine != null) {
      _engine = widget.engine!;
    } else {
      final router = CommandRouter();
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

    _harnessSessionBloc = HarnessSessionBloc(
      engine: _engine,
      keyStorage: _keyStorage,
      sessionService: SessionService(
        database: _database,
        fileSystem: HarnessFileSystem.instance,
      ),
    );
  }

  @override
  void dispose() {
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

import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/engine/harness_engine.dart';
import '../../data/database/app_database.dart';
import '../../data/secure_storage/key_storage_service.dart';
import '../../providers/model_provider_factory.dart';
import 'model_switcher_event.dart';
import 'model_switcher_state.dart';

/// BLoC managing AI provider configurations, active driver switching, and credential persistence.
///
/// Implements FEAT-002: Pluggable ModelProvider & Runtime Model Switcher.
class ModelSwitcherBloc extends Bloc<ModelSwitcherEvent, ModelSwitcherState> {
  final AppDatabase database;
  final KeyStorageService keyStorage;
  final HarnessEngine? engine;

  ModelSwitcherBloc({
    required this.database,
    required this.keyStorage,
    this.engine,
  }) : super(const ModelSwitcherInitial()) {
    on<LoadProviderConfigsEvent>(_onLoadProviderConfigs);
    on<SelectActiveProviderEvent>(_onSelectActiveProvider);
    on<SaveApiKeyForProviderEvent>(_onSaveApiKey);
    on<UpdateProviderConfigEvent>(_onUpdateProviderConfig);
    on<DeleteApiKeyForProviderEvent>(_onDeleteApiKey);
  }

  Future<void> _onLoadProviderConfigs(
    LoadProviderConfigsEvent event,
    Emitter<ModelSwitcherState> emit,
  ) async {
    emit(const ModelSwitcherLoading());
    try {
      final configs = await database.getAllProviderConfigs();
      final active = await database.getActiveProviderConfig() ?? configs.first;

      final hasKeyMap = <String, bool>{};
      for (final c in configs) {
        hasKeyMap[c.id] = await keyStorage.hasApiKey(c.id);
      }

      if (engine != null) {
        final newProvider = ModelProviderFactory.create(config: active);
        engine!.updateModelProvider(newProvider);
      }

      emit(ModelSwitcherLoaded(
        configs: configs,
        activeConfig: active,
        hasKeyMap: hasKeyMap,
      ));
    } catch (e) {
      emit(ModelSwitcherFailure('Failed to load model configurations: $e'));
    }
  }

  Future<void> _onSelectActiveProvider(
    SelectActiveProviderEvent event,
    Emitter<ModelSwitcherState> emit,
  ) async {
    if (state is! ModelSwitcherLoaded) return;
    final current = state as ModelSwitcherLoaded;

    try {
      await database.setActiveProvider(event.providerId);
      final configs = await database.getAllProviderConfigs();
      final active = configs.firstWhere((c) => c.id == event.providerId);

      if (engine != null) {
        final newProvider = ModelProviderFactory.create(config: active);
        engine!.updateModelProvider(newProvider);
      }

      emit(current.copyWith(
        configs: configs,
        activeConfig: active,
        notificationMessage: 'Active model switched to ${active.displayName}',
      ));
    } catch (e) {
      emit(ModelSwitcherFailure('Failed to switch model provider: $e'));
    }
  }

  Future<void> _onSaveApiKey(
    SaveApiKeyForProviderEvent event,
    Emitter<ModelSwitcherState> emit,
  ) async {
    if (state is! ModelSwitcherLoaded) return;
    final current = state as ModelSwitcherLoaded;

    try {
      await keyStorage.saveApiKey(event.providerId, event.apiKey);
      final updatedMap = Map<String, bool>.from(current.hasKeyMap);
      updatedMap[event.providerId] = true;

      emit(current.copyWith(
        hasKeyMap: updatedMap,
        notificationMessage: 'API Key for ${event.providerId} saved securely.',
      ));
    } catch (e) {
      emit(ModelSwitcherFailure('Failed to save API key securely: $e'));
    }
  }

  Future<void> _onUpdateProviderConfig(
    UpdateProviderConfigEvent event,
    Emitter<ModelSwitcherState> emit,
  ) async {
    if (state is! ModelSwitcherLoaded) return;
    final current = state as ModelSwitcherLoaded;

    try {
      await database.saveProviderConfig(event.config);
      final configs = await database.getAllProviderConfigs();
      final active = await database.getActiveProviderConfig() ?? configs.first;

      if (engine != null && active.id == event.config.id) {
        final newProvider = ModelProviderFactory.create(config: active);
        engine!.updateModelProvider(newProvider);
      }

      emit(current.copyWith(
        configs: configs,
        activeConfig: active,
        notificationMessage: 'Configuration for ${event.config.displayName} updated.',
      ));
    } catch (e) {
      emit(ModelSwitcherFailure('Failed to update provider configuration: $e'));
    }
  }

  Future<void> _onDeleteApiKey(
    DeleteApiKeyForProviderEvent event,
    Emitter<ModelSwitcherState> emit,
  ) async {
    if (state is! ModelSwitcherLoaded) return;
    final current = state as ModelSwitcherLoaded;

    try {
      await keyStorage.deleteApiKey(event.providerId);
      final updatedMap = Map<String, bool>.from(current.hasKeyMap);
      updatedMap[event.providerId] = false;

      emit(current.copyWith(
        hasKeyMap: updatedMap,
        notificationMessage: 'API Key for ${event.providerId} removed.',
      ));
    } catch (e) {
      emit(ModelSwitcherFailure('Failed to remove API key: $e'));
    }
  }
}

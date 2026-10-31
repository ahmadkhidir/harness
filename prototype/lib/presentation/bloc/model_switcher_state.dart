import 'package:equatable/equatable.dart';
import '../../core/models/provider_config.dart';

/// Base state class for [ModelSwitcherBloc].
abstract class ModelSwitcherState extends Equatable {
  const ModelSwitcherState();

  @override
  List<Object?> get props => [];
}

/// Initial uninitialized state.
class ModelSwitcherInitial extends ModelSwitcherState {
  const ModelSwitcherInitial();
}

/// Loading state while querying SQLite or Keystore.
class ModelSwitcherLoading extends ModelSwitcherState {
  const ModelSwitcherLoading();
}

/// Loaded state with all provider configurations and credential existence statuses.
class ModelSwitcherLoaded extends ModelSwitcherState {
  /// All installed provider configurations.
  final List<ProviderConfig> configs;

  /// The currently active provider configuration.
  final ProviderConfig activeConfig;

  /// Map indicating whether an encrypted API key exists for each provider ID.
  final Map<String, bool> hasKeyMap;

  /// Optional feedback notification for the user.
  final String? notificationMessage;

  const ModelSwitcherLoaded({
    required this.configs,
    required this.activeConfig,
    required this.hasKeyMap,
    this.notificationMessage,
  });

  ModelSwitcherLoaded copyWith({
    List<ProviderConfig>? configs,
    ProviderConfig? activeConfig,
    Map<String, bool>? hasKeyMap,
    String? notificationMessage,
  }) {
    return ModelSwitcherLoaded(
      configs: configs ?? this.configs,
      activeConfig: activeConfig ?? this.activeConfig,
      hasKeyMap: hasKeyMap ?? this.hasKeyMap,
      notificationMessage: notificationMessage,
    );
  }

  @override
  List<Object?> get props => [configs, activeConfig, hasKeyMap, notificationMessage];
}

/// Failure state when database or secure storage operation fails.
class ModelSwitcherFailure extends ModelSwitcherState {
  final String errorMessage;

  const ModelSwitcherFailure(this.errorMessage);

  @override
  List<Object?> get props => [errorMessage];
}

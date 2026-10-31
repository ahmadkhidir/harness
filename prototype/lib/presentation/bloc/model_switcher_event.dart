import 'package:equatable/equatable.dart';
import '../../core/models/provider_config.dart';

/// Base event class for [ModelSwitcherBloc].
abstract class ModelSwitcherEvent extends Equatable {
  const ModelSwitcherEvent();

  @override
  List<Object?> get props => [];
}

/// Dispatched to load provider configurations and credential statuses from database and keystore.
class LoadProviderConfigsEvent extends ModelSwitcherEvent {
  const LoadProviderConfigsEvent();
}

/// Dispatched to switch the active inference provider.
class SelectActiveProviderEvent extends ModelSwitcherEvent {
  final String providerId;

  const SelectActiveProviderEvent(this.providerId);

  @override
  List<Object?> get props => [providerId];
}

/// Dispatched to save an encrypted API key for a provider.
class SaveApiKeyForProviderEvent extends ModelSwitcherEvent {
  final String providerId;
  final String apiKey;

  const SaveApiKeyForProviderEvent({
    required this.providerId,
    required this.apiKey,
  });

  @override
  List<Object?> get props => [providerId, apiKey];
}

/// Dispatched to update model parameters (temperature, modelName, customEndpointUrl, headers).
class UpdateProviderConfigEvent extends ModelSwitcherEvent {
  final ProviderConfig config;

  const UpdateProviderConfigEvent(this.config);

  @override
  List<Object?> get props => [config];
}

/// Dispatched to remove an API key from secure storage.
class DeleteApiKeyForProviderEvent extends ModelSwitcherEvent {
  final String providerId;

  const DeleteApiKeyForProviderEvent(this.providerId);

  @override
  List<Object?> get props => [providerId];
}

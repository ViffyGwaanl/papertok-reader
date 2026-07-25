/// Client-stack agnostic AI provider management.
///
/// This package deliberately stops at "which provider, which model, which key,
/// which endpoint". Actually talking to the model (chat, streaming, tool
/// calling) is left to whatever client stack the host app prefers —
/// `langchain_dart`, `openai_dart`, or plain `http`.
library;

export 'src/catalog/ai_provider_presets.dart';
export 'src/config/ai_endpoint_config.dart';
export 'src/keys/api_key_rotation.dart';
export 'src/models/ai_api_key_entry.dart';
export 'src/models/ai_model_capability.dart';
export 'src/models/ai_provider_meta.dart';
export 'src/models/ai_thinking_mode.dart';
export 'src/service/ai_models_service.dart';

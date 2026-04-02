import 'package:anx_reader/service/ai/kairos/kairos_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Holds the current KAIROS hint (if any) for display in the reading UI.
final kairosHintProvider = StateProvider<KairosHint?>((ref) => null);

import 'dart:typed_data';
import 'package:anx_reader/service/tts/models/tts_voice.dart';

abstract class OnlineTtsBackend {
  String get serviceId;
  String get name;
  String get helpText;
  String get helpLink;
  List<String> get configFields;

  Future<Uint8List> speak(String text, String voice, double rate, double pitch);

  Future<List<TtsVoice>> getVoices();

  TtsVoice convertVoiceModel(dynamic voiceData);
}

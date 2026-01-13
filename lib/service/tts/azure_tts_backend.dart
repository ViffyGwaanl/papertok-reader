import 'dart:convert';
import 'dart:typed_data';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/service/tts/models/tts_voice.dart';
import 'package:anx_reader/service/tts/online_tts_backend.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

class AzureTtsBackend extends OnlineTtsBackend {
  static final AzureTtsBackend _instance = AzureTtsBackend._internal();

  factory AzureTtsBackend() {
    return _instance;
  }

  AzureTtsBackend._internal();

  @override
  String get serviceId => 'azure';

  @override
  String get name => 'Azure TTS';

  @override
  String helpText(BuildContext context) =>
      L10n.of(context).settingsNarrateAzureHelpText;

  @override
  String get helpLink => 'https://anx.anxcye.com/docs/tts/azure';

  @override
  List<String> get configFields => ['key', 'region'];

  @override
  Future<Uint8List> speak(
      String text, String voice, double rate, double pitch) async {
    final config = Prefs().getOnlineTtsConfig(serviceId);
    final String? key = config['key'];
    final String? region = config['region'];

    if (key == null || key.isEmpty || region == null || region.isEmpty) {
      throw Exception('Azure TTS config missing (key or region)');
    }

    final String url =
        "https://$region.tts.speech.microsoft.com/cognitiveservices/v1";

    final response = await http.post(
      Uri.parse(url),
      headers: {
        'Ocp-Apim-Subscription-Key': key,
        'Content-Type': 'application/ssml+xml',
        'X-Microsoft-OutputFormat': 'audio-24khz-48kbitrate-mono-mp3',
        'User-Agent': 'AnxReader',
      },
      body: _createSsml(text, voice, rate, pitch),
    );

    if (response.statusCode == 200) {
      return response.bodyBytes;
    } else {
      throw Exception(
          'Azure TTS failed: ${response.statusCode} ${response.body}');
    }
  }

  String _createSsml(String text, String voice, double rate, double pitch) {
    // Azure rate: relative value, e.g. +0.00%
    // AnxReader rate: likely 0.5 to 2.0 range.
    // Need to convert rate/pitch to SSML format if needed.
    // Simple implementation for now.

    // Convert rate (0.2 ~ 3.0) to percentage string
    // 1.0 = 0%
    // 1.5 = +50%
    // 0.5 = -50%
    int ratePercent = ((rate - 1.0) * 100).toInt();
    String rateStr = ratePercent >= 0 ? "+$ratePercent%" : "$ratePercent%";

    // Convert pitch (0.5 ~ 2.0 typically)
    // Similar logic? Let's assume AnxReader passes standard 1.0 float base.
    // If pitch comes from Prefs().ttsPitch which is double.
    int pitchPercent = ((pitch - 1.0) * 100).toInt();
    String pitchStr = pitchPercent >= 0 ? "+$pitchPercent%" : "$pitchPercent%";

    return '''
<speak version='1.0' xml:lang='en-US'>
<voice xml:lang='en-US' xml:gender='Female' name='$voice'>
<prosody rate='$rateStr' pitch='$pitchStr'>
$text
</prosody>
</voice>
</speak>
''';
  }

  @override
  Future<List<TtsVoice>> getVoices() async {
    final config = Prefs().getOnlineTtsConfig(serviceId);
    final String? key = config['key'];
    final String? region = config['region'];

    if (key == null || key.isEmpty || region == null || region.isEmpty) {
      return [];
    }

    final String url =
        "https://$region.tts.speech.microsoft.com/cognitiveservices/voices/list";

    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Ocp-Apim-Subscription-Key': key,
        },
      );

      if (response.statusCode == 200) {
        List<dynamic> data = jsonDecode(response.body);
        return data.map((e) => convertVoiceModel(e)).toList();
      } else {
        throw Exception('Failed to load voices: ${response.statusCode}');
      }
    } catch (e) {
      // Return empty or rethrow?
      rethrow;
    }
  }

  @override
  TtsVoice convertVoiceModel(dynamic voiceData) {
    // Convert Azure voice model to app's standard format
    // Azure format: {"Name": "Microsoft Server Speech Text to Speech Voice (en-US, JennyNeural)", "ShortName": "en-US-JennyNeural", "Gender": "Female", "Locale": "en-US", ...}
    return TtsVoice(
      shortName: voiceData['ShortName'],
      name: voiceData['LocalName'] ?? voiceData['Name'],
      locale: voiceData['Locale'],
      gender: voiceData['Gender'],
      rawData: voiceData,
    );
  }
}

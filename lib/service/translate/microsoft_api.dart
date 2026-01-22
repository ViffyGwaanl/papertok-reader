import 'package:anx_reader/enums/lang_list.dart';
import 'package:anx_reader/service/translate/index.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';

const _urlMicrosoftApi =
    'https://api.cognitive.microsofttranslator.com/translate';

class MicrosoftApiTranslateProvider extends TranslateServiceProvider {
  @override
  TranslateService get service => TranslateService.microsoftApi;

  @override
  String get label => 'Microsoft Azure API';

  @override
  Widget translate(
    String text,
    LangListEnum from,
    LangListEnum to, {
    String? contextText,
  }) {
    return convertStreamToWidget(
      translateStream(text, from, to, contextText: contextText),
    );
  }

  @override
  Stream<String> translateStream(
    String text,
    LangListEnum from,
    LangListEnum to, {
    String? contextText,
  }) async* {
    try {
      final config = getConfig();
      final apiKey = config['api_key']?.toString() ?? '';
      final region = config['region']?.toString() ?? '';

      if (apiKey.isEmpty) {
        yield* Stream.error(
            Exception('Please set Microsoft API Key in settings'));
        return;
      }

      yield "...";

      final params = {
        'api-version': '3.0',
        'from': from == LangListEnum.auto ? '' : mapLanguageCode(from),
        'to': mapLanguageCode(to),
      };
      final body = [
        {'Text': text},
      ];
      final uri = Uri.parse(_urlMicrosoftApi).replace(queryParameters: params);
      final headers = {
        'Content-Type': 'application/json',
        'Ocp-Apim-Subscription-Key': apiKey,
        if (region.isNotEmpty) 'Ocp-Apim-Subscription-Region': region,
      };

      final response = await Dio().post(
        uri.toString(),
        data: body,
        options: Options(headers: headers),
      );

      if (response.statusCode == 200 &&
          response.data is List &&
          response.data.isNotEmpty) {
        yield response.data[0]['translations'][0]['text'];
      } else {
        yield* Stream.error(Exception('Microsoft API Error: ${response.data}'));
      }
    } catch (e) {
      AnxLog.severe("Translate Microsoft API Error: error=$e");
      yield* Stream.error(Exception(e));
    }
  }

  @override
  List<ConfigItem> getConfigItems() {
    return [
      ConfigItem(
        key: 'tip',
        label: 'Tip',
        type: ConfigItemType.tip,
        defaultValue: 'Microsoft Azure Translate has a free quota of 2M chars/month.',
        link: 'https://anx.anxcye.com/docs/translate/azure',
      ),
      ConfigItem(
        key: 'api_key',
        label: 'API Key',
        description: 'Azure Cognitive Services API Key',
        type: ConfigItemType.password,
        defaultValue: '',
      ),
      ConfigItem(
        key: 'region',
        label: 'Region',
        description: 'Azure Region (e.g. global, westus)',
        type: ConfigItemType.text,
        defaultValue: 'global',
      ),
    ];
  }

  @override
  Map<String, dynamic> getConfig() {
    final config = Prefs().getTranslateServiceConfig(service);
    return config ?? {'api_key': '', 'region': 'global'};
  }

  @override
  void saveConfig(Map<String, dynamic> config) {
    Prefs().saveTranslateServiceConfig(service, config);
  }
}

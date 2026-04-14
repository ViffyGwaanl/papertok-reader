import 'dart:convert';

import 'package:papertok_reader/service/ai/tools/base_tool.dart';
import 'package:flutter_test/flutter_test.dart';

class _PlainInput {
  const _PlainInput({required this.value});

  final String value;
}

class _PlainInputTool
    extends RepositoryTool<_PlainInput, Map<String, dynamic>> {
  _PlainInputTool()
      : super(
          name: 'plain_input_tool',
          description: 'Test tool for non-JSON-encodable input objects',
          inputJsonSchema: const {
            'type': 'object',
            'properties': {
              'value': {'type': 'string'},
            },
            'required': ['value'],
          },
        );

  @override
  _PlainInput parseInput(Map<String, dynamic> json) =>
      _PlainInput(value: json['value'] as String);

  @override
  Future<Map<String, dynamic>> run(_PlainInput input) async => {
        'echo': input.value,
      };
}

void main() {
  test(
    'RepositoryTool executes even when input object is not JSON-encodable',
    () async {
      final tool = _PlainInputTool().tool;
      final input = tool.getInputFromJson({'value': 'hello'});

      final result = await tool.invoke(input) as String;
      final decoded = jsonDecode(result) as Map<String, dynamic>;

      expect(decoded['status'], 'ok');
      expect(decoded['name'], 'plain_input_tool');
      expect(decoded['data'], {'echo': 'hello'});
    },
  );
}

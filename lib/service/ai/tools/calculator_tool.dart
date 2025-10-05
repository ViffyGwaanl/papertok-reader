import 'package:anx_reader/utils/log/common.dart';
import 'package:langchain_core/tools.dart';
import 'package:math_expressions/math_expressions.dart';

class _CalculatorInput {
  const _CalculatorInput({required this.expression});

  final String expression;

  factory _CalculatorInput.fromJson(Map<String, dynamic> json) {
    return _CalculatorInput(
      expression: json['expression']?.toString() ?? '',
    );
  }
}

String _evaluateExpression(String expression) {
  AnxLog.info('Evaluating expression: $expression');
  final trimmed = expression.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError('Expression cannot be empty');
  }
  final parser = ShuntingYardParser();
  final parsed = parser.parse(trimmed);
  final result = parsed.evaluate(EvaluationType.REAL, ContextModel());
  return result.toString();
}

final Tool calculatorTool = Tool.fromFunction<_CalculatorInput, String>(
  name: 'calculator',
  description:
      'Use this to evaluate arithmetic expressions with numbers and + - * / ^.',
  inputJsonSchema: const {
    'type': 'object',
    'properties': {
      'expression': {
        'type': 'string',
        'description': 'The arithmetic expression to evaluate.',
      },
    },
    'required': ['expression'],
  },
  func: (input) {
    try {
      return _evaluateExpression(input.expression);
    } catch (e) {
      return 'Error: $e';
    }
  },
  getInputFromJson: _CalculatorInput.fromJson,
);

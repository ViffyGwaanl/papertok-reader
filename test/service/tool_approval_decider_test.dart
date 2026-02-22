import 'package:anx_reader/enums/ai_tool_approval_policy.dart';
import 'package:anx_reader/enums/ai_tool_risk_level.dart';
import 'package:anx_reader/service/ai/tools/tool_approval_decider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ToolApprovalDecider shouldPrompt respects policy', () {
    expect(
      ToolApprovalDecider.shouldPrompt(
        policy: AiToolApprovalPolicy.always,
        riskLevel: AiToolRiskLevel.readOnly,
        forceConfirmDestructive: true,
      ),
      isTrue,
    );

    expect(
      ToolApprovalDecider.shouldPrompt(
        policy: AiToolApprovalPolicy.writesOnly,
        riskLevel: AiToolRiskLevel.readOnly,
        forceConfirmDestructive: true,
      ),
      isFalse,
    );

    expect(
      ToolApprovalDecider.shouldPrompt(
        policy: AiToolApprovalPolicy.writesOnly,
        riskLevel: AiToolRiskLevel.write,
        forceConfirmDestructive: true,
      ),
      isTrue,
    );

    expect(
      ToolApprovalDecider.shouldPrompt(
        policy: AiToolApprovalPolicy.never,
        riskLevel: AiToolRiskLevel.write,
        forceConfirmDestructive: true,
      ),
      isFalse,
    );
  });

  test('ToolApprovalDecider shouldPrompt can force confirm destructive', () {
    expect(
      ToolApprovalDecider.shouldPrompt(
        policy: AiToolApprovalPolicy.never,
        riskLevel: AiToolRiskLevel.destructive,
        forceConfirmDestructive: true,
      ),
      isTrue,
    );

    expect(
      ToolApprovalDecider.shouldPrompt(
        policy: AiToolApprovalPolicy.never,
        riskLevel: AiToolRiskLevel.destructive,
        forceConfirmDestructive: false,
      ),
      isFalse,
    );
  });
}

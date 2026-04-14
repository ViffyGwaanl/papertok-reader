import 'package:papertok_reader/enums/ai_tool_approval_policy.dart';
import 'package:papertok_reader/enums/ai_tool_risk_level.dart';

class ToolApprovalDecider {
  static bool shouldPrompt({
    required AiToolApprovalPolicy policy,
    required AiToolRiskLevel riskLevel,
    required bool forceConfirmDestructive,
  }) {
    if (forceConfirmDestructive && riskLevel == AiToolRiskLevel.destructive) {
      return true;
    }

    return switch (policy) {
      AiToolApprovalPolicy.always => true,
      AiToolApprovalPolicy.writesOnly => riskLevel != AiToolRiskLevel.readOnly,
      AiToolApprovalPolicy.never => false,
    };
  }
}

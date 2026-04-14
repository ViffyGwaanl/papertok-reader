import 'package:papertok_reader/enums/ai_tool_risk_level.dart';

/// Request sent to the UI layer when a tool execution requires user approval.
class ToolApprovalRequest {
  const ToolApprovalRequest({
    required this.toolName,
    required this.displayName,
    required this.description,
    required this.riskLevel,
    required this.toolInput,
    required this.canRemember,
  });

  final String toolName;
  final String displayName;
  final String description;
  final AiToolRiskLevel riskLevel;
  final Map<String, dynamic> toolInput;
  final bool canRemember;
}

/// Result returned by the UI layer after user responds to an approval request.
class ToolApprovalResult {
  const ToolApprovalResult({
    required this.approved,
    required this.remember,
  });

  static const denied = ToolApprovalResult(approved: false, remember: false);

  final bool approved;
  final bool remember;
}

/// Callback signature for tool approval.
///
/// The UI layer provides an implementation (e.g. showing a dialog);
/// the service layer calls it without knowing anything about Flutter widgets.
typedef ToolApprovalDelegate = Future<ToolApprovalResult> Function(
  ToolApprovalRequest request,
);

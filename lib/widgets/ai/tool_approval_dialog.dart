import 'dart:async';
import 'dart:convert';

import 'package:papertok_reader/enums/ai_tool_risk_level.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/main.dart';
import 'package:papertok_reader/service/ai/tool_approval_delegate.dart';
import 'package:papertok_reader/theme/claude_palette.dart';
import 'package:papertok_reader/widgets/common/pt_dialog.dart';
import 'package:flutter/material.dart';

/// UI-side implementation of [ToolApprovalDelegate].
///
/// Shows a dialog asking the user to approve/deny a tool invocation.
/// This keeps all Flutter UI dependencies in the widget layer,
/// while the service layer remains pure Dart.
ToolApprovalDelegate buildToolApprovalDialogDelegate() {
  return _showToolApprovalDialog;
}

const Duration _toolApprovalTimeout = Duration(minutes: 2);

Future<ToolApprovalResult> _showToolApprovalDialog(
  ToolApprovalRequest request,
) async {
  final context = navigatorKey.currentContext;
  if (context == null) {
    return ToolApprovalResult.denied;
  }

  final l10n = L10n.of(context);

  final riskLabel = switch (request.riskLevel) {
    AiToolRiskLevel.readOnly => l10n.aiToolRiskReadOnly,
    AiToolRiskLevel.write => l10n.aiToolRiskWrite,
    AiToolRiskLevel.destructive => l10n.aiToolRiskDestructive,
  };

  final inputPretty =
      const JsonEncoder.withIndent('  ').convert(request.toolInput);

  final nav = navigatorKey.currentState;
  Timer? timeoutTimer;

  try {
    timeoutTimer = Timer(_toolApprovalTimeout, () {
      try {
        if (nav != null && nav.mounted && nav.canPop()) {
          nav.pop(ToolApprovalResult.denied);
        }
      } catch (_) {
        // ignore
      }
    });

    var remember = false;
    final result = await PTDialog.show<ToolApprovalResult>(
          context,
          barrierDismissible: false,
          title: l10n.aiToolApprovalTitle,
          content: StatefulBuilder(
            builder: (context, setDialogState) {
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${l10n.aiToolApprovalToolLabel}: ${request.displayName}',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${l10n.aiToolApprovalRiskLabel}: $riskLabel',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (request.description.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        '${l10n.aiToolApprovalDescriptionLabel}:\n${request.description}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      l10n.aiToolApprovalInputLabel,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: ClaudePalette.elevated(context),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        inputPretty,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(fontFamily: 'monospace'),
                      ),
                    ),
                    if (request.canRemember) ...[
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: remember,
                        onChanged: (v) {
                          setDialogState(() {
                            remember = v ?? false;
                          });
                        },
                        title: Text(
                          l10n.aiToolApprovalRememberForConversation5min,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
          actions: [
            PTDialogAction(
              label: l10n.aiToolApprovalDeny,
              onPressed: () => Navigator.of(context)
                  .pop(ToolApprovalResult.denied),
            ),
            PTDialogAction(
              label: l10n.aiToolApprovalApprove,
              isDefault: true,
              onPressed: () => Navigator.of(context).pop(
                ToolApprovalResult(
                  approved: true,
                  remember: remember,
                ),
              ),
            ),
          ],
        ) ??
        ToolApprovalResult.denied;

    return result;
  } finally {
    timeoutTimer?.cancel();
  }
}

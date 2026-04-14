import 'package:papertok_reader/enums/sync_protocol.dart';
import 'package:papertok_reader/main.dart';
import 'package:papertok_reader/service/sync/sync_connection_tester.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/widgets/common/pt_dialog.dart';
import 'package:flutter/material.dart';

class SyncTestHelper {
  /// Handle simple connection test (ping only)
  static Future<void> handleTestConnection(
    BuildContext context, {
    required SyncProtocol protocol,
    required Map<String, dynamic> config,
    VoidCallback? onTestStart,
    Function(bool success, String message)? onTestComplete,
  }) async {
    PTDialog.show(
      context,
      barrierDismissible: false,
      content: Row(
        children: [
          const CircularProgressIndicator(),
          const SizedBox(width: 20),
          Text(L10n.of(context).testingConnection),
        ],
      ),
    );

    onTestStart?.call();

    try {
      final result = await SyncConnectionTester.testConnection(
        protocol: protocol,
        config: config,
      );

      if (context.mounted) {
        Navigator.of(context).pop();
      }

      _showTestResult(navigatorKey.currentContext!, result);

      onTestComplete?.call(result.isSuccess, result.message);
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop();
      }

      final result = SyncTestResult.failure(
          L10n.of(navigatorKey.currentContext!)
                  .unknownErrorWhenTestingConnection +
              e.toString());
      _showTestResult(navigatorKey.currentContext!, result);

      onTestComplete?.call(false, result.message);
    }
  }

  /// Handle full connection test (create, upload, download, delete)
  static Future<void> handleFullTestConnection(
    BuildContext context, {
    required SyncProtocol protocol,
    required Map<String, dynamic> config,
    VoidCallback? onTestStart,
    Function(bool success, String message)? onTestComplete,
  }) async {
    PTDialog.show(
      context,
      barrierDismissible: false,
      content: Row(
        children: [
          const CircularProgressIndicator(),
          const SizedBox(width: 20),
          Text(L10n.of(context).testingConnection),
        ],
      ),
    );

    onTestStart?.call();

    try {
      final result = await SyncConnectionTester.testFullConnection(
        protocol: protocol,
        config: config,
      );

      if (context.mounted) {
        Navigator.of(context).pop();
      }

      _showTestResult(navigatorKey.currentContext!, result);

      onTestComplete?.call(result.isSuccess, result.message);
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop();
      }

      final result = SyncTestResult.failure(
          L10n.of(navigatorKey.currentContext!)
                  .unknownErrorWhenTestingConnection +
              e.toString());
      _showTestResult(navigatorKey.currentContext!, result);

      onTestComplete?.call(false, result.message);
    }
  }

  static void _showTestResult(BuildContext context, SyncTestResult result) {
    final l10n = L10n.of(context);
    PTDialog.show(
      context,
      title: result.isSuccess ? l10n.commonSuccess : l10n.commonFailed,
      message: result.message,
      actions: [
        PTDialogAction(
          label: l10n.commonOk,
          isDefault: true,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

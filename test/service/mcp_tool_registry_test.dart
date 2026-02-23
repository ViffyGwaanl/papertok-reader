import 'package:anx_reader/service/mcp/mcp_tool_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('McpToolRegistry buildCachedTools does not crash',
      (tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});

    // Allow Prefs async init to complete.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }

    final result = McpToolRegistry.buildCachedTools();
    expect(result.tools, isA<List>());
  });
}

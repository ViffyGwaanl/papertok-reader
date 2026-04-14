import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/page/memory/memory_home_page.dart';
import 'package:anx_reader/service/memory/memory_pending_count_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders INBOX / TODAY / LONG-TERM section headers',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // Stub out the FutureProvider so no real FS access occurs in tests.
          memoryPendingCountProvider.overrideWith((_) async => 0),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: const MemoryHomePage(),
        ),
      ),
    );
    // Allow the L10n delegates and async provider to settle.
    await tester.pump(const Duration(milliseconds: 50));

    // Section headers are rendered uppercased via title.toUpperCase() inside
    // _SectionHeader, so the matchers compare to the upper-case form.
    expect(find.textContaining('INBOX', findRichText: true), findsOneWidget);
    expect(find.textContaining('TODAY', findRichText: true), findsOneWidget);
    expect(find.textContaining('LONG-TERM', findRichText: true), findsOneWidget);
  });
}

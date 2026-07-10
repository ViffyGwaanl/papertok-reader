import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/providers/sync.dart';

void main() {
  test('syncProvider builds the Sync singleton so its state is attached', () {
    // Raw Sync() calls before any provider watcher used to hit
    // LateInitializationError (unattached Notifier state); all call sites
    // now read through syncProvider.notifier, which this test locks in.
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(syncProvider.notifier);
    expect(identical(notifier, Sync()), isTrue,
        reason: 'generated provider must attach the manual singleton');

    // Reading state through the container must not throw.
    expect(container.read(syncProvider).isSyncing, isFalse);
  });
}

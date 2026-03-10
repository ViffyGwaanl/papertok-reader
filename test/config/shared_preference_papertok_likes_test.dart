import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/papertok/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  test('paper tok likes persist ids and snapshots together', () {
    final card = PaperTokCard(
      id: 42,
      title: 'PaperTok title',
      displayTitle: 'Display title',
      extract: 'A compact summary',
      day: '2026-03-10',
      thumbnail: 'https://example.com/thumb.jpg',
      thumbnails: const ['https://example.com/thumb-1.jpg'],
      url: 'https://example.com/paper',
    );

    Prefs().setPaperTokLiked(card.id, true, card: card);

    expect(Prefs().paperTokLikedPaperIds, [42]);
    final snapshots = Prefs().paperTokLikedSnapshots;
    expect(snapshots, hasLength(1));
    expect(snapshots.first.id, 42);
    expect(snapshots.first.displayTitle, 'Display title');
    expect(snapshots.first.extract, 'A compact summary');

    Prefs().setPaperTokLiked(card.id, false);

    expect(Prefs().paperTokLikedPaperIds, isEmpty);
    expect(Prefs().paperTokLikedSnapshots, isEmpty);
  });

  test('paper tok liked snapshot can be queried by paper id', () {
    final card = PaperTokCard(
      id: 7,
      title: 'Another title',
      extract: 'Another extract',
    );

    Prefs().savePaperTokLikedSnapshot(card, likedAtMs: 123456);

    final snapshot = Prefs().getPaperTokLikedSnapshot(7);
    expect(snapshot, isNotNull);
    expect(snapshot!.likedAtMs, 123456);
    expect(snapshot.toCard().id, 7);
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/utils/book_file_types.dart';

void main() {
  test('cbz is an allowed import extension', () {
    expect(kAllowBookExtensions, contains('cbz'));
  });

  test('cbz magic-byte validation accepts zip and rejects garbage', () async {
    final dir = await Directory.systemTemp.createTemp('cbz_test');
    addTearDown(() => dir.delete(recursive: true));

    final zipLike = File('${dir.path}/ok.cbz');
    await zipLike.writeAsBytes([0x50, 0x4B, 0x03, 0x04, 0x00, 0x00]);
    expect(await validateBookMagicBytes(zipLike), isNull);

    final garbage = File('${dir.path}/bad.cbz');
    await garbage.writeAsBytes([0x00, 0x01, 0x02, 0x03]);
    expect(await validateBookMagicBytes(garbage), isNotNull);
  });
}

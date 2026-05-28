import 'dart:typed_data';

import 'package:papertok_reader/service/rag/ai_vector_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AiVectorCodec round-trips float32 vectors', () {
    final encoded = AiVectorCodec.encodeFloat32(const [1.25, -2.5, 0]);

    expect(encoded, isA<Uint8List>());
    expect(encoded.length, 12);
    expect(AiVectorCodec.decodeFloat32(encoded), [1.25, -2.5, 0]);
  });

  test('AiVectorCodec rejects malformed float32 blobs', () {
    expect(AiVectorCodec.decodeFloat32(Uint8List(3)), isNull);
  });
}

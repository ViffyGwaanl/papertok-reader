import 'dart:typed_data';
import 'dart:convert';

class AiVectorCodec {
  const AiVectorCodec._();

  static Uint8List encodeFloat32(List<double> vector) {
    final bytes = ByteData(vector.length * 4);
    for (var i = 0; i < vector.length; i++) {
      bytes.setFloat32(i * 4, vector[i], Endian.little);
    }
    return bytes.buffer.asUint8List();
  }

  static List<double>? decodeFloat32(Object? blob) {
    if (blob == null) return null;

    final Uint8List bytes;
    if (blob is Uint8List) {
      bytes = blob;
    } else if (blob is List<int>) {
      bytes = Uint8List.fromList(blob);
    } else {
      return null;
    }

    if (bytes.isEmpty || bytes.length % 4 != 0) return null;

    final data = ByteData.sublistView(bytes);
    return List<double>.generate(
      bytes.length ~/ 4,
      (i) => data.getFloat32(i * 4, Endian.little),
      growable: false,
    );
  }

  static List<double>? decodeJson(String jsonText) {
    try {
      final decoded = jsonDecode(jsonText);
      if (decoded is! List) return null;
      return decoded
          .whereType<num>()
          .map((e) => e.toDouble())
          .toList(growable: false);
    } catch (_) {
      return null;
    }
  }

  static List<double>? decodeVector({
    Object? blob,
    String? jsonText,
  }) {
    final fromBlob = decodeFloat32(blob);
    if (fromBlob != null && fromBlob.isNotEmpty) return fromBlob;
    final json = jsonText?.trim();
    if (json == null || json.isEmpty) return null;
    return decodeJson(json);
  }
}

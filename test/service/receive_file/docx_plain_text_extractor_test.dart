import 'dart:convert';
import 'dart:typed_data';

import 'package:anx_reader/service/receive_file/docx_plain_text_extractor.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _buildDocxBytes({
  required String documentXml,
  List<ArchiveFile> extraFiles = const [],
}) {
  // This is not a fully-valid Word document, but it is sufficient for our
  // extractor which only needs word/document.xml.
  const contentTypes =
      """<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>
<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">
  <Default Extension=\"xml\" ContentType=\"application/xml\"/>
  <Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/>
</Types>
""";

  final archive = Archive()
    ..addFile(
      ArchiveFile(
        '[Content_Types].xml',
        contentTypes.length,
        utf8.encode(contentTypes),
      ),
    )
    ..addFile(
      ArchiveFile(
        'word/document.xml',
        documentXml.length,
        utf8.encode(documentXml),
      ),
    );

  for (final f in extraFiles) {
    archive.addFile(f);
  }

  final zipped = ZipEncoder().encode(archive);
  if (zipped == null) {
    throw StateError('failed to encode zip');
  }
  return Uint8List.fromList(zipped);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DocxPlainTextExtractor', () {
    test('extracts <w:t>, <w:tab/>, <w:br/>, paragraph breaks; unescapes', () {
      const xml =
          """<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>
<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">
  <w:body>
    <w:p>
      <w:r><w:t>Hello &amp; &lt;world&gt;</w:t></w:r>
      <w:r><w:tab/></w:r>
      <w:r><w:t>Tab</w:t></w:r>
    </w:p>
    <w:p>
      <w:r>
        <w:t>Line1</w:t>
        <w:br/>
        <w:t>Line2</w:t>
      </w:r>
    </w:p>
  </w:body>
</w:document>
""";

      final docx = _buildDocxBytes(documentXml: xml);
      final res = DocxPlainTextExtractor.extract(docx);

      expect(res.truncated, isFalse);
      expect(res.text, 'Hello & <world>\tTab\n\nLine1\nLine2');
    });

    test('truncates output to maxChars', () {
      final longText = List.filled(2000, 'a').join();
      final xml =
          '<w:document xmlns:w="x"><w:body><w:p><w:r><w:t>$longText</w:t></w:r></w:p></w:body></w:document>';

      final docx = _buildDocxBytes(documentXml: xml);
      final res = DocxPlainTextExtractor.extract(docx, maxChars: 10);

      expect(res.truncated, isTrue);
      expect(res.text.length, 10);
      expect(res.text, 'aaaaaaaaaa');
    });

    test('rejects missing word/document.xml', () {
      final archive = Archive()..addFile(ArchiveFile('a.txt', 1, [0x61]));
      final zipped = ZipEncoder().encode(archive)!;

      expect(
        () => DocxPlainTextExtractor.extract(Uint8List.fromList(zipped)),
        throwsA(isA<FormatException>()),
      );
    });

    test('zip bomb: entry count limit', () {
      final xml =
          '<w:document xmlns:w="x"><w:body><w:p><w:r><w:t>x</w:t></w:r></w:p></w:body></w:document>';

      final extra = <ArchiveFile>[];
      for (var i = 0; i < 10; i++) {
        extra.add(ArchiveFile('word/extra_$i.bin', 1, [0x00]));
      }

      final docx = _buildDocxBytes(documentXml: xml, extraFiles: extra);

      expect(
        () => DocxPlainTextExtractor.extract(
          docx,
          zipLimits: const DocxZipLimits(maxEntries: 5),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('zip bomb: total uncompressed size limit', () {
      final xml =
          '<w:document xmlns:w="x"><w:body><w:p><w:r><w:t>x</w:t></w:r></w:p></w:body></w:document>';

      final big = Uint8List.fromList(List.filled(1024, 0x41));
      final docx = _buildDocxBytes(
        documentXml: xml,
        extraFiles: [ArchiveFile('word/big.bin', big.length, big)],
      );

      expect(
        () => DocxPlainTextExtractor.extract(
          docx,
          zipLimits: const DocxZipLimits(maxTotalUncompressedBytes: 50),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('zip bomb: suspicious compression ratio limit', () {
      final xml =
          '<w:document xmlns:w="x"><w:body><w:p><w:r><w:t>x</w:t></w:r></w:p></w:body></w:document>';

      // Highly-compressible data; should yield a high uncompressed/compressed ratio.
      final repetitive = utf8.encode(List.filled(200000, 'a').join());
      final docx = _buildDocxBytes(
        documentXml: xml,
        extraFiles: [
          ArchiveFile('word/repetitive.txt', repetitive.length, repetitive),
        ],
      );

      expect(
        () => DocxPlainTextExtractor.extract(
          docx,
          zipLimits: const DocxZipLimits(maxCompressionRatio: 20.0),
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/models/source_ref.dart';

void main() {
  group('SourceRef', () {
    test('enum wire values round-trip with safe defaults', () {
      expect(
        SourceRefKind.fromString('library-rag'),
        SourceRefKind.libraryRag,
      );
      expect(SourceRefKind.fromString('missing'), SourceRefKind.unknown);

      expect(
        AiOutputOwnership.aiGeneratedDraft.asString,
        'AI-generated-draft',
      );
      expect(
        AiOutputOwnership.fromString('AI-generated-approved'),
        AiOutputOwnership.aiGeneratedApproved,
      );
      expect(
        AiOutputOwnership.fromString('missing'),
        AiOutputOwnership.aiGeneratedDraft,
      );

      expect(
        AiProvenanceDataClass.fromString('user-asset'),
        AiProvenanceDataClass.userAsset,
      );
      expect(
        AiProvenanceDataClass.fromString('missing'),
        AiProvenanceDataClass.unknown,
      );
    });

    test('safe json caps snippets and never derives hash from chunkId alone',
        () {
      final longText = List.filled(700, 'a').join();
      final ref = SourceRef(
        bookId: 7,
        href: 'Text/ch1.xhtml',
        chunkId: 99,
        sourceTextSnippet: longText,
        sourceKind: SourceRefKind.libraryRag,
      );

      final json = ref.toSafeJson();
      final snippet = json['sourceTextSnippet'] as String;
      expect(snippet.length, lessThanOrEqualTo(SourceRef.maxSnippetChars));
      expect(snippet.endsWith('...'), true);
      expect(json, containsPair('chunkId', 99));
      expect(json, containsPair('derivedCacheHint', true));
      expect(json['sourceHash'], isA<String>());

      final chunkOnly = SourceRef(
        chunkId: 123,
        sourceKind: SourceRefKind.libraryRag,
      );
      expect(chunkOnly.sourceHash, isNull);
    });

    test('hash-only fingerprints are not formal evidence', () {
      final hashOnly = SourceRef(
        sourceTextSnippet: 'Detached model text',
        sourceKind: SourceRefKind.external,
      );

      expect(hashOnly.sourceHash, isNotNull);
      expect(hashOnly.hasHashOnlyFingerprint, isTrue);
      expect(hashOnly.hasEvidence, isFalse);
      expect(hashOnly.canJumpBack, isFalse);

      final unavailable = SourceRef(
        sourceTextSnippet: 'Detached model text',
        sourceKind: SourceRefKind.external,
        unavailableReason: 'external source has no reader location',
      );
      expect(unavailable.hasEvidence, isTrue);
      expect(unavailable.hasUnavailableReason, isTrue);
      expect(
        unavailable.toSafeJson()['unavailableReason'],
        'external source has no reader location',
      );
    });

    test('jump links must be valid reader source targets to count as evidence',
        () {
      final malformed = SourceRef(
        jumpLink: 'not a uri',
        sourceKind: SourceRefKind.external,
      );
      final wrongHost = SourceRef(
        jumpLink: 'paperreader://library/open?bookId=1&href=Text%2Fch.xhtml',
        sourceKind: SourceRefKind.external,
      );
      final noTarget = SourceRef(
        jumpLink: 'paperreader://reader/open?bookId=1',
        sourceKind: SourceRefKind.external,
      );
      final valid = SourceRef(
        jumpLink: 'paperreader://reader/open?bookId=1&href=Text%2Fch.xhtml',
        sourceKind: SourceRefKind.external,
      );

      expect(malformed.canJumpBack, false);
      expect(malformed.hasEvidence, false);
      expect(wrongHost.canJumpBack, false);
      expect(wrongHost.hasEvidence, false);
      expect(noTarget.canJumpBack, false);
      expect(noTarget.hasEvidence, false);
      expect(valid.canJumpBack, true);
      expect(valid.hasEvidence, true);
    });

    test('fromJson tolerates missing and unknown fields', () {
      final ref = SourceRef.fromJson(const {
        'bookId': 3,
        'href': 'Text/ch2.xhtml',
        'sourceKind': 'future-kind',
        'unexpected': 'ignored',
      });

      expect(ref.bookId, 3);
      expect(ref.href, 'Text/ch2.xhtml');
      expect(ref.sourceKind, SourceRefKind.unknown);
      expect(ref.hasBookAnchor, true);
    });
  });

  group('AiProvenance', () {
    test('empty provenance defaults to draft derived cache', () {
      const provenance = AiProvenance();
      expect(provenance.ownership, AiOutputOwnership.aiGeneratedDraft);
      expect(provenance.dataClass, AiProvenanceDataClass.derivedCache);
      expect(provenance.hasEvidence, false);
      expect(provenance.canEnterFormalKnowledge, false);
    });

    test('approved user asset with evidence can enter formal knowledge', () {
      final provenance = AiProvenance(
        ownership: AiOutputOwnership.aiGeneratedApproved,
        dataClass: AiProvenanceDataClass.userAsset,
        sourceRefs: [
          SourceRef(
            bookId: 1,
            href: 'Text/ch.xhtml',
            jumpLink: 'paperreader://reader/open?bookId=1&href=Text%2Fch.xhtml',
            sourceKind: SourceRefKind.reader,
          ),
        ],
      );

      final restored = AiProvenance.fromJson(provenance.toSafeJson());
      expect(restored.hasEvidence, true);
      expect(restored.canEnterFormalKnowledge, true);
      expect(restored.sourceRefs.single.jumpLink, startsWith('paperreader://'));
    });

    test('approved unknown data class still waits outside formal knowledge',
        () {
      final provenance = AiProvenance(
        ownership: AiOutputOwnership.aiGeneratedApproved,
        sourceRefs: [
          SourceRef(
            bookId: 1,
            href: 'Text/ch.xhtml',
            sourceKind: SourceRefKind.reader,
          ),
        ],
        dataClass: AiProvenanceDataClass.unknown,
      );

      expect(provenance.hasEvidence, true);
      expect(provenance.canEnterFormalKnowledge, false);
    });
  });
}

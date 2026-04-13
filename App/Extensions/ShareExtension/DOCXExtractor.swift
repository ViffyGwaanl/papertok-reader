import Foundation
import PTCore

#if canImport(Compression)
import Compression
#endif

/// Extracts plain text from `.docx` (OOXML) documents without any third-party
/// ZIP library. A `.docx` file is a ZIP archive containing
/// `word/document.xml`; this utility parses the ZIP central directory,
/// inflates the `document.xml` entry using `Compression.framework`, and
/// collects the text inside every `<w:t>` element via `XMLParser`.
public enum DOCXExtractor {
    public enum ExtractError: Error, LocalizedError {
        case cannotReadFile
        case notAZipFile
        case documentXMLNotFound
        case inflateFailed
        case xmlParseFailed(Error?)

        public var errorDescription: String? {
            switch self {
            case .cannotReadFile:
                return AppLocalization.string(
                    "errors.share.docx.read_failed",
                    value: "Could not read DOCX file."
                )
            case .notAZipFile:
                return AppLocalization.string(
                    "errors.share.docx.invalid_zip",
                    value: "File is not a valid ZIP archive."
                )
            case .documentXMLNotFound:
                return AppLocalization.string(
                    "errors.share.docx.document_xml_missing",
                    value: "word/document.xml was not found in the DOCX archive."
                )
            case .inflateFailed:
                return AppLocalization.string(
                    "errors.share.docx.inflate_failed",
                    value: "Failed to decompress word/document.xml."
                )
            case .xmlParseFailed(let error):
                return AppLocalization.format(
                    "errors.share.docx.parse_failed_format",
                    "Failed to parse word/document.xml: %@",
                    error?.localizedDescription ?? AppLocalization.string("common.unknown", value: "unknown")
                )
            }
        }
    }

    /// Extract the concatenated text from a `.docx` file at the given URL.
    public static func extractText(from url: URL) throws -> String {
        guard let data = try? Data(contentsOf: url) else {
            throw ExtractError.cannotReadFile
        }

        let xmlData = try extractDocumentXML(from: data)
        return try parseText(from: xmlData)
    }

    // MARK: - ZIP parsing

    /// Locates and inflates `word/document.xml` from a ZIP archive in memory.
    internal static func extractDocumentXML(from data: Data) throws -> Data {
        let entries = try readCentralDirectory(data)
        guard let entry = entries.first(where: { $0.name == "word/document.xml" }) else {
            throw ExtractError.documentXMLNotFound
        }
        return try readEntry(entry, from: data)
    }

    private struct ZipEntry {
        let name: String
        let compressionMethod: UInt16
        let compressedSize: UInt32
        let uncompressedSize: UInt32
        let localHeaderOffset: UInt32
    }

    private static func readCentralDirectory(_ data: Data) throws -> [ZipEntry] {
        // Search end-of-central-directory record (signature 0x06054b50)
        let eocdSignature: [UInt8] = [0x50, 0x4b, 0x05, 0x06]
        let maxCommentSize = 65_535
        let minEOCDLength = 22
        guard data.count >= minEOCDLength else { throw ExtractError.notAZipFile }

        let searchStart = max(0, data.count - (maxCommentSize + minEOCDLength))
        var eocdOffset: Int = -1
        var i = data.count - minEOCDLength
        while i >= searchStart {
            if data[i] == eocdSignature[0]
                && data[i + 1] == eocdSignature[1]
                && data[i + 2] == eocdSignature[2]
                && data[i + 3] == eocdSignature[3] {
                eocdOffset = i
                break
            }
            i -= 1
        }
        guard eocdOffset >= 0 else { throw ExtractError.notAZipFile }

        let totalEntries = Int(readUInt16(data, eocdOffset + 10))
        let centralDirSize = Int(readUInt32(data, eocdOffset + 12))
        let centralDirOffset = Int(readUInt32(data, eocdOffset + 16))
        guard centralDirOffset + centralDirSize <= data.count else {
            throw ExtractError.notAZipFile
        }

        var entries: [ZipEntry] = []
        var cursor = centralDirOffset
        for _ in 0..<totalEntries {
            guard cursor + 46 <= data.count else { throw ExtractError.notAZipFile }
            let signature = readUInt32(data, cursor)
            guard signature == 0x02014b50 else { throw ExtractError.notAZipFile }

            let compressionMethod = readUInt16(data, cursor + 10)
            let compressedSize = readUInt32(data, cursor + 20)
            let uncompressedSize = readUInt32(data, cursor + 24)
            let fileNameLength = Int(readUInt16(data, cursor + 28))
            let extraFieldLength = Int(readUInt16(data, cursor + 30))
            let commentLength = Int(readUInt16(data, cursor + 32))
            let localHeaderOffset = readUInt32(data, cursor + 42)

            let nameStart = cursor + 46
            guard nameStart + fileNameLength <= data.count else { throw ExtractError.notAZipFile }
            let nameData = data.subdata(in: nameStart..<(nameStart + fileNameLength))
            let name = String(data: nameData, encoding: .utf8) ?? ""

            entries.append(ZipEntry(
                name: name,
                compressionMethod: compressionMethod,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                localHeaderOffset: localHeaderOffset
            ))

            cursor = nameStart + fileNameLength + extraFieldLength + commentLength
        }
        return entries
    }

    private static func readEntry(_ entry: ZipEntry, from data: Data) throws -> Data {
        let offset = Int(entry.localHeaderOffset)
        guard offset + 30 <= data.count else { throw ExtractError.notAZipFile }
        let signature = readUInt32(data, offset)
        guard signature == 0x04034b50 else { throw ExtractError.notAZipFile }

        let fileNameLength = Int(readUInt16(data, offset + 26))
        let extraFieldLength = Int(readUInt16(data, offset + 28))
        let dataStart = offset + 30 + fileNameLength + extraFieldLength
        let compressedLength = Int(entry.compressedSize)
        guard dataStart + compressedLength <= data.count else { throw ExtractError.notAZipFile }

        let compressed = data.subdata(in: dataStart..<(dataStart + compressedLength))

        switch entry.compressionMethod {
        case 0:
            return compressed
        case 8:
            #if canImport(Compression)
            return try inflate(compressed, expectedSize: Int(entry.uncompressedSize))
            #else
            throw ExtractError.inflateFailed
            #endif
        default:
            throw ExtractError.inflateFailed
        }
    }

    #if canImport(Compression)
    private static func inflate(_ data: Data, expectedSize: Int) throws -> Data {
        let capacity = max(expectedSize, data.count * 8 + 1024)
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        defer { destination.deallocate() }

        let decoded: Int = data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return compression_decode_buffer(
                destination,
                capacity,
                base,
                data.count,
                nil,
                COMPRESSION_ZLIB
            )
        }

        guard decoded > 0 else { throw ExtractError.inflateFailed }
        return Data(bytes: destination, count: decoded)
    }
    #endif

    // MARK: - XML parsing

    private static func parseText(from xmlData: Data) throws -> String {
        let delegate = DocumentTextParserDelegate()
        let parser = XMLParser(data: xmlData)
        parser.shouldProcessNamespaces = false
        parser.delegate = delegate
        guard parser.parse() else {
            throw ExtractError.xmlParseFailed(parser.parserError)
        }
        return delegate.finalized()
    }

    // MARK: - Bytes

    private static func readUInt16(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func readUInt32(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}

private final class DocumentTextParserDelegate: NSObject, XMLParserDelegate {
    private var isCollectingText = false
    private var paragraphs: [String] = []
    private var currentParagraph: String = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch elementName {
        case "w:t":
            isCollectingText = true
        case "w:br", "w:tab":
            currentParagraph.append(elementName == "w:tab" ? "\t" : " ")
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard isCollectingText else { return }
        currentParagraph.append(string)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "w:t":
            isCollectingText = false
        case "w:p":
            paragraphs.append(currentParagraph)
            currentParagraph = ""
        default:
            break
        }
    }

    func finalized() -> String {
        if currentParagraph.isEmpty == false {
            paragraphs.append(currentParagraph)
            currentParagraph = ""
        }
        return paragraphs.joined(separator: "\n")
    }
}

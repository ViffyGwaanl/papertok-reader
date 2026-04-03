import Testing
import Foundation
@testable import PTNetworking

@Suite("WebDAVClient")
struct WebDAVClientTests {
    @Test("Parses PROPFIND multistatus XML response")
    func parsePropfindXML() throws {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <D:multistatus xmlns:D="DAV:">
          <D:response>
            <D:href>/paper_reader/</D:href>
            <D:propstat>
              <D:prop>
                <D:displayname>paper_reader</D:displayname>
                <D:resourcetype><D:collection/></D:resourcetype>
                <D:getcontentlength>0</D:getcontentlength>
              </D:prop>
              <D:status>HTTP/1.1 200 OK</D:status>
            </D:propstat>
          </D:response>
          <D:response>
            <D:href>/paper_reader/settings.json</D:href>
            <D:propstat>
              <D:prop>
                <D:displayname>settings.json</D:displayname>
                <D:resourcetype/>
                <D:getcontentlength>1234</D:getcontentlength>
                <D:getcontenttype>application/json</D:getcontenttype>
                <D:getetag>"abc123"</D:getetag>
                <D:getlastmodified>Thu, 03 Apr 2026 12:00:00 GMT</D:getlastmodified>
              </D:prop>
              <D:status>HTTP/1.1 200 OK</D:status>
            </D:propstat>
          </D:response>
        </D:multistatus>
        """
        let files = WebDAVXMLParser.parseMultistatus(xml.data(using: .utf8)!)
        #expect(files.count == 2)

        let dir = files[0]
        #expect(dir.name == "paper_reader")
        #expect(dir.isDirectory == true)

        let file = files[1]
        #expect(file.name == "settings.json")
        #expect(file.isDirectory == false)
        #expect(file.size == 1234)
        #expect(file.mimeType == "application/json")
        #expect(file.eTag == "\"abc123\"")
    }

    @Test("Basic auth header is correctly generated")
    func basicAuthHeader() {
        let auth = WebDAVAuth.basic(user: "admin", password: "secret")
        let header = auth.authorizationHeader()
        let expected = "Basic " + Data("admin:secret".utf8).base64EncodedString()
        #expect(header == expected)
    }

    @Test("URL path encoding handles spaces")
    func pathEncoding() {
        let encoded = WebDAVClient.encodePath("/paper reader/my file.epub")
        #expect(encoded == "/paper%20reader/my%20file.epub")
        #expect(!encoded.contains(" "))
    }
}

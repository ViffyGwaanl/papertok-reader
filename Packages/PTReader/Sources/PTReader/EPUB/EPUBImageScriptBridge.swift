#if canImport(UIKit)
import Foundation
import WebKit

public enum EPUBImageScriptBridge {
    public static let messageHandlerName = "paperTokReaderImageTap"

    public static func makeUserScript() -> WKUserScript {
        WKUserScript(
            source: """
            (() => {
              if (window.__paperTokReaderImageTapInstalled) {
                return;
              }
              window.__paperTokReaderImageTapInstalled = true;

              document.addEventListener('click', event => {
                const image = event.target instanceof Element ? event.target.closest('img') : null;
                if (!image) {
                  return;
                }

                event.preventDefault();
                event.stopPropagation();

                try {
                  const canvas = document.createElement('canvas');
                  const width = image.naturalWidth || image.width;
                  const height = image.naturalHeight || image.height;
                  if (!width || !height) {
                    return;
                  }

                  canvas.width = width;
                  canvas.height = height;
                  const context = canvas.getContext('2d');
                  if (!context) {
                    return;
                  }

                  context.drawImage(image, 0, 0, width, height);
                  const dataURL = canvas.toDataURL('image/png');
                  window.webkit.messageHandlers.\(messageHandlerName).postMessage({
                    dataURL: dataURL,
                    alt: image.alt || '',
                    title: image.title || '',
                    sourceURL: image.currentSrc || image.src || ''
                  });
                } catch (_) {
                }
              }, true);
            })();
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
    }

    public static func asset(from body: Any) -> ReaderImageAsset? {
        guard let payload = body as? [String: Any],
              let dataURL = payload["dataURL"] as? String,
              let (mimeType, data) = decodeDataURL(dataURL) else {
            return nil
        }

        return ReaderImageAsset(
            data: data,
            mimeType: mimeType,
            title: payload["title"] as? String,
            altText: payload["alt"] as? String,
            sourceURL: payload["sourceURL"] as? String
        )
    }

    private static func decodeDataURL(_ string: String) -> (String, Data)? {
        guard string.hasPrefix("data:"),
              let separatorIndex = string.range(of: ",")?.lowerBound else {
            return nil
        }

        let metadata = String(string[string.index(string.startIndex, offsetBy: 5)..<separatorIndex])
        let payload = String(string[string.index(after: separatorIndex)...])
        let components = metadata.split(separator: ";")
        guard let mimeType = components.first, metadata.contains("base64"),
              let data = Data(base64Encoded: payload) else {
            return nil
        }
        return (String(mimeType), data)
    }
}
#endif

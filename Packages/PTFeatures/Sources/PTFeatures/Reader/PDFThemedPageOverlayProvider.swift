#if canImport(UIKit)
@preconcurrency import CoreImage
@preconcurrency import PDFKit
import UIKit

/// iOS PDF theme tint strategy: a `PDFPageOverlayViewProvider` that renders a
/// Core Image filtered raster of the page over the page itself. On macOS the
/// reader uses `CALayer.filters` instead (see `NativePDFView` AppKit branch);
/// that path is a no-op on UIKit because `CALayer.filters` is a private SPI
/// with no visual effect, so the iOS reader cannot use it.
@available(iOS 16.0, *)
final class PDFThemedPageOverlayProvider: NSObject, PDFPageOverlayViewProvider {
    var tintKind: PDFThemeTintKind = .none {
        didSet {
            guard oldValue != tintKind else { return }
            for overlay in activeOverlays.values {
                overlay.updateTintKind(tintKind)
            }
        }
    }

    private var activeOverlays: [ObjectIdentifier: PDFThemedPageOverlayView] = [:]

    var activeOverlayCount: Int { activeOverlays.count }

    func overlayView(forPageIdentifier identifier: ObjectIdentifier) -> PDFThemedPageOverlayView? {
        activeOverlays[identifier]
    }

    func pdfView(_ pdfView: PDFView, overlayViewFor page: PDFPage) -> UIView? {
        guard tintKind != .none else { return nil }
        let overlay = PDFThemedPageOverlayView(page: page, tintKind: tintKind)
        activeOverlays[ObjectIdentifier(page)] = overlay
        return overlay
    }

    func pdfView(_ pdfView: PDFView, willDisplayOverlayView overlayView: UIView, for page: PDFPage) {
        // no-op; creation already installs tracking
    }

    func pdfView(_ pdfView: PDFView, willEndDisplayingOverlayView overlayView: UIView, for page: PDFPage) {
        activeOverlays.removeValue(forKey: ObjectIdentifier(page))
    }
}

@available(iOS 16.0, *)
final class PDFThemedPageOverlayView: UIView {
    private let page: PDFPage
    private(set) var tintKind: PDFThemeTintKind
    private let imageView = UIImageView()
    private var renderToken: Int = 0
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 32
        return cache
    }()

    init(page: PDFPage, tintKind: PDFThemeTintKind) {
        self.page = page
        self.tintKind = tintKind
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        imageView.contentMode = .scaleAspectFit
        imageView.frame = bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(imageView)
        scheduleRefresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    func updateTintKind(_ newKind: PDFThemeTintKind) {
        guard newKind != tintKind else { return }
        tintKind = newKind
        scheduleRefresh()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if imageView.image == nil {
            scheduleRefresh()
        }
    }

    private func scheduleRefresh() {
        guard tintKind != .none else {
            imageView.image = nil
            return
        }
        renderToken &+= 1
        let token = renderToken
        let page = self.page
        let kind = self.tintKind
        let bounds = page.bounds(for: .mediaBox)
        let cacheKey = Self.cacheKey(page: page, kind: kind, bounds: bounds)
        if let cached = Self.cache.object(forKey: cacheKey) {
            imageView.image = cached
            return
        }
        let screenScale = window?.screen.scale ?? UIScreen.main.scale
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let image = Self.renderTintedImage(page: page, kind: kind, scale: screenScale)
            DispatchQueue.main.async {
                guard let self else { return }
                guard self.renderToken == token, self.tintKind == kind else { return }
                if let image {
                    Self.cache.setObject(image, forKey: cacheKey)
                    self.imageView.image = image
                }
            }
        }
    }

    private static func cacheKey(page: PDFPage, kind: PDFThemeTintKind, bounds: CGRect) -> NSString {
        let widthBucket = Int(bounds.width / 100) * 100
        let heightBucket = Int(bounds.height / 100) * 100
        return "\(ObjectIdentifier(page).hashValue)-\(kind.rawValue)-\(widthBucket)x\(heightBucket)" as NSString
    }

    nonisolated private static func renderTintedImage(page: PDFPage, kind: PDFThemeTintKind, scale: CGFloat) -> UIImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let size = CGSize(width: bounds.width, height: bounds.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let baseImage = renderer.image { context in
            let ctx = context.cgContext
            ctx.saveGState()
            ctx.translateBy(x: 0, y: size.height)
            ctx.scaleBy(x: 1, y: -1)
            page.draw(with: .mediaBox, to: ctx)
            ctx.restoreGState()
        }
        guard let cg = baseImage.cgImage else { return nil }
        var ciImage = CIImage(cgImage: cg)
        for descriptor in PDFThemeTint.filterChain(for: kind) {
            guard let filter = CIFilter(name: descriptor.name) else { continue }
            filter.setValue(ciImage, forKey: kCIInputImageKey)
            for (key, parameter) in descriptor.parameters {
                filter.setValue(parameter.ciFilterValue, forKey: key)
            }
            if let output = filter.outputImage {
                ciImage = output
            }
        }
        let ciContext = CIContext(options: nil)
        guard let output = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            return baseImage
        }
        return UIImage(cgImage: output, scale: scale, orientation: .up)
    }
}
#endif

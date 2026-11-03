import UIKit
import CoreText

// MARK: - PDFExporter

/// Renders a titled text document into a paginated US-Letter PDF using
/// CoreText framesetter pagination.
enum PDFExporter {

    static func makePDF(title: String, body: String) -> Data {
        let titleParagraph = NSMutableParagraphStyle()
        titleParagraph.paragraphSpacing = 18
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 24, weight: .bold),
            .paragraphStyle: titleParagraph,
        ]

        let bodyParagraph = NSMutableParagraphStyle()
        bodyParagraph.lineSpacing = 6
        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12),
            .paragraphStyle: bodyParagraph,
        ]

        let attributed = NSMutableAttributedString(string: title, attributes: titleAttributes)
        attributed.append(NSAttributedString(string: "\n\n", attributes: bodyAttributes))
        attributed.append(NSAttributedString(string: body, attributes: bodyAttributes))

        // US Letter page with 54pt margins.
        let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let margin: CGFloat = 54
        let textRect = pageBounds.insetBy(dx: margin, dy: margin)

        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)

        let data = renderer.pdfData { context in
            var location = 0
            let total = attributed.length
            while location < total {
                context.beginPage()
                let path = CGPath(rect: textRect, transform: nil)
                let frame = CTFramesetterCreateFrame(
                    framesetter,
                    CFRange(location: location, length: 0),
                    path,
                    nil)
                CTFrameDraw(frame, context.cgContext)
                let visibleRange = CTFrameGetVisibleStringRange(frame)
                if visibleRange.length <= 0 {
                    // Safety valve against an endless pagination loop.
                    break
                }
                location += visibleRange.length
            }
        }
        return data
    }
}

import SwiftUI

// MARK: - Astral icon system (V5.0.0 — System-Adaptive Vector Icon Engine)
//
// 50+ professionally designed icons (the MIT-licensed Lucide set,
// downloaded from lucide.dev) are bundled in Resources/Icons/*.svg and
// rendered at runtime by this vector engine:
//
//   AIcon("monitor")            // 18pt, system-adaptive stroke
//   AIcon("cloud", size: 22)    // any size, razor sharp
//
// Every icon is a single stroked SwiftUI `Path` rendered with the caller's
// semantic color (`AstralTheme.textPrimary`, `AstralTheme.textSecondary`,
// etc.), so every glyph adapts automatically to iOS 27 Light Mode, Dark
// Mode, and Liquid Glass materials.

/// Renders a bundled Lucide icon as a stroked vector shape.
///
/// The icons live in the 24×24 design space and are scaled to `size`;
/// `strokeWidth` is expressed in that design space (Lucide default 2).
public struct AIcon: View {
    public let name: String
    public var size: CGFloat = 18
    public var strokeWidth: CGFloat = 2
    public var color: Color

    public init(
        _ name: String,
        size: CGFloat = 18,
        strokeWidth: CGFloat = 2,
        color: Color? = nil
    ) {
        self.name = name
        self.size = size
        self.strokeWidth = strokeWidth
        self.color = color ?? AstralTheme.textPrimary
    }

    public var body: some View {
        Group {
            if let path = Self.cachedPath(name) {
                StrokedIconPath(path: path)
                    .stroke(
                        color,
                        style: StrokeStyle(
                            lineWidth: strokeWidth * (size / 24),
                            lineCap: .round,
                            lineJoin: .round))
            } else {
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .strokeBorder(
                        color.opacity(0.4),
                        style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
            }
        }
        .frame(width: size, height: size)
    }

    // MARK: Cache

    private static let cacheLock = NSLock()
    private static var cache: [String: Path?] = [:]

    private static func cachedPath(_ name: String) -> Path? {
        cacheLock.lock()
        if let hit = cache[name] {
            cacheLock.unlock()
            return hit
        }
        cacheLock.unlock()

        let parsed = loadPath(name)
        cacheLock.lock()
        cache[name] = parsed
        cacheLock.unlock()
        return parsed
    }

    private static func loadPath(_ name: String) -> Path? {
        let sanitized = name.replacingOccurrences(of: "/", with: "")
        guard let url = Bundle.main.url(
            forResource: sanitized, withExtension: "svg", subdirectory: "Icons")
            ?? Bundle.main.url(
                forResource: sanitized, withExtension: "svg", subdirectory: nil),
            let svg = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        return LucideSVGParser.parse(svg)
    }

    private struct StrokedIconPath: Shape {
        let path: Path

        func path(in rect: CGRect) -> Path {
            let scale = min(rect.width, rect.height) / 24
            var transform = CGAffineTransform(translationX: rect.minX, y: rect.minY)
            transform = transform.scaledBy(x: scale, y: scale)
            return path.applying(transform)
        }
    }
}

// MARK: - System-Adaptive Astra Computer Vector Icon

/// System-adaptive wrapper around `AIcon(AstralIcons.computer)` (`monitor.svg`)
/// so every computer icon in the app uses the exact same stroked vector
/// system as all other Lucide icons and adapts automatically to iOS 27
/// Light/Dark mode and Liquid Glass surfaces.
public struct AstralComputerIcon: View {
    public var size: CGFloat = 18
    public var color: Color = AstralTheme.textPrimary
    public var accentColor: Color = AstralTheme.orbGreen
    public var isActive: Bool = false

    public init(
        size: CGFloat = 18,
        color: Color? = nil,
        accentColor: Color = AstralTheme.orbGreen,
        isActive: Bool = false
    ) {
        self.size = size
        self.color = color ?? AstralTheme.textPrimary
        self.accentColor = accentColor
        self.isActive = isActive
    }

    public var body: some View {
        AIcon(
            AstralIcons.computer,
            size: size,
            strokeWidth: 2.0,
            color: color)
            .accessibilityHidden(true)
    }
}

// MARK: - SVG parser (Lucide subset, complete)

enum LucideSVGParser {

    /// Parses the SVG source into one combined path (24×24 space).
    static func parse(_ svg: String) -> Path? {
        var combined = Path()
        var added = false

        for element in shapeElements(in: svg) {
            if let piece = path(for: element) {
                combined.addPath(piece)
                added = true
            }
        }
        return added ? combined : nil
    }

    // MARK: Element discovery

    private struct ShapeElement {
        let tag: String
        let attributes: [String: String]
    }

    private static func shapeElements(in svg: String) -> [ShapeElement] {
        var elements: [ShapeElement] = []
        let tags = ["path", "rect", "circle", "ellipse", "line", "polyline", "polygon"]

        for tag in tags {
            let pattern = "<\(tag)\\b([^>]*)>"
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(svg.startIndex..., in: svg)
                for match in regex.matches(in: svg, range: range) {
                    guard let raw = Range(match.range(at: 1), in: svg) else { continue }
                    let attributeString = String(svg[raw])
                    elements.append(
                        ShapeElement(tag: tag, attributes: attributes(of: attributeString)))
                }
            }
        }
        return elements
    }

    private static func attributes(of source: String) -> [String: String] {
        var result: [String: String] = [:]
        let pattern = #"([a-zA-Z:-]+)\s*=\s*("([^"]*)"|'([^']*)')"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return result }
        let range = NSRange(source.startIndex..., in: source)
        for match in regex.matches(in: source, range: range) {
            guard let keyRange = Range(match.range(at: 1), in: source),
                  let valueRange = Range(match.range(at: 2), in: source) else { continue }
            let key = String(source[keyRange])
            var value = String(source[valueRange])
            if value.hasPrefix("\"") || value.hasPrefix("'") {
                value.removeFirst()
                value.removeLast()
            }
            result[key] = value
        }
        return result
    }

    // MARK: Element → Path

    private static func path(for element: ShapeElement) -> Path? {
        let attributes = element.attributes

        switch element.tag {
        case "path":
            guard let d = attributes["d"] else { return nil }
            return SVGPathCommands.parse(d)
        case "rect":
            return rectPath(attributes)
        case "circle":
            guard let cx = Double(attributes["cx"] ?? ""),
                  let cy = Double(attributes["cy"] ?? ""),
                  let r = Double(attributes["r"] ?? "") else { return nil }
            var path = Path()
            path.addEllipse(
                in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
            return path
        case "ellipse":
            guard let cx = Double(attributes["cx"] ?? ""),
                  let cy = Double(attributes["cy"] ?? ""),
                  let rx = Double(attributes["rx"] ?? ""),
                  let ry = Double(attributes["ry"] ?? "") else { return nil }
            var path = Path()
            path.addEllipse(
                in: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2))
            return path
        case "line":
            guard let x1 = Double(attributes["x1"] ?? ""),
                  let y1 = Double(attributes["y1"] ?? ""),
                  let x2 = Double(attributes["x2"] ?? ""),
                  let y2 = Double(attributes["y2"] ?? "") else { return nil }
            var path = Path()
            path.move(to: CGPoint(x: x1, y: y1))
            path.addLine(to: CGPoint(x: x2, y: y2))
            return path
        case "polyline", "polygon":
            guard let points = attributes["points"] else { return nil }
            let vertices = parsePoints(points)
            guard vertices.count >= 2 else { return nil }
            var path = Path()
            path.move(to: vertices[0])
            for vertex in vertices.dropFirst() {
                path.addLine(to: vertex)
            }
            if element.tag == "polygon" {
                path.closeSubpath()
            }
            return path
        default:
            return nil
        }
    }

    private static func rectPath(_ attributes: [String: String]) -> Path? {
        guard let x = Double(attributes["x"] ?? "0"),
              let y = Double(attributes["y"] ?? "0"),
              let width = Double(attributes["width"] ?? ""),
              let height = Double(attributes["height"] ?? "") else { return nil }
        let rect = CGRect(x: x, y: y, width: width, height: height)
        let rx = Double(attributes["rx"] ?? attributes["ry"] ?? "0") ?? 0
        var path = Path()
        if rx > 0 {
            path.addRoundedRect(
                in: rect,
                cornerSize: CGSize(width: rx, height: rx),
                style: .continuous)
        } else {
            path.addRect(rect)
        }
        return path
    }

    private static func parsePoints(_ source: String) -> [CGPoint] {
        let numbers = source
            .split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\n" || $0 == "\t" })
            .compactMap { Double($0) }
        guard numbers.count >= 2 else { return [] }
        var points: [CGPoint] = []
        var index = 0
        while index + 1 < numbers.count {
            points.append(CGPoint(x: numbers[index], y: numbers[index + 1]))
            index += 2
        }
        return points
    }
}

// MARK: - SVG path "d" command parser

enum SVGPathCommands {

    static func parse(_ d: String) -> Path? {
        var path = Path()
        var scanner = Scanner(string: d)
        scanner.charactersToBeSkipped = CharacterSet(charactersIn: " ,\n\t\r")

        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        var lastControl = CGPoint.zero
        var hasCurved = false
        var started = false

        func ensureStarted() {
            if !started {
                path.move(to: current)
                started = true
            }
        }

        while let command = scanner.scanCharacter() {
            let isRelative = command.isLowercase
            let code = command.uppercased().first ?? command

            switch code {
            case "M":
                var first = true
                while let x = scanNumber(&scanner) {
                    guard let y = scanNumber(&scanner) else { break }
                    let point = isRelative
                        ? CGPoint(x: current.x + x, y: current.y + y)
                        : CGPoint(x: x, y: y)
                    if first {
                        path.move(to: point)
                        subpathStart = point
                        current = point
                        started = true
                        first = false
                    } else {
                        path.addLine(to: point)
                        current = point
                    }
                }
            case "L":
                while let x = scanNumber(&scanner) {
                    guard let y = scanNumber(&scanner) else { break }
                    let point = isRelative
                        ? CGPoint(x: current.x + x, y: current.y + y)
                        : CGPoint(x: x, y: y)
                    ensureStarted()
                    path.addLine(to: point)
                    current = point
                }
            case "H":
                while let x = scanNumber(&scanner) {
                    let targetX = isRelative ? current.x + x : x
                    ensureStarted()
                    path.addLine(to: CGPoint(x: targetX, y: current.y))
                    current.x = targetX
                }
            case "V":
                while let y = scanNumber(&scanner) {
                    let targetY = isRelative ? current.y + y : y
                    ensureStarted()
                    path.addLine(to: CGPoint(x: current.x, y: targetY))
                    current.y = targetY
                }
            case "C":
                while let c1x = scanNumber(&scanner) {
                    guard let c1y = scanNumber(&scanner),
                          let c2x = scanNumber(&scanner),
                          let c2y = scanNumber(&scanner),
                          let x = scanNumber(&scanner),
                          let y = scanNumber(&scanner) else { break }
                    let control1 = isRelative
                        ? CGPoint(x: current.x + c1x, y: current.y + c1y)
                        : CGPoint(x: c1x, y: c1y)
                    let control2 = isRelative
                        ? CGPoint(x: current.x + c2x, y: current.y + c2y)
                        : CGPoint(x: c2x, y: c2y)
                    let end = isRelative
                        ? CGPoint(x: current.x + x, y: current.y + y)
                        : CGPoint(x: x, y: y)
                    ensureStarted()
                    path.addCurve(to: end, control1: control1, control2: control2)
                    lastControl = control2
                    hasCurved = true
                    current = end
                }
            case "S":
                while let c2x = scanNumber(&scanner) {
                    guard let c2y = scanNumber(&scanner),
                          let x = scanNumber(&scanner),
                          let y = scanNumber(&scanner) else { break }
                    let reflected = hasCurved
                        ? CGPoint(x: 2 * current.x - lastControl.x, y: 2 * current.y - lastControl.y)
                        : current
                    let control2 = isRelative
                        ? CGPoint(x: current.x + c2x, y: current.y + c2y)
                        : CGPoint(x: c2x, y: c2y)
                    let end = isRelative
                        ? CGPoint(x: current.x + x, y: current.y + y)
                        : CGPoint(x: x, y: y)
                    ensureStarted()
                    path.addCurve(to: end, control1: reflected, control2: control2)
                    lastControl = control2
                    hasCurved = true
                    current = end
                }
            case "Q":
                while let c1x = scanNumber(&scanner) {
                    guard let c1y = scanNumber(&scanner),
                          let x = scanNumber(&scanner),
                          let y = scanNumber(&scanner) else { break }
                    let control = isRelative
                        ? CGPoint(x: current.x + c1x, y: current.y + c1y)
                        : CGPoint(x: c1x, y: c1y)
                    let end = isRelative
                        ? CGPoint(x: current.x + x, y: current.y + y)
                        : CGPoint(x: x, y: y)
                    ensureStarted()
                    path.addQuadCurve(to: end, control: control)
                    lastControl = control
                    hasCurved = true
                    current = end
                }
            case "T":
                while let x = scanNumber(&scanner) {
                    guard let y = scanNumber(&scanner) else { break }
                    let control = hasCurved
                        ? CGPoint(x: 2 * current.x - lastControl.x, y: 2 * current.y - lastControl.y)
                        : current
                    let end = isRelative
                        ? CGPoint(x: current.x + x, y: current.y + y)
                        : CGPoint(x: x, y: y)
                    ensureStarted()
                    path.addQuadCurve(to: end, control: control)
                    lastControl = control
                    hasCurved = true
                    current = end
                }
            case "A":
                while let rx = scanNumber(&scanner) {
                    guard let ry = scanNumber(&scanner),
                          let rotation = scanNumber(&scanner),
                          let largeArc = scanInt(&scanner),
                          let sweep = scanInt(&scanner),
                          let x = scanNumber(&scanner),
                          let y = scanNumber(&scanner) else { break }
                    let end = isRelative
                        ? CGPoint(x: current.x + x, y: current.y + y)
                        : CGPoint(x: x, y: y)
                    ensureStarted()
                    appendArc(
                        to: &path, from: current, to: end,
                        rx: rx, ry: ry, rotation: rotation,
                        largeArc: largeArc == 1, sweep: sweep == 1)
                    current = end
                    hasCurved = false
                }
            case "Z":
                path.closeSubpath()
                current = subpathStart
                hasCurved = false
            default:
                return path.isEmpty ? nil : path
            }
        }
        return path.isEmpty ? nil : path
    }

    // MARK: Number scanning

    private static func scanNumber(_ scanner: inout Scanner) -> Double? {
        return scanner.scanDouble()
    }

    private static func scanInt(_ scanner: inout Scanner) -> Int? {
        return scanner.scanInt()
    }

    // MARK: Elliptical arc (SVG endpoint → center parameterization)

    private static func appendArc(
        to path: inout Path,
        from start: CGPoint,
        to end: CGPoint,
        rx: Double,
        ry: Double,
        rotation: Double,
        largeArc: Bool,
        sweep: Bool
    ) {
        guard rx > 0, ry > 0 else {
            path.addLine(to: end)
            return
        }

        let radians = rotation * .pi / 180
        let cosR = cos(radians)
        let sinR = sin(radians)

        let dx = (start.x - end.x) / 2
        let dy = (start.y - end.y) / 2
        let x1 = cosR * dx + sinR * dy
        let y1 = -sinR * dx + cosR * dy

        var radiusX = abs(rx)
        var radiusY = abs(ry)

        let reach = (x1 * x1) / (radiusX * radiusX)
            + (y1 * y1) / (radiusY * radiusY)
        if reach > 1 {
            let scale = sqrt(reach)
            radiusX *= scale
            radiusY *= scale
        }

        guard radiusX > 0, radiusY > 0 else {
            path.addLine(to: end)
            return
        }

        let sign = (largeArc != sweep) ? 1.0 : -1.0
        let numerator = radiusX * radiusX * radiusY * radiusY
            - radiusX * radiusX * y1 * y1
            - radiusY * radiusY * x1 * x1
        let inner = max(0, numerator) / max(
            .ulpOfOne,
            radiusX * radiusX * y1 * y1 + radiusY * radiusY * x1 * x1)
        let coefficient = sign * sqrt(inner)

        let centerX = coefficient * (radiusX * y1 / radiusY)
        let centerY = coefficient * (-radiusY * x1 / radiusX)

        let centerXL = cosR * centerX - sinR * centerY + (start.x + end.x) / 2
        let centerYL = sinR * centerX + cosR * centerY + (start.y + end.y) / 2

        func angle(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double {
            let dot = ux * vx + uy * vy
            let length = sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy))
            var value = acos(min(1, max(-1, dot / max(length, .ulpOfOne))))
            if ux * vy - uy * vx < 0 {
                value = -value
            }
            return value
        }

        let startAngle = angle(
            1, 0,
            (x1 - centerX) / radiusX, (y1 - centerY) / radiusY)
        var sweepAngle = angle(
            (x1 - centerX) / radiusX, (y1 - centerY) / radiusY,
            (-x1 - centerX) / radiusX, (-y1 - centerY) / radiusY)

        if !sweep && sweepAngle > 0 {
            sweepAngle -= 2 * .pi
        } else if sweep && sweepAngle < 0 {
            sweepAngle += 2 * .pi
        }

        let segments = max(
            2,
            Int(ceil(abs(sweepAngle) / (.pi / 2))) * 2)
        let increment = sweepAngle / Double(segments)
        var t = startAngle

        var previous = start
        for _ in 0..<segments {
            let next = t + increment
            let point1 = arcPoint(
                center: CGPoint(x: centerXL, y: centerYL),
                radiusX: radiusX, radiusY: radiusY,
                rotation: radians, angle: next)
            let handle = 4.0 / 3.0 * tan(increment / 4)
            let tangent0 = arcTangent(
                radiusX: radiusX, radiusY: radiusY, rotation: radians, angle: t)
            let tangent1 = arcTangent(
                radiusX: radiusX, radiusY: radiusY, rotation: radians, angle: next)

            let control1 = CGPoint(
                x: previous.x + handle * tangent0.x,
                y: previous.y + handle * tangent0.y)
            let control2 = CGPoint(
                x: point1.x - handle * tangent1.x,
                y: point1.y - handle * tangent1.y)

            path.addCurve(to: point1, control1: control1, control2: control2)
            previous = point1
            t = next
        }
    }

    private static func arcPoint(
        center: CGPoint,
        radiusX: Double,
        radiusY: Double,
        rotation: Double,
        angle: Double
    ) -> CGPoint {
        let x = radiusX * cos(angle)
        let y = radiusY * sin(angle)
        return CGPoint(
            x: center.x + cos(rotation) * x - sin(rotation) * y,
            y: center.y + sin(rotation) * x + cos(rotation) * y)
    }

    private static func arcTangent(
        radiusX: Double,
        radiusY: Double,
        rotation: Double,
        angle: Double
    ) -> CGPoint {
        let dx = -radiusX * sin(angle)
        let dy = radiusY * cos(angle)
        let length = max(.ulpOfOne, sqrt(dx * dx + dy * dy))
        return CGPoint(
            x: (cos(rotation) * dx - sin(rotation) * dy) / length,
            y: (sin(rotation) * dx + cos(rotation) * dy) / length)
    }
}

// MARK: - Icon name registry

enum AstralIcons {
    static let computer = "monitor"
    static let terminal = "square-terminal"
    static let browser = "globe"
    static let search = "search"
    static let file = "file-text"
    static let filePlus = "file-plus"
    static let fileCode = "file-code"
    static let folder = "folder"
    static let folderPlus = "folder-plus"
    static let folderOpen = "folder-open"
    static let folderTree = "folder-tree"
    static let send = "send"
    static let settings = "settings"
    static let sparkles = "sparkles"
    static let cpu = "cpu"
    static let cloud = "cloud"
    static let cloudOff = "cloud-off"
    static let hardDrive = "hard-drive"
    static let click = "mouse-pointer-click"
    static let back = "arrow-left"
    static let forward = "arrow-right"
    static let plus = "plus"
    static let check = "check"
    static let close = "x"
    static let play = "play"
    static let stop = "square"
    static let download = "download"
    static let upload = "upload"
    static let chevronDown = "chevron-down"
    static let chevronUp = "chevron-up"
    static let chevronForward = "chevron-right"
    static let externalLink = "external-link"
    static let todo = "list-todo"
    static let chat = "message-circle"
    static let zap = "zap"
    static let package = "package"
    static let trash = "trash"
    static let eye = "eye"
    static let share = "share-2"
    static let key = "key-round"
    static let rocket = "rocket"
    static let bot = "bot"
    static let brain = "brain"
    static let wrench = "wrench"
    static let refresh = "refresh-cw"
    static let image = "image"
    static let wifi = "wifi"
    static let shield = "shield-check"
    static let languages = "languages"
    static let compass = "compass"

    // V4.5.6 / V5.0.0 additions
    static let spinner = "loader-circle"
    static let sidebar = "panel-left"
    static let newChat = "message-square-plus"
    static let arrowUp = "arrow-up"
    static let chevronsUpDown = "chevrons-up-down"
    static let puzzle = "puzzle"
    static let map = "map"
    static let braces = "braces"
    static let table = "table"
    static let mic = "mic"
    static let history = "history"
    static let checkCircle = "circle-check"
    static let fileUp = "file-up"
    static let plug = "plug-zap"
    static let users = "users"

    // V5.0.0 corrected source: referenced by the table copy buttons
    // (MessageViews / MarkdownView) and the onboarding language row.
    static let copy = "copy"
    static let globe = "globe"
}

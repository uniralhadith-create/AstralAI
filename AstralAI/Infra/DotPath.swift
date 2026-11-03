import Foundation

// MARK: - Dot-path extraction

/// Dot-path navigation over `JSONSerialization` output
/// (`[String: Any]` / `[Any]` / `String` / `NSNumber` trees).
///
/// Path rules:
/// - Segments are split on ".".
/// - A numeric segment indexes into an array ("choices.0.delta").
/// - An empty segment ("") or "[]" expands across an array: the remaining
///   path is applied to every element and all non-nil results are
///   collected ("data.[].id").
/// - An empty path returns the value itself.
enum DotPath {

    /// Returns the first value reachable via the path, or nil.
    static func extract(from value: Any, path: String) -> Any? {
        // An empty path addresses the value itself. This is checked
        // explicitly so the behavior never depends on how String.split
        // handles the empty string.
        if path.isEmpty { return value }
        let segments = parse(path)
        guard !segments.isEmpty else { return value }
        return collect(from: value, segments: segments).first
    }

    /// Returns every value reachable via the path ([] when nothing matches).
    static func extractArray(from value: Any, path: String) -> [Any] {
        if path.isEmpty { return [value] }
        let segments = parse(path)
        guard !segments.isEmpty else { return [value] }
        return collect(from: value, segments: segments)
    }

    /// Converts scalar JSON values to a display string.
    /// Strings pass through, numbers use their description, collections
    /// and null return nil.
    static func stringValue(_ value: Any) -> String? {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.description
        default:
            return nil
        }
    }

    // MARK: - Internals

    private static func parse(_ path: String) -> [String] {
        path.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
    }

    /// Applies the remaining segments, collecting every reachable value.
    private static func collect(from value: Any, segments: [String]) -> [Any] {
        guard let segment = segments.first else { return [value] }
        let rest = Array(segments.dropFirst())

        // Expansion segment: map the remaining path over array elements.
        if segment.isEmpty || segment == "[]" {
            guard let array = value as? [Any] else { return [] }
            var results: [Any] = []
            for element in array {
                results.append(contentsOf: collect(from: element, segments: rest))
            }
            return results
        }

        // Numeric segment: array index.
        if let index = Int(segment) {
            guard let array = value as? [Any],
                  index >= 0,
                  index < array.count else { return [] }
            return collect(from: array[index], segments: rest)
        }

        // Dictionary key segment.
        guard let dictionary = value as? [String: Any],
              let next = dictionary[segment] else { return [] }
        return collect(from: next, segments: rest)
    }
}

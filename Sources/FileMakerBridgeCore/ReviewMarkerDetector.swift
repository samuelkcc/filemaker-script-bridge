import Foundation

public enum ReviewMarkerDetector {
    public static func count(in source: String) -> Int {
        source
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("# ▶︎ Unsupported") }
            .count
    }
}

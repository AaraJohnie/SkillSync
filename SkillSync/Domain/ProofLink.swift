import Foundation

enum ProofLink {
    static func normalize(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AppError.missingProof }

        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = url.host?.lowercased(),
              isPublicHost(host)
        else {
            throw AppError.invalidProof
        }

        return url.absoluteString
    }

    static func isValid(_ raw: String) -> Bool {
        (try? normalize(raw)) != nil
    }

    static func hostLabel(_ raw: String?) -> String? {
        guard let raw, let url = URL(string: raw), let host = url.host?.lowercased() else { return nil }
        if host.contains("github") { return "GitHub" }
        if host.contains("figma") { return "Figma" }
        if host.contains("testflight") || host.contains("apple.com") { return "TestFlight" }
        return host.replacingOccurrences(of: "www.", with: "")
    }

    static func url(_ raw: String?) -> URL? {
        guard let raw else { return nil }
        return try? URL(string: normalize(raw))
    }

    private static func isPublicHost(_ host: String) -> Bool {
        guard host.contains("."),
              !host.hasPrefix("."),
              !host.hasSuffix("."),
              host.rangeOfCharacter(from: .letters) != nil
        else {
            return false
        }
        let blocked = ["localhost", "example.com", "invalid"]
        return !blocked.contains(host)
    }
}

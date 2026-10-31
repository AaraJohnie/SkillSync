import Foundation

struct CredentialCheck: Equatable, Identifiable {
    var input: String
    var platform: WorkPlatform?
    var normalizedURL: String?
    var handle: String?
    var status: CredentialStatus
    var reason: String

    var id: String { normalizedURL ?? input }

    var credential: PlatformCredential? {
        guard status == .verified, let platform, let normalizedURL, let handle else { return nil }
        return PlatformCredential(
            platform: platform,
            normalizedURL: normalizedURL,
            handle: handle,
            status: .verified,
            reason: reason
        )
    }
}

struct CredentialVerdict: Equatable {
    var checks: [CredentialCheck]

    var verified: [PlatformCredential] {
        checks.compactMap(\.credential)
    }

    var trust: TrustLevel {
        CredentialVerifier.trust(for: verified)
    }
}

/// Shape and uniqueness rules for work links. The Cloud Function `verifyCredentials`
/// is the platform-wide authority. This mirror lets the campus demo decide trust
/// before Firebase is connected. It never reads a profile narrative.
enum CredentialVerifier {
    static func trust(for links: [PlatformCredential]) -> TrustLevel {
        let verified = links.filter { $0.status == .verified }
        let hasLinkedIn = verified.contains { $0.platform.isProfileNetwork }
        let hasWork = verified.contains { !$0.platform.isProfileNetwork }
        if hasLinkedIn && hasWork { return .trusted }
        if hasLinkedIn || hasWork { return .partial }
        return .unverified
    }

    static func evaluate(links: [String], existing: [UserProfile], claimedBy userId: String? = nil) -> CredentialVerdict {
        let taken = Set(
            existing
                .filter { $0.id != userId }
                .flatMap(\.platformLinks)
                .filter { $0.status == .verified }
                .map(\.normalizedURL)
        )
        var seen = Set<String>()
        let checks = links.map { raw in
            check(raw, taken: taken, seen: &seen)
        }
        return CredentialVerdict(checks: checks)
    }

    private static func check(_ raw: String, taken: Set<String>, seen: inout Set<String>) -> CredentialCheck {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return CredentialCheck(input: raw, status: .rejected, reason: "Add a link.")
        }
        guard let normalized = try? ProofLink.normalize(trimmed),
              let url = URL(string: normalized),
              let host = url.host?.lowercased()
        else {
            return CredentialCheck(input: trimmed, status: .rejected, reason: "That is not a public https link.")
        }

        guard let classified = classify(host: host, path: url.path) else {
            return CredentialCheck(
                input: trimmed,
                status: .rejected,
                reason: "Use LinkedIn, GitHub, GitLab, Behance, Dribbble, Figma, Devpost, CodePen, Kaggle, or Bitbucket."
            )
        }

        let canonical = canonicalURL(host: classified.host, path: classified.path)
        if taken.contains(canonical) || seen.contains(canonical) {
            return CredentialCheck(
                input: trimmed,
                platform: classified.platform,
                normalizedURL: canonical,
                handle: classified.handle,
                status: .rejected,
                reason: "That profile is already linked to another student."
            )
        }
        seen.insert(canonical)
        return CredentialCheck(
            input: trimmed,
            platform: classified.platform,
            normalizedURL: canonical,
            handle: classified.handle,
            status: .verified,
            reason: "\(classified.platform.label) profile @\(classified.handle) is a public link no one else has claimed."
        )
    }

    private struct Classified {
        var platform: WorkPlatform
        var host: String
        var path: String
        var handle: String
    }

    private static let reserved: Set<String> = [
        "about", "apps", "blog", "company", "contact", "download", "enterprise", "explore",
        "features", "feed", "help", "home", "jobs", "legal", "login", "marketplace", "new",
        "notifications", "orgs", "pricing", "privacy", "search", "settings", "signin",
        "signup", "terms", "topics"
    ]

    private static func classify(host: String, path: String) -> Classified? {
        let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        let parts = path.split(separator: "/").map(String.init)
        switch bare {
        case "linkedin.com":
            guard parts.count >= 2, parts[0] == "in" || parts[0] == "pub", let handle = clean(parts[1]) else { return nil }
            return Classified(platform: .linkedin, host: "linkedin.com", path: "/\(parts[0])/\(handle)", handle: handle)
        case "github.com":
            guard let handle = clean(parts.first), !reserved.contains(handle.lowercased()) else { return nil }
            let project = parts.count >= 2 ? clean(parts[1]) : nil
            let suffix = project.map { "/\($0)" } ?? ""
            return Classified(platform: .github, host: "github.com", path: "/\(handle)\(suffix)", handle: handle)
        case "gitlab.com":
            guard let handle = clean(parts.first), !reserved.contains(handle.lowercased()) else { return nil }
            return Classified(platform: .gitlab, host: "gitlab.com", path: "/\(handle)", handle: handle)
        case "behance.net", "behance.com":
            guard let handle = clean(parts.first), !reserved.contains(handle.lowercased()) else { return nil }
            return Classified(platform: .behance, host: "behance.net", path: "/\(handle)", handle: handle)
        case "dribbble.com":
            guard let handle = clean(parts.first), !reserved.contains(handle.lowercased()) else { return nil }
            return Classified(platform: .dribbble, host: "dribbble.com", path: "/\(handle)", handle: handle)
        case "figma.com":
            return classifyFigma(parts)
        case "devpost.com":
            guard let handle = clean(parts.first), !reserved.contains(handle.lowercased()) else { return nil }
            return Classified(platform: .devpost, host: "devpost.com", path: "/\(handle)", handle: handle)
        case "codepen.io":
            guard let handle = clean(parts.first), !reserved.contains(handle.lowercased()) else { return nil }
            return Classified(platform: .codepen, host: "codepen.io", path: "/\(handle)", handle: handle)
        case "kaggle.com":
            guard let handle = clean(parts.first), !reserved.contains(handle.lowercased()) else { return nil }
            return Classified(platform: .kaggle, host: "kaggle.com", path: "/\(handle)", handle: handle)
        case "bitbucket.org":
            guard let handle = clean(parts.first), !reserved.contains(handle.lowercased()) else { return nil }
            return Classified(platform: .bitbucket, host: "bitbucket.org", path: "/\(handle)", handle: handle)
        case "lnkd.in":
            return nil
        default:
            return nil
        }
    }

    private static func classifyFigma(_ parts: [String]) -> Classified? {
        if let first = parts.first, first.hasPrefix("@"), let handle = clean(String(first.dropFirst())) {
            return Classified(platform: .figma, host: "figma.com", path: "/@\(handle)", handle: handle)
        }
        let kinds = ["file", "proto", "design"]
        if let kind = parts.first, kinds.contains(kind), parts.count >= 2, let key = clean(parts[1]) {
            return Classified(platform: .figma, host: "figma.com", path: "/\(kind)/\(key)", handle: key)
        }
        return nil
    }

    private static func clean(_ raw: String?) -> String? {
        guard var value = raw?.removingPercentEncoding ?? raw else { return nil }
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count >= 2, value.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." }) else {
            return nil
        }
        return value
    }

    private static func canonicalURL(host: String, path: String) -> String {
        "https://\(host)\(path)"
    }
}

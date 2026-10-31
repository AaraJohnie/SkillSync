import Foundation
import SkillEvidenceAgent

enum GitHubPublicLookup {
    struct Failure: LocalizedError {
        var message: String
        var errorDescription: String? { message }
    }

    static func snapshot(login: String) async throws -> GitHubSnapshot {
        let handle = login.trimmingCharacters(in: .whitespacesAndNewlines)
        guard handle.range(of: "^[A-Za-z0-9-]{1,39}$", options: .regularExpression) != nil else {
            throw Failure(message: "That GitHub username cannot be looked up.")
        }
        guard let url = URL(string: "https://api.github.com/users/\(handle)/repos?per_page=30&sort=updated") else {
            throw Failure(message: "That GitHub username cannot be looked up.")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("SkillSync", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw Failure(message: "GitHub did not answer.")
        }
        guard http.statusCode == 200 else {
            throw Failure(message: http.statusCode == 404 ? "GitHub has no user named \(handle)." : "GitHub declined the lookup.")
        }
        struct Repo: Decodable {
            var name: String
            var description: String?
            var language: String?
            var fork: Bool?
            var topics: [String]?
        }
        let repos = try JSONDecoder().decode([Repo].self, from: data)
        return GitHubSnapshot(
            login: handle,
            repositories: repos.map {
                GitHubRepository(
                    name: $0.name,
                    description: $0.description ?? "",
                    language: $0.language,
                    topics: $0.topics ?? [],
                    isFork: $0.fork ?? false
                )
            },
            recentCommitCount: 0,
            pullRequestCount: 0
        )
    }
}

enum PortfolioTextFetch {
    static func load(url: URL) async throws -> String {
        guard PortfolioGuard.hostIsAllowed(url.host ?? "") else {
            throw GitHubPublicLookup.Failure(message: "That address is not allowed.")
        }
        let session = URLSession(configuration: .ephemeral, delegate: RedirectGuard(), delegateQueue: nil)
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("SkillSync", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw GitHubPublicLookup.Failure(message: "The page did not load.")
        }
        guard data.count <= 200_000 else {
            throw GitHubPublicLookup.Failure(message: "The page is too large to read.")
        }
        let raw = String(data: data, encoding: .utf8) ?? ""
        let stripped = raw
            .replacingOccurrences(of: "(?is)<script.*?>.*?</script>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "(?is)<style.*?>.*?</style>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let collapsed = stripped.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return String(collapsed.prefix(8_000))
    }
}

private final class RedirectGuard: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let host = request.url?.host, PortfolioGuard.hostIsAllowed(host), request.url?.scheme == "https" else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

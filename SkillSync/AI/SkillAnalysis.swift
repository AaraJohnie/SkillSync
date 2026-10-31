import Foundation

struct SkillAnalysis: Codable, Equatable {
    var summary: String
    var skills: [AssessedSkill]
    var recommendations: [String]
}

struct AssessedSkill: Codable, Equatable, Identifiable {
    var name: String
    var level: String
    var evidence: String

    var id: String { name }
}

struct SkillAnalysisRequest: Codable {
    var skills: [String]
    var projectDescription: String
    var experience: String
}

struct SkillProfile: Codable, Equatable {
    var summary: String
    var skills: [ProfiledSkill]
}

struct ProfiledSkill: Codable, Equatable, Identifiable {
    var name: String
    var category: String
    var evidence: String

    var id: String { name }
}

struct SkillGapReport: Codable, Equatable {
    var target: String
    var summary: String
    var missing: [SkillGapItem]
    var path: [String]
}

struct SkillGapItem: Codable, Equatable, Identifiable {
    var name: String
    var why: String
    var nextStep: String

    var id: String { name }
}

private struct SkillProfileRequest: Codable {
    var source: String
}

private struct SkillGapRequest: Codable {
    var skills: [String]
    var target: String
}

enum SkillSyncBackend {
    /// Origin of the deployed `analyzeSkills` function. The Gemini key is not stored here.
    /// Example: https://us-central1-your-project.cloudfunctions.net
    static let baseURL = URL(string: "https://us-central1-YOUR_PROJECT.cloudfunctions.net")!

    static var isConfigured: Bool {
        !baseURL.absoluteString.contains("YOUR_PROJECT")
    }
}

enum SkillSyncAPIError: LocalizedError {
    case needsDetail(String)
    case invalidResponse
    case server(status: Int, message: String)
    case invalidJSON

    var errorDescription: String? {
        switch self {
        case .needsDetail(let message):
            message
        case .invalidResponse:
            "The server returned an invalid response."
        case .server(_, let message):
            message
        case .invalidJSON:
            "The assessment came back in an unexpected shape."
        }
    }
}

enum SkillSyncAPI {
    static func profileSkillsRemote(source: String) async throws -> SkillProfile {
        try await post(SkillProfileRequest(source: source), path: "profileSkills")
    }

    static func analyzeSkillsRemote(_ request: SkillAnalysisRequest) async throws -> SkillAnalysis {
        try await post(request, path: "analyzeSkills")
    }

    static func detectSkillGapRemote(skills: [String], target: String) async throws -> SkillGapReport {
        try await post(SkillGapRequest(skills: skills, target: target), path: "detectSkillGap")
    }

    private static func post<Body: Encodable, Result: Decodable>(_ body: Body, path: String) async throws -> Result {
        guard SkillSyncBackend.isConfigured else {
            throw SkillSyncAPIError.needsDetail("The cloud skill check is not configured, so this stayed on the device.")
        }

        let url = SkillSyncBackend.baseURL.appendingPathComponent(path)
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw SkillSyncAPIError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let message = serverMessage(from: data) ?? "The skill check failed."
            throw SkillSyncAPIError.server(status: http.statusCode, message: message)
        }
        do {
            return try JSONDecoder().decode(Result.self, from: data)
        } catch {
            throw SkillSyncAPIError.invalidJSON
        }
    }

    private static func serverMessage(from data: Data) -> String? {
        struct Envelope: Decodable { var error: String? }
        return (try? JSONDecoder().decode(Envelope.self, from: data))?.error
    }
}

import Foundation
import SkillEvidenceAgent

struct IdentityCheck: Equatable {
    var profile: TrustProfile
    var finding: String
    var gitHubLogin: String?
}

enum IdentityEvidenceCheck {
    static func run(narrative: String, checks: [CredentialCheck]) async -> IdentityCheck {
        let claims = claimedSkills(in: narrative)
        var notes: [String] = []
        var gitHub: GitHubSnapshot?
        var portfolio: PortfolioDocument?

        if let github = checks.first(where: { $0.platform == .github && $0.status == .verified }), let handle = github.handle {
            do {
                gitHub = try await GitHubPublicLookup.snapshot(login: handle)
                let languages = Set(gitHub?.ownedRepositories.compactMap(\.language) ?? []).sorted()
                let count = gitHub?.ownedRepositories.count ?? 0
                if count == 0 {
                    notes.append("GitHub @\(handle) exists, and it has no public repositories.")
                } else {
                    let languageLine = languages.isEmpty ? "no language is listed" : languages.joined(separator: ", ")
                    notes.append("GitHub @\(handle) has \(count) public \(count == 1 ? "repository" : "repositories"). \(languageLine).")
                }
            } catch {
                notes.append(error.localizedDescription)
            }
        }

        if let project = checks.first(where: { $0.platform != .github && $0.platform != .linkedin && $0.status == .verified }),
           let url = project.normalizedURL.flatMap(URL.init(string:)),
           EvidenceAgent().screenPortfolioURL(url.absoluteString).isAllowed {
            do {
                let text = try await PortfolioTextFetch.load(url: url)
                if text.count >= 40 {
                    portfolio = PortfolioDocument(url: url.absoluteString, text: text, wasFetched: true)
                    notes.append("\(project.platform?.label ?? "The project page") returned text the agent could read.")
                } else {
                    notes.append("\(project.platform?.label ?? "The project page") loaded, but it had no readable project text.")
                }
            } catch {
                notes.append("\(project.platform?.label ?? "The project page") could not be read, so it is not evidence.")
            }
        }

        if checks.contains(where: { $0.platform == .linkedin && $0.status == .verified }) {
            notes.append("The LinkedIn address is a real profile link. LinkedIn does not let this app read the page, so it is not used as skill evidence.")
        }

        let corpus = EvidenceCorpus(
            subjectId: "signup",
            displayName: "This account",
            emailVerified: false,
            institution: "",
            claimedSkills: claims.map(ClaimedSkill.init(name:)),
            gitHub: gitHub,
            portfolio: portfolio,
            certificates: [],
            projects: [],
            collaborations: [],
            completedCollaborationCount: 0,
            uniqueCollaboratorCount: 0,
            peerConfirmationCount: 0
        )
        let profile = EvidenceAgent().assemble(AssemblyInput(stage: .signup, corpus: corpus, portfolioURL: portfolio?.url)).profile
        let finding = verdictSentence(claims: profile.skills, notes: notes, narrative: narrative, gitHub: gitHub)
        return IdentityCheck(profile: profile, finding: finding, gitHubLogin: gitHub?.login)
    }

    static func claimedSkills(in narrative: String) -> [String] {
        let lower = narrative.lowercased()
        var names = SkillCatalog.all
            .filter { lower.contains($0.name.lowercased()) }
            .map(\.name)
        let saysIOS = lower.contains("ios") || lower.contains("iphone") || lower.contains("swift")
        if saysIOS, !names.contains("Swift") { names.append("Swift") }
        if saysIOS, !names.contains("SwiftUI") { names.append("SwiftUI") }
        return names
    }

    static func supportsClaim(_ check: IdentityCheck) -> Bool {
        let skills = check.profile.skills
        guard !skills.isEmpty else { return true }
        return skills.contains { $0.status != .unverified }
    }

    private static func verdictSentence(claims: [SkillVerdict], notes: [String], narrative: String, gitHub: GitHubSnapshot?) -> String {
        let header = notes.joined(separator: " ")
        let trimmed = narrative.trimmingCharacters(in: .whitespacesAndNewlines)
        if claims.isEmpty {
            let ask = trimmed.isEmpty
                ? "Name the skill, for example iOS or Swift."
                : "“\(trimmed)” does not name a skill, so there is nothing specific to confirm."
            return [header, ask].filter { !$0.isEmpty }.joined(separator: " ")
        }
        let lines = claims.map { "\($0.claimedSkill) is \($0.status.label.lowercased())." }
        let swift = claims.first { $0.claimedSkill == "Swift" }
        let iosLine: String
        if let swift, swift.status == .unverified {
            let languages = Set(gitHub?.ownedRepositories.compactMap(\.language) ?? [])
            if languages.isEmpty {
                iosLine = "The profiles do not show Swift or iOS work, so the iOS claim stays unverified."
            } else {
                iosLine = "Those repositories are not Swift, so the iOS claim stays unverified."
            }
        } else if swift != nil {
            iosLine = "The GitHub account has work that matches the iOS claim. That is evidence, not a declaration that the person is an expert."
        } else {
            iosLine = ""
        }
        return ([header] + lines + [iosLine]).filter { !$0.isEmpty }.joined(separator: " ")
    }
}

import Foundation

struct TaskBrief: Hashable {
    var title: String
    var detail: String
    var requiredSkills: [String]
}

struct TaskRead: Hashable {
    var skills: [String]
    var complexity: String
    var lane: ContributionLane
    var reasons: [String]
}

struct RecommendedPerson: Identifiable, Hashable {
    var id: String { user.id }
    var user: UserProfile
    var synergy: SynergyBreakdown
    var why: String
}

struct WorkCall: Hashable {
    var lane: ContributionLane
    var skills: [String]
    var person: RecommendedPerson?
}

struct CallPlan: Hashable {
    var read: TaskRead
    var primary: WorkCall
    var other: WorkCall?
}

enum TaskClassifier {
    private static let coreSkills: Set<String> = ["Machine Learning", "Product Strategy", "APIs", "Node.js", "Python", "Firebase", "ARKit"]
    private static let handsSkills: Set<String> = ["SwiftUI", "UIKit", "Figma", "UI/UX", "Illustration", "Copywriting", "Motion", "Video", "Product Design"]
    private static let corePhrases = [
        "architect", "architecture", "algorithm", "system design", "schema", "distributed",
        "machine learning", "neural", "model training", "inference", "pipeline", "backend",
        "cloud function", "conflict", "security model", "compiler", "optimization", "protocol"
    ]
    private static let handsPhrases = [
        "ui", "screen", "button", "layout", "copy", "document", "docs", "test", "testing",
        "qa", "data entry", "config", "configure", "boilerplate", "empty state", "style",
        "icon", "pixel", "basic", "repetitive", "wireframe", "snapshot"
    ]

    static func analyze(_ brief: TaskBrief) -> TaskRead {
        let text = "\(brief.title) \(brief.detail)".lowercased()
        let skills = inferSkills(from: text, hints: brief.requiredSkills)
        let coreLanguage = corePhrases.filter { text.contains($0) }.count
        let handsLanguage = handsPhrases.filter { text.contains($0) }.count
        let lane = classify(textScore: coreLanguage - handsLanguage, skills: skills)
        let complexity = complexityLabel(lane: lane, skills: skills, text: text)
        let reason = lane == .technicalCore
            ? "The work needs system design, algorithms, or specialized implementation."
            : "The work is implementation, testing, configuration, or other hands-on technical effort."
        return TaskRead(skills: skills, complexity: complexity, lane: lane, reasons: [reason])
    }

    static func plan(seeker: UserProfile, pool: [UserProfile], brief: TaskBrief) -> CallPlan {
        let read = analyze(brief)
        let core = read.skills.filter { coreSkills.contains($0) }
        let hands = read.skills.filter { handsSkills.contains($0) }
        let primarySkills = read.lane == .technicalCore ? (core.isEmpty ? read.skills : core) : (hands.isEmpty ? read.skills : hands)
        let primary = WorkCall(
            lane: read.lane,
            skills: primarySkills,
            person: recommend(seeker: seeker, pool: pool, brief: brief, read: read, skills: primarySkills).first
        )
        let otherSkills = read.lane == .technicalCore ? hands : core
        let otherLane: ContributionLane = read.lane == .technicalCore ? .technicalHands : .technicalCore
        let other: WorkCall? = otherSkills.isEmpty ? nil : WorkCall(
            lane: otherLane,
            skills: otherSkills,
            person: recommend(seeker: seeker, pool: pool, brief: brief, read: read, skills: otherSkills, lane: otherLane).first
        )
        return CallPlan(read: read, primary: primary, other: other)
    }

    static func recommend(seeker: UserProfile, pool: [UserProfile], brief: TaskBrief, read: TaskRead, skills: [String]? = nil, lane preferredLane: ContributionLane? = nil) -> [RecommendedPerson] {
        let needed = skills ?? read.skills
        let lane = preferredLane ?? read.lane
        return pool
            .filter { $0.id != seeker.id && $0.onboardingComplete }
            .compactMap { candidate -> (RecommendedPerson, Int, Int)? in
                let hits = needed.compactMap { name -> (String, SkillLevel)? in
                    guard let skill = candidate.skill(named: name) else { return nil }
                    return (name, skill.level)
                }
                guard !hits.isEmpty else { return nil }
                let synergy = SynergyEngine.evaluate(seeker: seeker, candidate: candidate, project: nil)
                let matched = hits.map { "\($0.0) (\($0.1.label))" }.joined(separator: ", ")
                let why = "Has \(matched)."
                let coverage = hits.count
                let depth = hits.map(\.1.rank).max() ?? 0
                return (RecommendedPerson(user: candidate, synergy: synergy, why: why), coverage, depth)
            }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                if lane == .technicalCore { return lhs.2 > rhs.2 }
                return abs(lhs.2 - 2) < abs(rhs.2 - 2)
            }
            .map(\.0)
    }

    private static func inferSkills(from text: String, hints: [String]) -> [String] {
        var names = SkillCatalog.all.filter { text.localizedCaseInsensitiveContains($0.name) }.map(\.name)
        names.append(contentsOf: hints)
        if text.contains("machine learning") || text.contains("neural") { names.append("Machine Learning") }
        if text.contains("backend") || text.contains("cloud function") || text.contains("api") { names.append("APIs") }
        if text.contains("swiftui") || text.contains("screen") || text.contains("layout") { names.append("SwiftUI") }
        if text.contains("test") { names.append("Testing") }
        if text.contains("document") || text.contains("copy") { names.append("Documentation") }
        if text.contains("config") { names.append("Configuration") }
        var seen = Set<String>()
        return names.filter { seen.insert($0.lowercased()).inserted }
    }

    private static func classify(textScore: Int, skills: [String]) -> ContributionLane {
        if textScore > 0 { return .technicalCore }
        if textScore < 0 { return .technicalHands }
        let coreHits = skills.filter { coreSkills.contains($0) }.count
        let handsHits = skills.filter { handsSkills.contains($0) }.count
        if coreHits > handsHits { return .technicalCore }
        if handsHits > coreHits { return .technicalHands }
        return coreHits > 0 ? .technicalCore : .technicalHands
    }

    private static func complexityLabel(lane: ContributionLane, skills: [String], text: String) -> String {
        if lane == .technicalCore { return skills.count > 2 || text.contains("architect") ? "Specialized" : "Deep" }
        return skills.count > 2 ? "Broad implementation" : "Straightforward"
    }
}

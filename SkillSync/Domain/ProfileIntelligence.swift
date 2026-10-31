import Foundation

struct ExtractedSkill: Equatable, Sendable {
    var name: String
    var level: SkillLevel
}

struct ProfileExtraction: Equatable, Sendable {
    var summary: String
    var skills: [ExtractedSkill]
    /// `on-device` when Apple Intelligence wrote the structure. `catalog` when the phone matched known skill names.
    var source: String

    var userSkills: [UserSkill] {
        skills.map { skill in
            UserSkill(name: skill.name, level: skill.level, category: SkillCatalog.category(for: skill.name))
        }
    }
}

/// On-device understanding only. Trust decisions stay in `CredentialVerifier` and Cloud Functions.
enum ProfileUnderstandingService {
    static func understand(narrative: String, links: [String]) async -> ProfileExtraction {
        if let onDevice = await OnDeviceProfileIntelligence.extract(narrative: narrative, links: links),
           !onDevice.skills.isEmpty || !onDevice.summary.isEmpty {
            return onDevice
        }
        return CatalogProfileIntelligence.extract(narrative: narrative, links: links)
    }
}

enum CatalogProfileIntelligence {
    static func extract(narrative: String, links: [String]) -> ProfileExtraction {
        let text = narrative.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = text.lowercased()
        let level: SkillLevel = (lowered.contains("shipped") || lowered.contains("years") || lowered.contains("lead"))
            ? .advanced
            : .intermediate
        var remaining = lowered
        let skills: [ExtractedSkill] = SkillCatalog.all
            .sorted { $0.name.count > $1.name.count }
            .compactMap { skill in
                let needle = skill.name.lowercased()
                guard let range = remaining.range(of: needle) else { return nil }
                remaining.removeSubrange(range)
                return ExtractedSkill(name: skill.name, level: level)
            }
        let summary: String
        if text.isEmpty {
            summary = ""
        } else if let sentence = text.split(separator: ".").first {
            summary = String(sentence).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            summary = text
        }
        _ = links
        return ProfileExtraction(summary: summary, skills: skills, source: "catalog")
    }
}

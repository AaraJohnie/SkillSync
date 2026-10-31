import Foundation

enum OnDeviceProfileIntelligence {
    static func extract(narrative: String, links: [String]) async -> ProfileExtraction? {
        let text = narrative.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !links.isEmpty else { return nil }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return await AppleProfileExtractor.extract(narrative: text, links: links)
        }
        #endif
        return nil
    }
}

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, *)
private enum AppleProfileExtractor {
    static func extract(narrative: String, links: [String]) async -> ProfileExtraction? {
        guard SystemLanguageModel.default.isAvailable else { return nil }
        let catalog = SkillCatalog.all.map(\.name).joined(separator: ", ")
        let session = LanguageModelSession(instructions: """
        You extract a student profile for SkillSync. Use only the skill names in this catalog: \(catalog).
        Levels are beginner, intermediate, advanced, or mentor. Ignore employers, schools, and links as proof.
        Write one short sentence about what they can ship. Do not decide whether a link is trustworthy.
        """)
        let linkLine = links.isEmpty ? "No links." : links.joined(separator: "\n")
        let prompt = """
        Narrative:
        \(narrative.isEmpty ? "None." : narrative)

        Links, for context only:
        \(linkLine)
        """
        do {
            let response = try await session.respond(to: prompt, generating: GeneratedProfile.self)
            let draft = response.content
            let skills = draft.skills.compactMap { item -> ExtractedSkill? in
                guard let match = SkillCatalog.all.first(where: { $0.name.caseInsensitiveCompare(item.name) == .orderedSame }),
                      let level = SkillLevel(rawValue: item.level.lowercased())
                else { return nil }
                return ExtractedSkill(name: match.name, level: level)
            }
            let summary = draft.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            let catalogFill = CatalogProfileIntelligence.extract(narrative: narrative, links: links)
            let names = Set(skills.map(\.name))
            let merged = skills + catalogFill.skills.filter { !names.contains($0.name) }
            return ProfileExtraction(summary: summary.isEmpty ? catalogFill.summary : summary, skills: merged, source: "on-device")
        } catch {
            return nil
        }
    }
}

@available(iOS 26.0, *)
@Generable
private struct GeneratedProfile {
    @Guide(description: "One sentence about what this student can ship")
    var summary: String

    @Guide(description: "Catalog skills mentioned in the narrative")
    var skills: [GeneratedSkill]
}

@available(iOS 26.0, *)
@Generable
private struct GeneratedSkill {
    @Guide(description: "Exact catalog skill name")
    var name: String

    @Guide(description: "beginner, intermediate, advanced, or mentor")
    var level: String
}
#endif

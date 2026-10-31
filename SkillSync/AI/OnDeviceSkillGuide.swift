import Foundation

enum SkillGuide {
    static func profile(source: String) async throws -> SkillProfile {
        let text = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 8 else { throw SkillSyncAPIError.needsDetail("Add a bit more about what you've done.") }
        if SkillSyncBackend.isConfigured, let remote = try? await SkillSyncAPI.profileSkillsRemote(source: text) {
            return remote
        }
        if let generated = await OnDeviceSkillGuide.profile(text) {
            return generated
        }
        return SkillGuideFallback.profile(text)
    }

    static func analyze(_ request: SkillAnalysisRequest) async throws -> SkillAnalysis {
        if SkillSyncBackend.isConfigured, let remote = try? await SkillSyncAPI.analyzeSkillsRemote(request) {
            return remote
        }
        if let generated = await OnDeviceSkillGuide.analyze(request) {
            return generated
        }
        return SkillGuideFallback.analyze(request)
    }

    static func gap(skills: [String], target: String) async throws -> SkillGapReport {
        let role = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !skills.isEmpty, role.count >= 2 else {
            throw SkillSyncAPIError.needsDetail("Add the skills you have and a target role.")
        }
        if SkillSyncBackend.isConfigured, let remote = try? await SkillSyncAPI.detectSkillGapRemote(skills: skills, target: role) {
            return remote
        }
        if let generated = await OnDeviceSkillGuide.gap(skills: skills, target: role) {
            return generated
        }
        return SkillGuideFallback.gap(skills: skills, target: role)
    }
}

enum SkillGuideFallback {
    static func profile(_ source: String) -> SkillProfile {
        let found = mentioned(in: source)
        let skills = found.map { skill in
            ProfiledSkill(name: skill.name, category: skill.category.label, evidence: sentence(containing: skill.name, in: source))
        }
        let summary = skills.isEmpty
            ? "The note doesn't name a specific tool yet. Say which skill you used and on what."
            : "Pulled \(skills.map(\.name).joined(separator: ", ")) from what you wrote."
        return SkillProfile(summary: summary, skills: skills.isEmpty ? [ProfiledSkill(name: "Unspecified", category: "General", evidence: source)] : skills)
    }

    static func analyze(_ request: SkillAnalysisRequest) -> SkillAnalysis {
        let corpus = "\(request.projectDescription) \(request.experience)"
        let names = request.skills.isEmpty ? mentioned(in: corpus).map(\.name) : request.skills
        let skills = names.map { name -> AssessedSkill in
            let hit = corpus.localizedCaseInsensitiveContains(name)
            return AssessedSkill(
                name: name,
                level: hit ? "Developing" : "Beginner",
                evidence: hit ? sentence(containing: name, in: corpus) : "Named as a skill, with no project detail yet."
            )
        }
        return SkillAnalysis(
            summary: "This reads the words you supplied. It is not proof of expertise.",
            skills: skills,
            recommendations: skills.filter { $0.level == "Beginner" }.map { "Show one project where you used \($0.name)." }
        )
    }

    static func gap(skills: [String], target: String) -> SkillGapReport {
        let owned = Set(skills.map { $0.lowercased() })
        let wanted = SkillCatalog.all.filter { skill in
            !owned.contains(skill.name.lowercased()) && roleHints(target).contains(skill.category)
        }
        let missing = (wanted.isEmpty ? SkillCatalog.all.filter { !owned.contains($0.name.lowercased()) }.prefix(3) : wanted.prefix(4)).map { skill in
            SkillGapItem(name: skill.name, why: "\(target) usually needs \(skill.name), and it isn't in your list.", nextStep: "Ship a small piece that uses \(skill.name).")
        }
        return SkillGapReport(
            target: target,
            summary: "Compared \(skills.joined(separator: ", ")) with \(target).",
            missing: Array(missing),
            path: missing.map { "Practice \($0.name)" }
        )
    }

    private static func mentioned(in text: String) -> [CatalogSkill] {
        SkillCatalog.all.filter { text.localizedCaseInsensitiveContains($0.name) }
    }

    private static func sentence(containing name: String, in text: String) -> String {
        let parts = text.split { ".!?\n".contains($0) }.map { $0.trimmingCharacters(in: .whitespaces) }
        return parts.first { $0.localizedCaseInsensitiveContains(name) } ?? String(text.prefix(140))
    }

    private static func roleHints(_ target: String) -> Set<SkillCategory> {
        let lower = target.lowercased()
        if lower.contains("design") || lower.contains("ux") { return [.design, .creative] }
        if lower.contains("data") || lower.contains("machine") { return [.data] }
        if lower.contains("ios") || lower.contains("mobile") || lower.contains("swift") { return [.mobile] }
        if lower.contains("back") || lower.contains("server") { return [.backend] }
        return [.mobile, .design, .product]
    }
}

enum OnDeviceSkillGuide {
    static func profile(_ source: String) async -> SkillProfile? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return await AppleSkillGuide.profile(source)
        }
        #endif
        return nil
    }

    static func analyze(_ request: SkillAnalysisRequest) async -> SkillAnalysis? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return await AppleSkillGuide.analyze(request)
        }
        #endif
        return nil
    }

    static func gap(skills: [String], target: String) async -> SkillGapReport? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return await AppleSkillGuide.gap(skills: skills, target: target)
        }
        #endif
        return nil
    }
}

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, *)
private enum AppleSkillGuide {
    static func profile(_ source: String) async -> SkillProfile? {
        let generated: GeneratedSkillProfile? = await run(
            "Extract only skills this student text actually shows. Do not invent tools.\n\n\(source)",
            as: GeneratedSkillProfile.self
        )
        guard let generated, !generated.skills.isEmpty else { return nil }
        return SkillProfile(
            summary: generated.summary,
            skills: generated.skills.map { ProfiledSkill(name: $0.name, category: $0.category, evidence: $0.evidence) }
        )
    }

    static func analyze(_ request: SkillAnalysisRequest) async -> SkillAnalysis? {
        let prompt = """
        Assess evidence only from this text. Levels are Beginner, Developing, Strong, or Advanced. This is not proof of expertise.
        Skills: \(request.skills.joined(separator: ", "))
        Project: \(request.projectDescription)
        Experience: \(request.experience)
        """
        let generated: GeneratedSkillAnalysis? = await run(prompt, as: GeneratedSkillAnalysis.self)
        guard let generated, !generated.skills.isEmpty else { return nil }
        return SkillAnalysis(
            summary: generated.summary,
            skills: generated.skills.map { AssessedSkill(name: $0.name, level: $0.level, evidence: $0.evidence) },
            recommendations: generated.recommendations
        )
    }

    static func gap(skills: [String], target: String) async -> SkillGapReport? {
        let prompt = """
        Current skills: \(skills.joined(separator: ", "))
        Target role: \(target)
        List only missing or weaker skills. Do not repeat skills they already have.
        """
        let generated: GeneratedSkillGap? = await run(prompt, as: GeneratedSkillGap.self)
        guard let generated, !generated.missing.isEmpty else { return nil }
        return SkillGapReport(
            target: generated.target.isEmpty ? target : generated.target,
            summary: generated.summary,
            missing: generated.missing.map { SkillGapItem(name: $0.name, why: $0.why, nextStep: $0.nextStep) },
            path: generated.path
        )
    }

    private static func run<Output: Generable>(_ prompt: String, as type: Output.Type) async -> Output? {
        guard SystemLanguageModel.default.isAvailable else { return nil }
        let session = LanguageModelSession(instructions: "You are SkillSync's on-device skill guide. Use only the student's text.")
        return try? await session.respond(to: prompt, generating: type).content
    }
}

@available(iOS 26.0, *)
@Generable
private struct GeneratedSkillProfile {
    @Guide(description: "One sentence on what the text shows")
    var summary: String
    @Guide(description: "At most eight skills the text supports")
    var skills: [GeneratedProfileSkill]
}

@available(iOS 26.0, *)
@Generable
private struct GeneratedProfileSkill {
    var name: String
    var category: String
    @Guide(description: "The phrase in the text that supports this skill")
    var evidence: String
}

@available(iOS 26.0, *)
@Generable
private struct GeneratedSkillAnalysis {
    var summary: String
    var skills: [GeneratedAssessedSkill]
    var recommendations: [String]
}

@available(iOS 26.0, *)
@Generable
private struct GeneratedAssessedSkill {
    var name: String
    @Guide(description: "Beginner, Developing, Strong, or Advanced")
    var level: String
    var evidence: String
}

@available(iOS 26.0, *)
@Generable
private struct GeneratedSkillGap {
    var target: String
    var summary: String
    var missing: [GeneratedGapItem]
    var path: [String]
}

@available(iOS 26.0, *)
@Generable
private struct GeneratedGapItem {
    var name: String
    var why: String
    var nextStep: String
}
#endif

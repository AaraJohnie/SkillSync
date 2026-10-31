import Foundation

enum CampusModelAvailability: Equatable {
    case onDevice
    case unavailable(String)
}

enum OnDeviceCampusAgent {
    static var availability: CampusModelAvailability {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return AppleIntelligenceStatus.current
        }
        #endif
        return .unavailable("This iOS version has no on-device model.")
    }

    static func reply(to prompt: String, brief: CampusBrief, history: [String] = []) async -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return await AppleCampusSession.shared.reply(to: prompt, brief: brief, history: history)
        }
        #endif
        return nil
    }

    static func reset() {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            AppleCampusSession.shared.reset()
        }
        #endif
    }
}

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, *)
enum AppleIntelligenceStatus {
    static var current: CampusModelAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .onDevice
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable("Turn on Apple Intelligence in Settings to let the agent write replies.")
        case .unavailable(.deviceNotEligible):
            return .unavailable("This device cannot run Apple Intelligence. Replies stay on campus matches.")
        case .unavailable(.modelNotReady):
            return .unavailable("Apple Intelligence is still downloading. Replies stay on campus matches until it is ready.")
        @unknown default:
            return .unavailable("Apple Intelligence is unavailable. Replies stay on campus matches.")
        }
    }
}

@available(iOS 26.0, *)
final class AppleCampusSession: @unchecked Sendable {
    static let shared = AppleCampusSession()

    private let lock = NSLock()
    private var session: LanguageModelSession?
    private var holder = BriefHolder()

    func reset() {
        lock.lock()
        session = nil
        lock.unlock()
    }

    func reply(to prompt: String, brief: CampusBrief, history: [String]) async -> String? {
        guard SystemLanguageModel.default.isAvailable else { return nil }
        holder.update(brief)
        let session = currentSession()
        let prior = history.suffix(6).joined(separator: "\n")
        let request = prior.isEmpty ? prompt : "Earlier in this chat:\n\(prior)\n\nStudent now: \(prompt)"
        do {
            let response = try await session.respond(to: request)
            let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        } catch {
            reset()
            return nil
        }
    }

    private func currentSession() -> LanguageModelSession {
        lock.lock()
        defer { lock.unlock() }
        if let session { return session }
        let created = LanguageModelSession(
            model: .default,
            tools: [
                CampusMatchesTool(holder: holder),
                CampusPersonTool(holder: holder),
                CampusPitchTool(holder: holder),
                CampusHuddleTool(holder: holder),
                CampusProfileTool(holder: holder)
            ],
            instructions: """
            You are Apple Intelligence inside SkillSync. Write the reply yourself in plain sentences.
            Call a tool before you name a student, score, skill, or project. Use only facts the tool returns.
            If the student asks for people or a pitch, suggest collaborators. Talk about the huddle only when they ask about tasks, milestones, or what to do next in it.
            Name the strongest person, why they fit, and one pitch sentence. Then offer one next step. Under 110 words.
            """
        )
        session = created
        return created
    }
}

@available(iOS 26.0, *)
private final class BriefHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var brief: CampusBrief?

    func update(_ brief: CampusBrief) {
        lock.lock()
        self.brief = brief
        lock.unlock()
    }

    func current() -> CampusBrief? {
        lock.lock()
        defer { lock.unlock() }
        return brief
    }
}

@available(iOS 26.0, *)
private struct CampusMatchesTool: Tool {
    let holder: BriefHolder
    let name = "listMatches"
    let description = "List the student's strongest complementary matches, with synergy scores and reasons."

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        guard let brief = holder.current() else { return "No signed-in student." }
        let lines = brief.matches.prefix(4).map { match in
            let reasons = match.synergy.reasons.joined(separator: " ")
            let pitch = PitchTemplates.lines(seeker: brief.me, candidate: match.user, project: match.project).first ?? ""
            return "\(match.user.displayName) (\(match.user.firstName)), \(match.synergy.score)% synergy. \(reasons) Pitch: \(pitch)"
        }
        return lines.isEmpty ? "No matches." : lines.joined(separator: "\n")
    }
}

@available(iOS 26.0, *)
private struct CampusPersonTool: Tool {
    let holder: BriefHolder
    let name = "explainPerson"
    let description = "Explain why a named campus student is or is not a good collaborator."

    @Generable
    struct Arguments {
        @Guide(description: "First or full name of the student")
        var name: String
    }

    func call(arguments: Arguments) async throws -> String {
        guard let brief = holder.current() else { return "No signed-in student." }
        guard let person = CampusAgent.person(in: arguments.name, brief: brief),
              let match = brief.matches.first(where: { $0.user.id == person.id }) else {
            return "No student named \(arguments.name) is in the match list."
        }
        let pitch = PitchTemplates.lines(seeker: brief.me, candidate: person, project: match.project).first ?? ""
        return "\(person.displayName), \(match.synergy.score)% synergy. \(match.synergy.reasons.joined(separator: " ")) Pitch: \(pitch)"
    }
}

@available(iOS 26.0, *)
private struct CampusPitchTool: Tool {
    let holder: BriefHolder
    let name = "draftPitch"
    let description = "Draft a one-line collaboration pitch to a named student, or the best match if no name is given."

    @Generable
    struct Arguments {
        @Guide(description: "First or full name. Use an empty string for the best match.")
        var name: String
    }

    func call(arguments: Arguments) async throws -> String {
        guard let brief = holder.current() else { return "No signed-in student." }
        let person = CampusAgent.person(in: arguments.name, brief: brief) ?? brief.matches.first?.user
        guard let person else { return "No one to pitch." }
        let match = brief.matches.first { $0.user.id == person.id }
        let pitch = PitchTemplates.lines(seeker: brief.me, candidate: person, project: match?.project).first ?? ""
        return "Pitch \(person.displayName). \(pitch)"
    }
}

@available(iOS 26.0, *)
private struct CampusHuddleTool: Tool {
    let holder: BriefHolder
    let name = "huddleStatus"
    let description = "Summarize the active huddle, open tasks, and the next thing to do."

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        guard let brief = holder.current() else { return "No signed-in student." }
        guard let huddle = brief.huddles.first(where: { $0.status == .active }) else {
            return "No active huddle."
        }
        let title = brief.projects.first { $0.id == huddle.projectId }?.title ?? "Huddle"
        let names = huddle.memberIds.compactMap { id in brief.users.first { $0.id == id }?.displayName }
        let role = huddle.roleList.first { $0.userId == brief.me.id }?.role ?? "Collaborator"
        let open = brief.tasks.filter { $0.huddleId == huddle.id && $0.lane != .done }.map(\.title)
        let milestone = brief.milestones.first { $0.huddleId == huddle.id && !$0.isComplete }?.title
        return "\(title) is active with \(names.joined(separator: ", ")). Role: \(role). Open tasks: \(open.joined(separator: ", ")). Next milestone: \(milestone ?? "none")."
    }
}

@available(iOS 26.0, *)
private struct CampusProfileTool: Tool {
    let holder: BriefHolder
    let name = "mySkills"
    let description = "List the signed-in student's skills and the skills they still need."

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        guard let brief = holder.current() else { return "No signed-in student." }
        let have = brief.me.skills.map { "\($0.name) (\($0.level.label))" }.joined(separator: ", ")
        return "\(brief.me.displayName) has \(have). Still needs \(brief.me.neededSkills.joined(separator: ", "))."
    }
}
#endif

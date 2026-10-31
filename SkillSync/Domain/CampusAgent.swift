import Foundation
import SkillEvidenceAgent

struct CampusBrief {
    var me: UserProfile
    var users: [UserProfile]
    var matches: [MatchCandidate]
    var incoming: [CollaborationRequest]
    var huddles: [Huddle]
    var projects: [Project]
    var tasks: [HuddleTask]
    var milestones: [Milestone]
}

enum AgentAction: Equatable, Identifiable {
    case pitch(userId: String, title: String)
    case openHuddle(id: String, title: String)

    var id: String {
        switch self {
        case .pitch(let userId, _): "pitch-\(userId)"
        case .openHuddle(let id, _): "huddle-\(id)"
        }
    }

    var title: String {
        switch self {
        case .pitch(_, let title), .openHuddle(_, let title): title
        }
    }
}

struct AgentMemory: Equatable {
    var focusUserId: String?
}

struct AgentReply: Equatable {
    var text: String
    var actions: [AgentAction]
    var followUps: [String] = []
}

enum CampusAgent {
    @MainActor
    static func brief(from store: DemoStore) -> CampusBrief? {
        guard let me = store.currentUser else { return nil }
        return CampusBrief(
            me: me,
            users: store.users,
            matches: store.matches(for: me),
            incoming: store.incomingRequests(for: me.id),
            huddles: store.huddles(for: me.id),
            projects: store.projects,
            tasks: store.tasks,
            milestones: store.milestones
        )
    }

    static func reply(to prompt: String, brief: CampusBrief) -> AgentReply {
        var memory = AgentMemory()
        return reply(to: prompt, brief: brief, memory: &memory)
    }

    static func reply(to prompt: String, brief: CampusBrief, memory: inout AgentMemory) -> AgentReply {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()
        guard !lower.isEmpty else {
            return AgentReply(text: "Ask who to pitch, or what to do next in a huddle.", actions: [])
        }

        if isHelp(lower) {
            return help(brief)
        }
        if wantsAlternative(lower) {
            return alternative(brief, excluding: memory.focusUserId, memory: &memory)
        }
        if isAffirmative(lower) || (wantsPitch(lower) && !wantsRoster(lower) && person(in: text, brief: brief) == nil && memory.focusUserId != nil && !lower.contains("pitch to")) {
            let focus = focusedUser(memory, brief: brief)
            return draftPitch(for: person(in: text, brief: brief) ?? focus ?? brief.matches.first?.user, brief: brief, memory: &memory)
        }
        if wantsPitch(lower) && !wantsRoster(lower) {
            return draftPitch(for: person(in: text, brief: brief) ?? focusedUser(memory, brief: brief) ?? brief.matches.first?.user, brief: brief, memory: &memory)
        }
        if let person = person(in: text, brief: brief) {
            return explain(person, brief: brief, memory: &memory)
        }
        if wantsHuddle(lower) {
            return huddleStatus(brief, memory: &memory)
        }
        if lower == "why" || lower == "why?" || lower.hasPrefix("why ") && person(in: text, brief: brief) == nil {
            if let focus = focusedUser(memory, brief: brief) {
                return explain(focus, brief: brief, memory: &memory)
            }
        }
        if wantsRoster(lower) {
            return roster(brief, memory: &memory)
        }
        if wantsEvidence(lower) {
            return evidence(brief)
        }
        if wantsProfile(lower) {
            return profile(brief)
        }
        return nextStep(brief, memory: &memory)
    }

    static func person(in prompt: String, brief: CampusBrief) -> UserProfile? {
        let lower = prompt.lowercased()
        return brief.users
            .filter { $0.id != brief.me.id }
            .sorted { $0.displayName.count > $1.displayName.count }
            .first { person in
                lower.contains(person.displayName.lowercased()) || lower.contains(person.firstName.lowercased())
            }
    }

    private static func isHelp(_ lower: String) -> Bool {
        lower == "help" || lower.contains("what can you") || lower.contains("how do you")
    }

    private static func wantsPitch(_ lower: String) -> Bool {
        lower.contains("pitch") || lower.contains("draft") || lower.contains("write a") || lower.contains("one-line") || lower.contains("one line")
    }

    private static func wantsHuddle(_ lower: String) -> Bool {
        lower.contains("huddle") || lower.contains("task") || lower.contains("milestone") || lower.contains("ship") || lower.contains("what's next") || lower.contains("whats next") || lower.contains("what is next") || lower.contains("next step")
    }

    private static func wantsRoster(_ lower: String) -> Bool {
        lower.contains("who") || lower.contains("match") || lower.contains("collaborat") || lower.contains("partner") || lower.contains("recommend") || lower.contains("suggest") || lower.contains("people")
    }

    private static func wantsEvidence(_ lower: String) -> Bool {
        lower.contains("evidence") || lower.contains("verify") || lower.contains("trust") || lower.contains("vouch")
    }

    private static func wantsProfile(_ lower: String) -> Bool {
        lower.contains("skill") || lower.contains("gap") || lower.contains("need") || lower.contains("my profile") || lower.contains("about me")
    }

    private static func wantsAlternative(_ lower: String) -> Bool {
        lower.contains("say no") || lower.contains("says no") || lower.contains("someone else") || lower.contains("instead") || lower.contains("another")
    }

    private static func isAffirmative(_ lower: String) -> Bool {
        let trimmed = lower.trimmingCharacters(in: CharacterSet(charactersIn: "?.!"))
        return ["yes", "yeah", "yep", "ok", "okay", "sure", "do it", "draft it", "draft the pitch", "send it", "go on", "continue", "tell me more"].contains(trimmed)
    }

    private static func focusedUser(_ memory: AgentMemory, brief: CampusBrief) -> UserProfile? {
        guard let id = memory.focusUserId else { return nil }
        return brief.users.first { $0.id == id }
    }

    private static func remember(_ user: UserProfile?, memory: inout AgentMemory) {
        if let user { memory.focusUserId = user.id }
    }

    /// Alternatives under this score do not cover the gap well enough to recommend.
    private static func worthPitching(_ match: MatchCandidate) -> Bool {
        match.synergy.score >= 60 && match.synergy.complementaryCoverage >= 0.34
    }

    private static func help(_ brief: CampusBrief) -> AgentReply {
        AgentReply(
            text: "I can tell you who fills your skill gap, draft a one-line pitch, and say what is still open in a huddle. I only use people already on this campus.",
            actions: brief.matches.first.map { [.pitch(userId: $0.user.id, title: "Pitch \($0.user.firstName)")] } ?? []
        )
    }

    private static func roster(_ brief: CampusBrief, memory: inout AgentMemory) -> AgentReply {
        guard let best = brief.matches.first, worthPitching(best) else {
            return AgentReply(text: "Nobody on campus covers your gap well enough to pitch yet. Add the skill you still need, or open your huddle and ship what you already started.", actions: huddleAction(brief))
        }
        remember(best.user, memory: &memory)
        let pitch = PitchTemplates.lines(seeker: brief.me, candidate: best.user, project: best.project).first ?? ""
        var lines = ["Pitch \(best.user.displayName). \(best.synergy.score)% synergy."]
        if let reason = best.synergy.reasons.first {
            lines.append(reason)
        }
        lines.append("Send this:\n\(pitch)")
        let alternates = brief.matches.dropFirst().filter(worthPitching).prefix(2)
        if !alternates.isEmpty {
            let names = alternates.map { "\($0.user.firstName) (\($0.synergy.score)%)" }.joined(separator: ", ")
            lines.append("If \(best.user.firstName) says no, \(names) still cover the gap.")
        }
        if let huddleLine = activeHuddleLine(brief) {
            lines.append(huddleLine)
        }
        lines.append("Say yes and I will open the pitch, or ask what happens if they decline.")
        var actions: [AgentAction] = [.pitch(userId: best.user.id, title: "Pitch \(best.user.firstName)")]
        actions.append(contentsOf: huddleAction(brief))
        return AgentReply(
            text: lines.joined(separator: "\n\n"),
            actions: actions,
            followUps: ["Why \(best.user.firstName)?", "What if they say no?", "What's next in my huddle?"]
        )
    }

    private static func explain(_ person: UserProfile, brief: CampusBrief, memory: inout AgentMemory) -> AgentReply {
        remember(person, memory: &memory)
        guard let match = brief.matches.first(where: { $0.user.id == person.id }) else {
            return AgentReply(text: "\(person.displayName) is on campus, but not in your current match list.", actions: [])
        }
        let reasons = match.synergy.reasons.isEmpty
            ? "Synergy is \(match.synergy.score)%."
            : match.synergy.reasons.joined(separator: " ")
        let pitch = PitchTemplates.lines(seeker: brief.me, candidate: person, project: match.project).first ?? ""
        let verdict = worthPitching(match)
            ? "Worth a pitch."
            : "Weak fit. I would not spend the pitch on \(person.firstName)."
        return AgentReply(
            text: "\(person.displayName) — \(match.synergy.score)% synergy. \(verdict)\n\n\(reasons)\n\nPitch:\n\(pitch)",
            actions: worthPitching(match) ? [.pitch(userId: person.id, title: "Pitch \(person.firstName)")] : [],
            followUps: ["Draft the pitch", "What if they say no?"]
        )
    }

    private static func draftPitch(for person: UserProfile?, brief: CampusBrief, memory: inout AgentMemory) -> AgentReply {
        guard let person else {
            return AgentReply(text: "Name someone on campus, or ask who you should pitch.", actions: [])
        }
        remember(person, memory: &memory)
        let match = brief.matches.first { $0.user.id == person.id }
        let lines = PitchTemplates.lines(seeker: brief.me, candidate: person, project: match?.project)
        let score = match.map { "\($0.synergy.score)% synergy. " } ?? ""
        return AgentReply(
            text: "\(score)This is the line for \(person.firstName):\n\n\(lines[0])\n\nOpen the pitch to send it. A huddle starts only if they accept. If they decline, ask me for the next person.",
            actions: [.pitch(userId: person.id, title: "Open pitch to \(person.firstName)")],
            followUps: ["What if they say no?", "What's next in my huddle?"]
        )
    }

    private static func alternative(_ brief: CampusBrief, excluding focusId: String?, memory: inout AgentMemory) -> AgentReply {
        let next = brief.matches.first { match in
            match.user.id != focusId && worthPitching(match)
        }
        guard let next else {
            return AgentReply(
                text: "Nobody else covers your gap well enough. Stay with the person you already picked, or ship the huddle you have open.",
                actions: huddleAction(brief)
            )
        }
        remember(next.user, memory: &memory)
        let pitch = PitchTemplates.lines(seeker: brief.me, candidate: next.user, project: next.project).first ?? ""
        return AgentReply(
            text: "If they decline, pitch \(next.user.displayName) next. \(next.synergy.score)% synergy.\n\n\(next.synergy.reasons.first ?? "")\n\n\(pitch)",
            actions: [.pitch(userId: next.user.id, title: "Pitch \(next.user.firstName)")],
            followUps: ["Draft the pitch", "Why \(next.user.firstName)?"]
        )
    }

    private static func evidence(_ brief: CampusBrief) -> AgentReply {
        let report = SkillEvidenceBridge.profile(
            user: brief.me,
            projects: brief.projects,
            portfolioText: nil,
            portfolioWasFetched: false,
            gitHub: nil
        )
        let lines = report.skills.map { "\($0.claimedSkill) — \($0.status.label). \($0.observation.notes.first ?? $0.status.detail)" }
        let body = lines.isEmpty ? "No skills are claimed yet." : lines.joined(separator: "\n")
        return AgentReply(
            text: "\(body)\n\n\(report.completedCollaborations) completed collaborations. \(report.peerConfirmations) peer confirmations. This is evidence, not a trust score.",
            actions: [],
            followUps: ["Who should I pitch?"]
        )
    }

    private static func profile(_ brief: CampusBrief) -> AgentReply {
        let have = brief.me.skills.map { "\($0.name) (\($0.level.label))" }.joined(separator: ", ")
        let need = brief.me.neededSkills.joined(separator: ", ")
        let haveLine = have.isEmpty ? "You have not listed a skill yet." : "You have \(have)."
        let needLine = need.isEmpty ? "You have not listed a skill you still need." : "You still need \(need)."
        return AgentReply(text: "\(haveLine)\n\n\(needLine)\n\nMatches rank people who cover that gap and need something you already do.", actions: [])
    }

    private static func huddleStatus(_ brief: CampusBrief, memory: inout AgentMemory) -> AgentReply {
        guard let huddle = brief.huddles.first(where: { $0.status == .active }) ?? brief.huddles.first else {
            if let request = brief.incoming.first, let from = brief.users.first(where: { $0.id == request.fromUserId }) {
                return AgentReply(
                    text: "No active huddle. \(from.displayName) already pitched you at \(request.synergyScore)% synergy. Accept it from Home if you want to start.",
                    actions: []
                )
            }
            return nextStep(brief, memory: &memory)
        }
        let project = brief.projects.first { $0.id == huddle.projectId }
        let title = project?.title ?? "This huddle"
        let names = huddle.memberIds.compactMap { id in brief.users.first { $0.id == id }?.displayName }
        let openTasks = brief.tasks.filter { $0.huddleId == huddle.id && $0.lane != .done }
        let openMilestones = brief.milestones.filter { $0.huddleId == huddle.id && !$0.isComplete }
        var lines = ["\(title) is \(huddle.status == .active ? "active" : "shipped") with \(names.joined(separator: " and "))."]
        if let role = huddle.roleList.first(where: { $0.userId == brief.me.id }) {
            lines.append("Your role is \(role.role).")
        }
        if openTasks.isEmpty {
            lines.append(huddle.status == .active ? "Tasks are clear. Ship with a proof link when the slice is real." : "Nothing left open.")
        } else {
            let titles = openTasks.prefix(3).map(\.title).joined(separator: ", ")
            lines.append("Still open: \(titles).")
        }
        if let milestone = openMilestones.first {
            lines.append("Next milestone: \(milestone.title).")
        }
        return AgentReply(
            text: lines.joined(separator: "\n\n"),
            actions: [.openHuddle(id: huddle.id, title: "Open \(title)")],
            followUps: ["Who should I pitch?", "What skill am I missing?"]
        )
    }

    private static func nextStep(_ brief: CampusBrief, memory: inout AgentMemory) -> AgentReply {
        if brief.huddles.contains(where: { $0.status == .active }) {
            return huddleStatus(brief, memory: &memory)
        }
        if let request = brief.incoming.first, let from = brief.users.first(where: { $0.id == request.fromUserId }) {
            return AgentReply(
                text: "\(from.displayName) is waiting on your answer to a \(request.synergyScore)% pitch. Respond before you send a new one.",
                actions: [],
                followUps: ["Who should I pitch?"]
            )
        }
        return roster(brief, memory: &memory)
    }

    private static func activeHuddleLine(_ brief: CampusBrief) -> String? {
        guard let huddle = brief.huddles.first(where: { $0.status == .active }) else { return nil }
        let title = brief.projects.first { $0.id == huddle.projectId }?.title ?? "your huddle"
        let open = brief.tasks.filter { $0.huddleId == huddle.id && $0.lane != .done }.count
        if open == 0 {
            return "You already have \(title) open. Ship that slice if it is the real work."
        }
        return "You already have \(title) open, with \(open) task\(open == 1 ? "" : "s") still unfinished."
    }

    private static func huddleAction(_ brief: CampusBrief) -> [AgentAction] {
        guard let huddle = brief.huddles.first(where: { $0.status == .active }) else { return [] }
        let title = brief.projects.first { $0.id == huddle.projectId }?.title ?? "huddle"
        return [.openHuddle(id: huddle.id, title: "Open \(title)")]
    }
}

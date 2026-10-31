import Foundation

enum RoleContract {
    static func suggest(members: [UserProfile], required: [String]) -> [RoleAssignment] {
        var claimed = Set<String>()
        var assignments: [RoleAssignment] = []

        for skill in required {
            let owner = members
                .filter { !claimed.contains($0.id) }
                .compactMap { member -> (UserProfile, UserSkill)? in
                    guard let owned = member.skill(named: skill) else { return nil }
                    return (member, owned)
                }
                .max { $0.1.level.rank < $1.1.level.rank }
            if let owner {
                claimed.insert(owner.0.id)
                assignments.append(RoleAssignment(userId: owner.0.id, role: skill))
            }
        }

        for member in members where !claimed.contains(member.id) {
            let role = member.skills.max { $0.level.rank < $1.level.rank }?.name ?? "Collaborator"
            assignments.append(RoleAssignment(userId: member.id, role: role))
        }
        return assignments
    }
}

enum Reliability {
    static func showedUp(userId: String, huddleId: String, tasks: [HuddleTask], messages: [HuddleMessage]) -> Bool {
        let finished = tasks.contains { $0.huddleId == huddleId && $0.assigneeId == userId && $0.lane == .done }
        let wrote = messages.filter { $0.huddleId == huddleId && $0.authorId == userId }.count >= 2
        return finished || wrote
    }
}

enum PitchTemplates {
    static func bridge(seeker: UserProfile, candidate: UserProfile) -> (have: String, need: String) {
        let have = seeker.skills.first?.name ?? "your skills"
        let need = seeker.neededSkills.first { candidate.ownedSkillNames.contains($0) }
            ?? candidate.skills.first?.name
            ?? "the missing skill"
        return (have, need)
    }

    static func lines(seeker: UserProfile, candidate: UserProfile, project: Project?) -> [String] {
        let pair = bridge(seeker: seeker, candidate: candidate)
        let title = project?.title ?? "a shippable slice"
        let days = project?.durationDays ?? 7
        return [
            "I have \(pair.have), you have \(pair.need). Let’s ship \(title) in \(days) days.",
            "You cover what I’m missing. No followers — \(days) days and a proof link.",
            "I’ll own \(pair.have). You own \(pair.need). Huddle this week."
        ]
    }
}

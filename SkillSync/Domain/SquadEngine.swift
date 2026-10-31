import Foundation

enum SquadEngine {
    static func propose(
        seeker: UserProfile,
        project: Project,
        pool: [UserProfile],
        limit: Int = 3
    ) -> [MicroSquad] {
        let others = pool.filter { $0.id != seeker.id && $0.onboardingComplete }
        let missing = GapAnalyzer.missing(required: project.requiredSkills, owned: seeker.skills)
        var squads: [MicroSquad] = []

        for candidate in others {
            if covers(missing, with: [candidate]) {
                squads.append(make(seeker: seeker, project: project, members: [candidate], missing: missing))
            }
        }

        if missing.count >= 2 {
            for i in others.indices {
                for j in others.indices where j > i {
                    let pair = [others[i], others[j]]
                    if covers(missing, with: pair) {
                        squads.append(make(seeker: seeker, project: project, members: pair, missing: missing))
                    }
                }
            }
        }

        return Array(
            squads
                .sorted { $0.score > $1.score }
                .prefix(limit)
        )
    }

    private static func covers(_ missing: [String], with members: [UserProfile]) -> Bool {
        guard !missing.isEmpty else { return false }
        let owned = Set(members.flatMap { $0.skills.map(\.name) })
        return missing.allSatisfy { owned.contains($0) }
    }

    private static func make(
        seeker: UserProfile,
        project: Project,
        members: [UserProfile],
        missing: [String]
    ) -> MicroSquad {
        let team = [seeker] + members
        var owners: [String: String] = [:]
        for skill in project.requiredSkills {
            if let owner = team
                .compactMap({ member -> (UserProfile, Int)? in
                    guard let level = member.skill(named: skill)?.level.rank else { return nil }
                    return (member, level)
                })
                .max(by: { $0.1 < $1.1 })?
                .0
            {
                owners[skill] = owner.id
            }
        }

        let synergies = members.map { SynergyEngine.evaluate(seeker: seeker, candidate: $0, project: project).score }
        let average = synergies.isEmpty ? 0 : synergies.reduce(0, +) / synergies.count
        let overlapPenalty = redundantCount(team: members, skills: missing)
        let score = min(99, max(40, average - overlapPenalty * 8))

        var reasons: [String] = []
        for skill in missing {
            if let ownerId = owners[skill], let owner = team.first(where: { $0.id == ownerId }) {
                reasons.append("\(owner.firstName) brings \(skill).")
            }
        }
        if members.count == 1 {
            reasons.append("Two-person huddle covers the gap.")
        } else {
            reasons.append("A micro-squad of \(team.count) covers every required skill.")
        }

        return MicroSquad(
            id: members.map(\.id).sorted().joined(separator: "-"),
            projectId: project.id,
            memberIds: members.map(\.id),
            skillOwners: owners,
            score: score,
            reasons: reasons
        )
    }

    private static func redundantCount(team: [UserProfile], skills: [String]) -> Int {
        skills.filter { skill in
            team.filter { $0.ownedSkillNames.contains(skill) }.count > 1
        }.count
    }
}

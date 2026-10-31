import Foundation

struct EvidenceLine: Identifiable, Hashable {
    var id: String
    var title: String
    var detail: String
    var isPresent: Bool
}

struct TrustDossier: Hashable {
    var identity: [EvidenceLine]
    var skillEvidence: [EvidenceLine]
    var history: [EvidenceLine]

    var summary: [EvidenceLine] {
        (identity + skillEvidence + history).filter(\.isPresent)
    }

    static func make(for user: UserProfile, completedTasks: Int) -> TrustDossier {
        let emailOK = user.isStudentVerified
        let schoolOK = !user.university.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let github = user.platformLinks.first { $0.status == .verified && $0.platform == .github }
        let portfolio = user.platformLinks.first {
            $0.status == .verified && $0.platform != .github && !$0.platform.isProfileNetwork
        }
        let projects = user.collaborations.count
        let vouches = user.vouches.count
        let skillName = user.skills.first?.name ?? "Skill"
        let hasSkillProof = !user.skills.isEmpty && (github != nil || projects > 0)

        return TrustDossier(
            identity: [
                EvidenceLine(id: "email", title: "Email", detail: emailOK ? user.email : "Use a campus email so identity can be checked.", isPresent: emailOK),
                EvidenceLine(id: "institution", title: "Institution", detail: schoolOK ? user.university : "Add the school you attend.", isPresent: schoolOK)
            ],
            skillEvidence: [
                EvidenceLine(id: "github", title: "GitHub", detail: github.map { "@\($0.handle)" } ?? "No GitHub profile linked yet.", isPresent: github != nil),
                EvidenceLine(id: "portfolio", title: "Portfolio", detail: portfolio.map { $0.platform.label } ?? "No Behance, Dribbble, or Figma link yet.", isPresent: portfolio != nil),
                EvidenceLine(
                    id: "skill",
                    title: skillName,
                    detail: hasSkillProof ? "Evidence available from a profile link or shipped work." : "Listed, with no project evidence yet.",
                    isPresent: hasSkillProof
                )
            ],
            history: [
                EvidenceLine(id: "projects", title: "Completed projects", detail: projects == 0 ? "None shipped inside SkillSync yet." : "\(projects) completed collaboration\(projects == 1 ? "" : "s").", isPresent: projects > 0),
                EvidenceLine(id: "tasks", title: "Completed tasks", detail: completedTasks == 0 ? "No finished tasks yet." : "\(completedTasks) task\(completedTasks == 1 ? "" : "s") marked done.", isPresent: completedTasks > 0),
                EvidenceLine(id: "vouches", title: "Peer vouches", detail: vouches == 0 ? "No teammate has vouched yet." : "\(vouches) peer vouch\(vouches == 1 ? "" : "es").", isPresent: vouches > 0)
            ]
        )
    }
}

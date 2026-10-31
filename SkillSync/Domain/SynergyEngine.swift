import Foundation

enum SynergyEngine {
    private static let complementaryWeight = 0.40
    private static let reverseWeight = 0.25
    private static let proficiencyWeight = 0.15
    private static let availabilityWeight = 0.10
    private static let projectWeight = 0.10

    static func evaluate(
        seeker: UserProfile,
        candidate: UserProfile,
        project: Project? = nil
    ) -> SynergyBreakdown {
        let seekerNeeds = effectiveNeeds(for: seeker, project: project)
        let candidateNeeds = candidate.neededSkills

        let complementary = coverage(needs: seekerNeeds, skills: candidate.skills)
        let reverse = coverage(needs: candidateNeeds, skills: seeker.skills)
        let proficiency = proficiencyFit(needs: seekerNeeds, skills: candidate.skills)
        let availability = availabilityOverlap(seeker.availability, candidate.availability)
        let projectFit = projectCoverage(project, candidate: candidate, seeker: seeker)

        var raw =
            complementary * complementaryWeight +
            reverse * reverseWeight +
            proficiency * proficiencyWeight +
            availability * availabilityWeight +
            projectFit * projectWeight

        if complementary == 0 {
            raw = min(raw, 0.35)
        }

        let score = Int((raw * 100).rounded())
        let reasons = reasonList(
            seeker: seeker,
            candidate: candidate,
            seekerNeeds: seekerNeeds,
            complementary: complementary,
            reverse: reverse,
            project: project
        )

        return SynergyBreakdown(
            score: min(max(score, 0), 99),
            complementaryCoverage: complementary,
            reverseCoverage: reverse,
            proficiencyFit: proficiency,
            availabilityOverlap: availability,
            projectFit: projectFit,
            reasons: reasons
        )
    }

    static func effectiveNeeds(for user: UserProfile, project: Project?) -> [String] {
        if let project, !project.requiredSkills.isEmpty {
            return GapAnalyzer.missing(required: project.requiredSkills, owned: user.skills)
        }
        return user.neededSkills
    }

    private static func coverage(needs: [String], skills: [UserSkill]) -> Double {
        guard !needs.isEmpty else { return 0.55 }
        let owned = Set(skills.map(\.name))
        let hits = needs.filter { owned.contains($0) }.count
        return Double(hits) / Double(needs.count)
    }

    private static func proficiencyFit(needs: [String], skills: [UserSkill]) -> Double {
        let covering = GapAnalyzer.covering(required: needs, owned: skills)
        guard !covering.isEmpty else { return 0.25 }
        let average = covering.map { Double($0.level.rank) }.reduce(0, +) / Double(covering.count)
        return average / 4.0
    }

    private static func availabilityOverlap(_ a: Availability, _ b: Availability) -> Double {
        let days = Double(a.weekdays.intersection(b.weekdays).count) / 7.0
        let hoursDelta = abs(a.hoursPerWeek - b.hoursPerWeek)
        let hours = max(0, 1.0 - Double(hoursDelta) / 20.0)
        return (days * 0.6) + (hours * 0.4)
    }

    private static func projectCoverage(_ project: Project?, candidate: UserProfile, seeker: UserProfile) -> Double {
        guard let project else { return 0.72 }
        let missing = GapAnalyzer.missing(required: project.requiredSkills, owned: seeker.skills)
        if missing.isEmpty { return 0.8 }
        return coverage(needs: missing, skills: candidate.skills)
    }

    private static func reasonList(
        seeker: UserProfile,
        candidate: UserProfile,
        seekerNeeds: [String],
        complementary: Double,
        reverse: Double,
        project: Project?
    ) -> [String] {
        var reasons: [String] = []
        let candidateNames = candidate.ownedSkillNames
        let filled = seekerNeeds.filter { candidateNames.contains($0) }
        if !filled.isEmpty {
            reasons.append("Has \(filled.joined(separator: ", ")) — the skill\(filled.count == 1 ? "" : "s") you still need.")
        }
        let reverseHits = candidate.neededSkills.filter { seeker.ownedSkillNames.contains($0) }
        if !reverseHits.isEmpty {
            reasons.append("Needs \(reverseHits.joined(separator: ", ")) — work you already do.")
        }
        let sharedDays = seeker.availability.weekdays.intersection(candidate.availability.weekdays).count
        if sharedDays >= 3 {
            reasons.append("Availability overlaps on \(sharedDays) days.")
        }
        if let project {
            reasons.append("Fits “\(project.title)” better than a popularity match would.")
        }
        if complementary < 0.34 {
            reasons.append("Limited complementary coverage — this is a weak collaboration fit.")
        }
        if reverse == 0 && complementary > 0.5 {
            reasons.append("Strong one-way fit. They may still want a different partner.")
        }
        return reasons
    }
}

import Foundation
import SkillEvidenceAgent

enum SkillEvidenceBridge {
    static func corpus(
        user: UserProfile,
        projects: [Project],
        peerNotes: [String],
        portfolioText: String?,
        portfolioWasFetched: Bool,
        gitHub: GitHubSnapshot?
    ) -> EvidenceCorpus {
        let completed = user.collaborations
        let teammateNames = Set(completed.flatMap(\.teammateNames))
        let facts = completed.map { item in
            let peer = peerNotes.contains { note in
                note.localizedCaseInsensitiveContains(item.projectTitle)
            }
            return CollaborationFact(
                id: item.id,
                projectId: item.projectId,
                projectTitle: item.projectTitle,
                role: item.role,
                note: [item.shipNote, peerNotes.joined(separator: ". ")].compactMap { $0 }.joined(separator: ". "),
                teammateIds: item.teammateNames,
                completed: true,
                peerConfirmed: peer || !user.vouches.filter { $0.projectTitle == item.projectTitle }.isEmpty
            )
        }
        let projectRecords = projects
            .filter { $0.memberIds.contains(user.id) || $0.ownerId == user.id }
            .map { project in
                ProjectRecord(
                    id: project.id,
                    name: project.title,
                    description: [project.summary, project.shipNote].compactMap { $0 }.joined(separator: ". "),
                    technologies: project.requiredSkills,
                    repositoryURL: project.proofURL,
                    portfolioURL: nil,
                    contributorIds: project.memberIds,
                    isPlatformRecord: project.status == .completed
                )
            }
        let portfolio = portfolioText.flatMap { text -> PortfolioDocument? in
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return PortfolioDocument(url: nil, text: trimmed, wasFetched: portfolioWasFetched)
        }
        return EvidenceCorpus(
            subjectId: user.id,
            displayName: user.displayName,
            emailVerified: user.isStudentVerified,
            institution: user.university,
            claimedSkills: user.skills.map { ClaimedSkill(name: $0.name) },
            gitHub: gitHub,
            portfolio: portfolio,
            certificates: [],
            projects: projectRecords,
            collaborations: facts,
            completedCollaborationCount: completed.count,
            uniqueCollaboratorCount: teammateNames.count,
            peerConfirmationCount: user.vouches.count
        )
    }

    static func profile(
        user: UserProfile,
        projects: [Project],
        portfolioText: String?,
        portfolioWasFetched: Bool,
        gitHub: GitHubSnapshot?
    ) -> TrustProfile {
        return assemble(
            user: user,
            projects: projects,
            portfolioText: portfolioText,
            portfolioWasFetched: portfolioWasFetched,
            gitHub: gitHub
        ).profile
    }

    static func assemble(
        user: UserProfile,
        projects: [Project],
        portfolioText: String?,
        portfolioWasFetched: Bool,
        portfolioURL: String? = nil,
        gitHub: GitHubSnapshot?,
        stage override: ProjectStage? = nil,
        vouch: VouchAttempt? = nil
    ) -> AssemblyResult {
        let notes = user.vouches.map { "\($0.projectTitle). \($0.note)" }
        let corpus = corpus(
            user: user,
            projects: projects,
            peerNotes: notes,
            portfolioText: portfolioText,
            portfolioWasFetched: portfolioWasFetched,
            gitHub: gitHub
        )
        let stage = override ?? stage(for: user, projects: projects)
        return EvidenceAgent().assemble(AssemblyInput(stage: stage, corpus: corpus, portfolioURL: portfolioURL, vouch: vouch))
    }

    private static func stage(for user: UserProfile, projects: [Project]) -> ProjectStage {
        let mine = projects.filter { $0.memberIds.contains(user.id) || $0.ownerId == user.id }
        if !user.vouches.isEmpty { return .vouched }
        if !user.collaborations.isEmpty || mine.contains(where: { $0.status == .completed }) { return .shipped }
        if mine.contains(where: { $0.status == .active }) { return .huddle }
        if mine.contains(where: { $0.status == .recruiting }) { return .recruiting }
        return .signup
    }
}

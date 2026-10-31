import SwiftUI
import SkillEvidenceAgent

struct TrustProfileView: View {
    @Environment(AppSession.self) private var session
    @State private var portfolioDraft = ""
    @State private var fetchedPortfolio: String?
    @State private var portfolioFetched = false
    @State private var gitHub: GitHubSnapshot?
    @State private var profile: TrustProfile?
    @State private var sequence = ""
    @State private var projects: [ExtractedPortfolioProject] = []
    @State private var message: String?
    @State private var busy = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let profile {
                    if !sequence.isEmpty {
                        Text(sequence)
                            .font(.caption)
                            .foregroundStyle(Ink.mute)
                    }
                    card(profile)
                    skills(profile)
                    if !projects.isEmpty {
                        extracted
                    }
                    if !profile.notices.isEmpty {
                        notices(profile.notices)
                    }
                }
                sources
            }
            .padding(20)
        }
        .background(Ink.bg.ignoresSafeArea())
        .navigationTitle("Evidence")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh(fetchGitHub: false) }
    }

    private func card(_ profile: TrustProfile) -> some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(profile.displayName)
                    .font(Typeface.display(28))
                    .foregroundStyle(Ink.paper)
                ForEach(profile.identity) { line in
                    Text(line.confirmed ? "✓ \(line.detail)" : line.detail)
                        .font(.subheadline)
                        .foregroundStyle(line.confirmed ? Ink.teal : Ink.mute)
                }
                Text("\(profile.completedCollaborations) completed collaborations")
                    .foregroundStyle(Ink.paper)
                Text("\(profile.uniqueCollaborators) collaborators · \(profile.peerConfirmations) peer confirmations")
                    .font(.subheadline)
                    .foregroundStyle(Ink.mute)
                if !profile.evidenceSources.isEmpty {
                    Text(profile.evidenceSources.map(label).joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(Ink.gold)
                }
            }
        }
    }

    private func skills(_ profile: TrustProfile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Skills")
            ForEach(profile.skills) { verdict in
                PaperCard(padding: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(verdict.claimedSkill)
                                .font(.headline)
                                .foregroundStyle(Ink.paper)
                            Spacer()
                            Text(verdict.status.label)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(color(verdict.status))
                        }
                        Text(verdict.status.detail)
                            .font(.caption)
                            .foregroundStyle(Ink.mute)
                        ForEach(verdict.observation.notes, id: \.self) { note in
                            Text(note)
                                .font(.subheadline)
                                .foregroundStyle(Ink.paper.opacity(0.9))
                        }
                    }
                }
            }
        }
    }

    private var extracted: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Projects read from the portfolio")
            ForEach(projects) { project in
                PaperCard(padding: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(project.name).font(.headline).foregroundStyle(Ink.paper)
                        Text(project.technologies.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(Ink.teal)
                        Text(project.category).font(.caption).foregroundStyle(Ink.mute)
                    }
                }
            }
        }
    }

    private func notices(_ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(lines, id: \.self) { line in
                Text(line).font(.caption).foregroundStyle(Ink.mute)
            }
        }
    }

    private var sources: some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(text: "Add a source")
                TextField("Portfolio page or a sentence from it", text: $portfolioDraft, axis: .vertical)
                    .lineLimit(2...4)
                    .foregroundStyle(Ink.paper)
                if let message {
                    Text(message).font(.caption).foregroundStyle(Ink.coral)
                }
                Button(busy ? "Checking…" : "Check this source") {
                    Task { await addSource() }
                }
                .font(.headline)
                .foregroundStyle(Ink.stamp)
                .disabled(busy)
                Button("Read linked GitHub") {
                    Task { await refresh(fetchGitHub: true) }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Ink.teal)
                .disabled(busy)
            }
        }
    }

    private func addSource() async {
        let raw = portfolioDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        busy = true
        message = nil
        let decision = EvidenceAgent().screenPortfolioURL(raw)
        if decision.isAllowed, let url = decision.url {
            do {
                fetchedPortfolio = try await PortfolioTextFetch.load(url: url)
                portfolioFetched = true
            } catch {
                message = error.localizedDescription
                busy = false
                return
            }
        } else if decision.rejection == .notHTTPS && !raw.hasPrefix("http") {
            fetchedPortfolio = raw
            portfolioFetched = false
        } else if let rejection = decision.rejection {
            message = rejectionCopy(rejection)
            busy = false
            return
        }
        projects = PortfolioExtractor.projects(from: fetchedPortfolio ?? raw)
        await refresh(fetchGitHub: false)
        busy = false
    }

    private func refresh(fetchGitHub: Bool) async {
        guard let user = session.store.currentUser else { return }
        if fetchGitHub, let login = user.platformLinks.first(where: { $0.platform == .github && $0.status == .verified })?.handle {
            busy = true
            message = nil
            do {
                gitHub = try await GitHubPublicLookup.snapshot(login: login)
            } catch {
                message = error.localizedDescription
            }
            busy = false
        }
        let assembled = SkillEvidenceBridge.assemble(
            user: user,
            projects: session.store.projects,
            portfolioText: fetchedPortfolio,
            portfolioWasFetched: portfolioFetched,
            gitHub: gitHub
        )
        profile = assembled.profile
        sequence = assembled.summary
    }

    private func label(_ source: EvidenceSourceKind) -> String {
        switch source {
        case .gitHub: "GitHub"
        case .portfolio: "Portfolio"
        case .project: "Projects"
        case .certificate: "Certificates"
        case .contribution: "Contributions"
        case .collaboration: "Collaborations"
        }
    }

    private func color(_ status: EvidenceStatus) -> Color {
        switch status {
        case .verified: Ink.teal
        case .supported: Ink.teal
        case .evidenceAvailable: Ink.gold
        case .unverified: Ink.mute
        }
    }

    private func rejectionCopy(_ rejection: PortfolioURLRejection) -> String {
        switch rejection {
        case .empty: "Add a page address or a sentence."
        case .notHTTPS: "Portfolio pages have to use https."
        case .hasCredentials: "Remove the username and password from the address."
        case .addressHost: "Use a site name, not a numeric address."
        case .localHost: "That address points at this device or a private network."
        case .unusualPort: "Use the standard https port."
        case .tooLong: "That address is too long."
        }
    }
}

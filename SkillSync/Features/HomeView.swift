import SwiftUI

struct HomeView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if session.store.showPitchCoach {
                    coach
                }
                if let request = incoming.first {
                    requestBanner(request)
                }
                if let huddle = activeHuddles.first {
                    huddleCard(huddle)
                }
                nextStep
                otherMatches
            }
            .padding(20)
        }
        .background(Ink.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                CampusAccountButton()
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    session.coordinator.sheet = .createProject
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(Ink.gold)
                }
                .accessibilityLabel("Start a project")
            }
        }
    }

    private var user: UserProfile? { session.store.currentUser }
    private var incoming: [CollaborationRequest] {
        guard let id = user?.id else { return [] }
        return session.store.incomingRequests(for: id)
    }
    private var activeHuddles: [Huddle] {
        guard let id = user?.id else { return [] }
        return session.store.huddles(for: id).filter { $0.status == .active }
    }
    private var topMatches: [MatchCandidate] {
        guard let user else { return [] }
        return Array(session.store.matches(for: user).prefix(3))
    }

    private var featuredMatch: MatchCandidate? { topMatches.first }
    private var otherPeople: [MatchCandidate] { Array(topMatches.dropFirst().prefix(2)) }

    private var header: some View {
        Text(greeting)
            .font(Typeface.display(34))
            .foregroundStyle(Ink.paper)
    }

    private var greeting: String {
        "Hello, \(user?.firstName ?? "there")."
    }

    private var coach: some View {
        Button {
            session.store.dismissPitchCoach()
        } label: {
            PaperCard(padding: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "How this works")
                    Text("1. See who fills your gap.  2. Send a one-line pitch.  3. If they accept, you huddle.")
                        .font(.subheadline)
                        .foregroundStyle(Ink.paper)
                    Text("Tap to hide")
                        .font(.caption)
                        .foregroundStyle(Ink.mute)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var nextStep: some View {
        Group {
            if let match = featuredMatch, let me = user {
                let pair = PitchTemplates.bridge(seeker: me, candidate: match.user)
                PaperCard {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(text: "Next step")
                        Text("You still need \(pair.need). \(match.user.firstName) has it.")
                            .font(Typeface.title())
                            .foregroundStyle(Ink.paper)
                        Text("Send a one-line pitch. If they accept, you start a huddle.")
                            .font(.subheadline)
                            .foregroundStyle(Ink.mute)
                        PrimaryButton(title: "Pitch \(match.user.firstName)") {
                            session.store.dismissPitchCoach()
                            session.coordinator.sheet = .pitch(match)
                        }
                    }
                }
            }
        }
    }

    private var otherMatches: some View {
        Group {
            if !otherPeople.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        SectionLabel(text: "Or pitch someone else")
                        Spacer()
                        Button("See all") { session.coordinator.tab = .discover }
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Ink.teal)
                    }
                    ForEach(Array(otherPeople.enumerated()), id: \.element.id) { index, match in
                        Button {
                            session.coordinator.sheet = .pitch(match)
                        } label: {
                            MatchRow(match: match)
                        }
                        .buttonStyle(.plain)
                        .listAppear(index: index)
                    }
                }
            }
        }
    }

    private func requestBanner(_ request: CollaborationRequest) -> some View {
        let from = session.store.user(request.fromUserId)
        return Button {
            session.coordinator.open(.requests)
        } label: {
            PaperCard {
                HStack(spacing: 14) {
                    InitialsMark(name: from?.displayName ?? "?", initials: from?.initials ?? "?")
                    VStack(alignment: .leading, spacing: 4) {
                        SectionLabel(text: "Collaboration pitch")
                        Text("\(from?.displayName ?? "Someone") wants to build with you")
                            .foregroundStyle(Ink.paper)
                            .font(.headline)
                        Text("\(request.synergyScore)% synergy")
                            .foregroundStyle(Ink.gold)
                            .font(.subheadline)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(Ink.mute)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func huddleCard(_ huddle: Huddle) -> some View {
        let project = session.store.project(huddle.projectId)
        return Button {
            session.coordinator.openHuddle(huddle.id)
        } label: {
            PaperCard {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "Active huddle")
                    Text(project?.title ?? "Huddle")
                        .font(Typeface.title())
                        .foregroundStyle(Ink.paper)
                    Text(memberLine(huddle))
                        .foregroundStyle(Ink.mute)
                    if !huddle.roleList.isEmpty {
                        Text(huddle.roleList.map { role in
                            let name = session.store.user(role.userId)?.firstName ?? "Member"
                            return "\(name) owns \(role.role)"
                        }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(Ink.gold)
                    }
                    let done = session.store.milestones(in: huddle.id).filter(\.isComplete).count
                    let total = max(session.store.milestones(in: huddle.id).count, 1)
                    ProgressView(value: Double(done), total: Double(total))
                        .tint(Ink.teal)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func memberLine(_ huddle: Huddle) -> String {
        huddle.memberIds.compactMap { session.store.user($0)?.firstName }.joined(separator: " · ")
    }
}

struct NamedItem: Identifiable {
    var id: String
    init(_ id: String) { self.id = id }
}

struct MatchRow: View {
    @Environment(AppSession.self) private var session
    var match: MatchCandidate
    var showRing: Bool = true
    var emphasizedRing: Bool = false

    var body: some View {
        let locked = session.store.blindMatching && !session.store.identityUnlocked(with: match.user.id)
        PaperCard(padding: 14) {
            HStack(spacing: 14) {
                ZStack {
                    if locked {
                        ZStack {
                            Circle().fill(Ink.teal.opacity(0.2)).frame(width: 44, height: 44)
                            Image(systemName: "eye.slash")
                                .foregroundStyle(Ink.teal)
                        }
                        .transition(.opacity)
                    } else {
                        InitialsMark(name: match.user.displayName, initials: match.user.initials)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.35), value: locked)
                VStack(alignment: .leading, spacing: 4) {
                    Text(locked ? "Complementary collaborator" : match.user.displayName)
                        .font(.headline)
                        .foregroundStyle(Ink.paper)
                    Text(match.user.skills.prefix(3).map(\.name).joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(Ink.mute)
                    TrustMark(trust: match.user.trust)
                    if locked, let shipped = match.user.collaborations.first?.projectTitle {
                        Text("Shipped \(shipped)")
                            .font(.caption)
                            .foregroundStyle(Ink.gold)
                    } else if let first = match.synergy.reasons.first {
                        Text(first)
                            .font(.caption)
                            .foregroundStyle(Ink.teal)
                            .lineLimit(2)
                    }
                }
                Spacer()
                if showRing {
                    SynergyRing(
                        score: match.synergy.score,
                        size: emphasizedRing ? 72 : 54,
                        emphasized: emphasizedRing,
                        starCount: min(match.synergy.reasons.count, 4)
                    )
                }
            }
        }
    }
}

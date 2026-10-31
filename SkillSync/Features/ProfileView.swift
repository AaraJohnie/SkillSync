import SwiftUI

struct ProfileView: View {
    @Environment(AppSession.self) private var session
    var userId: String?

    var body: some View {
        ScrollView {
            if let user = resolved {
                VStack(alignment: .leading, spacing: 18) {
                    header(user)
                    skills(user)
                    if !user.neededSkills.isEmpty {
                        PaperCard {
                            VStack(alignment: .leading, spacing: 8) {
                                SectionLabel(text: "Looking for")
                                FlowWrap(items: user.neededSkills.map { NamedItem($0) }) { item in
                                    SkillChip(name: item.id, tone: .gold)
                                }
                            }
                        }
                    }
                    collaborations(user)
                    vouches(user)
                    if isSelf {
                        actions
                    } else if let me = session.store.currentUser {
                        let match = MatchCandidate(
                            user: user,
                            project: nil,
                            synergy: SynergyEngine.evaluate(seeker: me, candidate: user)
                        )
                        PrimaryButton(title: "Pitch collaboration") {
                            session.coordinator.sheet = .pitch(match)
                        }
                    }
                }
                .padding(20)
            }
        }
        .background(Ink.bg.ignoresSafeArea())
        .navigationTitle(isSelf ? "Profile" : resolved?.firstName ?? "Profile")
        .toolbar {
            if isSelf {
                ToolbarItem(placement: .topBarLeading) {
                    CampusAccountButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: AppRoute.skillTree) {
                        Text("Skill tree")
                    }
                }
            }
        }
    }

    private var resolved: UserProfile? {
        userId.flatMap(session.store.user) ?? session.store.currentUser
    }

    private var isSelf: Bool {
        resolved?.id == session.store.currentUserId
    }

    private func header(_ user: UserProfile) -> some View {
        PaperCard {
            HStack(alignment: .top, spacing: 14) {
                InitialsMark(name: user.displayName, initials: user.initials, size: 64)
                VStack(alignment: .leading, spacing: 6) {
                    Text(user.displayName)
                        .font(Typeface.display(26))
                        .foregroundStyle(Ink.paper)
                    Text("\(user.university) · \(user.year)")
                        .foregroundStyle(Ink.mute)
                    if user.isStudentVerified {
                        Text("Student verified")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Ink.teal)
                    }
                    TrustMark(trust: user.trust)
                    NavigationLink(value: AppRoute.evidence) {
                        Text("Skill evidence")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Ink.teal)
                    }
                    if !user.platformLinks.isEmpty {
                        FlowWrap(items: user.platformLinks.filter { $0.status == .verified }) { link in
                            if let url = URL(string: link.normalizedURL) {
                                Link(destination: url) {
                                    Label(link.platform.label, systemImage: link.platform.symbol)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Ink.gold)
                                }
                            }
                        }
                    }
                    Text(user.bio)
                        .foregroundStyle(Ink.paper.opacity(0.86))
                        .font(.subheadline)
                    Text(user.availability.summary)
                        .font(.caption)
                        .foregroundStyle(Ink.mute)
                }
            }
        }
    }

    private func skills(_ user: UserProfile) -> some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Skills")
                FlowWrap(items: user.skills) { skill in
                    SkillChip(name: skill.name, level: skill.level, tone: .teal)
                }
            }
        }
    }

    private func collaborations(_ user: UserProfile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Verified collaborations")
            if user.collaborations.isEmpty {
                Text("Nothing shipped yet. Profiles grow from completed huddles, not from posting.")
                    .foregroundStyle(Ink.mute)
                    .font(.subheadline)
            }
            ForEach(user.collaborations) { item in
                PaperCard(padding: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.projectTitle)
                            .font(.headline)
                            .foregroundStyle(Ink.paper)
                        Text("Role: \(item.role) · \(item.teammateNames.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(Ink.mute)
                        Text("\(item.durationDays) days · Completed")
                            .font(.caption)
                            .foregroundStyle(Ink.teal)
                        if let note = item.shipNote, !note.isEmpty {
                            Text(note)
                                .font(.subheadline)
                                .foregroundStyle(Ink.paper.opacity(0.86))
                        }
                        if item.showedUp == true {
                            Text("Showed up")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Ink.teal)
                                .softPop()
                        }
                        ProofChip(urlString: item.proofURL)
                    }
                }
            }
        }
    }

    private func vouches(_ user: UserProfile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Peer vouches")
            if user.vouches.isEmpty {
                Text("Vouches appear after a teammate rates a shipped project.")
                    .foregroundStyle(Ink.mute)
                    .font(.subheadline)
            }
            ForEach(user.vouches) { vouch in
                PaperCard(padding: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(vouch.fromName) vouches \(user.firstName) for \(vouch.projectTitle)")
                            .foregroundStyle(Ink.paper)
                            .font(.headline)
                        Text(vouch.note)
                            .foregroundStyle(Ink.mute)
                            .font(.subheadline)
                    }
                }
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            appearancePicker
            Button("Switch campus account") {
                session.coordinator.sheet = .switchAccount
            }
            .font(.headline)
            .foregroundStyle(Ink.teal)
            NavigationLink(value: AppRoute.skillAnalysis) {
                Text("Skill guide")
                    .font(.headline)
                    .foregroundStyle(Ink.paper)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Ink.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Ink.line))
            }
            NavigationLink(value: AppRoute.requests) {
                Text("Incoming pitches")
                    .font(.headline)
                    .foregroundStyle(Ink.gold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Ink.gold.opacity(0.4)))
            }
            Button("Sign out") { session.store.signOut() }
                .foregroundStyle(Ink.mute)
            Button("Reset campus demo") { session.store.resetCampus() }
                .font(.caption)
                .foregroundStyle(Ink.coral)
        }
    }

    private var appearancePicker: some View {
        @Bindable var store = session.store
        return VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Appearance")
            Picker("Appearance", selection: $store.appearance) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}

struct SkillTreeView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("The tree is evidence of what you can do, not a badge wall.")
                    .foregroundStyle(Ink.mute)
                if let user = session.store.currentUser {
                    ForEach(SkillCatalog.grouped(), id: \.0) { category, catalog in
                        VStack(alignment: .leading, spacing: 10) {
                            Label(category.label, systemImage: category.symbol)
                                .font(.headline)
                                .foregroundStyle(Ink.teal)
                            ForEach(catalog) { skill in
                                let owned = user.skill(named: skill.name)
                                HStack {
                                    Circle()
                                        .fill(owned == nil ? Ink.line : Ink.gold)
                                        .frame(width: 10, height: 10)
                                    Text(skill.name)
                                        .foregroundStyle(Ink.paper)
                                    Spacer()
                                    if let owned {
                                        Text(owned.level.label)
                                            .foregroundStyle(Ink.gold)
                                            .font(.caption.weight(.semibold))
                                    } else if user.neededSkills.contains(skill.name) {
                                        Text("Needed")
                                            .foregroundStyle(Ink.mute)
                                            .font(.caption)
                                    }
                                }
                                .padding(.vertical, 6)
                            }
                        }
                        .padding(16)
                        .background(Ink.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
            }
            .padding(20)
        }
        .background(Ink.bg.ignoresSafeArea())
        .navigationTitle("Skill tree")
    }
}

import SwiftUI

struct DiscoverView: View {
    @Environment(AppSession.self) private var session
    @State private var segment = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Picker("Discover", selection: $segment) {
                    Text("People").tag(0)
                    Text("Projects").tag(1)
                    Text("Shipped").tag(2)
                    Text("Squads").tag(3)
                }
                .pickerStyle(.segmented)

                if segment == 0 {
                    people
                } else if segment == 1 {
                    projects
                } else if segment == 2 {
                    shipped
                } else {
                    squads
                }
            }
            .padding(20)
        }
        .background(Ink.bg.ignoresSafeArea())
        .navigationTitle("Discover")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                CampusAccountButton()
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack {
                    if segment == 0 {
                        Button {
                            session.store.blindMatching.toggle()
                        } label: {
                            Image(systemName: session.store.blindMatching ? "eye.slash" : "eye")
                        }
                        .accessibilityLabel(session.store.blindMatching ? "Show names" : "Blind synergy")
                    }
                    Button {
                        session.coordinator.sheet = .createProject
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
    }

    private var people: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(peopleCaption)
                .font(.subheadline)
                .foregroundStyle(Ink.mute)
            ForEach(Array(rankedPeople.enumerated()), id: \.element.id) { index, match in
                if session.store.blindMatching && !session.store.identityUnlocked(with: match.user.id) {
                    Button {
                        session.coordinator.sheet = .pitch(match)
                    } label: {
                        MatchRow(match: match)
                    }
                    .buttonStyle(.plain)
                    .listAppear(index: index)
                } else {
                    NavigationLink(value: AppRoute.user(match.user.id)) {
                        MatchRow(match: match)
                    }
                    .buttonStyle(.plain)
                    .listAppear(index: index)
                }
            }
        }
    }

    private var projects: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Each project says Technical Core or Technical Hands. You decide whether to do it or ask someone.")
                .font(.subheadline)
                .foregroundStyle(Ink.mute)
            ForEach(Array(openProjects.enumerated()), id: \.element.id) { index, project in
                NavigationLink(value: AppRoute.project(project.id)) {
                    ProjectCard(project: project)
                }
                .buttonStyle(.plain)
                .listAppear(index: index)
            }
        }
    }

    private var rankedPeople: [MatchCandidate] {
        guard let user = session.store.currentUser else { return [] }
        return session.store.matches(for: user)
    }

    private var openProjects: [Project] {
        session.store.projects.filter { $0.status != .completed }
    }

    private var peopleCaption: String {
        session.store.blindMatching
            ? "Blind synergy — names stay hidden until you pitch or huddle."
            : "Ranked against the skills you said you still need."
    }

    private var shipped: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Only completed work. No posts, no likes.")
                .font(.subheadline)
                .foregroundStyle(Ink.mute)
            let items = session.store.shippedProjects()
            if items.isEmpty {
                EmptyNote(symbol: "checkmark.seal", title: "Nothing shipped yet", detail: "Completed huddles with a proof link land here.")
            }
            ForEach(Array(items.enumerated()), id: \.element.id) { index, project in
                PaperCard {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(text: "Shipped")
                        Text(project.title)
                            .font(Typeface.title())
                            .foregroundStyle(Ink.paper)
                        if let note = project.shipNote, !note.isEmpty {
                            Text(note)
                                .foregroundStyle(Ink.mute)
                        } else {
                            Text(project.summary)
                                .foregroundStyle(Ink.mute)
                                .lineLimit(2)
                        }
                        Text(project.memberIds.compactMap { session.store.user($0)?.displayName }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(Ink.mute)
                        ProofChip(urlString: project.proofURL)
                    }
                }
                .listAppear(index: index)
            }
        }
    }

    private var squads: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Micro-squads cover every required skill, not a popularity contest.")
                .font(.subheadline)
                .foregroundStyle(Ink.mute)
            let recruiting = session.store.projects.filter { $0.status == .recruiting && $0.requiredSkills.count >= 2 }
            if recruiting.isEmpty {
                EmptyNote(symbol: "person.3", title: "Create a project first", detail: "Squads appear when a project still has missing skills.")
            }
            ForEach(Array(recruiting.enumerated()), id: \.element.id) { index, project in
                VStack(alignment: .leading, spacing: 10) {
                    Text(project.title)
                        .font(.headline)
                        .foregroundStyle(Ink.paper)
                    ForEach(session.store.squads(for: project)) { squad in
                        SquadCard(project: project, squad: squad)
                    }
                }
                .listAppear(index: index)
            }
        }
    }
}

struct SquadCard: View {
    @Environment(AppSession.self) private var session
    var project: Project
    var squad: MicroSquad

    var body: some View {
        PaperCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionLabel(text: squad.memberIds.count == 1 ? "Pair" : "Micro-squad")
                    Spacer()
                    Text("\(squad.score)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Ink.gold)
                }
                Text(displayMembers)
                    .font(.headline)
                    .foregroundStyle(Ink.paper)
                let locked = isLocked
                if locked {
                    Text("Covers the missing skills without overlapping your stack.")
                        .font(.caption)
                        .foregroundStyle(Ink.mute)
                } else {
                    ForEach(squad.reasons, id: \.self) { reason in
                        Text(reason)
                            .font(.caption)
                            .foregroundStyle(Ink.mute)
                    }
                }
                if let first = firstCandidate {
                    Button("Pitch this squad") {
                        session.coordinator.sheet = .pitch(
                            MatchCandidate(
                                user: first,
                                project: project,
                                synergy: SynergyEngine.evaluate(
                                    seeker: session.store.currentUser ?? first,
                                    candidate: first,
                                    project: project
                                )
                            )
                        )
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Ink.teal)
                }
            }
        }
    }

    private var isLocked: Bool {
        session.store.blindMatching && squad.memberIds.contains { !session.store.identityUnlocked(with: $0) }
    }

    private var displayMembers: String {
        if isLocked {
            return squad.memberIds.count == 1 ? "Complementary collaborator" : "\(squad.memberIds.count) complementary collaborators"
        }
        return memberLine
    }

    private var memberLine: String {
        squad.memberIds.compactMap { session.store.user($0)?.displayName }.joined(separator: " · ")
    }

    private var firstCandidate: UserProfile? {
        squad.memberIds.compactMap { session.store.user($0) }.first
    }
}

struct ProjectCard: View {
    @Environment(AppSession.self) private var session
    var project: Project

    var body: some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionLabel(text: project.status == .active ? "In huddle" : "Recruiting")
                    Spacer()
                    Text("\(project.durationDays) days")
                        .font(.caption)
                        .foregroundStyle(Ink.mute)
                }
                Text(project.title)
                    .font(Typeface.title())
                    .foregroundStyle(Ink.paper)
                Text(project.summary)
                    .font(.subheadline)
                    .foregroundStyle(Ink.mute)
                    .lineLimit(3)
                if let user = session.store.currentUser {
                    callLine(project.taskLane)
                    let missing = GapAnalyzer.missing(required: project.requiredSkills, owned: user.skills)
                    FlowWrap(items: project.requiredSkills.map { NamedItem($0) }) { item in
                        SkillChip(name: item.id, tone: missing.contains(item.id) ? .gold : .teal)
                    }
                    SkillGapRadar(required: project.requiredSkills, owned: user.skills)
                    if !missing.isEmpty {
                        Text("You still need \(missing.joined(separator: ", ")).")
                            .font(.caption)
                            .foregroundStyle(Ink.gold)
                    }
                }
            }
        }
    }

    private func callLine(_ lane: ContributionLane) -> some View {
        Text(lane == .technicalCore ? "Technical Core" : "Technical Hands")
            .font(.caption.weight(.semibold))
            .foregroundStyle(lane == .technicalCore ? Ink.gold : Ink.teal)
    }
}

struct ProjectDetailView: View {
    @Environment(AppSession.self) private var session
    var projectId: String

    var body: some View {
        ScrollView {
            if let project = session.store.project(projectId), let user = session.store.currentUser {
                VStack(alignment: .leading, spacing: 18) {
                    ProjectCard(project: project)
                    Text("People who fill the missing skills")
                        .font(Typeface.title())
                        .foregroundStyle(Ink.paper)
                    SkillGapRadar(required: project.requiredSkills, owned: user.skills)
                    let squads = session.store.squads(for: project)
                    if !squads.isEmpty {
                        SectionLabel(text: "Micro-squads")
                        ForEach(squads) { squad in
                            SquadCard(project: project, squad: squad)
                        }
                    }
                    ForEach(Array(session.store.matches(for: user, project: project).prefix(5).enumerated()), id: \.element.id) { index, match in
                        Button {
                            session.coordinator.sheet = .pitch(match)
                        } label: {
                            MatchRow(match: match)
                        }
                        .buttonStyle(.plain)
                        .listAppear(index: index)
                    }
                }
                .padding(20)
            }
        }
        .background(Ink.bg.ignoresSafeArea())
        .navigationTitle("Project")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct CreateProjectView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var summary = ""
    @State private var duration = 7.0
    @State private var required: Set<String> = []
    @State private var taskLane: ContributionLane?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    FieldLabel(title: "Project name", text: $title)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What you want to ship")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Ink.mute)
                        TextField("", text: $summary, axis: .vertical)
                            .lineLimit(3...8)
                            .foregroundStyle(Ink.paper)
                            .padding(12)
                            .background(Ink.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    TaskTypePicker(selection: $taskLane)
                    Text("Required skills")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Ink.paper)
                    FlowWrap(items: SkillCatalog.all) { skill in
                        let on = required.contains(skill.name)
                        Button {
                            if on { required.remove(skill.name) } else { required.insert(skill.name) }
                        } label: {
                            SkillChip(name: skill.name, tone: on ? .gold : .mute)
                        }
                        .buttonStyle(.plain)
                    }
                    Text("Duration: \(Int(duration)) days")
                        .foregroundStyle(Ink.paper)
                    Slider(value: $duration, in: 3...30, step: 1)
                        .tint(Ink.gold)
                    if let user = session.store.currentUser, !required.isEmpty {
                        let missing = GapAnalyzer.missing(required: Array(required), owned: user.skills)
                        SkillGapRadar(required: Array(required), owned: user.skills)
                        if !missing.isEmpty {
                            Text("SkillSync will look for people who bring \(missing.joined(separator: ", ")).")
                                .foregroundStyle(Ink.teal)
                                .font(.subheadline)
                        }
                    }
                    PrimaryButton(title: "Publish project") {
                        let deadline = Calendar.current.date(byAdding: .day, value: Int(duration), to: .now) ?? .now
                        guard let taskLane else { return }
                        if let project = session.store.createProject(
                            title: title,
                            summary: summary,
                            requiredSkills: Array(required),
                            durationDays: Int(duration),
                            deadline: deadline,
                            taskLane: taskLane
                        ) {
                            dismiss()
                            session.coordinator.tab = .discover
                            session.coordinator.discoverPath.append(AppRoute.project(project.id))
                        }
                    }
                    .disabled(title.isEmpty || required.isEmpty || taskLane == nil)
                    .opacity(title.isEmpty || required.isEmpty || taskLane == nil ? 0.4 : 1)
                }
                .padding(20)
            }
            .background(Ink.bg.ignoresSafeArea())
            .navigationTitle("New project")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .softSheetIntro()
        }
    }
}

struct PitchSheet: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    var match: MatchCandidate
    @State private var pitch = ""
    @State private var error: String?
    @State private var sent = false
    @State private var showTemplates = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .center, spacing: 14) {
                        SynergyRing(
                            score: match.synergy.score,
                            size: 54,
                            emphasized: false,
                            starCount: min(match.synergy.reasons.count, 3)
                        )
                        VStack(alignment: .leading, spacing: 6) {
                            Text(bridgeLine)
                                .font(Typeface.title())
                                .foregroundStyle(Ink.paper)
                            Text(match.user.skillLine)
                                .font(.caption)
                                .foregroundStyle(Ink.mute)
                        }
                    }
                    if sent {
                        PaperCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Pitch sent.")
                                    .font(Typeface.title())
                                    .foregroundStyle(Ink.paper)
                                Text("They’ll see it under Pitches. If they accept, you huddle.")
                                    .foregroundStyle(Ink.mute)
                                Button("Switch to \(match.user.firstName) to try the other side") {
                                    session.switchAccount(to: match.user.id)
                                }
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Ink.teal)
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Your pitch")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Ink.mute)
                            TextField("What you want to make together", text: $pitch, axis: .vertical)
                                .lineLimit(3...6)
                                .foregroundStyle(Ink.paper)
                                .padding(12)
                                .background(Ink.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        if let me = session.store.currentUser {
                            Button(showTemplates ? "Hide other lines" : "Use a different line") {
                                withAnimation(.easeOut(duration: 0.2)) { showTemplates.toggle() }
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Ink.teal)
                            if showTemplates {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(PitchTemplates.lines(seeker: me, candidate: match.user, project: match.project), id: \.self) { line in
                                        Button(line) { pitch = line }
                                            .font(.caption)
                                            .foregroundStyle(Ink.teal)
                                            .multilineTextAlignment(.leading)
                                    }
                                }
                            }
                        }
                        if let error {
                            Text(error).foregroundStyle(Ink.coral).font(.footnote)
                        }
                        PrimaryButton(title: "Send pitch") {
                            do {
                                try session.store.sendPitch(to: match.user, project: match.project, text: pitch)
                                sent = true
                            } catch {
                                self.error = error.localizedDescription
                            }
                        }
                        .disabled(pitch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(20)
            }
            .background(Ink.bg.ignoresSafeArea())
            .navigationTitle(sent ? "Sent" : "Pitch")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .softSheetIntro()
            .onAppear { prefill() }
        }
    }

    private var bridgeLine: String {
        guard let me = session.store.currentUser else {
            return "Send a one-line pitch."
        }
        let pair = PitchTemplates.bridge(seeker: me, candidate: match.user)
        return "You bring \(pair.have). They bring \(pair.need)."
    }

    private func prefill() {
        guard pitch.isEmpty, let me = session.store.currentUser else { return }
        pitch = PitchTemplates.lines(seeker: me, candidate: match.user, project: match.project).first ?? ""
    }
}

struct RequestsView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                incomingSection
                outgoingSection
            }
            .padding(20)
        }
        .background(Ink.bg.ignoresSafeArea())
        .navigationTitle("Pitches")
    }

    private var incomingSection: some View {
        let incoming = session.store.incomingRequests(for: session.store.currentUserId ?? "")
        return VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Incoming")
            if incoming.isEmpty {
                Text("Nobody is waiting on you right now. Switch to Maya or Priya to see pitches on their desks.")
                    .foregroundStyle(Ink.mute)
                    .font(.subheadline)
            }
            ForEach(incoming) { request in
                requestCard(request)
            }
        }
    }

    private var outgoingSection: some View {
        let outgoing = session.store.outgoingRequests(for: session.store.currentUserId ?? "")
        return VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Sent")
            if outgoing.isEmpty {
                Text("Pitches you send will wait on the other person’s account.")
                    .foregroundStyle(Ink.mute)
                    .font(.subheadline)
            }
            ForEach(outgoing) { request in
                outgoingCard(request)
            }
        }
    }

    private func requestCard(_ request: CollaborationRequest) -> some View {
        let from = session.store.user(request.fromUserId)
        return PaperCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    InitialsMark(name: from?.displayName ?? "?", initials: from?.initials ?? "?")
                    VStack(alignment: .leading) {
                        Text(from?.displayName ?? "Unknown")
                            .foregroundStyle(Ink.paper)
                            .font(.headline)
                        Text("\(request.synergyScore)% synergy")
                            .foregroundStyle(Ink.gold)
                    }
                }
                Text(request.pitch)
                    .foregroundStyle(Ink.mute)
                HStack {
                    Button("Decline") { session.store.respond(to: request.id, accept: false) }
                        .foregroundStyle(Ink.coral)
                    Spacer()
                    Button("Accept & open huddle") {
                        session.store.respond(to: request.id, accept: true)
                        if let huddle = session.store.huddles(for: session.store.currentUserId ?? "").first(where: { $0.status == .active }) {
                            session.coordinator.openHuddle(huddle.id)
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Ink.stamp)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Ink.gold, in: Capsule())
                }
            }
        }
    }

    private func outgoingCard(_ request: CollaborationRequest) -> some View {
        let to = session.store.user(request.toUserId)
        return PaperCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("To \(to?.displayName ?? "someone") · \(request.status.rawValue)")
                    .font(.headline)
                    .foregroundStyle(Ink.paper)
                Text(request.pitch)
                    .foregroundStyle(Ink.mute)
                if request.status == .pending, let to {
                    Button("Switch to \(to.firstName) to respond") {
                        session.switchAccount(to: to.id)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Ink.gold)
                }
            }
        }
    }
}

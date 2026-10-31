import SwiftUI

struct HuddleListView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                let items = session.store.huddles(for: session.store.currentUserId ?? "")
                if items.isEmpty {
                    EmptyNote(
                        symbol: "person.2",
                        title: "No huddles yet",
                        detail: "Accept a pitch or send one from Discover. A huddle is a temporary workshop, not a group chat for its own sake."
                    )
                }
                ForEach(Array(items.enumerated()), id: \.element.id) { index, huddle in
                    NavigationLink(value: AppRoute.huddle(huddle.id)) {
                        huddleRow(huddle)
                    }
                    .buttonStyle(.plain)
                    .listAppear(index: index)
                }
            }
            .padding(20)
        }
        .background(Ink.bg.ignoresSafeArea())
        .navigationTitle("Huddles")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                CampusAccountButton()
            }
        }
    }

    private func huddleRow(_ huddle: Huddle) -> some View {
        let project = session.store.project(huddle.projectId)
        return PaperCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SectionLabel(text: huddle.status == .completed ? "Shipped" : "Active")
                    Spacer()
                    Text(project?.title ?? "Huddle")
                        .font(.headline)
                        .foregroundStyle(Ink.paper)
                }
                Text(huddle.memberIds.compactMap { session.store.user($0)?.displayName }.joined(separator: " · "))
                    .foregroundStyle(Ink.mute)
                    .font(.subheadline)
                if !huddle.roleList.isEmpty {
                    Text(huddle.roleList.map { role in
                        let name = session.store.user(role.userId)?.firstName ?? "Member"
                        return "\(name): \(role.role)"
                    }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(Ink.gold)
                }
            }
        }
    }
}

struct HuddleView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var huddleId: String
    @State private var pane = 0
    @State private var draft = ""
    @State private var taskTitle = ""
    @State private var milestoneTitle = ""
    @State private var milestoneDays = 5.0

    var body: some View {
        VStack(spacing: 0) {
            if let huddle = session.store.huddle(huddleId) {
                header(huddle)
                Picker("Pane", selection: $pane) {
                    Text("Chat").tag(0)
                    Text("Tasks").tag(1)
                    Text("Milestones").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

                switch pane {
                case 1: tasks(huddle)
                case 2: milestones(huddle)
                default: chat(huddle)
                }
            } else {
                EmptyNote(symbol: "questionmark", title: "Huddle closed", detail: "This workspace is no longer available.")
            }
        }
        .background(Ink.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if session.store.huddle(huddleId)?.status == .active {
                    NavigationLink(value: AppRoute.complete(huddleId)) {
                        Text("Ship")
                            .foregroundStyle(Ink.gold)
                    }
                }
            }
        }
    }

    private func header(_ huddle: Huddle) -> some View {
        let project = session.store.project(huddle.projectId)
        return VStack(alignment: .leading, spacing: 10) {
            Text(project?.title ?? "Huddle")
                .font(Typeface.display(28))
                .foregroundStyle(Ink.paper)
            Text("Role contract — who owns what")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Ink.mute)
            ForEach(huddle.memberIds, id: \.self) { memberId in
                let member = session.store.user(memberId)
                let role = huddle.roleList.first(where: { $0.userId == memberId })?.role ?? "Collaborator"
                HStack {
                    Text(member?.firstName ?? "Member")
                        .foregroundStyle(Ink.paper)
                    Spacer()
                    if huddle.status == .active {
                        Menu {
                            ForEach(roleChoices(project: project, member: member), id: \.self) { option in
                                Button(option) { session.store.setRole(huddleId: huddle.id, userId: memberId, role: option) }
                            }
                        } label: {
                            Text(role)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Ink.gold)
                                .roleUnderline()
                        }
                    } else {
                        Text(role)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Ink.gold)
                            .roleUnderline()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private func roleChoices(project: Project?, member: UserProfile?) -> [String] {
        var options = project?.requiredSkills ?? []
        options.append(contentsOf: member?.skills.map(\.name) ?? [])
        var seen = Set<String>()
        return options.filter { seen.insert($0).inserted }
    }

    private func chat(_ huddle: Huddle) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(session.store.messages(in: huddle.id)) { message in
                        let mine = message.authorId == session.store.currentUserId
                        let author = session.store.user(message.authorId)
                        HStack {
                            if mine { Spacer(minLength: 40) }
                            VStack(alignment: mine ? .trailing : .leading, spacing: 4) {
                                Text(author?.firstName ?? "Member")
                                    .font(.caption)
                                    .foregroundStyle(Ink.mute)
                                Text(message.text)
                                    .foregroundStyle(mine ? Ink.stamp : Ink.paper)
                                    .padding(12)
                                    .background(mine ? Ink.gold : Ink.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .transition(.asymmetric(
                                        insertion: .move(edge: mine ? .trailing : .leading).combined(with: .opacity),
                                        removal: .opacity
                                    ))
                            }
                            if !mine { Spacer(minLength: 40) }
                        }
                    }
                }
                .padding(20)
            }
            HStack {
                TextField("Message the huddle", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .foregroundStyle(Ink.paper)
                    .padding(12)
                    .background(Ink.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                Button {
                    if reduceMotion {
                        session.store.sendMessage(huddleId: huddle.id, text: draft)
                    } else {
                        withAnimation(.easeOut(duration: 0.28)) {
                            session.store.sendMessage(huddleId: huddle.id, text: draft)
                        }
                    }
                    draft = ""
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Ink.gold)
                }
            }
            .padding(16)
        }
    }

    private func tasks(_ huddle: Huddle) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    TextField("Add a task", text: $taskTitle)
                        .foregroundStyle(Ink.paper)
                        .padding(12)
                        .background(Ink.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Button("Add") {
                        session.store.addTask(huddleId: huddle.id, title: taskTitle, assigneeId: nil)
                        taskTitle = ""
                    }
                    .foregroundStyle(Ink.gold)
                    .disabled(taskTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let me = session.store.currentUser, !taskTitle.trimmingCharacters(in: .whitespaces).isEmpty {
                    TaskClassificationCard(
                        title: taskTitle,
                        hintedSkills: session.store.project(huddle.projectId)?.requiredSkills ?? [],
                        seeker: me,
                        pool: session.store.users
                    )
                }
                ForEach(TaskLane.allCases, id: \.self) { lane in
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(text: lane.label)
                        let items = session.store.tasks(in: huddle.id).filter { $0.lane == lane }
                        if items.isEmpty {
                            Text("Nothing here.")
                                .font(.caption)
                                .foregroundStyle(Ink.mute)
                        }
                        ForEach(items) { task in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(task.title)
                                        .foregroundStyle(Ink.paper)
                                    let lane = TaskClassifier.analyze(TaskBrief(title: task.title, detail: "", requiredSkills: [])).lane
                                    Text(lane == .technicalCore ? "Technical Core" : "Technical Hands")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(lane == .technicalCore ? Ink.gold : Ink.teal)
                                    Text(session.store.user(task.assigneeId ?? "")?.firstName ?? "Unassigned")
                                        .font(.caption)
                                        .foregroundStyle(Ink.mute)
                                }
                                Spacer()
                                Menu {
                                    Button("I'll do this") {
                                        session.store.assignTask(task.id, to: session.store.currentUserId)
                                    }
                                    Button("Leave unassigned") {
                                        session.store.assignTask(task.id, to: nil)
                                    }
                                    Divider()
                                    ForEach(huddle.memberIds, id: \.self) { memberId in
                                        Button(session.store.user(memberId)?.firstName ?? "Member") {
                                            session.store.assignTask(task.id, to: memberId)
                                        }
                                    }
                                    Divider()
                                    ForEach(TaskLane.allCases, id: \.self) { next in
                                        Button(next.label) { session.store.moveTask(task.id, to: next) }
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                        .foregroundStyle(Ink.mute)
                                }
                            }
                            .padding(12)
                            .background(Ink.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    private func milestones(_ huddle: Huddle) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if huddle.status == .active {
                    HStack {
                        TextField("New milestone", text: $milestoneTitle)
                            .foregroundStyle(Ink.paper)
                            .padding(12)
                            .background(Ink.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        Button("Add") {
                            let due = Calendar.current.date(byAdding: .day, value: Int(milestoneDays), to: .now) ?? .now
                            session.store.addMilestone(huddleId: huddle.id, title: milestoneTitle, dueDate: due)
                            milestoneTitle = ""
                        }
                        .foregroundStyle(Ink.gold)
                        .disabled(milestoneTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    Text("Due in \(Int(milestoneDays)) days")
                        .font(.caption)
                        .foregroundStyle(Ink.mute)
                    Slider(value: $milestoneDays, in: 1...21, step: 1)
                        .tint(Ink.gold)
                }
                ForEach(session.store.milestones(in: huddle.id)) { milestone in
                    Button {
                        session.store.toggleMilestone(milestone.id)
                    } label: {
                        HStack {
                            Image(systemName: milestone.isComplete ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(milestone.isComplete ? Ink.teal : Ink.mute)
                            VStack(alignment: .leading) {
                                Text(milestone.title)
                                    .foregroundStyle(Ink.paper)
                                    .strikethrough(milestone.isComplete)
                                Text(milestone.dueDate.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption)
                                    .foregroundStyle(Ink.mute)
                            }
                            Spacer()
                        }
                        .padding(14)
                        .background(Ink.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
        }
    }
}

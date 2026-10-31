import SwiftUI

@MainActor
@Observable
final class AgentChatModel {
    struct Turn: Identifiable {
        let id = UUID()
        var role: Role
        var text: String
        var actions: [AgentAction]
        var followUps: [String] = []
        var usedAppleIntelligence = false

        enum Role {
            case user
            case agent
        }
    }

    private let store: DemoStore
    private var memory = AgentMemory()
    var turns: [Turn] = []
    var draft = ""
    var isThinking = false

    var availability: CampusModelAvailability { OnDeviceCampusAgent.availability }

    init(store: DemoStore) {
        self.store = store
    }

    func reset() {
        turns = []
        memory = AgentMemory()
        draft = ""
        isThinking = false
        OnDeviceCampusAgent.reset()
    }

    func ask(_ text: String) async {
        draft = text
        await send()
    }

    func send() async {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isThinking else { return }
        guard let brief = CampusAgent.brief(from: store) else { return }

        draft = ""
        isThinking = true
        turns.append(Turn(role: .user, text: prompt, actions: []))

        let history = turns.dropLast().map { "\($0.role == .user ? "Student" : "Agent"): \($0.text)" }
        let local = CampusAgent.reply(to: prompt, brief: brief, memory: &memory)
        let spoken = await OnDeviceCampusAgent.reply(to: prompt, brief: brief, history: history)
        turns.append(Turn(
            role: .agent,
            text: spoken ?? local.text,
            actions: local.actions,
            followUps: local.followUps,
            usedAppleIntelligence: spoken != nil
        ))
        isThinking = false
    }
}

struct AgentView: View {
    @Environment(AppSession.self) private var session
    private var chat: AgentChatModel { session.agent }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        intro
                        if chat.turns.isEmpty {
                            suggestions
                        }
                        ForEach(chat.turns) { turn in
                            bubble(turn)
                                .id(turn.id)
                        }
                        if chat.isThinking {
                            ProgressView()
                                .tint(Ink.gold)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id("thinking")
                        }
                    }
                    .padding(20)
                }
                .onChange(of: chat.turns.count) {
                    guard let last = chat.turns.last?.id else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
            composer
        }
        .background(Ink.bg.ignoresSafeArea())
        .navigationTitle("Agent")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                CampusAccountButton()
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ask who fills the gap.")
                .font(Typeface.display(32))
                .foregroundStyle(Ink.paper)
            Text(statusLine)
                .font(.subheadline)
                .foregroundStyle(Ink.mute)
        }
    }

    private var statusLine: String {
        switch chat.availability {
        case .onDevice:
            "Apple Intelligence writes the reply. Names and scores come from campus matches."
        case .unavailable(let reason):
            reason
        }
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 10) {
            suggestion("Suggest people")
            suggestion("Draft a pitch")
            suggestion("What's next in my huddle?")
            suggestion("What skill am I missing?")
            suggestion("Check my skill evidence")
        }
    }

    private func suggestion(_ text: String) -> some View {
        Button {
            Task { await chat.ask(text) }
        } label: {
            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Ink.paper)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Ink.card, in: Capsule())
                .overlay(Capsule().stroke(Ink.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func bubble(_ turn: AgentChatModel.Turn) -> some View {
        VStack(alignment: turn.role == .user ? .trailing : .leading, spacing: 8) {
            if turn.usedAppleIntelligence {
                Text("Apple Intelligence")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Ink.gold)
            }
            Text(turn.text)
                .font(.body)
                .foregroundStyle(turn.role == .user ? Ink.stamp : Ink.paper)
                .padding(14)
                .background(turn.role == .user ? Ink.gold : Ink.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    if turn.role == .agent {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Ink.line, lineWidth: 1)
                    }
                }
            ForEach(turn.actions) { action in
                Button(action.title) { perform(action) }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Ink.teal)
            }
            if turn.id == chat.turns.last?.id {
                ForEach(turn.followUps, id: \.self) { followUp in
                    suggestion(followUp)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: turn.role == .user ? .trailing : .leading)
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("Ask the campus agent", text: Bindable(chat).draft, axis: .vertical)
                .lineLimit(1...4)
                .foregroundStyle(Ink.paper)
                .padding(12)
                .background(Ink.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            Button {
                Task { await chat.send() }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.headline)
                    .foregroundStyle(Ink.stamp)
                    .frame(width: 44, height: 44)
                    .background(Ink.gold, in: Circle())
            }
            .disabled(chat.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || chat.isThinking)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Ink.bg)
    }

    private func perform(_ action: AgentAction) {
        guard let me = session.store.currentUser else { return }
        switch action {
        case .pitch(let userId, _):
            guard let match = session.store.matches(for: me).first(where: { $0.user.id == userId }) else { return }
            session.coordinator.sheet = .pitch(match)
        case .openHuddle(let id, _):
            session.coordinator.openHuddle(id)
        }
    }
}

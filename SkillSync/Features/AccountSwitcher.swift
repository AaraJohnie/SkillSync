import SwiftUI

struct CampusAccountButton: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        Button {
            session.coordinator.sheet = .switchAccount
        } label: {
            HStack(spacing: 8) {
                if let user = session.store.currentUser {
                    InitialsMark(name: user.displayName, initials: user.initials, size: 28)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Ink.mute)
                } else {
                    Image(systemName: "person.2.fill")
                        .foregroundStyle(Ink.gold)
                }
            }
        }
        .accessibilityLabel("Switch campus account")
    }
}

struct AccountSwitcherSheet: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Everyone shares one campus. Pitch as Jordan, then become Maya to accept it.")
                        .foregroundStyle(Ink.mute)
                    ForEach(sortedUsers) { user in
                        Button {
                            session.switchAccount(to: user.id)
                            dismiss()
                        } label: {
                            accountRow(user)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
            .background(Ink.bg.ignoresSafeArea())
            .navigationTitle("Campus accounts")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .softSheetIntro()
        }
    }

    private var sortedUsers: [UserProfile] {
        session.store.users.sorted { lhs, rhs in
            if lhs.id == session.store.currentUserId { return true }
            if rhs.id == session.store.currentUserId { return false }
            return lhs.displayName < rhs.displayName
        }
    }

    private func accountRow(_ user: UserProfile) -> some View {
        let active = user.id == session.store.currentUserId
        return PaperCard(padding: 14) {
            HStack(spacing: 12) {
                InitialsMark(name: user.displayName, initials: user.initials)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(user.displayName)
                            .font(.headline)
                            .foregroundStyle(Ink.paper)
                        if active {
                            Text("You")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Ink.stamp)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Ink.gold, in: Capsule())
                        }
                    }
                    Text(user.skillLine.isEmpty ? "Still building a skill profile" : user.skillLine)
                        .font(.caption)
                        .foregroundStyle(Ink.mute)
                    Text(session.store.platformStatus(for: user.id))
                        .font(.caption)
                        .foregroundStyle(Ink.teal)
                }
                Spacer()
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(active ? Ink.gold.opacity(0.55) : Color.clear, lineWidth: 1.5)
        )
    }
}

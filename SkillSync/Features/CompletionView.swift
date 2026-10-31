import SwiftUI

struct CompleteProjectView: View {
    @Environment(AppSession.self) private var session
    var huddleId: String
    @State private var proof = ""
    @State private var shipNote = ""
    @State private var error: String?
    @State private var shipped = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Ship with proof, then vouch. The profile should only grow when the work exists.")
                    .foregroundStyle(Ink.mute)

                if alreadyShipped {
                    PaperCard {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionLabel(text: "Already shipped")
                            Text("This huddle is complete. Vouch for your teammate below.")
                                .foregroundStyle(Ink.mute)
                            if let project = session.store.project(session.store.huddle(huddleId)?.projectId ?? "") {
                                if let note = project.shipNote, !note.isEmpty {
                                    Text(note)
                                        .foregroundStyle(Ink.paper)
                                }
                                ProofChip(urlString: project.proofURL)
                            }
                        }
                    }
                } else {
                    FieldLabel(title: "GitHub, Figma, TestFlight, or site", text: $proof, keyboard: .URL)
                    Text("Paste a real https link. A word like “hi” is not proof of work.")
                        .font(.caption)
                        .foregroundStyle(proofHintColor)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What we shipped")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Ink.mute)
                        TextField("One line that lands on both profiles", text: $shipNote, axis: .vertical)
                            .lineLimit(2...4)
                            .foregroundStyle(Ink.paper)
                            .padding(12)
                            .background(Ink.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    if let error {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(Ink.coral)
                    }
                    PrimaryButton(title: "Mark project complete") {
                        do {
                            try session.store.complete(huddleId: huddleId, proofURL: proof, shipNote: shipNote)
                            error = nil
                            shipped = true
                        } catch {
                            self.error = error.localizedDescription
                        }
                    }
                    .opacity(canShip ? 1 : 0.45)
                    .disabled(!canShip)
                }

                if showVouch, let huddle = session.store.huddle(huddleId) {
                    ForEach(huddle.memberIds.filter { $0 != session.store.currentUserId }, id: \.self) { memberId in
                        if let member = session.store.user(memberId) {
                            VouchForm(huddleId: huddleId, teammate: member)
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(Ink.bg.ignoresSafeArea())
        .navigationTitle("Complete")
        .onAppear {
            shipped = alreadyShipped
        }
    }

    private var alreadyShipped: Bool {
        session.store.huddle(huddleId)?.status == .completed
    }

    private var showVouch: Bool {
        shipped || alreadyShipped
    }

    private var canShip: Bool {
        ProofLink.isValid(proof) && shipNote.trimmingCharacters(in: .whitespacesAndNewlines).count >= 8
    }

    private var proofHintColor: Color {
        if proof.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return Ink.mute }
        return ProofLink.isValid(proof) ? Ink.teal : Ink.coral
    }
}

struct VouchForm: View {
    @Environment(AppSession.self) private var session
    var huddleId: String
    var teammate: UserProfile
    @State private var scores: [VouchDimension: Int] = Dictionary(
        uniqueKeysWithValues: VouchDimension.allCases.map { ($0, 4) }
    )
    @State private var note = ""
    @State private var sent = false
    @State private var error: String?

    var body: some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Vouch for \(teammate.firstName)")
                    .font(Typeface.title())
                    .foregroundStyle(Ink.paper)
                if alreadyVouched || sent {
                    Text(alreadyVouched && !sent ? "You already vouched for \(teammate.firstName) on this project." : "Vouch saved to their profile.")
                        .foregroundStyle(Ink.teal)
                } else {
                    ForEach(VouchDimension.allCases) { dimension in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(dimension.label)
                                    .foregroundStyle(Ink.paper)
                                    .font(.subheadline)
                                Spacer()
                                Text("\(scores[dimension] ?? 3)")
                                    .foregroundStyle(Ink.gold)
                            }
                            Slider(
                                value: Binding(
                                    get: { Double(scores[dimension] ?? 3) },
                                    set: { scores[dimension] = Int($0) }
                                ),
                                in: 1...5,
                                step: 1
                            )
                            .tint(Ink.gold)
                        }
                    }
                    TextField("What they actually did", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                        .foregroundStyle(Ink.paper)
                        .padding(10)
                        .background(Ink.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    if let error {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(Ink.coral)
                    }
                    PrimaryButton(title: "Submit vouch") {
                        do {
                            try session.store.submitVouch(
                                huddleId: huddleId,
                                toUserId: teammate.id,
                                scores: scores,
                                note: note
                            )
                            error = nil
                            sent = true
                        } catch {
                            self.error = error.localizedDescription
                        }
                    }
                }
            }
        }
    }

    private var alreadyVouched: Bool {
        session.store.hasVouched(for: teammate.id, huddleId: huddleId)
    }
}

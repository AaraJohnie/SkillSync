import SwiftUI

struct TaskTypePicker: View {
    @Binding var selection: ContributionLane?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Task type")
                .font(.headline)
                .foregroundStyle(Ink.paper)
            Text("Choose how this task should be handled")
                .font(.subheadline)
                .foregroundStyle(Ink.mute)
            option(
                .technicalCore,
                title: "Technical Core",
                symbol: "brain",
                detail: "Advanced technical work, system design, algorithms, AI/ML, complex programming, architecture, etc."
            )
            option(
                .technicalHands,
                title: "Technical Hands",
                symbol: "hammer",
                detail: "Implementation, UI work, testing, documentation, configuration, etc."
            )
        }
    }

    private func option(_ lane: ContributionLane, title: String, symbol: String, detail: String) -> some View {
        let on = selection == lane
        return Button {
            selection = lane
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(on ? Ink.gold : Ink.mute)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(Ink.paper)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(Ink.mute)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(on ? Ink.gold : Ink.line)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Ink.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(on ? Ink.gold : Ink.line, lineWidth: on ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct TaskClassificationCard: View {
    var title: String
    var detail: String = ""
    var hintedSkills: [String] = []
    var seeker: UserProfile
    var pool: [UserProfile]
    @State private var suggestSomeone = false

    var body: some View {
        let brief = TaskBrief(title: title, detail: detail, requiredSkills: hintedSkills)
        let plan = TaskClassifier.plan(seeker: seeker, pool: pool, brief: brief)
        return PaperCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                labeled("Task", title)
                labeled("Category", plan.primary.lane == .technicalCore ? "Technical Core" : "Technical Hands", tone: plan.primary.lane == .technicalCore ? Ink.gold : Ink.teal)
                Text(plan.read.reasons.first ?? plan.read.complexity)
                    .font(.caption)
                    .foregroundStyle(Ink.mute)
                if !plan.read.skills.isEmpty {
                    labeled("Required skills", plan.read.skills.joined(separator: ", "))
                }
                if suggestSomeone {
                    callRow(plan.primary, heading: "You could call")
                    if let other = plan.other {
                        callRow(other, heading: other.lane == .technicalCore ? "Or call for Technical Core" : "Or call for Technical Hands")
                    }
                    Button("I'll do this myself") { suggestSomeone = false }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Ink.teal)
                } else {
                    Text("You'll handle this.")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Ink.paper)
                    Button("Suggest someone") { suggestSomeone = true }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Ink.teal)
                }
            }
        }
    }

    private func labeled(_ label: String, _ value: String, tone: Color = Ink.paper) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Ink.mute)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tone)
        }
    }

    private func callRow(_ call: WorkCall, heading: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(heading)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Ink.mute)
            if let person = call.person {
                Text(person.user.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Ink.paper)
                Text(person.why)
                    .font(.caption)
                    .foregroundStyle(Ink.mute)
            } else {
                Text("No one on campus lists these skills yet.")
                    .font(.caption)
                    .foregroundStyle(Ink.mute)
            }
        }
    }
}

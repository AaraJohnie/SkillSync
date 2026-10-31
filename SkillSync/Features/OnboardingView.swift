import SwiftUI

@MainActor
@Observable
final class OnboardingViewModel {
    var name = ""
    var institution = ""
    var roleTitle = ""
    var lane: ContributionLane = .technicalHands
    var skills: [UserSkill] = []
    var step = 0

    func load(_ user: UserProfile) {
        name = user.displayName
        institution = user.university
        roleTitle = user.roleTitle
        lane = user.lane
        skills = user.skills
    }

    func toggleSkill(_ catalog: CatalogSkill) {
        if let index = skills.firstIndex(where: { $0.name == catalog.name }) {
            skills.remove(at: index)
        } else {
            skills.append(UserSkill(name: catalog.name, level: .intermediate, category: catalog.category))
        }
    }

    func cycleLevel(_ name: String) {
        guard let index = skills.firstIndex(where: { $0.name == name }) else { return }
        let next = SkillLevel.allCases[(skills[index].level.rank) % SkillLevel.allCases.count]
        skills[index].level = next
    }

    func save(into store: DemoStore) {
        guard var user = store.currentUser else { return }
        user.displayName = name
        user.university = institution
        user.roleTitle = roleTitle
        user.lane = lane
        user.skills = skills
        user.onboardingComplete = !name.isEmpty && !institution.isEmpty && !skills.isEmpty && !roleTitle.isEmpty
        user.trustReviewed = false
        store.saveProfile(user)
    }
}

struct OnboardingView: View {
    @Environment(AppSession.self) private var session
    @State private var model = OnboardingViewModel()

    var body: some View {
        ZStack {
            Ink.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                progress
                TabView(selection: $model.step) {
                    identity.tag(0)
                    haveSkills.tag(1)
                    role.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                actions
            }
        }
        .onAppear {
            if let user = session.store.currentUser {
                model.load(user)
            }
        }
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(stepTitle)
                .font(Typeface.display(28))
                .foregroundStyle(Ink.paper)
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(index <= model.step ? Ink.gold : Ink.line)
                        .frame(height: 4)
                }
            }
        }
        .padding(24)
    }

    private var stepTitle: String {
        switch model.step {
        case 1: "What can you ship?"
        case 2: "What role do you play?"
        default: "Create your profile"
        }
    }

    private var identity: some View {
        ScrollView {
            VStack(spacing: 16) {
                FieldLabel(title: "Name", text: $model.name, contentType: .name, capitalization: .words, disablesAutocorrection: false)
                FieldLabel(title: "Institution", text: $model.institution, capitalization: .words, disablesAutocorrection: false)
            }
            .padding(.horizontal, 24)
        }
    }

    private var haveSkills: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Tap the skills you can actually do. Tap a selected chip again to raise the level.")
                    .foregroundStyle(Ink.mute)
                ForEach(SkillCatalog.grouped(), id: \.0) { category, skills in
                    VStack(alignment: .leading, spacing: 10) {
                        Label(category.label, systemImage: category.symbol)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Ink.teal)
                        FlowWrap(items: skills) { skill in
                            let selected = model.skills.first { $0.name == skill.name }
                            Button {
                                if selected == nil {
                                    model.toggleSkill(skill)
                                } else {
                                    model.cycleLevel(skill.name)
                                }
                            } label: {
                                SkillChip(name: skill.name, level: selected?.level, tone: selected == nil ? .mute : .teal)
                            }
                            .buttonStyle(.plain)
                            .simultaneousGesture(LongPressGesture().onEnded { _ in
                                model.toggleSkill(skill)
                            })
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
        }
    }

    private var role: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                FieldLabel(title: "Role", text: $model.roleTitle, capitalization: .words, disablesAutocorrection: false, prompt: "iOS Developer")
                ForEach(ContributionLane.allCases) { lane in
                    Button {
                        model.lane = lane
                    } label: {
                        PaperCard(padding: 14) {
                            VStack(alignment: .leading, spacing: 6) {
                                Label(lane.label, systemImage: lane.symbol)
                                    .font(.headline)
                                    .foregroundStyle(model.lane == lane ? Ink.gold : Ink.paper)
                                Text(lane.detail)
                                    .font(.subheadline)
                                    .foregroundStyle(Ink.mute)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
        }
    }

    private var actions: some View {
        HStack {
            if model.step > 0 {
                Button("Back") { model.step -= 1 }
                    .foregroundStyle(Ink.mute)
            }
            Spacer()
            Button(model.step == 2 ? "Continue to verification" : "Next") {
                if model.step == 2 {
                    model.save(into: session.store)
                } else {
                    model.step += 1
                }
            }
            .font(.headline)
            .foregroundStyle(Ink.stamp)
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background(Ink.gold, in: Capsule())
        }
        .padding(24)
    }
}

struct FlowWrap<Item: Identifiable, Content: View>: View {
    var items: [Item]
    @ViewBuilder var content: (Item) -> Content

    var body: some View {
        FlexibleWrap {
            ForEach(items) { item in
                content(item)
            }
        }
    }
}

private struct FlexibleWrap: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, origin) in result.origins.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (origins: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var width: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            width = max(width, x)
        }
        return (origins, CGSize(width: width, height: y + rowHeight))
    }
}

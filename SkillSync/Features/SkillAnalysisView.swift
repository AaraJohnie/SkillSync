import SwiftUI

enum SkillGuidePane: String, CaseIterable, Identifiable {
    case profile
    case evidence
    case gap

    var id: String { rawValue }

    var label: String {
        switch self {
        case .profile: "Profile"
        case .evidence: "Evidence"
        case .gap: "Gap"
        }
    }
}

@MainActor
@Observable
final class SkillAnalysisModel {
    var pane: SkillGuidePane = .profile
    var sourceText = ""
    var skillsText = ""
    var projectText = ""
    var experienceText = ""
    var targetText = ""
    var isLoading = false
    var profile: SkillProfile?
    var analysis: SkillAnalysis?
    var gap: SkillGapReport?
    var errorMessage: String?

    func load(from user: UserProfile?) {
        guard sourceText.isEmpty, skillsText.isEmpty, let user else { return }
        skillsText = user.skills.map(\.name).joined(separator: ", ")
        sourceText = [user.bio, user.collaborations.first.map { "\($0.projectTitle). \($0.shipNote ?? "")" } ?? ""]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        projectText = user.collaborations.first.map { "\($0.projectTitle). \($0.shipNote ?? "")" } ?? ""
        experienceText = user.bio
        targetText = user.neededSkills.first ?? ""
    }

    func run() async {
        isLoading = true
        errorMessage = nil
        do {
            switch pane {
            case .profile:
                let result = try await SkillGuide.profile(source: sourceText)
                profile = result
                skillsText = result.skills.map(\.name).joined(separator: ", ")
            case .evidence:
                analysis = try await SkillGuide.analyze(
                    SkillAnalysisRequest(skills: skillNames, projectDescription: projectText, experience: experienceText)
                )
            case .gap:
                gap = try await SkillGuide.gap(skills: skillNames, target: targetText)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private var skillNames: [String] {
        skillsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

struct SkillAnalysisView: View {
    @Environment(AppSession.self) private var session
    @State private var model = SkillAnalysisModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Skill guide")
                    .font(Typeface.display(32))
                    .foregroundStyle(Ink.paper)
                Text(intro)
                    .font(.subheadline)
                    .foregroundStyle(Ink.mute)
                Picker("Guide", selection: $model.pane) {
                    ForEach(SkillGuidePane.allCases) { pane in
                        Text(pane.label).tag(pane)
                    }
                }
                .pickerStyle(.segmented)
                editor
                if model.isLoading {
                    ProgressView("Reading what you wrote…")
                        .tint(Ink.gold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    result
                }
                if let errorMessage = model.errorMessage {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(Ink.coral)
                }
            }
            .padding(20)
        }
        .background(Ink.bg.ignoresSafeArea())
        .navigationTitle("Skill guide")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.load(from: session.store.currentUser) }
    }

    private var intro: String {
        switch model.pane {
        case .profile:
            "Paste a project, certificate, or résumé excerpt. The guide extracts skills it can actually see."
        case .evidence:
            "An assessment of the work you describe. It is not proof of identity or expertise."
        case .gap:
            "Compare the skills you have with a role you want, and see what is still missing."
        }
    }

    @ViewBuilder
    private var editor: some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 14) {
                switch model.pane {
                case .profile:
                    field("What you've done", text: $model.sourceText)
                case .evidence:
                    field("Skills", text: $model.skillsText)
                    field("Project", text: $model.projectText)
                    field("Experience", text: $model.experienceText)
                case .gap:
                    field("Skills you have", text: $model.skillsText)
                    field("Target role", text: $model.targetText)
                }
                PrimaryButton(title: model.isLoading ? "Checking…" : buttonTitle) {
                    Task { await model.run() }
                }
                .disabled(model.isLoading)
            }
        }
    }

    private var buttonTitle: String {
        switch model.pane {
        case .profile: "Build profile"
        case .evidence: "Check evidence"
        case .gap: "Find the gap"
        }
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Ink.mute)
            TextField(title, text: text, axis: .vertical)
                .lineLimit(2...6)
                .foregroundStyle(Ink.paper)
                .padding(12)
                .background(Ink.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    @ViewBuilder
    private var result: some View {
        switch model.pane {
        case .profile:
            if let profile = model.profile { profileResult(profile) }
        case .evidence:
            if let analysis = model.analysis { evidenceResult(analysis) }
        case .gap:
            if let gap = model.gap { gapResult(gap) }
        }
    }

    private func profileResult(_ profile: SkillProfile) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            summaryCard(profile.summary)
            ForEach(profile.skills) { skill in
                PaperCard(padding: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(skill.name).font(.headline).foregroundStyle(Ink.paper)
                            Spacer()
                            Text(skill.category).font(.caption.weight(.semibold)).foregroundStyle(Ink.teal)
                        }
                        Text(skill.evidence).font(.subheadline).foregroundStyle(Ink.mute)
                    }
                }
            }
        }
    }

    private func evidenceResult(_ analysis: SkillAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            summaryCard(analysis.summary)
            ForEach(analysis.skills) { skill in
                PaperCard(padding: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(skill.name).font(.headline).foregroundStyle(Ink.paper)
                            Spacer()
                            Text(skill.level).font(.subheadline.weight(.semibold)).foregroundStyle(Ink.gold)
                        }
                        Text(skill.evidence).font(.subheadline).foregroundStyle(Ink.mute)
                    }
                }
            }
            stepsCard("Work on next", analysis.recommendations)
        }
    }

    private func gapResult(_ gap: SkillGapReport) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            summaryCard(gap.summary)
            ForEach(gap.missing) { item in
                PaperCard(padding: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.name).font(.headline).foregroundStyle(Ink.paper)
                        Text(item.why).font(.subheadline).foregroundStyle(Ink.mute)
                        Text(item.nextStep).font(.subheadline).foregroundStyle(Ink.gold)
                    }
                }
            }
            stepsCard("Learning path", gap.path)
        }
    }

    private func summaryCard(_ text: String) -> some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Assessment")
                Text(text).foregroundStyle(Ink.paper)
            }
        }
    }

    @ViewBuilder
    private func stepsCard(_ title: String, _ steps: [String]) -> some View {
        if !steps.isEmpty {
            PaperCard {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: title)
                    ForEach(steps, id: \.self) { step in
                        Text(step).foregroundStyle(Ink.paper)
                    }
                }
            }
        }
    }
}

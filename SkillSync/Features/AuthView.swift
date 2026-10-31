import SwiftUI

@MainActor
@Observable
final class AuthViewModel {
    var name = ""
    var email = ""
    var password = ""
    var linkedIn = ""
    var github = ""
    var otherLink = ""
    var narrative = ""
    var error: String?
    var isCreating = false
    var isChecking = false
    var verdict: CredentialVerdict?
    var extraction: ProfileExtraction?
    var identity: IdentityCheck?

    var submittedLinks: [String] {
        [linkedIn, github, otherLink]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var hasInvalidLink: Bool {
        verdict?.checks.contains { $0.status == .rejected } == true
    }

    func continueDemo(store: DemoStore) {
        store.signInDemo()
    }

    func invalidateCheck() {
        verdict = nil
        extraction = nil
        identity = nil
    }

    func verify(against store: DemoStore) async {
        error = nil
        isChecking = true
        defer { isChecking = false }
        let links = submittedLinks
        let narrative = self.narrative
        let extraction = await ProfileUnderstandingService.understand(narrative: narrative, links: links)
        self.extraction = extraction
        var verdict = CredentialVerifier.evaluate(links: links, existing: store.users)
        let identity = await IdentityEvidenceCheck.run(narrative: narrative, checks: verdict.checks)
        if identity.gitHubLogin == nil, let index = verdict.checks.firstIndex(where: { $0.platform == .github && $0.status == .verified }) {
            let finding = identity.finding.lowercased()
            let lookupFailed = finding.contains("github") && (finding.contains("declined") || finding.contains("no user") || finding.contains("could not") || finding.contains("did not answer"))
            if lookupFailed {
                verdict.checks[index].status = .rejected
                verdict.checks[index].reason = "GitHub could not be read, so this link is not accepted."
            }
        }
        self.identity = identity
        self.verdict = verdict
    }

    func submit(store: DemoStore) async {
        error = nil
        do {
            if verdict == nil {
                await verify(against: store)
            }
            guard !hasInvalidLink else {
                error = "Fix the invalid link before creating an account."
                return
            }
            guard let verdict, !verdict.verified.isEmpty else {
                throw AppError.unverifiedCredentials
            }
            if let identity, !IdentityEvidenceCheck.supportsClaim(identity) {
                throw AppError.claimUnsupported(identity.finding)
            }
            let supported = Set((identity?.profile.skills ?? []).filter { $0.status != .unverified }.map(\.claimedSkill))
            let skills = (extraction?.userSkills ?? []).filter { supported.isEmpty || supported.contains($0.name) }
            let claimed = IdentityEvidenceCheck.claimedSkills(in: narrative)
            let evidenced = claimed.filter { supported.contains($0) }.map { name in
                UserSkill(name: name, level: .intermediate, category: SkillCatalog.category(for: name))
            }
            let merged = skills.isEmpty ? evidenced : skills
            try store.signUp(
                name: name,
                email: email,
                password: password,
                bio: extraction?.summary ?? narrative,
                skills: merged,
                platformLinks: verdict.verified
            )
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct AuthView: View {
    @Environment(AppSession.self) private var session
    @State private var model = AuthViewModel()

    var body: some View {
        ZStack {
            Ink.bg.ignoresSafeArea()
            Circle()
                .fill(Ink.gold.opacity(0.08))
                .frame(width: 420)
                .offset(x: 140, y: -280)
            Circle()
                .fill(Ink.teal.opacity(0.08))
                .frame(width: 320)
                .offset(x: -160, y: 260)

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("SkillSync")
                            .font(Typeface.display(42))
                            .foregroundStyle(Ink.paper)
                        Text("Find the person who has what you don’t.")
                            .font(Typeface.title())
                            .foregroundStyle(Ink.paper)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Then send a one-line pitch.")
                            .font(.title3)
                            .foregroundStyle(Ink.mute)
                    }
                    .padding(.top, 48)

                    if model.isCreating {
                        createAccount
                    } else {
                        PrimaryButton(title: "Continue with existing account") {
                            model.continueDemo(store: session.store)
                        }
                        Button("Create new account") {
                            withAnimation(.easeOut(duration: 0.25)) { model.isCreating = true }
                        }
                        .font(.headline)
                        .foregroundStyle(Ink.teal)
                    }
                }
                .padding(24)
            }
        }
    }

    private var createAccount: some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionLabel(text: "Create a new account")
                FieldLabel(
                    title: "Name",
                    text: $model.name,
                    contentType: .name,
                    capitalization: .words,
                    disablesAutocorrection: false
                )
                FieldLabel(
                    title: "University email",
                    text: $model.email,
                    keyboard: .emailAddress,
                    contentType: .emailAddress,
                    capitalization: .never,
                    disablesAutocorrection: true,
                    addressKeys: true
                )
                FieldLabel(title: "Password", text: $model.password, secure: true)
                credentialFields
                if let error = model.error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(Ink.coral)
                }
                PrimaryButton(title: model.isChecking ? "Checking links…" : "Create trusted account") {
                    guard !model.isChecking, !model.hasInvalidLink else { return }
                    Task { await model.submit(store: session.store) }
                }
                .disabled(model.isChecking || model.hasInvalidLink)
                .opacity(model.hasInvalidLink ? 0.4 : 1)
                Button("Continue with existing account") {
                    withAnimation(.easeOut(duration: 0.25)) {
                        model.isCreating = false
                        model.error = nil
                    }
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Ink.teal)
            }
        }
    }

    private var credentialFields: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Other students trust a profile that points at a real LinkedIn and a real project. This phone reads your skills. The campus check decides whether the links are yours to claim.")
                .font(.footnote)
                .foregroundStyle(Ink.mute)
            FieldLabel(title: "LinkedIn", text: $model.linkedIn, keyboard: .emailAddress, allowsClipboard: true)
                .onChange(of: model.linkedIn) { _, _ in model.invalidateCheck() }
            FieldLabel(title: "GitHub", text: $model.github, keyboard: .emailAddress, allowsClipboard: true)
                .onChange(of: model.github) { _, _ in model.invalidateCheck() }
            FieldLabel(title: "Behance, Dribbble, Figma, or another project link", text: $model.otherLink, keyboard: .emailAddress, allowsClipboard: true)
                .onChange(of: model.otherLink) { _, _ in model.invalidateCheck() }
            FieldLabel(
                title: "What you can ship",
                text: $model.narrative,
                capitalization: .sentences,
                disablesAutocorrection: false,
                allowsClipboard: true,
                axis: .vertical,
                prompt: "SwiftUI and Firebase. I shipped a booking app."
            )
            .onChange(of: model.narrative) { _, _ in model.invalidateCheck() }
            Button(model.isChecking ? "Reading your profile…" : "Check links") {
                guard !model.isChecking else { return }
                Task { await model.verify(against: session.store) }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Ink.gold)
            if let verdict = model.verdict {
                TrustMark(trust: verdict.trust)
                ForEach(verdict.checks) { check in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: check.status == .verified ? "checkmark.seal.fill" : "xmark.seal")
                            .foregroundStyle(check.status == .verified ? Ink.teal : Ink.coral)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(check.platform?.label ?? "Link")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Ink.paper)
                            Text(check.reason)
                                .font(.caption)
                                .foregroundStyle(Ink.mute)
                        }
                    }
                }
                if let identity = model.identity {
                    Text(identity.finding)
                        .font(.footnote)
                        .foregroundStyle(Ink.paper)
                    ForEach(identity.profile.skills) { verdict in
                        HStack {
                            Text(verdict.claimedSkill)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Ink.paper)
                            Spacer()
                            Text(verdict.status.label)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(verdict.status == .unverified ? Ink.coral : Ink.teal)
                        }
                    }
                }
                if let extraction = model.extraction, !extraction.skills.isEmpty {
                    Text(extraction.source == "on-device" ? "Skills read on this device." : "Skills matched from the catalog on this device.")
                        .font(.caption)
                        .foregroundStyle(Ink.mute)
                    FlowWrap(items: extraction.userSkills) { skill in
                        SkillChip(name: skill.name, level: skill.level, tone: .teal)
                    }
                }
            }
        }
    }

}

import Foundation
import SkillEvidenceAgent
import Observation

struct StoreSnapshot: Codable {
    var seedVersion: Int?
    var currentUserId: String?
    var users: [UserProfile]
    var projects: [Project]
    var requests: [CollaborationRequest]
    var huddles: [Huddle]
    var messages: [HuddleMessage]
    var tasks: [HuddleTask]
    var milestones: [Milestone]
}

@MainActor
@Observable
final class DemoStore {
    var currentUserId: String?
    var users: [UserProfile] = []
    var projects: [Project] = []
    var requests: [CollaborationRequest] = []
    var huddles: [Huddle] = []
    var messages: [HuddleMessage] = []
    var tasks: [HuddleTask] = []
    var milestones: [Milestone] = []
    var lastError: String?
    var blindMatching: Bool = UserDefaults.standard.object(forKey: "skillsync.blindMatching") as? Bool ?? true {
        didSet { UserDefaults.standard.set(blindMatching, forKey: "skillsync.blindMatching") }
    }
    var appearance: AppearanceMode = AppearanceMode(rawValue: UserDefaults.standard.string(forKey: "skillsync.appearance") ?? "") ?? .dark {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: "skillsync.appearance") }
    }
    var showPitchCoach: Bool = UserDefaults.standard.object(forKey: "skillsync.showPitchCoach") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showPitchCoach, forKey: "skillsync.showPitchCoach") }
    }

    func dismissPitchCoach() {
        showPitchCoach = false
    }

    private let cache: LocalCache

    var currentUser: UserProfile? {
        get { users.first { $0.id == currentUserId } }
        set {
            guard let newValue else { return }
            upsert(newValue)
        }
    }

    var seedVersion: Int = 0

    init(cache: LocalCache) {
        self.cache = cache
        if let snapshot = Self.loadSnapshot() {
            seedVersion = snapshot.seedVersion ?? 0
            currentUserId = snapshot.currentUserId
            users = snapshot.users
            projects = snapshot.projects
            requests = snapshot.requests
            huddles = snapshot.huddles
            messages = snapshot.messages
            tasks = snapshot.tasks
            milestones = snapshot.milestones
            if seedVersion < CampusSeed.version {
                mergeCampusPlatform(from: CampusSeed.make())
            }
        } else {
            apply(CampusSeed.make(), keepingCurrentUser: false)
        }
    }

    func switchTo(userId: String) {
        guard users.contains(where: { $0.id == userId }) else { return }
        currentUserId = userId
        persist()
    }

    func platformStatus(for userId: String) -> String {
        let pitches = incomingRequests(for: userId).count
        let active = huddles(for: userId).filter { $0.status == .active }.count
        let shipped = user(userId)?.collaborations.count ?? 0
        var parts: [String] = []
        if pitches > 0 { parts.append("\(pitches) pitch\(pitches == 1 ? "" : "es") waiting") }
        if active > 0 { parts.append("\(active) huddle") }
        if shipped > 0 { parts.append("\(shipped) shipped") }
        return parts.isEmpty ? "Ready to match" : parts.joined(separator: " · ")
    }

    func user(_ id: String) -> UserProfile? {
        users.first { $0.id == id }
    }

    func project(_ id: String) -> Project? {
        projects.first { $0.id == id }
    }

    func identityUnlocked(with otherId: String) -> Bool {
        guard let me = currentUserId else { return false }
        if me == otherId { return true }
        let connected = requests.contains {
            (($0.fromUserId == me && $0.toUserId == otherId) || ($0.fromUserId == otherId && $0.toUserId == me))
            && $0.status != .declined
        }
        let together = huddles.contains { $0.memberIds.contains(me) && $0.memberIds.contains(otherId) }
        return connected || together
    }

    func shippedProjects() -> [Project] {
        projects.filter { $0.status == .completed }.sorted { $0.deadline > $1.deadline }
    }

    func squads(for project: Project) -> [MicroSquad] {
        guard let user = currentUser else { return [] }
        return SquadEngine.propose(seeker: user, project: project, pool: users)
    }

    func oppositeMatches() -> [MatchCandidate] {
        guard let user = currentUser else { return [] }
        return Array(matches(for: user).filter { $0.synergy.complementaryCoverage >= 0.5 && $0.synergy.reverseCoverage >= 0.5 }.prefix(3))
    }

    func hasVouched(for userId: String, huddleId: String) -> Bool {
        guard let from = currentUserId, let huddle = huddle(huddleId) else { return false }
        let title = project(huddle.projectId)?.title
        return user(userId)?.vouches.contains { $0.fromUserId == from && $0.projectTitle == title } == true
    }

    func matches(for user: UserProfile, project: Project? = nil) -> [MatchCandidate] {
        users
            .filter { $0.id != user.id && $0.onboardingComplete }
            .map { candidate in
                MatchCandidate(
                    user: candidate,
                    project: project,
                    synergy: SynergyEngine.evaluate(seeker: user, candidate: candidate, project: project)
                )
            }
            .sorted { $0.synergy.score > $1.synergy.score }
    }

    func incomingRequests(for userId: String) -> [CollaborationRequest] {
        requests
            .filter { $0.toUserId == userId && $0.status == .pending }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func outgoingRequests(for userId: String) -> [CollaborationRequest] {
        requests.filter { $0.fromUserId == userId }
    }

    func huddle(_ id: String) -> Huddle? {
        huddles.first { $0.id == id }
    }

    func huddles(for userId: String) -> [Huddle] {
        huddles
            .filter { $0.memberIds.contains(userId) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func messages(in huddleId: String) -> [HuddleMessage] {
        messages
            .filter { $0.huddleId == huddleId }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func tasks(in huddleId: String) -> [HuddleTask] {
        tasks.filter { $0.huddleId == huddleId }
    }

    func milestones(in huddleId: String) -> [Milestone] {
        milestones
            .filter { $0.huddleId == huddleId }
            .sorted { $0.dueDate < $1.dueDate }
    }

    func signInDemo() {
        currentUserId = CampusSeed.jordanID
        persist()
    }

    func signOut() {
        currentUserId = nil
        persist()
    }

    func signUp(
        name: String,
        email: String,
        password _: String,
        bio: String = "",
        skills: [UserSkill] = [],
        platformLinks: [PlatformCredential] = []
    ) throws {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.contains("@") else { throw AppError.invalidEmail }
        let verified = platformLinks.filter { $0.status == .verified }
        guard !verified.isEmpty else { throw AppError.unverifiedCredentials }
        if let existing = users.first(where: { $0.email.lowercased() == trimmed }) {
            currentUserId = existing.id
            persist()
            return
        }
        let profile = UserProfile(
            id: UUID().uuidString,
            email: trimmed,
            displayName: name.isEmpty ? trimmed.split(separator: "@").first.map(String.init) ?? "Student" : name,
            university: "",
            year: "Year 2",
            bio: bio,
            isStudentVerified: StudentVerification.isVerified(email: trimmed),
            onboardingComplete: false,
            skills: skills,
            neededSkills: [],
            availability: .typical,
            collaborations: [],
            vouches: [],
            platformLinks: verified,
            createdAt: .now
        )
        users.append(profile)
        currentUserId = profile.id
        persist()
    }

    func signIn(email: String, password _: String) throws {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let existing = users.first(where: { $0.email.lowercased() == trimmed }) else {
            throw AppError.unknownAccount
        }
        currentUserId = existing.id
        persist()
    }

    func saveProfile(_ profile: UserProfile) {
        var updated = profile
        updated.onboardingComplete = !profile.displayName.isEmpty && !profile.skills.isEmpty
        upsert(updated)
        cache.remember(profile: updated)
        persist()
    }

    func createProject(title: String, summary: String, requiredSkills: [String], durationDays: Int, deadline: Date, taskLane: ContributionLane) -> Project? {
        guard let user = currentUser else { return nil }
        let project = Project(
            id: UUID().uuidString,
            title: title,
            summary: summary,
            ownerId: user.id,
            requiredSkills: requiredSkills,
            durationDays: durationDays,
            deadline: deadline,
            status: .recruiting,
            memberIds: [user.id],
            huddleId: nil,
            proofURL: nil,
            taskLane: taskLane,
            createdAt: .now
        )
        projects.insert(project, at: 0)
        cache.remember(project: project)
        persist()
        return project
    }

    func sendPitch(to candidate: UserProfile, project: Project?, text: String) throws {
        guard let user = currentUser else { throw AppError.missingProfile }
        guard user.id != candidate.id else { throw AppError.cannotPitchSelf }
        let exists = requests.contains {
            $0.status == .pending &&
            (($0.fromUserId == user.id && $0.toUserId == candidate.id) ||
             ($0.fromUserId == candidate.id && $0.toUserId == user.id))
        }
        if exists { throw AppError.requestAlreadyExists }
        let synergy = SynergyEngine.evaluate(seeker: user, candidate: candidate, project: project)
        let request = CollaborationRequest(
            id: UUID().uuidString,
            fromUserId: user.id,
            toUserId: candidate.id,
            projectId: project?.id,
            pitch: text,
            synergyScore: synergy.score,
            status: .pending,
            createdAt: .now
        )
        requests.insert(request, at: 0)
        dismissPitchCoach()
        persist()
    }

    func respond(to requestId: String, accept: Bool) {
        guard let index = requests.firstIndex(where: { $0.id == requestId }) else { return }
        requests[index].status = accept ? .accepted : .declined
        if accept {
            _ = openHuddle(from: requests[index])
        }
        persist()
    }

    func sendMessage(huddleId: String, text: String) {
        guard let user = currentUser else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        messages.append(
            HuddleMessage(
                id: UUID().uuidString,
                huddleId: huddleId,
                authorId: user.id,
                text: trimmed,
                createdAt: .now
            )
        )
        persist()
    }

    func addTask(huddleId: String, title: String, assigneeId: String?) {
        tasks.append(
            HuddleTask(
                id: UUID().uuidString,
                huddleId: huddleId,
                title: title,
                assigneeId: assigneeId,
                lane: .todo,
                createdAt: .now
            )
        )
        persist()
    }

    func assignTask(_ taskId: String, to userId: String?) {
        guard let index = tasks.firstIndex(where: { $0.id == taskId }) else { return }
        tasks[index].assigneeId = userId
        persist()
    }

    func addMilestone(huddleId: String, title: String, dueDate: Date) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        milestones.append(
            Milestone(
                id: UUID().uuidString,
                huddleId: huddleId,
                title: trimmed,
                dueDate: dueDate,
                isComplete: false
            )
        )
        persist()
    }

    func setRole(huddleId: String, userId: String, role: String) {
        guard let index = huddles.firstIndex(where: { $0.id == huddleId }) else { return }
        var roles = huddles[index].roleList
        if let existing = roles.firstIndex(where: { $0.userId == userId }) {
            roles[existing].role = role
        } else {
            roles.append(RoleAssignment(userId: userId, role: role))
        }
        huddles[index].roles = roles
        persist()
    }

    func moveTask(_ taskId: String, to lane: TaskLane) {
        guard let index = tasks.firstIndex(where: { $0.id == taskId }) else { return }
        tasks[index].lane = lane
        persist()
    }

    func toggleMilestone(_ id: String) {
        guard let index = milestones.firstIndex(where: { $0.id == id }) else { return }
        milestones[index].isComplete.toggle()
        persist()
    }

    func complete(huddleId: String, proofURL: String, shipNote: String) throws {
        let proof = try ProofLink.normalize(proofURL)
        let note = shipNote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard note.count >= 8 else { throw AppError.missingShipNote }
        guard let huddleIndex = huddles.firstIndex(where: { $0.id == huddleId }) else {
            throw AppError.huddleNotFound
        }
        huddles[huddleIndex].status = .completed
        huddles[huddleIndex].shipNote = note
        let huddle = huddles[huddleIndex]
        if let projectIndex = projects.firstIndex(where: { $0.id == huddle.projectId }) {
            projects[projectIndex].status = .completed
            projects[projectIndex].proofURL = proof
            projects[projectIndex].shipNote = note
            let project = projects[projectIndex]
            for memberId in huddle.memberIds {
                guard let userIndex = users.firstIndex(where: { $0.id == memberId }) else { continue }
                let teammates = huddle.memberIds
                    .filter { $0 != memberId }
                    .compactMap { user($0)?.displayName }
                let role = huddle.roleList.first(where: { $0.userId == memberId })?.role
                    ?? users[userIndex].skills.first?.name
                    ?? "Collaborator"
                let showed = Reliability.showedUp(
                    userId: memberId,
                    huddleId: huddle.id,
                    tasks: tasks,
                    messages: messages
                )
                let record = VerifiedCollaboration(
                    id: UUID().uuidString,
                    projectId: project.id,
                    projectTitle: project.title,
                    role: role,
                    teammateNames: teammates,
                    durationDays: project.durationDays,
                    proofURL: proof,
                    shipNote: note,
                    showedUp: showed,
                    completedAt: .now
                )
                users[userIndex].collaborations.insert(record, at: 0)
                cache.remember(profile: users[userIndex])
            }
        }
        persist()
    }

    func submitVouch(huddleId: String, toUserId: String, scores: [VouchDimension: Int], note: String) throws {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 12 else { throw AppError.missingVouchNote }
        guard let from = currentUser, let huddle = huddle(huddleId) else { return }
        if hasVouched(for: toUserId, huddleId: huddleId) { throw AppError.alreadyVouched }
        let projectCompleted = huddle.status == .completed
        let spoke = messages.contains { $0.huddleId == huddleId && $0.authorId == from.id }
            || tasks.contains { $0.huddleId == huddleId && $0.assigneeId == from.id }
        let pair = (users.first { $0.id == toUserId }?.vouches.filter { $0.fromUserId == from.id }.count ?? 0)
            + from.vouches.filter { $0.fromUserId == toUserId }.count
        let subject = users.first { $0.id == toUserId }
        let assembled = SkillEvidenceBridge.assemble(
            user: subject ?? from,
            projects: projects,
            portfolioText: nil,
            portfolioWasFetched: false,
            gitHub: nil,
            stage: projectCompleted ? .shipped : .huddle,
            vouch: VouchAttempt(
            voucherId: from.id,
            subjectId: toUserId,
            projectId: huddle.projectId,
            voucherWasMember: huddle.memberIds.contains(from.id),
            projectCompleted: projectCompleted,
            interactionRecorded: spoke,
            alreadyVouchedThisProject: false,
            vouchesBetweenPair: pair,
            voucherCreatedAt: from.createdAt
        )
        )
        guard let decision = assembled.vouch else { throw AppError.vouchRejected("A vouch waits until the project is in the sequence.") }
        if let rejection = decision.rejection {
            throw AppError.vouchRejected(vouchMessage(rejection))
        }
        let projectTitle = project(huddle.projectId)?.title ?? "Huddle"
        let encoded = Dictionary(uniqueKeysWithValues: scores.map { ($0.key.rawValue, $0.value) })
        let badge = VouchBadge(
            id: UUID().uuidString,
            fromUserId: from.id,
            fromName: from.displayName,
            projectTitle: projectTitle,
            scores: encoded,
            note: trimmed,
            createdAt: .now
        )
        guard let index = users.firstIndex(where: { $0.id == toUserId }) else { return }
        users[index].vouches.insert(badge, at: 0)
        persist()
    }

    private func vouchMessage(_ rejection: VouchRejection) -> String {
        switch rejection {
        case .selfVouch: "You cannot vouch for yourself."
        case .notOnProject: "Only someone on that project can vouch."
        case .projectOpen: "Finish the project before a vouch counts."
        case .noInteraction: "A vouch needs a recorded message or task on that project."
        case .duplicate: "You already vouched for them on this project."
        case .pairTooDense: "These two accounts have already vouched for each other enough times."
        case .accountTooNew: "A new account has to wait a day before a vouch counts."
        }
    }

    func resetCampus() {
        showPitchCoach = true
        apply(CampusSeed.make(), keepingCurrentUser: false)
    }

    private func apply(_ seed: StoreSnapshot, keepingCurrentUser: Bool) {
        let preservedId = keepingCurrentUser ? currentUserId : nil
        seedVersion = CampusSeed.version
        currentUserId = preservedId
        users = seed.users
        projects = seed.projects
        requests = seed.requests
        huddles = seed.huddles
        messages = seed.messages
        tasks = seed.tasks
        milestones = seed.milestones
        persist()
    }

    private func mergeCampusPlatform(from seed: StoreSnapshot) {
        for profile in seed.users {
            if let index = users.firstIndex(where: { $0.id == profile.id }) {
                for collab in profile.collaborations where !users[index].collaborations.contains(where: { $0.id == collab.id }) {
                    users[index].collaborations.append(collab)
                }
                for vouch in profile.vouches where !users[index].vouches.contains(where: { $0.id == vouch.id }) {
                    users[index].vouches.append(vouch)
                }
                if users[index].platformLinks.isEmpty {
                    users[index].platformLinks = profile.platformLinks
                }
            } else {
                users.append(profile)
            }
        }
        func insertMissing<Item: Identifiable>(_ incoming: [Item], into existing: inout [Item]) {
            for item in incoming where !existing.contains(where: { $0.id == item.id }) {
                existing.append(item)
            }
        }
        insertMissing(seed.projects, into: &projects)
        insertMissing(seed.requests, into: &requests)
        insertMissing(seed.huddles, into: &huddles)
        insertMissing(seed.messages, into: &messages)
        insertMissing(seed.tasks, into: &tasks)
        insertMissing(seed.milestones, into: &milestones)
        for index in huddles.indices where huddles[index].roles == nil {
            let members = huddles[index].memberIds.compactMap(user)
            let required = project(huddles[index].projectId)?.requiredSkills ?? []
            huddles[index].roles = RoleContract.suggest(members: members, required: required)
        }
        seedVersion = CampusSeed.version
        persist()
    }

    private func openHuddle(from request: CollaborationRequest) -> Huddle {
        let ownerId = request.fromUserId
        let memberIds = [request.fromUserId, request.toUserId]
        let existingProject: Project
        if let projectId = request.projectId, let found = project(projectId) {
            existingProject = found
        } else {
            let fromName = user(ownerId)?.firstName ?? "Team"
            existingProject = Project(
                id: UUID().uuidString,
                title: "\(fromName)’s huddle",
                summary: request.pitch,
                ownerId: ownerId,
                requiredSkills: Array(user(request.toUserId)?.skills.map(\.name).prefix(3) ?? []),
                durationDays: 14,
                deadline: Calendar.current.date(byAdding: .day, value: 14, to: .now) ?? .now,
                status: .recruiting,
                memberIds: memberIds,
                huddleId: nil,
                proofURL: nil,
                createdAt: .now
            )
            projects.insert(existingProject, at: 0)
        }

        let huddle = Huddle(
            id: UUID().uuidString,
            projectId: existingProject.id,
            memberIds: Array(Set(existingProject.memberIds + memberIds)),
            status: .active,
            roles: RoleContract.suggest(
                members: Array(Set(existingProject.memberIds + memberIds)).compactMap(user),
                required: existingProject.requiredSkills
            ),
            createdAt: .now
        )
        huddles.insert(huddle, at: 0)
        if let index = projects.firstIndex(where: { $0.id == existingProject.id }) {
            projects[index].status = .active
            projects[index].huddleId = huddle.id
            projects[index].memberIds = huddle.memberIds
        }
        messages.append(
            HuddleMessage(
                id: UUID().uuidString,
                huddleId: huddle.id,
                authorId: ownerId,
                text: request.pitch,
                createdAt: .now
            )
        )
        seedWorkspace(for: huddle)
        return huddle
    }

    private func seedWorkspace(for huddle: Huddle) {
        let start = Date()
        let titles = ["Kickoff", "Build", "Review", "Ship"]
        milestones.append(contentsOf: titles.enumerated().map { index, title in
            Milestone(
                id: UUID().uuidString,
                huddleId: huddle.id,
                title: title,
                dueDate: Calendar.current.date(byAdding: .day, value: (index + 1) * 3, to: start) ?? start,
                isComplete: false
            )
        })
        tasks.append(
            HuddleTask(
                id: UUID().uuidString,
                huddleId: huddle.id,
                title: "Agree on the first shippable slice",
                assigneeId: huddle.memberIds.first,
                lane: .doing,
                createdAt: .now
            )
        )
    }

    private func upsert(_ profile: UserProfile) {
        if let index = users.firstIndex(where: { $0.id == profile.id }) {
            users[index] = profile
        } else {
            users.append(profile)
        }
    }

    private func persist() {
        let snapshot = StoreSnapshot(
            seedVersion: seedVersion,
            currentUserId: currentUserId,
            users: users,
            projects: projects,
            requests: requests,
            huddles: huddles,
            messages: messages,
            tasks: tasks,
            milestones: milestones
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: Self.fileURL(), options: [.atomic])
    }

    private static func loadSnapshot() -> StoreSnapshot? {
        guard let data = try? Data(contentsOf: fileURL()) else { return nil }
        return try? JSONDecoder().decode(StoreSnapshot.self, from: data)
    }

    private static func fileURL() -> URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SkillSync", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("campus.json")
    }
}

enum CampusSeed {
    static let version = 5
    static let jordanID = "user-jordan"
    static let mayaID = "user-maya"
    static let priyaID = "user-priya"
    static let leoID = "user-leo"
    static let samiraID = "user-samira"
    static let alexID = "user-alex"
    static let rileyID = "user-riley"

    static func make() -> StoreSnapshot {
        let jordan = UserProfile(
            id: jordanID,
            email: "jordan@campus.edu",
            displayName: "Jordan Hale",
            university: "Northshore University",
            year: "Year 3",
            bio: "iOS developer looking for a designer who wants to ship, not just moodboard.",
            isStudentVerified: true,
            onboardingComplete: true,
            skills: [
                UserSkill(name: "Swift", level: .advanced, category: .mobile),
                UserSkill(name: "SwiftUI", level: .advanced, category: .mobile),
                UserSkill(name: "Firebase", level: .intermediate, category: .backend)
            ],
            neededSkills: ["UI/UX", "Figma"],
            availability: Availability(weekdays: [1, 2, 3, 4, 6], hoursPerWeek: 12),
            collaborations: [
                VerifiedCollaboration(
                    id: "collab-studio-jordan",
                    projectId: "project-studio",
                    projectTitle: "Studio Hours",
                    role: "iOS Developer",
                    teammateNames: ["Leo Park"],
                    durationDays: 10,
                    proofURL: "https://github.com/campus/studio-hours",
                    shipNote: "Students can book studio time from their phone.",
                    showedUp: true,
                    completedAt: Calendar.current.date(byAdding: .day, value: -18, to: .now) ?? .now
                )
            ],
            vouches: [
                VouchBadge(
                    id: "vouch-leo-jordan",
                    fromUserId: leoID,
                    fromName: "Leo Park",
                    projectTitle: "Studio Hours",
                    scores: [
                        VouchDimension.communication.rawValue: 5,
                        VouchDimension.reliability.rawValue: 5,
                        VouchDimension.technicalContribution.rawValue: 5
                    ],
                    note: "Shipped the SwiftUI client in a week and never left art files hanging.",
                    createdAt: Calendar.current.date(byAdding: .day, value: -17, to: .now) ?? .now
                )
            ],
            createdAt: .now
        )
        let maya = UserProfile(
            id: mayaID,
            email: "maya@campus.edu",
            displayName: "Maya Chen",
            university: "Northshore University",
            year: "Year 2",
            bio: "Product designer. I think in flows and want an engineer who ships weekly.",
            isStudentVerified: true,
            onboardingComplete: true,
            skills: [
                UserSkill(name: "Figma", level: .mentor, category: .design),
                UserSkill(name: "UI/UX", level: .advanced, category: .design),
                UserSkill(name: "Product Design", level: .intermediate, category: .product)
            ],
            neededSkills: ["Swift", "SwiftUI"],
            availability: Availability(weekdays: [1, 2, 3, 4, 5], hoursPerWeek: 10),
            collaborations: [],
            vouches: [],
            createdAt: .now
        )
        let priya = UserProfile(
            id: priyaID,
            email: "priya@campus.edu",
            displayName: "Priya Nair",
            university: "Northshore University",
            year: "Year 4",
            bio: "Backend and Firebase. Happiest when the iOS client actually hits a real API.",
            isStudentVerified: true,
            onboardingComplete: true,
            skills: [
                UserSkill(name: "Firebase", level: .mentor, category: .backend),
                UserSkill(name: "Node.js", level: .advanced, category: .backend),
                UserSkill(name: "APIs", level: .advanced, category: .backend)
            ],
            neededSkills: ["SwiftUI", "UI/UX"],
            availability: Availability(weekdays: [2, 3, 4, 5, 7], hoursPerWeek: 8),
            collaborations: [],
            vouches: [],
            createdAt: .now
        )
        let leo = UserProfile(
            id: leoID,
            email: "leo@campus.edu",
            displayName: "Leo Park",
            university: "Riverside College of Art",
            year: "Year 2",
            bio: "Motion and illustration. Looking for someone who can put the work on a phone.",
            isStudentVerified: true,
            onboardingComplete: true,
            skills: [
                UserSkill(name: "Illustration", level: .advanced, category: .creative),
                UserSkill(name: "Motion", level: .advanced, category: .creative),
                UserSkill(name: "Video", level: .intermediate, category: .creative)
            ],
            neededSkills: ["Swift", "Firebase"],
            availability: Availability(weekdays: [1, 3, 5, 6], hoursPerWeek: 14),
            collaborations: [
                VerifiedCollaboration(
                    id: "collab-studio-leo",
                    projectId: "project-studio",
                    projectTitle: "Studio Hours",
                    role: "Motion / Illustration",
                    teammateNames: ["Jordan Hale"],
                    durationDays: 10,
                    proofURL: "https://github.com/campus/studio-hours",
                    shipNote: "Students can book studio time from their phone.",
                    showedUp: true,
                    completedAt: Calendar.current.date(byAdding: .day, value: -18, to: .now) ?? .now
                )
            ],
            vouches: [
                VouchBadge(
                    id: "vouch-jordan-leo",
                    fromUserId: jordanID,
                    fromName: "Jordan Hale",
                    projectTitle: "Studio Hours",
                    scores: [
                        VouchDimension.creativity.rawValue: 5,
                        VouchDimension.adaptability.rawValue: 4,
                        VouchDimension.reliability.rawValue: 5
                    ],
                    note: "Every screen had a real visual system. I never had to invent empty states.",
                    createdAt: Calendar.current.date(byAdding: .day, value: -17, to: .now) ?? .now
                )
            ],
            createdAt: .now
        )
        let samira = UserProfile(
            id: samiraID,
            email: "samira@campus.edu",
            displayName: "Samira Okonkwo",
            university: "Northshore University",
            year: "Year 3",
            bio: "ML student. I can rank things. I cannot design a login screen.",
            isStudentVerified: true,
            onboardingComplete: true,
            skills: [
                UserSkill(name: "Python", level: .advanced, category: .data),
                UserSkill(name: "Machine Learning", level: .intermediate, category: .data)
            ],
            neededSkills: ["UI/UX", "Swift"],
            availability: Availability(weekdays: [1, 2, 4, 5], hoursPerWeek: 9),
            collaborations: [],
            vouches: [],
            createdAt: .now
        )
        let alex = UserProfile(
            id: alexID,
            email: "alex@campus.edu",
            displayName: "Alex Rivera",
            university: "Northshore University",
            year: "Year 1",
            bio: "ARKit tinkerer. Need a designer before this becomes another spinning cube.",
            isStudentVerified: true,
            onboardingComplete: true,
            skills: [
                UserSkill(name: "Swift", level: .intermediate, category: .mobile),
                UserSkill(name: "ARKit", level: .advanced, category: .mobile)
            ],
            neededSkills: ["UI/UX", "Figma", "Product Design"],
            availability: Availability(weekdays: [3, 4, 5, 6, 7], hoursPerWeek: 11),
            collaborations: [],
            vouches: [],
            createdAt: .now
        )
        let riley = UserProfile(
            id: rileyID,
            email: "riley@campus.edu",
            displayName: "Riley Cho",
            university: "Northshore University",
            year: "Year 2",
            bio: "Product and copy. I will write the onboarding; someone else has to make the buttons real.",
            isStudentVerified: true,
            onboardingComplete: true,
            skills: [
                UserSkill(name: "Product Strategy", level: .advanced, category: .product),
                UserSkill(name: "Copywriting", level: .advanced, category: .creative),
                UserSkill(name: "Product Design", level: .intermediate, category: .product)
            ],
            neededSkills: ["Swift", "SwiftUI", "Firebase"],
            availability: Availability(weekdays: [1, 2, 3, 4, 5], hoursPerWeek: 8),
            collaborations: [],
            vouches: [],
            createdAt: .now
        )

        let campusEvent = Project(
            id: "project-campus-event",
            title: "Campus Event App",
            summary: "A seven-day sprint to let clubs post events and students RSVP without another Instagram story.",
            ownerId: jordanID,
            requiredSkills: ["Swift", "SwiftUI", "UI/UX", "Figma"],
            durationDays: 7,
            deadline: Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now,
            status: .recruiting,
            memberIds: [jordanID],
            huddleId: nil,
            proofURL: nil,
            createdAt: .now
        )
        let labTracker = Project(
            id: "project-lab",
            title: "Lab Equipment Tracker",
            summary: "Students reserve oscilloscopes without a clipboard. Priya already has the API sketch.",
            ownerId: priyaID,
            requiredSkills: ["Firebase", "APIs", "SwiftUI"],
            durationDays: 14,
            deadline: Calendar.current.date(byAdding: .day, value: 12, to: .now) ?? .now,
            status: .active,
            memberIds: [priyaID, jordanID],
            huddleId: "huddle-lab",
            proofURL: nil,
            createdAt: Calendar.current.date(byAdding: .day, value: -3, to: .now) ?? .now
        )
        let lostFound = Project(
            id: "project-lost",
            title: "Dorm Lost & Found",
            summary: "Photo-first lost and found for first-year halls. Needs illustration and a patient iOS person.",
            ownerId: leoID,
            requiredSkills: ["Illustration", "Swift", "Firebase"],
            durationDays: 10,
            deadline: Calendar.current.date(byAdding: .day, value: 16, to: .now) ?? .now,
            status: .recruiting,
            memberIds: [leoID],
            huddleId: nil,
            proofURL: nil,
            createdAt: .now
        )
        let studioHours = Project(
            id: "project-studio",
            title: "Studio Hours",
            summary: "Booking board for art studio time. Jordan and Leo already shipped it.",
            ownerId: jordanID,
            requiredSkills: ["Swift", "Illustration"],
            durationDays: 10,
            deadline: Calendar.current.date(byAdding: .day, value: -8, to: .now) ?? .now,
            status: .completed,
            memberIds: [jordanID, leoID],
            huddleId: "huddle-studio",
            proofURL: "https://github.com/campus/studio-hours",
            shipNote: "Students can book studio time from their phone.",
            createdAt: Calendar.current.date(byAdding: .day, value: -28, to: .now) ?? .now
        )
        let studyMatch = Project(
            id: "project-study",
            title: "Quiet Hours Finder",
            summary: "Samira can rank library noise. She still needs someone who can put it on iPhone.",
            ownerId: samiraID,
            requiredSkills: ["Python", "Machine Learning", "SwiftUI", "UI/UX"],
            durationDays: 12,
            deadline: Calendar.current.date(byAdding: .day, value: 14, to: .now) ?? .now,
            status: .recruiting,
            memberIds: [samiraID],
            huddleId: nil,
            proofURL: nil,
            createdAt: .now
        )

        let mayaToJordan = CollaborationRequest(
            id: "request-maya",
            fromUserId: mayaID,
            toUserId: jordanID,
            projectId: campusEvent.id,
            pitch: "I can take the event flows and a Figma system this week if you own SwiftUI. No followers required — I just want it shipped.",
            synergyScore: 92,
            status: .pending,
            createdAt: Calendar.current.date(byAdding: .hour, value: -5, to: .now) ?? .now
        )
        let alexToMaya = CollaborationRequest(
            id: "request-alex-maya",
            fromUserId: alexID,
            toUserId: mayaID,
            projectId: nil,
            pitch: "I have ARKit working. I need a designer so this stops looking like a spinning cube with confidence.",
            synergyScore: 88,
            status: .pending,
            createdAt: Calendar.current.date(byAdding: .hour, value: -2, to: .now) ?? .now
        )
        let rileyToPriya = CollaborationRequest(
            id: "request-riley-priya",
            fromUserId: rileyID,
            toUserId: priyaID,
            projectId: nil,
            pitch: "I can write the reservation copy and empty states if you keep the API honest. Want a two-week huddle?",
            synergyScore: 74,
            status: .pending,
            createdAt: Calendar.current.date(byAdding: .hour, value: -1, to: .now) ?? .now
        )

        let huddle = Huddle(
            id: "huddle-lab",
            projectId: labTracker.id,
            memberIds: [priyaID, jordanID],
            status: .active,
            roles: [
                RoleAssignment(userId: jordanID, role: "SwiftUI"),
                RoleAssignment(userId: priyaID, role: "Firebase")
            ],
            createdAt: Calendar.current.date(byAdding: .day, value: -3, to: .now) ?? .now
        )
        let studioHuddle = Huddle(
            id: "huddle-studio",
            projectId: studioHours.id,
            memberIds: [jordanID, leoID],
            status: .completed,
            roles: [
                RoleAssignment(userId: jordanID, role: "Swift"),
                RoleAssignment(userId: leoID, role: "Illustration")
            ],
            shipNote: "Students can book studio time from their phone.",
            createdAt: Calendar.current.date(byAdding: .day, value: -28, to: .now) ?? .now
        )

        let chat = [
            HuddleMessage(id: "m1", huddleId: huddle.id, authorId: priyaID, text: "Firestore schema is up. Users, reservations, equipment.", createdAt: Calendar.current.date(byAdding: .hour, value: -26, to: .now) ?? .now),
            HuddleMessage(id: "m2", huddleId: huddle.id, authorId: jordanID, text: "I’ll bind the reservation list tonight. Need empty and conflict states from you.", createdAt: Calendar.current.date(byAdding: .hour, value: -20, to: .now) ?? .now),
            HuddleMessage(id: "m3", huddleId: huddle.id, authorId: priyaID, text: "Conflict rule: one active reservation per device. I’ll enforce it in a function so the client stays honest.", createdAt: Calendar.current.date(byAdding: .hour, value: -6, to: .now) ?? .now),
            HuddleMessage(id: "ms1", huddleId: studioHuddle.id, authorId: leoID, text: "Studio calendar illustrations are in the repo.", createdAt: Calendar.current.date(byAdding: .day, value: -20, to: .now) ?? .now),
            HuddleMessage(id: "ms2", huddleId: studioHuddle.id, authorId: jordanID, text: "TestFlight is live. Thanks for actually shipping with me.", createdAt: Calendar.current.date(byAdding: .day, value: -18, to: .now) ?? .now)
        ]

        let huddleTasks = [
            HuddleTask(id: "t1", huddleId: huddle.id, title: "Reservation list in SwiftUI", assigneeId: jordanID, lane: .doing, createdAt: .now),
            HuddleTask(id: "t2", huddleId: huddle.id, title: "Cloud Function: conflict check", assigneeId: priyaID, lane: .done, createdAt: .now),
            HuddleTask(id: "t3", huddleId: huddle.id, title: "Empty state copy", assigneeId: priyaID, lane: .todo, createdAt: .now)
        ]

        let huddleMilestones = [
            Milestone(id: "ms1", huddleId: huddle.id, title: "Kickoff", dueDate: Calendar.current.date(byAdding: .day, value: -3, to: .now) ?? .now, isComplete: true),
            Milestone(id: "ms2", huddleId: huddle.id, title: "API + list", dueDate: Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now, isComplete: false),
            Milestone(id: "ms3", huddleId: huddle.id, title: "Reserve + conflict", dueDate: Calendar.current.date(byAdding: .day, value: 5, to: .now) ?? .now, isComplete: false),
            Milestone(id: "ms4", huddleId: huddle.id, title: "Ship TestFlight", dueDate: Calendar.current.date(byAdding: .day, value: 12, to: .now) ?? .now, isComplete: false)
        ]

        let seededLinks: [String: [String]] = [
            jordanID: ["https://www.linkedin.com/in/jordan-hale", "https://github.com/jordanhale"],
            mayaID: ["https://www.linkedin.com/in/maya-chen", "https://www.behance.net/mayachen"],
            priyaID: ["https://www.linkedin.com/in/priya-nair", "https://github.com/priyanair"],
            leoID: ["https://www.linkedin.com/in/leo-park", "https://dribbble.com/leopark"],
            samiraID: ["https://github.com/samira-okonkwo", "https://www.kaggle.com/samiraokonkwo"],
            alexID: ["https://www.linkedin.com/in/alex-rivera", "https://github.com/alexrivera"],
            rileyID: ["https://www.linkedin.com/in/riley-cho", "https://www.figma.com/@rileycho"]
        ]
        var people = [jordan, maya, priya, leo, samira, alex, riley]
        for index in people.indices {
            let raw = seededLinks[people[index].id] ?? []
            people[index].platformLinks = CredentialVerifier.evaluate(links: raw, existing: []).verified
            people[index].createdAt = Calendar.current.date(byAdding: .day, value: -40, to: .now) ?? .now
        }

        return StoreSnapshot(
            seedVersion: version,
            currentUserId: nil,
            users: people,
            projects: [campusEvent, labTracker, lostFound, studioHours, studyMatch],
            requests: [mayaToJordan, alexToMaya, rileyToPriya],
            huddles: [huddle, studioHuddle],
            messages: chat,
            tasks: huddleTasks,
            milestones: huddleMilestones
        )
    }
}

import Foundation
import SwiftUI

enum SkillLevel: String, Codable, CaseIterable, Identifiable, Hashable {
    case beginner
    case intermediate
    case advanced
    case mentor

    var id: String { rawValue }

    var rank: Int {
        switch self {
        case .beginner: 1
        case .intermediate: 2
        case .advanced: 3
        case .mentor: 4
        }
    }

    var label: String {
        switch self {
        case .beginner: "Beginner"
        case .intermediate: "Intermediate"
        case .advanced: "Advanced"
        case .mentor: "Mentor"
        }
    }
}

enum SkillCategory: String, Codable, CaseIterable, Identifiable, Hashable {
    case mobile
    case design
    case backend
    case product
    case creative
    case data

    var id: String { rawValue }

    var label: String {
        switch self {
        case .mobile: "Mobile"
        case .design: "Design"
        case .backend: "Backend"
        case .product: "Product"
        case .creative: "Creative"
        case .data: "Data"
        }
    }

    var symbol: String {
        switch self {
        case .mobile: "iphone"
        case .design: "pencil.and.outline"
        case .backend: "server.rack"
        case .product: "map"
        case .creative: "paintbrush.pointed"
        case .data: "chart.xyaxis.line"
        }
    }
}

struct CatalogSkill: Identifiable, Hashable, Codable {
    var id: String { name }
    var name: String
    var category: SkillCategory
}

struct UserSkill: Identifiable, Hashable, Codable {
    var name: String
    var level: SkillLevel
    var category: SkillCategory

    var id: String { name }
}

struct Availability: Hashable, Codable {
    var weekdays: Set<Int>
    var hoursPerWeek: Int

    static let typical = Availability(weekdays: [1, 2, 3, 4, 5], hoursPerWeek: 10)

    var summary: String {
        "\(hoursPerWeek) hrs/week · \(weekdayLabel)"
    }

    var weekdayLabel: String {
        let names = [1: "Mon", 2: "Tue", 3: "Wed", 4: "Thu", 5: "Fri", 6: "Sat", 7: "Sun"]
        let ordered = weekdays.sorted().compactMap { names[$0] }
        if ordered == ["Mon", "Tue", "Wed", "Thu", "Fri"] { return "weekdays" }
        return ordered.joined(separator: " ")
    }
}

struct RoleAssignment: Identifiable, Hashable, Codable {
    var userId: String
    var role: String

    var id: String { userId }
}

enum WorkPlatform: String, Codable, CaseIterable, Hashable, Identifiable {
    case linkedin
    case github
    case gitlab
    case behance
    case dribbble
    case figma
    case devpost
    case codepen
    case kaggle
    case bitbucket

    var id: String { rawValue }

    var label: String {
        switch self {
        case .linkedin: "LinkedIn"
        case .github: "GitHub"
        case .gitlab: "GitLab"
        case .behance: "Behance"
        case .dribbble: "Dribbble"
        case .figma: "Figma"
        case .devpost: "Devpost"
        case .codepen: "CodePen"
        case .kaggle: "Kaggle"
        case .bitbucket: "Bitbucket"
        }
    }

    var isProfileNetwork: Bool { self == .linkedin }

    var symbol: String {
        switch self {
        case .linkedin: "person.crop.rectangle"
        case .github, .gitlab, .bitbucket: "chevron.left.forwardslash.chevron.right"
        case .figma, .behance, .dribbble: "paintbrush.pointed"
        case .devpost, .codepen, .kaggle: "shippingbox"
        }
    }
}

enum CredentialStatus: String, Codable, Hashable {
    case verified
    case rejected
}

enum TrustLevel: String, Codable, Hashable {
    case trusted
    case partial
    case unverified

    var label: String {
        switch self {
        case .trusted: "LinkedIn and work verified"
        case .partial: "Partly verified"
        case .unverified: "Not verified"
        }
    }
}

struct PlatformCredential: Identifiable, Hashable, Codable {
    var platform: WorkPlatform
    var normalizedURL: String
    var handle: String
    var status: CredentialStatus
    var reason: String

    var id: String { normalizedURL }
}

protocol EmptyDefault: Codable {
    static var empty: Self { get }
}

extension Array: EmptyDefault where Element: Codable {
    static var empty: [Element] { [] }
}

@propertyWrapper
struct DefaultEmpty<T: EmptyDefault & Hashable>: Codable, Hashable {
    var wrappedValue: T

    init(wrappedValue: T) {
        self.wrappedValue = wrappedValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        wrappedValue = (try? container.decode(T.self)) ?? T.empty
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue)
    }
}

extension KeyedDecodingContainer {
    func decode<T: EmptyDefault & Hashable>(_ type: DefaultEmpty<T>.Type, forKey key: Key) throws -> DefaultEmpty<T> {
        try decodeIfPresent(type, forKey: key) ?? DefaultEmpty(wrappedValue: T.empty)
    }
}

enum ContributionLane: String, Codable, CaseIterable, Identifiable, Hashable {
    case technicalCore
    case technicalHands

    var id: String { rawValue }

    var label: String {
        switch self {
        case .technicalCore: "Technical core"
        case .technicalHands: "Technical hands"
        }
    }

    var symbol: String {
        switch self {
        case .technicalCore: "cpu"
        case .technicalHands: "hammer"
        }
    }

    var detail: String {
        switch self {
        case .technicalCore: "Own the architecture, the model, or the system."
        case .technicalHands: "Implement the screens and ship the slice."
        }
    }
}

protocol DefaultCodable: Codable {
    static var defaultValue: Self { get }
}

extension String: DefaultCodable {
    static var defaultValue: String { "" }
}

extension Bool: DefaultCodable {
    static var defaultValue: Bool { false }
}

extension ContributionLane: DefaultCodable {
    static var defaultValue: ContributionLane { .technicalHands }
}

@propertyWrapper
struct DefaultCodableValue<T: DefaultCodable & Hashable>: Codable, Hashable {
    var wrappedValue: T

    init(wrappedValue: T) {
        self.wrappedValue = wrappedValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        wrappedValue = (try? container.decode(T.self)) ?? T.defaultValue
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue)
    }
}

extension KeyedDecodingContainer {
    func decode<T: DefaultCodable & Hashable>(_ type: DefaultCodableValue<T>.Type, forKey key: Key) throws -> DefaultCodableValue<T> {
        try decodeIfPresent(type, forKey: key) ?? DefaultCodableValue(wrappedValue: T.defaultValue)
    }
}

struct UserProfile: Identifiable, Hashable, Codable {
    var id: String
    var email: String
    var displayName: String
    var university: String
    var year: String
    var bio: String
    var isStudentVerified: Bool
    var onboardingComplete: Bool
    var skills: [UserSkill]
    var neededSkills: [String]
    var availability: Availability
    var collaborations: [VerifiedCollaboration]
    var vouches: [VouchBadge]
    @DefaultEmpty var platformLinks: [PlatformCredential] = []
    @DefaultCodableValue var roleTitle: String = ""
    @DefaultCodableValue var lane: ContributionLane = .technicalHands
    @DefaultCodableValue var trustReviewed: Bool = false
    var createdAt: Date

    var trust: TrustLevel {
        CredentialVerifier.trust(for: platformLinks)
    }

    var firstName: String {
        displayName.split(separator: " ").first.map(String.init) ?? displayName
    }

    var skillLine: String {
        skills.prefix(3).map(\.name).joined(separator: " · ")
    }

    var initials: String {
        let parts = displayName.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return letters.map(String.init).joined()
    }

    var ownedSkillNames: Set<String> {
        Set(skills.map(\.name))
    }

    func skill(named name: String) -> UserSkill? {
        skills.first { $0.name == name }
    }
}

enum ProjectStatus: String, Codable, Hashable {
    case recruiting
    case active
    case completed
}

struct Project: Identifiable, Hashable, Codable {
    var id: String
    var title: String
    var summary: String
    var ownerId: String
    var requiredSkills: [String]
    var durationDays: Int
    var deadline: Date
    var status: ProjectStatus
    var memberIds: [String]
    var huddleId: String?
    var proofURL: String?
    var shipNote: String? = nil
    @DefaultCodableValue var taskLane: ContributionLane = .technicalHands
    var createdAt: Date
}

enum RequestStatus: String, Codable, Hashable {
    case pending
    case accepted
    case declined
}

struct CollaborationRequest: Identifiable, Hashable, Codable {
    var id: String
    var fromUserId: String
    var toUserId: String
    var projectId: String?
    var pitch: String
    var synergyScore: Int
    var status: RequestStatus
    var createdAt: Date
}

enum HuddleStatus: String, Codable, Hashable {
    case active
    case completed
}

struct Huddle: Identifiable, Hashable, Codable {
    var id: String
    var projectId: String
    var memberIds: [String]
    var status: HuddleStatus
    var roles: [RoleAssignment]? = nil
    var shipNote: String? = nil
    var createdAt: Date

    var roleList: [RoleAssignment] { roles ?? [] }
}

struct HuddleMessage: Identifiable, Hashable, Codable {
    var id: String
    var huddleId: String
    var authorId: String
    var text: String
    var createdAt: Date
}

enum TaskLane: String, Codable, CaseIterable, Hashable {
    case todo
    case doing
    case done

    var label: String {
        switch self {
        case .todo: "To do"
        case .doing: "Doing"
        case .done: "Done"
        }
    }
}

struct HuddleTask: Identifiable, Hashable, Codable {
    var id: String
    var huddleId: String
    var title: String
    var assigneeId: String?
    var lane: TaskLane
    var createdAt: Date
}

struct Milestone: Identifiable, Hashable, Codable {
    var id: String
    var huddleId: String
    var title: String
    var dueDate: Date
    var isComplete: Bool
}

struct VerifiedCollaboration: Identifiable, Hashable, Codable {
    var id: String
    var projectId: String
    var projectTitle: String
    var role: String
    var teammateNames: [String]
    var durationDays: Int
    var proofURL: String?
    var shipNote: String? = nil
    var showedUp: Bool? = nil
    var completedAt: Date
}

enum VouchDimension: String, Codable, CaseIterable, Identifiable, Hashable {
    case communication
    case reliability
    case problemSolving
    case creativity
    case adaptability
    case technicalContribution

    var id: String { rawValue }

    var label: String {
        switch self {
        case .communication: "Communication"
        case .reliability: "Reliability"
        case .problemSolving: "Problem solving"
        case .creativity: "Creativity"
        case .adaptability: "Adaptability"
        case .technicalContribution: "Technical contribution"
        }
    }
}

struct VouchBadge: Identifiable, Hashable, Codable {
    var id: String
    var fromUserId: String
    var fromName: String
    var projectTitle: String
    var scores: [String: Int]
    var note: String
    var createdAt: Date

    var strongest: VouchDimension? {
        scores
            .compactMap { key, value -> (VouchDimension, Int)? in
                guard let dimension = VouchDimension(rawValue: key) else { return nil }
                return (dimension, value)
            }
            .max { $0.1 < $1.1 }?
            .0
    }
}

struct MicroSquad: Identifiable, Hashable {
    var id: String
    var projectId: String?
    var memberIds: [String]
    var skillOwners: [String: String]
    var score: Int
    var reasons: [String]
}

struct MatchCandidate: Identifiable, Hashable {
    var id: String { user.id }
    var user: UserProfile
    var project: Project?
    var synergy: SynergyBreakdown
}

struct SynergyBreakdown: Hashable {
    var score: Int
    var complementaryCoverage: Double
    var reverseCoverage: Double
    var proficiencyFit: Double
    var availabilityOverlap: Double
    var projectFit: Double
    var reasons: [String]
}

enum AppError: LocalizedError {
    case invalidEmail
    case unknownAccount
    case missingProfile
    case cannotPitchSelf
    case requestAlreadyExists
    case huddleNotFound
    case missingProof
    case invalidProof
    case unverifiedCredentials
    case missingVouchNote
    case missingShipNote
    case alreadyVouched
    case vouchRejected(String)
    case claimUnsupported(String)

    var errorDescription: String? {
        switch self {
        case .invalidEmail: "Use a valid email address."
        case .unknownAccount: "No account uses that email yet. Create one and verify a work link."
        case .missingProfile: "Create a profile before matching."
        case .cannotPitchSelf: "You cannot collaborate with yourself."
        case .requestAlreadyExists: "A request is already waiting."
        case .huddleNotFound: "That huddle no longer exists."
        case .missingProof: "Add a link to the work before you mark it complete."
        case .invalidProof: "Proof has to be a real link — GitHub, Figma, TestFlight, or a project site. “hi” is not evidence."
        case .unverifiedCredentials: "Verify at least one LinkedIn, GitHub, or project link before creating an account."
        case .missingVouchNote: "Say what they actually did before you vouch."
        case .missingShipNote: "Write one line about what you actually shipped."
        case .alreadyVouched: "You already vouched for them on this project."
        case .vouchRejected(let message): message
        case .claimUnsupported(let message): message
        }
    }
}

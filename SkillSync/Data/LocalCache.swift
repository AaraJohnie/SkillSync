import Foundation
import SwiftData

@Model
final class CachedProfile {
    @Attribute(.unique) var userId: String
    var payload: Data
    var updatedAt: Date

    init(userId: String, payload: Data, updatedAt: Date = .now) {
        self.userId = userId
        self.payload = payload
        self.updatedAt = updatedAt
    }
}

@Model
final class CachedProject {
    @Attribute(.unique) var projectId: String
    var payload: Data
    var updatedAt: Date

    init(projectId: String, payload: Data, updatedAt: Date = .now) {
        self.projectId = projectId
        self.payload = payload
        self.updatedAt = updatedAt
    }
}

@MainActor
final class LocalCache {
    let container: ModelContainer

    init() {
        let schema = Schema([CachedProfile.self, CachedProject.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("SwiftData container failed: \(error)")
        }
    }

    func remember(profile: UserProfile) {
        let context = container.mainContext
        let data = (try? JSONEncoder().encode(profile)) ?? Data()
        let id = profile.id
        var descriptor = FetchDescriptor<CachedProfile>(predicate: #Predicate { $0.userId == id })
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first {
            existing.payload = data
            existing.updatedAt = .now
        } else {
            context.insert(CachedProfile(userId: profile.id, payload: data))
        }
        try? context.save()
    }

    func remember(project: Project) {
        let context = container.mainContext
        let data = (try? JSONEncoder().encode(project)) ?? Data()
        let id = project.id
        var descriptor = FetchDescriptor<CachedProject>(predicate: #Predicate { $0.projectId == id })
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first {
            existing.payload = data
            existing.updatedAt = .now
        } else {
            context.insert(CachedProject(projectId: project.id, payload: data))
        }
        try? context.save()
    }
}

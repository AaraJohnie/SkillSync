import SwiftUI
import SwiftData

@main
struct SkillSyncApp: App {
    @State private var session = AppSession()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .preferredColorScheme(session.store.appearance.colorScheme)
                .modelContainer(session.cache.container)
        }
    }
}

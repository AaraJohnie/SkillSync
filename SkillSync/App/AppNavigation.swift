import SwiftUI
import Observation

enum MainTab: Hashable {
    case home
    case discover
    case agent
    case huddles
    case profile
}

enum AppRoute: Hashable {
    case user(String)
    case project(String)
    case huddle(String)
    case requests
    case skillTree
    case skillAnalysis
    case evidence
    case complete(String)
}

enum AppSheet: Identifiable {
    case createProject
    case pitch(MatchCandidate)
    case switchAccount

    var id: String {
        switch self {
        case .createProject: "create-project"
        case .pitch(let match): "pitch-\(match.id)"
        case .switchAccount: "switch-account"
        }
    }
}

@MainActor
@Observable
final class AppCoordinator {
    var tab: MainTab = .home
    var homePath = NavigationPath()
    var discoverPath = NavigationPath()
    var agentPath = NavigationPath()
    var huddlePath = NavigationPath()
    var profilePath = NavigationPath()
    var sheet: AppSheet?

    func open(_ route: AppRoute, on tab: MainTab? = nil) {
        if let tab {
            self.tab = tab
        }
        switch self.tab {
        case .home: homePath.append(route)
        case .discover: discoverPath.append(route)
        case .agent: agentPath.append(route)
        case .huddles: huddlePath.append(route)
        case .profile: profilePath.append(route)
        }
    }

    func openHuddle(_ id: String) {
        tab = .huddles
        huddlePath.append(AppRoute.huddle(id))
    }

    func resetToHome() {
        tab = .home
        homePath = NavigationPath()
        discoverPath = NavigationPath()
        agentPath = NavigationPath()
        huddlePath = NavigationPath()
        profilePath = NavigationPath()
        sheet = nil
    }
}

@MainActor
@Observable
final class AppSession {
    let store: DemoStore
    let coordinator: AppCoordinator
    let cache: LocalCache
    let agent: AgentChatModel

    init() {
        let cache = LocalCache()
        self.cache = cache
        self.store = DemoStore(cache: cache)
        self.coordinator = AppCoordinator()
        self.agent = AgentChatModel(store: store)
        if let user = store.currentUser {
            cache.remember(profile: user)
        }
    }

    func switchAccount(to userId: String) {
        store.switchTo(userId: userId)
        agent.reset()
        coordinator.resetToHome()
        if let user = store.currentUser {
            cache.remember(profile: user)
        }
    }
}

struct RootView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        Group {
            if session.store.currentUser == nil {
                AuthView()
            } else if session.store.currentUser?.onboardingComplete == false {
                OnboardingView()
            } else {
                MainTabView()
            }
        }
        .tint(Ink.gold)
        .background(Ink.bg.ignoresSafeArea())
        .preferredColorScheme(session.store.appearance.colorScheme)
        .animation(.easeInOut(duration: 0.35), value: session.store.appearance)
    }
}

struct MainTabView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        @Bindable var coordinator = session.coordinator
        TabView(selection: $coordinator.tab) {
            NavigationStack(path: $coordinator.homePath) {
                HomeView()
                    .navigationDestination(for: AppRoute.self) { route in
                        RouteView(route: route)
                    }
            }
            .tabItem { Label("Home", systemImage: "house.fill") }
            .badge(incomingCount)
            .tag(MainTab.home)

            NavigationStack(path: $coordinator.discoverPath) {
                DiscoverView()
                    .navigationDestination(for: AppRoute.self) { route in
                        RouteView(route: route)
                    }
            }
            .tabItem { Label("Discover", systemImage: "sparkle.magnifyingglass") }
            .tag(MainTab.discover)

            NavigationStack(path: $coordinator.agentPath) {
                AgentView()
                    .navigationDestination(for: AppRoute.self) { route in
                        RouteView(route: route)
                    }
            }
            .tabItem { Label("Agent", systemImage: "sparkles") }
            .tag(MainTab.agent)

            NavigationStack(path: $coordinator.huddlePath) {
                HuddleListView()
                    .navigationDestination(for: AppRoute.self) { route in
                        RouteView(route: route)
                    }
            }
            .tabItem { Label("Huddles", systemImage: "person.2.fill") }
            .badge(huddleCount == 0 ? 0 : huddleCount)
            .tag(MainTab.huddles)

            NavigationStack(path: $coordinator.profilePath) {
                ProfileView(userId: session.store.currentUserId)
                    .navigationDestination(for: AppRoute.self) { route in
                        RouteView(route: route)
                    }
            }
            .tabItem { Label("Profile", systemImage: "person.crop.circle") }
            .tag(MainTab.profile)
        }
        .toolbarBackground(Ink.bg, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .sheet(item: $coordinator.sheet) { sheet in
            switch sheet {
            case .createProject:
                CreateProjectView()
            case .pitch(let match):
                PitchSheet(match: match)
            case .switchAccount:
                AccountSwitcherSheet()
            }
        }
    }

    private var incomingCount: Int {
        session.store.incomingRequests(for: session.store.currentUserId ?? "").count
    }

    private var huddleCount: Int {
        session.store.huddles(for: session.store.currentUserId ?? "").filter { $0.status == .active }.count
    }
}

struct RouteView: View {
    var route: AppRoute

    var body: some View {
        switch route {
        case .user(let id):
            ProfileView(userId: id)
        case .project(let id):
            ProjectDetailView(projectId: id)
        case .huddle(let id):
            HuddleView(huddleId: id)
        case .requests:
            RequestsView()
        case .skillTree:
            SkillTreeView()
        case .skillAnalysis:
            SkillAnalysisView()
        case .evidence:
            TrustProfileView()
        case .complete(let id):
            CompleteProjectView(huddleId: id)
        }
    }
}

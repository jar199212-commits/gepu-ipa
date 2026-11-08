import SwiftUI

@main
struct GePuApp: App {
    @StateObject private var store = AppStore.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(store.colorScheme)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            HomeView()
                .tabItem { Label("首页", systemImage: "square.grid.2x2") }
                .tag(0)
            HistoryView()
                .tabItem { Label("浏览记录", systemImage: "clock") }
                .tag(1)
            TagsView()
                .tabItem { Label("标签", systemImage: "tag") }
                .tag(2)
            MeView()
                .tabItem { Label("我的", systemImage: "person.crop.circle") }
                .tag(3)
        }
        .onAppear {
            store.cleanupTrash(auto: true)
            store.ensureSearchIndex()
        }
    }
}

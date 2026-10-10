import SwiftUI

@main
struct QimaoReaderApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack {
                SearchView()
            }
            .tabItem { Label("找书", systemImage: "magnifyingglass") }
            .tag(0)

            NavigationStack {
                LibraryView()
            }
            .tabItem { Label("书架", systemImage: "books.vertical.fill") }
            .tag(1)
        }
        .tint(QTheme.primary)
    }
}

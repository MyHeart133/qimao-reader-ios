import SwiftUI
import SwiftData

@main
struct NovelFlowApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [ShelfBook.self, ReadingPosition.self])
    }
}

struct RootView: View {
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack {
                ShelfView()
            }
            .tabItem { Label("书架", systemImage: "books.vertical") }
            .tag(0)

            NavigationStack {
                TypesettingLabView()
            }
            .tabItem { Label("排版实验室", systemImage: "textformat.size") }
            .tag(1)

            NavigationStack {
                AboutView()
            }
            .tabItem { Label("关于", systemImage: "info.circle") }
            .tag(2)
        }
        .tint(NFTheme.accent)
    }
}

struct AboutView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("NovelFlow")
                        .font(.title2.weight(.semibold))
                    Text("安静、耐用的小说阅读器")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            Section("当前版本状态") {
                LabeledContent("版本", value: "0.1.0（P0 骨架）")
                LabeledContent("阅读引擎", value: "章节解析 / 分页 / 锚点 已就绪")
                LabeledContent("书源", value: "待接入（P4）")
                LabeledContent("本地导入", value: "开发中（P1）")
            }
            Section {
                Text("P0 阶段交付:工程骨架、设计系统、阅读引擎核心与排版实验室。后续阶段按路线图推进。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("关于")
    }
}
